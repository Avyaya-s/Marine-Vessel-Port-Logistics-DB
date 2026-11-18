"""Evaluate document extraction and HS suggestion (run from the backend folder):

    .venv\\Scripts\\python eval_docs.py

1. Field accuracy: each sample PDF in data/sample_docs is extracted and every
   field is compared with <name>.expected.json (written by
   data/make_sample_docs.py).  Run on the sample data (database/rebuild.sql).
2. HS suggestion: hit@1 / hit@3 for known cargo descriptions (the 6 sample
   shipments in the database plus the 3 sample documents).
"""

import json
import time
from pathlib import Path

from db import close_pools, pool
from services import documents, hs_suggest

SAMPLES = Path(__file__).resolve().parents[1] / "data" / "sample_docs"
FIELDS = ["shipment_no", "vessel_name", "shipper_name", "consignee_name", "origin_port",
          "cargo_description", "cargo_quantity", "gross_weight"]

HS_TESTS = [   # description -> correct 6-digit HS heading
    ("Lithium-ion battery packs", "850760"),
    ("LED television panels", "852872"),
    ("Cotton bed linen", "630221"),
    ("CNC milling machines", "845961"),
    ("Hydraulic pumps", "841360"),
    ("Steam coal in bulk", "270112"),
    ("Industrial ball bearings, assorted sizes", "848210"),
    ("Solar photovoltaic panels, 550W monocrystalline modules", "854143"),
    ("Hand tools: adjustable spanners and wrenches, chrome vanadium steel", "820412"),
]


def same(a, b):
    if isinstance(b, float):
        return abs(float(a or 0) - b) < 0.01
    return str(a).strip().lower() == str(b).strip().lower()


def main():
    pool.open()
    total = right = 0
    for pdf in sorted(SAMPLES.glob("*.pdf")):
        exp = json.loads(pdf.with_suffix("").with_suffix(".expected.json").read_text(encoding="utf-8"))
        exp["shipment_no"], exp["gross_weight"] = exp["bl_number"], exp["gross_weight_kg"]
        t = time.perf_counter()
        r = documents.extract(pdf.read_bytes())
        secs = time.perf_counter() - t
        f = r["fields"]
        print(f"\n== {pdf.name}  [{secs:.1f}s]")
        for k in FIELDS:
            ok = same(f[k], exp[k])
            total += 1; right += ok
            print(f"  {'OK  ' if ok else 'MISS'} {k:18} {f[k]!r}" + ("" if ok else f"   expected {exp[k]!r}"))
        got = [(c["container_no"], c["iso_type"], c["seal_no"]) for c in r["containers"]]
        want = [(c["container_no"], c["iso_type"], c["seal_no"]) for c in exp["containers"]]
        total += 1; right += got == want
        print(f"  {'OK  ' if got == want else 'MISS'} {'containers':18} {got}" + ("" if got == want else f"   expected {want}"))
        if exp["hs_code"]:
            ok = f["hs_code"] == exp["hs_code"]
            total += 1; right += ok
            print(f"  {'OK  ' if ok else 'MISS'} {'hs_code (printed)':18} {f['hs_code']!r}")
        for c in r["checks"]:
            print(f"     [{c['level']}] {c['text']}")
    print(f"\nField accuracy: {right}/{total} = {right / total:.0%}")

    hit1 = hit3 = 0
    for desc, gold in HS_TESTS:
        codes = [s["hs_code"] for s in hs_suggest.suggest(desc)]
        hit1 += codes[:1] == [gold]
        hit3 += gold in codes
    print(f"HS suggestion: hit@1 {hit1}/{len(HS_TESTS)}, hit@3 {hit3}/{len(HS_TESTS)}")
    close_pools()


if __name__ == "__main__":
    main()
