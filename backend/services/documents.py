"""Bill of Lading upload: PDF -> fields -> checks -> (user confirms) -> insert.

Extraction is a hybrid, each part doing what it is reliable at:
  * pdfplumber   reads the PDF's text layer
  * the LLM      reads the messy text and returns JSON of a fixed shape
                 (structured output), so it copes with any layout or label
  * regex        finds container numbers (exact ISO 6346 format), which is
                 more reliable than asking the model
  * Python       does the arithmetic (tonnes -> kg) and normalises codes:
                 "the LLM reads, the code computes"
Nothing is written until the user confirms; the insert is one transaction,
and the database's own constraints and triggers still check every row.
"""

import io
import re
import time

import pdfplumber
from psycopg import Error as PgError

from db import pool
from services import hs_suggest
from services.llm import chat

MAX_PAGES = 5

FIELDS_SCHEMA = {
    "type": "object",
    "properties": {
        "bl_number":          {"type": "string"},
        "vessel_name":        {"type": "string"},
        "voyage":             {"type": "string"},
        "shipper_name":       {"type": "string"},
        "consignee_name":     {"type": "string"},
        "port_of_loading":    {"type": "string"},
        "origin_port_code":   {"type": "string"},
        "cargo_description":  {"type": "string"},
        "hs_code":            {"type": "string"},
        "package_count":      {"type": "integer"},
        "gross_weight_value": {"type": "number"},
        "gross_weight_unit":  {"type": "string", "enum": ["KG", "MT", "LB"]},
        "containers": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "container_no": {"type": "string"},
                    "iso_type":     {"type": "string"},
                    "seal_no":      {"type": "string"},
                },
                "required": ["container_no", "iso_type", "seal_no"],
            },
        },
    },
    "required": ["bl_number", "vessel_name", "voyage", "shipper_name", "consignee_name",
                 "port_of_loading", "origin_port_code", "cargo_description", "hs_code",
                 "package_count", "gross_weight_value", "gross_weight_unit", "containers"],
}

PROMPT = """You extract data from the text of a shipping Bill of Lading (B/L).
Labels differ between companies: the shipper may be called "Exporter", the consignee "Importer",
the vessel "Ocean Vessel", the B/L number "Bill No", the port of loading "Port of Lading".
Rules:
- Copy values exactly as printed. Company names only: no address.
- origin_port_code: the 5-letter UN/LOCODE of the port of loading if it is printed, otherwise "".
- hs_code: the HS / tariff code exactly as printed, otherwise "".
- cargo_description: the full description of the goods only. In tables it may be split over several
  lines that also contain other columns; leave out package counts, weights, seals and container numbers.
- gross_weight_value and gross_weight_unit: the total gross weight and its unit
  (KGS/KG -> "KG", MT/tonnes -> "MT", LBS -> "LB").
- containers: every container with its size/type code (like 45G1) and seal number.
- Use "" or 0 for anything that is not in the text.

Bill of Lading text:
"""

CONTAINER_RE = re.compile(r"\b([A-Z]{4}\d{7})\b")
ISO_RE = re.compile(r"\b([24L][0-9A-Z][A-Z][0-9])\b")
LOCODE_RE = re.compile(r"^[A-Z]{2}[A-Z2-9]{3}$")
TO_KG = {"KG": 1, "MT": 1000, "LB": 0.45359237}
# "240 CARTONS" leaking into the description from a neighbouring table column
PACKAGES_RE = re.compile(r"\s*\b\d[\d,]*\s+(?:CARTONS?|PALLETS?|PACKAGES?|PKGS?|BAGS?|DRUMS?|CASES?|BOXES|CRATES?)\b",
                         re.I)


class DocumentError(ValueError):
    """A problem with the uploaded file itself (shown to the user as-is)."""


# ---------------------------------------------------------------- 1. text

def pdf_text(data: bytes) -> tuple[str, int]:
    if not data.startswith(b"%PDF"):
        raise DocumentError("This is not a PDF file.")
    try:
        with pdfplumber.open(io.BytesIO(data)) as pdf:
            pages = pdf.pages[:MAX_PAGES]
            text = "\n".join(p.extract_text() or "" for p in pages)
            n = len(pdf.pages)
    except Exception as e:
        raise DocumentError(f"Could not read the PDF ({e}).") from e
    if len(text.strip()) < 30:
        raise DocumentError("No text found in this PDF: it is probably a scanned image. "
                            "OCR (Tesseract) is not installed yet, so enter the details manually.")
    return text, n


# ---------------------------------------------------------------- 2. fields

def llm_fields(text: str) -> dict:
    import json
    reply = chat([{"role": "user", "content": PROMPT + text}], schema=FIELDS_SCHEMA)
    return json.loads(reply)


