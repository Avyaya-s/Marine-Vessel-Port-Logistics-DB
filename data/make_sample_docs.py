"""Generate sample Bill of Lading PDFs for testing document upload.

    pip install reportlab
    python data/make_sample_docs.py

Writes data/sample_docs/<name>.pdf and <name>.expected.json (the correct
field values, used by backend/eval_docs.py).  Two different layouts with
different labels and units, so extraction cannot rely on one template:

  Layout A: classic form, labels "Shipper / Consignee / Vessel / Voyage",
            weight in KGS, HS code printed with dots
  Layout B: "Exporter / Importer / Ocean Vessel", weight in metric tonnes,
            HS code sometimes missing (the HS suggester has to help)
All three are for the vessel CORAL TRADER, whose import manifest in the
sample data is IGM-2026-0002.
"""

import json
import textwrap
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas

OUT = Path(__file__).parent / "sample_docs"

DOCS = [
    {
        "file": "bl_rotterdam_bearings", "layout": "A",
        "bl_number": "BL-RTM-260007", "vessel": "CORAL TRADER", "voyage": "042E",
        "shipper": "Rotterdam Machinery BV", "shipper_addr": "Waalhaven Z.z. 21, 3089 JH Rotterdam, Netherlands",
        "consignee": "Kaveri Imports Pvt Ltd", "consignee_addr": "Plot 14, MIDC Taloja, Navi Mumbai 410208, India",
        "pol": "Rotterdam, Netherlands", "pol_code": "NLRTM", "pod": "Nhava Sheva, India (INNSA)",
        "cargo": "Industrial ball bearings, assorted sizes", "hs_printed": "8482.10.00",
        "packages": 240, "package_type": "CARTONS", "weight_text": "12,350.00 KGS",
        "containers": [("MAEU4471203", "45G1", "ML-8831204"), ("MAEU4471219", "45G1", "ML-8831205")],
        "expected": {"gross_weight_kg": 12350.0, "hs_code": "84821000"},
    },
    {
        "file": "bl_shenzhen_solar", "layout": "B",
        "bl_number": "BL-SZX-260008", "vessel": "CORAL TRADER", "voyage": "042E",
        "shipper": "Shenzhen Bright Electronics", "shipper_addr": "Bao'an District, Shenzhen 518101, China",
        "consignee": "Nilgiri Trading Co", "consignee_addr": "22 Ring Road, Coimbatore 641018, India",
        "pol": "Shekou / Shenzhen, China", "pol_code": "CNSZX", "pod": "Nhava Sheva, India",
        "cargo": "Solar photovoltaic panels, 550W monocrystalline modules", "hs_printed": "854143",
        "packages": 62, "package_type": "PALLETS", "weight_text": "24.6 MT",
        "containers": [("TGHU8812345", "45G1", "SZ0091832"), ("TCNU5501938", "45G1", "SZ0091833")],
        "expected": {"gross_weight_kg": 24600.0, "hs_code": "854143"},
    },
    {
        "file": "bl_hamburg_tools", "layout": "B",
        "bl_number": "BL-HAM-260009", "vessel": "CORAL TRADER", "voyage": "042E",
        "shipper": "Hamburg Precision Tools GmbH", "shipper_addr": "Am Sandtorkai 5, 20457 Hamburg, Germany",
        "consignee": "Sahyadri Engineering Pvt Ltd", "consignee_addr": "Bhosari MIDC, Pune 411026, India",
        "pol": "Hamburg, Germany", "pol_code": "DEHAM", "pod": "Nhava Sheva, India",
        "cargo": "Hand tools: adjustable spanners and wrenches, chrome vanadium steel", "hs_printed": None,
        "packages": 860, "package_type": "CARTONS", "weight_text": "9.87 MT",
        "containers": [("HLXU7730045", "22G1", "HL-220931")],
        "expected": {"gross_weight_kg": 9870.0, "hs_code": None},
    },
]


def box(c, x, y, w, h, label, lines, size=9):
    c.setStrokeColor(colors.HexColor("#555555"))
    c.rect(x, y, w, h)
    c.setFont("Helvetica-Bold", 7)
    c.drawString(x + 3, y + h - 9, label.upper())
    c.setFont("Helvetica", size)
    for i, line in enumerate(lines):
        c.drawString(x + 4, y + h - 21 - i * 11, line)


