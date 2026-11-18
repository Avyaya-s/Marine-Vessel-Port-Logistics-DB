"""Natural-language query assistant: question -> SQL -> rows.

Pipeline
  1. describe the schema (tables, views, columns, foreign keys) from
     information_schema, plus a short glossary of what the columns mean
  2. ask a local LLM (Ollama) to write ONE PostgreSQL SELECT for the question
  3. validate the SQL text (single statement, SELECT/WITH only, no write keywords)
  4. run it as the read-only role nl_assistant (read-only transactions,
     5 s timeout), never as the admin user
  5. if PostgreSQL rejects it (wrong column, syntax error), send the error back
     to the LLM once so it can correct itself

The LLM is never trusted.  Step 3 catches obvious mistakes early with a clear
message; step 4 is the real guarantee: even SQL that slips past the checks
cannot change data, because the database account itself is read-only.
"""

import json
import os
import re
import time
import urllib.error
import urllib.request
from datetime import date, datetime, timedelta
from decimal import Decimal

from psycopg import Error as PgError
from psycopg import errors as pg_errors
from psycopg.rows import dict_row

from db import nl_pool

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "qwen2.5:7b")
MAX_ROWS = 200

# ---------------------------------------------------------------- schema text

GLOSSARY = """\
Meaning of the data (single sea port, times are timestamptz in IST):
- port_call = one visit by one vessel. Planned times: eta (agent), predicted_eta (ML model),
  berth_start/berth_end (booked berth window). Actual times: ata (arrived at anchorage),
  atb (actually berthed), atd (departed).
- port_call.call_status is one of 'Expected','Waiting','Berthed','Departed'.
- vessel_type and berth.cargo_type are one of 'Container','Bulk','Tanker','General Cargo','RoRo'.
- loa = ship length in metres, draft = depth in metres. berth.max_loa / max_draft are limits.
- company.company_type is 'agent', 'shipper' or 'consignee'. port_call.agent_id, shipment.shipper_id
  and shipment.consignee_id all reference company.company_id.
- shipping_manifest.manifest_type is 'IGM' (import) or 'EGM' (export).
- shipment = one Bill of Lading. hs_code = goods code, origin_port = UN/LOCODE like 'CNSZX'.
- container.size is 20, 40 or 45 (feet). shipment_container links shipments and containers;
  container_status is 'Loaded','Discharged','Held','Released'.
- customs_filing.filing_status is 'Filed','Under Review','Held','Cleared'; risk_score is 0-1
  (higher = riskier); declared_value and duty_amount are in INR.
- inspection.result is 'Pending','Clear','Discrepancy'. INSPECTION is a weak entity: one inspection
  is identified by (filing_no, inspection_no), so always show filing_no with it.
- "Waiting" has two meanings. call_status = 'Waiting' means a ship is at anchorage NOW.
  Waiting TIME ("waited", "how long", "average wait") comes from v_waiting_time.waiting_hours.
Prefer these views when they fit the question:
- v_waiting_time: per arrived call; waiting_time (interval) and waiting_hours (numeric) = atb - ata,
  berthing_delay = atb - berth_start, agent_eta_error = ata - eta, model_eta_error = ata - predicted_eta.
- v_berth_occupancy: per berth; occupied_by (vessel alongside now), next_vessel, next_berth_start.
- v_pending_customs: uncleared filings with cargo, consignee, vessel_name, containers, inspections.
"""

RULES = """\
Rules:
- Write exactly ONE PostgreSQL query that answers the question. It must start with SELECT or WITH.
- Use only the tables, views and columns listed above. Join through the listed foreign keys.
- Keep the query as simple as possible: select only the columns the question asks about, plus the
  row's own identifier or name. Do not join a table unless the question needs a column from it.
- For place names and flags, use the exact values listed under "Values in the data".
- Never write INSERT, UPDATE, DELETE, DDL or anything that changes data.
- Give columns readable names with AS when helpful. Add ORDER BY when the order matters.
- Compare text values exactly as listed (e.g. 'Under Review', not 'under review').
- If the question cannot be answered from this data, reply with exactly: CANNOT_ANSWER: <short reason>
- Reply with the SQL inside a ```sql code block and nothing else.
"""