def merge_containers(text: str, llm_list: list[dict]) -> tuple[list[dict], list[str]]:
    """Container numbers come from the regex (exact format, never invented).
    Type and seal come from the LLM's entry for the same number, or failing
    that, from an ISO type code on the same line of text."""
    notes = []
    by_no = {c["container_no"].replace(" ", "").upper(): c for c in llm_list}
    found = list(dict.fromkeys(CONTAINER_RE.findall(text)))      # unique, in order
    out = []
    for no in found:
        llm = by_no.get(no, {})
        iso = (llm.get("iso_type") or "").upper()
        if not ISO_RE.fullmatch(iso):
            line = next((l for l in text.splitlines() if no in l), "")
            m = ISO_RE.search(line.replace(no, ""))
            iso = m.group(1) if m else ""
        out.append({"container_no": no, "iso_type": iso, "seal_no": (llm.get("seal_no") or "").strip()})
    for no in by_no:
        if no and no not in found:
            notes.append(f"The model listed container {no}, which is not in the text; it was ignored.")
    return out, notes


def normalise(f: dict) -> dict:
    hs = re.sub(r"\D", "", f.get("hs_code") or "")
    unit = (f.get("gross_weight_unit") or "KG").upper()
    weight = f.get("gross_weight_value") or 0
    return {
        "shipment_no": (f.get("bl_number") or "").strip().upper(),
        "vessel_name": (f.get("vessel_name") or "").strip(),
        "voyage": (f.get("voyage") or "").strip(),
        "shipper_name": (f.get("shipper_name") or "").strip(),
        "consignee_name": (f.get("consignee_name") or "").strip(),
        "port_of_loading": (f.get("port_of_loading") or "").strip(),
        "origin_port": (f.get("origin_port_code") or "").strip().upper(),
        "cargo_description": " ".join(PACKAGES_RE.sub("", f.get("cargo_description") or "").split()),
        "hs_code": hs[:8] if len(hs) >= 6 else "",
        "hs_printed": f.get("hs_code") or "",
        "cargo_quantity": int(f.get("package_count") or 0),
        "gross_weight": round(weight * TO_KG.get(unit, 1), 2),
        "weight_as_printed": f"{weight} {unit}",
    }


# ---------------------------------------------------------------- 3. checks

def manifests() -> list[dict]:
    """Import manifests to choose from, with the vessel of each call."""
    with pool.connection() as conn:
        return conn.execute("""
            SELECT m.manifest_no, m.call_id, v.vessel_name, pc.call_status
            FROM shipping_manifest m
            JOIN port_call pc ON pc.call_id = m.call_id
            JOIN vessel v ON v.imo_number = pc.imo_number
            WHERE m.manifest_type = 'IGM'
            ORDER BY m.manifest_no
        """).fetchall()


def _company(conn, name):
    return conn.execute("SELECT company_id, company_type FROM company WHERE lower(company_name) = lower(%s) LIMIT 1",
                        (name,)).fetchone()


def run_checks(f: dict, containers: list[dict]) -> tuple[list[dict], str | None]:
    checks = []
    add = lambda level, text: checks.append({"level": level, "text": text})
    suggested_manifest = None
    with pool.connection() as conn:
        if not f["shipment_no"]:
            add("error", "No B/L number found.")
        elif conn.execute("SELECT 1 FROM shipment WHERE shipment_no = %s", (f["shipment_no"],)).fetchone():
            add("error", f'{f["shipment_no"]} is already in the database (this B/L was uploaded before).')
        else:
            add("ok", f'{f["shipment_no"]} is a new Bill of Lading.')

        for role, name in (("shipper", f["shipper_name"]), ("consignee", f["consignee_name"])):
            row = _company(conn, name) if name else None
            if not name:
                add("error", f"No {role} found.")
            elif row and row["company_type"] == role:
                add("ok", f'{role.title()} "{name}" matches existing company #{row["company_id"]}.')
            elif row:
                add("error", f'"{name}" exists but is a {row["company_type"]}, not a {role}.')
            else:
                add("info", f'{role.title()} "{name}" is new; it will be created on confirm.')

        for c in containers:
            if not c["iso_type"]:
                add("warning", f'No size/type code found for {c["container_no"]}; please fill it in.')
            if conn.execute("SELECT 1 FROM container WHERE container_no = %s", (c["container_no"],)).fetchone():
                add("info", f'Container {c["container_no"]} is already known (reused, not re-created).')
        if not containers:
            add("info", "No containers found (bulk cargo?).")

        if f["vessel_name"]:
            for m in manifests():
                if m["vessel_name"].lower() == f["vessel_name"].lower():
                    suggested_manifest = m["manifest_no"]
                    add("ok", f'Vessel {f["vessel_name"]} -> import manifest {m["manifest_no"]} (call {m["call_id"]}).')
                    break
            else:
                add("warning", f'No import manifest found for vessel "{f["vessel_name"]}"; choose one.')

    if f["origin_port"] and not LOCODE_RE.match(f["origin_port"]):
        add("warning", f'"{f["origin_port"]}" is not a valid UN/LOCODE (5 letters, e.g. NLRTM).')
    elif not f["origin_port"]:
        add("warning", f'No UN/LOCODE printed for "{f["port_of_loading"]}"; please enter it.')
    if f["gross_weight"] <= 0:
        add("warning", "No gross weight found.")
    if f["weight_as_printed"].endswith(("MT", "LB")):
        add("info", f'Weight printed as {f["weight_as_printed"]}, converted to {f["gross_weight"]:,} kg.')
    return checks, suggested_manifest