def layout_a(c, d):
    W, H = A4
    c.setFont("Helvetica-Bold", 16)
    c.drawString(20 * mm, H - 22 * mm, "BILL OF LADING")
    c.setFont("Helvetica", 8)
    c.drawString(20 * mm, H - 27 * mm, "For combined transport or port to port shipment")
    left, top, colw = 20 * mm, H - 35 * mm, 85 * mm
    box(c, left, top - 28 * mm, colw, 28 * mm, "Shipper", [d["shipper"], *textwrap.wrap(d["shipper_addr"], 46)])
    box(c, left + colw, top - 14 * mm, colw, 14 * mm, "B/L No.", [d["bl_number"]], size=11)
    box(c, left + colw, top - 28 * mm, colw, 14 * mm, "Reference", ["Booking RTM-55102"])
    box(c, left, top - 56 * mm, colw, 28 * mm, "Consignee", [d["consignee"], *textwrap.wrap(d["consignee_addr"], 46)])
    box(c, left + colw, top - 56 * mm, colw, 28 * mm, "Notify Party", ["SAME AS CONSIGNEE"])
    box(c, left, top - 70 * mm, colw / 2, 14 * mm, "Vessel", [d["vessel"]])
    box(c, left + colw / 2, top - 70 * mm, colw / 2, 14 * mm, "Voyage No.", [d["voyage"]])
    box(c, left + colw, top - 70 * mm, colw, 14 * mm, "Port of Loading", [f'{d["pol"]} ({d["pol_code"]})'])
    box(c, left, top - 84 * mm, colw, 14 * mm, "Port of Discharge", [d["pod"]])
    box(c, left + colw, top - 84 * mm, colw, 14 * mm, "Place of Delivery", ["Nhava Sheva CFS"])

    y = top - 96 * mm
    c.setFont("Helvetica-Bold", 8)
    for x, t in [(0, "CONTAINER NO."), (30, "SEAL NO."), (55, "TYPE"), (68, "DESCRIPTION OF GOODS"),
                 (122, "PACKAGES"), (148, "GROSS WEIGHT")]:
        c.drawString(left + x * mm, y, t)
    c.line(left, y - 3, left + 170 * mm, y - 3)
    c.setFont("Helvetica", 9)
    for i, (no, iso, seal) in enumerate(d["containers"]):
        yy = y - 14 - i * 12
        c.drawString(left, yy, no)
        c.drawString(left + 30 * mm, yy, seal)
        c.drawString(left + 55 * mm, yy, iso)
    for i, line in enumerate(textwrap.wrap(d["cargo"], 28)):
        c.drawString(left + 68 * mm, y - 14 - i * 12, line)
    if d["hs_printed"]:
        c.drawString(left + 68 * mm, y - 50, f'HS Code: {d["hs_printed"]}')
    c.drawString(left + 122 * mm, y - 14, f'{d["packages"]} {d["package_type"]}')
    c.drawString(left + 148 * mm, y - 14, d["weight_text"])
    c.setFont("Helvetica", 7)
    c.drawString(left, 30 * mm, "SHIPPED on board in apparent good order and condition. Freight prepaid.")
    c.drawString(left, 25 * mm, "Place and date of issue: Rotterdam, 02 Oct 2026")


def layout_b(c, d):
    W, H = A4
    c.setFillColor(colors.HexColor("#123b5c"))
    c.rect(0, H - 30 * mm, W, 30 * mm, fill=1, stroke=0)
    c.setFillColor(colors.white)
    c.setFont("Helvetica-Bold", 18)
    c.drawString(20 * mm, H - 18 * mm, "OCEAN BILL OF LADING")
    c.setFont("Helvetica", 10)
    c.drawRightString(W - 20 * mm, H - 18 * mm, f'Bill No: {d["bl_number"]}')
    c.setFillColor(colors.black)

    y = H - 42 * mm
    rows = [
        ("Exporter", f'{d["shipper"]}, {d["shipper_addr"]}'),
        ("Importer", f'{d["consignee"]}, {d["consignee_addr"]}'),
        ("Ocean Vessel / Voy", f'{d["vessel"]} / {d["voyage"]}'),
        ("Port of Lading", f'{d["pol"]}  [UN/LOCODE {d["pol_code"]}]'),
        ("Destination", d["pod"]),
    ]
    for label, value in rows:
        c.setFont("Helvetica-Bold", 9)
        c.drawString(20 * mm, y, f"{label}:")
        c.setFont("Helvetica", 9)
        c.drawString(55 * mm, y, value[:95])
        y -= 8 * mm

    y -= 4 * mm
    c.setFont("Helvetica-Bold", 10)
    c.drawString(20 * mm, y, "Particulars furnished by shipper")
    y -= 7 * mm
    c.setFont("Helvetica", 9)
    c.drawString(20 * mm, y, f'Goods: {d["cargo"]}')
    y -= 6 * mm
    if d["hs_printed"]:
        c.drawString(20 * mm, y, f'Tariff heading (HS): {d["hs_printed"]}')
        y -= 6 * mm
    c.drawString(20 * mm, y, f'No. of packages: {d["packages"]} {d["package_type"].lower()}')
    y -= 6 * mm
    c.drawString(20 * mm, y, f'Total gross weight: {d["weight_text"]}')
    y -= 10 * mm
    c.setFont("Helvetica-Bold", 9)
    c.drawString(20 * mm, y, "Equipment")
    y -= 6 * mm
    c.setFont("Helvetica", 9)
    for no, iso, seal in d["containers"]:
        c.drawString(20 * mm, y, f"{no}   size/type {iso}   seal {seal}")
        y -= 6 * mm
    c.setFont("Helvetica", 7)
    c.drawString(20 * mm, 25 * mm, "Received for shipment. Three original bills of lading issued.")


def main():
    OUT.mkdir(exist_ok=True)
    for d in DOCS:
        c = canvas.Canvas(str(OUT / f'{d["file"]}.pdf'), pagesize=A4)
        c.setTitle(f'Bill of Lading {d["bl_number"]}')
        (layout_a if d["layout"] == "A" else layout_b)(c, d)
        c.save()
        expected = {
            "bl_number": d["bl_number"], "vessel_name": d["vessel"],
            "shipper_name": d["shipper"], "consignee_name": d["consignee"],
            "origin_port": d["pol_code"], "cargo_description": d["cargo"],
            "hs_code": d["expected"]["hs_code"], "cargo_quantity": d["packages"],
            "gross_weight_kg": d["expected"]["gross_weight_kg"],
            "containers": [{"container_no": n, "iso_type": t, "seal_no": s} for n, t, s in d["containers"]],
        }
        (OUT / f'{d["file"]}.expected.json').write_text(json.dumps(expected, indent=2), encoding="utf-8")
        print("wrote", d["file"])


if __name__ == "__main__":
    main()