EXAMPLES = [
    ("Which ships are waiting at anchorage?",
     "SELECT v.vessel_name, pc.ata\nFROM port_call pc\nJOIN vessel v ON v.imo_number = pc.imo_number\n"
     "WHERE pc.call_status = 'Waiting'\nORDER BY pc.ata;"),
    ("What was the longest wait at anchorage?",
     "SELECT vessel_name, waiting_time\nFROM v_waiting_time\nWHERE waiting_time IS NOT NULL\n"
     "ORDER BY waiting_time DESC\nLIMIT 1;"),
    ("How many port calls does each agent handle?",
     "SELECT c.company_name AS agent, count(*) AS port_calls\nFROM port_call pc\n"
     "JOIN company c ON c.company_id = pc.agent_id\nGROUP BY c.company_name\nORDER BY port_calls DESC;"),
]

# Columns whose real values are listed in the prompt, so the model uses the
# actual codes (e.g. Rotterdam = 'NLRTM') instead of guessing them.
# A fixed list of trusted identifiers, never user input.
VALUE_HINTS = [("shipment", "origin_port"), ("vessel", "flag")]

_schema_cache: str | None = None


def schema_text() -> str:
    """Compact description of every table/view and its columns, read live
    from information_schema (so it never goes out of date), plus FKs."""
    global _schema_cache
    if _schema_cache:
        return _schema_cache
    with nl_pool().connection() as conn:
        cur = conn.cursor(row_factory=dict_row)
        cols = cur.execute("""
            SELECT c.table_name, t.table_type, c.column_name, c.data_type
            FROM information_schema.columns c
            JOIN information_schema.tables t
              ON t.table_schema = c.table_schema AND t.table_name = c.table_name
            WHERE c.table_schema = 'public'
            ORDER BY t.table_type, c.table_name, c.ordinal_position
        """).fetchall()
        fks = cur.execute("""
            SELECT tc.table_name, kcu.column_name, ccu.table_name AS ref_table, ccu.column_name AS ref_column
            FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
              ON kcu.constraint_name = tc.constraint_name AND kcu.table_schema = tc.table_schema
            JOIN information_schema.constraint_column_usage ccu
              ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema
            WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = 'public'
            ORDER BY 1, 2
        """).fetchall()

    short = {"character varying": "text", "character": "text", "timestamp with time zone": "timestamptz",
             "integer": "int", "smallint": "int", "bigint": "int", "numeric": "num"}
    tables: dict[str, tuple[str, list[str]]] = {}
    for r in cols:
        kind = "view" if r["table_type"] == "VIEW" else "table"
        tables.setdefault(r["table_name"], (kind, []))[1].append(
            f'{r["column_name"]} {short.get(r["data_type"], r["data_type"])}')

    lines = ["Tables and views (PostgreSQL):"]
    for name, (kind, columns) in tables.items():
        lines.append(f"{kind} {name}({', '.join(columns)})")
    lines.append("Foreign keys:")
    lines += [f'{r["table_name"]}.{r["column_name"]} -> {r["ref_table"]}.{r["ref_column"]}' for r in fks]
    lines.append("Values in the data:")
    with nl_pool().connection() as conn:
        for table, column in VALUE_HINTS:
            values = [r[0] for r in conn.execute(
                f"SELECT DISTINCT {column} FROM {table} WHERE {column} IS NOT NULL ORDER BY 1 LIMIT 40")]
            lines.append(f"{table}.{column}: " + ", ".join(f"'{v}'" for v in values))
    _schema_cache = "\n".join(lines)
    return _schema_cache


# ---------------------------------------------------------------- LLM call

