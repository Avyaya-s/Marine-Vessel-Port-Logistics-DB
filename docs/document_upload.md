# Document Upload (Bill of Lading → shipment)

Upload a Bill of Lading PDF; the system extracts the fields, suggests an HS code, runs checks against the database, and inserts the shipment only after the user reviews and confirms it.

Files: `backend/services/documents.py` (pipeline), `backend/services/hs_suggest.py` (HS suggestion), `backend/services/llm.py` (Ollama calls), `backend/routers/documents.py` (API), `backend/eval_docs.py` (evaluation), `frontend/src/pages/Upload.jsx` (page), `data/hs_codes.csv` (HS reference list), `data/make_sample_docs.py` + `data/sample_docs/` (sample documents).

---

## 1. Pipeline

```
PDF ─► pdfplumber: text layer        (no text? scanned image → asked to enter manually; OCR not installed yet)
    ─► LLM (qwen2.5:7b) with a JSON schema → fields  (shipper, consignee, vessel, cargo, weight + unit, …)
    ─► regex: container numbers       (exact ISO 6346 pattern; the LLM's list is only used for type/seal)
    ─► Python: tonnes/lbs → kg, HS digits only, strip "240 CARTONS" leaking into the description
    ─► checks against the database    (B/L already exists? companies known? which manifest? formats valid?)
    ─► HS suggestion: embeddings of the description vs data/hs_codes.csv (top 3)
    ─► user reviews and edits the form
    ─► Confirm: ONE transaction        (new companies + shipment + containers + links)
```

## 2. Design choices

| Choice | Why | Alternative |
|---|---|---|
| **LLM for field extraction** | Bills of Lading from different companies use different layouts and labels ("Shipper" vs "Exporter", "Vessel" vs "Ocean Vessel"); the LLM handles any wording | Regex per field per layout: breaks on every new template |
| **Structured output (JSON schema)** | The model must reply with exactly these fields and types, so the result is parsed safely, never free text | Asking for JSON in the prompt and hoping |
| **Regex for container numbers** | The format is exact (4 letters + 7 digits), so a pattern is 100% reliable and can't invent numbers; containers the model "finds" that aren't in the text are discarded with a warning | Trusting the LLM's list |
| **"The LLM reads, the code computes"** | Unit conversion (24.6 MT → 24,600 kg) and cleaning are done in Python, deterministically | Letting the model do arithmetic |
| **Human confirmation before insert** | Extraction can be wrong; nothing reaches the database until a person checks it | Auto-insert |
| **Checks against the database** | Catches duplicates, matches companies to existing IDs, finds the manifest from the vessel name, flags wrong-type companies | Only format checks |
| **One transaction on confirm** | If any row is rejected, nothing is saved: no half-created companies | Separate inserts |
| **Database constraints still apply** | Container format CHECKs, company-role triggers, the shipment primary key all validate the insert | Validating only in Python |
| **HS codes by embedding search** | Ranks codes that exist in the reference list, so it **cannot invent a code**; matches meaning, not exact words ("spanners and wrenches" → "Adjustable hand spanners") | Asking a chat model for a code (can hallucinate plausible-looking but wrong codes) |
| **HS list as a CSV, not a table** | Reference data, not port data; the schema is settled | A new `hs_code` table |
| **Printed HS code cross-check** | If the printed code doesn't match the description's suggestions, a warning asks the user to check it | Trusting the printed code |

## 3. Evaluation (`backend/eval_docs.py`)

Three generated Bills of Lading in **two different layouts** (different labels, weight in KGS vs MT, HS code printed with dots / without / missing).

| Measure | Result |
|---|---|
| Field accuracy (9-10 fields per document, incl. containers with type and seal) | **29 / 29 = 100 %** |
| HS suggestion, correct code ranked first (9 cargo descriptions) | **9 / 9** (hit@1) |
| Time per document | about 7-8 s (LLM extraction); HS suggestion about 40 ms |

How it got there:

| Version | Field accuracy | Problem fixed |
|---|---|---|
| First run | 28 / 29 | In Layout A the description wraps across table rows; the model merged "240 CARTONS" into it |
| Clearer prompt rule | 28 / 29 | The 7b model still merged it |
| Deterministic clean-up (regex removes "<n> CARTONS/PALLETS/…") | **29 / 29** | Fixed in code, not by more prompting |

API tests: duplicate B/L flagged on upload and rejected on confirm (primary key); a broken container number on confirm is rejected by the CHECK constraint and **no new companies are left behind** (whole transaction rolled back); non-PDF files and path tricks on the sample endpoint are refused.

**Limitations:** three generated documents are an indicative test, not a benchmark; real scanned B/Ls need OCR (Tesseract, not installed yet); the HS list has 65 common headings; semantically close but wrong codes are possible ("used tyres" → "new tyres"), which is why the user confirms the code.

## 4. Issues faced

1. **Windows `localhost` delay:** every Ollama call took about 2 s extra because `localhost` tries IPv6 (`::1`) first and Ollama only listens on IPv4. Using `127.0.0.1` cut HS suggestion from 2,073 ms to about 40 ms (and sped up the NL assistant too). Found by comparing Ollama's own timing (49 ms) with the time measured in Python.
2. **The sample generator's own layout bugs** (overlapping columns, addresses cut mid-word) showed up in the extracted text, so always look at what the PDF reader actually returns.
3. **React StrictMode runs effects twice in development**, so the demo deep-link uploaded the sample twice (17 s instead of 8). Fixed with a `useRef` guard.
4. **New Python packages crash a `--reload` server** until they are installed in its virtual environment (`pip install -r requirements.txt`).