def hs_advice(f: dict) -> tuple[list[dict], list[dict]]:
    """Suggestions from the description; cross-check against a printed code."""
    suggestions = hs_suggest.suggest(f["cargo_description"])
    notes = []
    if f["hs_code"]:
        top = [s["hs_code"] for s in suggestions]
        if f["hs_code"][:6] in top:
            notes.append({"level": "ok", "text": f'Printed HS code {f["hs_printed"]} agrees with the description.'})
        else:
            ref = hs_suggest.describe(f["hs_code"])
            notes.append({"level": "warning",
                          "text": f'Printed HS code {f["hs_printed"]} ({ref or "not in reference list"}) does not '
                                  f'match the description; suggested {top[0] if top else "-"}. Check it.'})
    else:
        notes.append({"level": "info", "text": "No HS code printed; pick one of the suggestions."})
    return suggestions, notes


# ---------------------------------------------------------------- extract

def extract(data: bytes) -> dict:
    started = time.perf_counter()
    text, pages = pdf_text(data)
    raw = llm_fields(text)
    fields = normalise(raw)
    containers, notes = merge_containers(text, raw.get("containers") or [])
    checks, suggested_manifest = run_checks(fields, containers)
    suggestions, hs_notes = hs_advice(fields)
    if not fields["hs_code"] and suggestions:
        fields["hs_code"] = suggestions[0]["hs_code"]          # pre-fill; the user confirms
    checks += hs_notes + [{"level": "warning", "text": n} for n in notes]
    return {
        "fields": fields,
        "containers": containers,
        "hs_suggestions": suggestions,
        "manifests": manifests(),
        "suggested_manifest": suggested_manifest,
        "checks": checks,
        "raw_text": text,
        "pages": pages,
        "seconds": round(time.perf_counter() - started, 1),
    }


# ---------------------------------------------------------------- confirm

def _get_or_create_company(conn, name: str, role: str) -> int:
    row = _company(conn, name)
    if row:
        if row["company_type"] != role:
            raise ValueError(f'"{name}" is a {row["company_type"]}, not a {role}.')
        return row["company_id"]
    return conn.execute("INSERT INTO company (company_name, company_type) VALUES (%s, %s) RETURNING company_id",
                        (name, role)).fetchone()["company_id"]


def confirm(s: dict) -> dict:
    """Insert the confirmed shipment in ONE transaction: new companies, the
    shipment, new containers and the shipment-container links.  If any row
    is rejected (by a CHECK, FK or trigger) nothing at all is saved."""
    try:
        with pool.connection() as conn:          # one transaction: commit at the end, rollback on error
            shipper_id = _get_or_create_company(conn, s["shipper_name"], "shipper")
            consignee_id = _get_or_create_company(conn, s["consignee_name"], "consignee")
            conn.execute("""
                INSERT INTO shipment (shipment_no, manifest_no, shipper_id, consignee_id, cargo_description,
                                      origin_port, hs_code, cargo_quantity, gross_weight)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (s["shipment_no"], s["manifest_no"], shipper_id, consignee_id, s["cargo_description"],
                  s["origin_port"], s["hs_code"], s["cargo_quantity"], s["gross_weight"]))
            for c in s["containers"]:
                conn.execute("INSERT INTO container (container_no, iso_type) VALUES (%s, %s) "
                             "ON CONFLICT (container_no) DO NOTHING", (c["container_no"], c["iso_type"]))
                conn.execute("INSERT INTO shipment_container (shipment_no, container_no, seal_no) VALUES (%s, %s, %s)",
                             (s["shipment_no"], c["container_no"], c["seal_no"] or None))
    except PgError as e:
        raise ValueError(e.diag.message_primary or str(e)) from e
    return {"shipment_no": s["shipment_no"], "containers": len(s["containers"]),
            "shipper_id": shipper_id, "consignee_id": consignee_id}