def _ollama_chat(messages: list[dict]) -> str:
    body = json.dumps({
        "model": OLLAMA_MODEL,
        "messages": messages,
        "stream": False,
        "keep_alive": "30m",                       # keep the model in GPU memory between questions
        "options": {"temperature": 0, "num_ctx": 8192},   # temperature 0 = same answer every time
    }).encode()
    req = urllib.request.Request(f"{OLLAMA_URL}/api/chat", data=body,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            return json.loads(resp.read())["message"]["content"]
    except urllib.error.URLError as e:
        raise RuntimeError(f"Cannot reach Ollama at {OLLAMA_URL}. Is it running? ({e.reason})") from e


def _base_messages(question: str) -> list[dict]:
    system = f"{schema_text()}\n\n{GLOSSARY}\n{RULES}"
    messages = [{"role": "system", "content": system}]
    for q, sql in EXAMPLES:                          # few-shot: show the expected format
        messages.append({"role": "user", "content": q})
        messages.append({"role": "assistant", "content": f"```sql\n{sql}\n```"})
    messages.append({"role": "user", "content": question})
    return messages


def extract_sql(reply: str) -> str:
    """Pull the SQL out of the model's reply (it may wrap it in ``` fences)."""
    m = re.search(r"```(?:sql)?\s*(.*?)```", reply, re.S | re.I)
    return (m.group(1) if m else reply).strip()


# ---------------------------------------------------------------- validation

FORBIDDEN = re.compile(
    r"\b(insert|update|delete|merge|drop|alter|create|truncate|grant|revoke|copy|call|do|"
    r"vacuum|analyze|lock|reindex|cluster|refresh|comment|security|set|reset|listen|notify|"
    r"prepare|execute|deallocate|discard)\b", re.I)


def check_sql(sql: str) -> str:
    """Reject anything that is not a single read-only query.  Returns the
    cleaned SQL or raises ValueError with the reason."""
    s = re.sub(r"--[^\n]*", "", sql)            # drop -- comments
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)  # drop /* */ comments
    s = s.strip().rstrip(";").strip()
    no_strings = re.sub(r"'(?:[^']|'')*'", "''", s)   # ignore words inside string literals
    if not s:
        raise ValueError("The model returned no SQL.")
    if ";" in no_strings:
        raise ValueError("Only one SQL statement is allowed.")
    if not re.match(r"(?is)^\s*(select|with)\b", no_strings):
        raise ValueError("Only SELECT queries are allowed.")
    bad = FORBIDDEN.search(no_strings)
    if bad:
        raise ValueError(f"Blocked keyword in query: {bad.group(0).upper()}")
    return s


# ---------------------------------------------------------------- run

def _json_value(v):
    if isinstance(v, Decimal):
        return float(v)
    if isinstance(v, timedelta):
        total = int(v.total_seconds())
        sign = "-" if total < 0 else ""
        h, rem = divmod(abs(total), 3600)
        return f"{sign}{h}h {rem // 60:02d}m"
    if isinstance(v, (datetime, date)):
        return v.isoformat()
    return v


def _run(sql: str) -> tuple[list[str], list[list], bool]:
    with nl_pool().connection() as conn:
        cur = conn.execute(sql)
        columns = [d.name for d in cur.description]
        rows = cur.fetchmany(MAX_ROWS)
        truncated = cur.fetchone() is not None
        conn.rollback()                          # nothing to keep; read-only anyway
    return columns, [[_json_value(v) for v in r] for r in rows], truncated


def ask(question: str) -> dict:
    """Answer one question.  Always returns a dict with ok=True/False so the
    page can show the generated SQL even when something went wrong."""
    started = time.perf_counter()
    result = {"question": question, "model": OLLAMA_MODEL, "sql": None, "attempts": 0}

    def done(**extra):
        result.update(extra, seconds=round(time.perf_counter() - started, 1))
        return result

    try:
        messages = _base_messages(question)
        for attempt in (1, 2):                   # one self-correction retry
            result["attempts"] = attempt
            reply = _ollama_chat(messages)
            if reply.strip().upper().startswith("CANNOT_ANSWER"):
                return done(ok=False, error=reply.split(":", 1)[-1].strip() or "The data cannot answer this.")
            sql = extract_sql(reply)
            result["sql"] = sql
            try:
                clean = check_sql(sql)
            except ValueError as e:
                return done(ok=False, error=f"Rejected by the safety check: {e}")
            try:
                columns, rows, truncated = _run(clean)
                return done(ok=True, columns=columns, rows=rows,
                            row_count=len(rows), truncated=truncated)
            except (pg_errors.InsufficientPrivilege, pg_errors.ReadOnlySqlTransaction) as e:
                # the database's own guard fired: never retry, just report it
                return done(ok=False, error=f"Blocked by the read-only database role: {e.diag.message_primary}")
            except pg_errors.QueryCanceled:
                return done(ok=False, error="The query took longer than 5 seconds and was cancelled.")
            except PgError as e:
                if attempt == 2:
                    return done(ok=False, error=f"PostgreSQL error: {e.diag.message_primary}")
                messages += [
                    {"role": "assistant", "content": reply},
                    {"role": "user", "content": f"That query failed with this PostgreSQL error:\n"
                                                f"{e.diag.message_primary}\nWrite a corrected query."},
                ]
    except RuntimeError as e:
        return done(ok=False, error=str(e))
    return done(ok=False, error="No answer.")


def warm_up() -> None:
    """Load the model into GPU memory at server start, so the first question is fast."""
    try:
        _ollama_chat([{"role": "user", "content": "Reply with OK."}])
    except Exception:
        pass   # Ollama not running yet: the first real question will report it
