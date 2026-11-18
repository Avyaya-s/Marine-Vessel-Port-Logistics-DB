# backend/

FastAPI server between the React frontend and PostgreSQL. It runs SQL against the views and stored procedures in `database/`; it contains no business rules of its own (those live in the database's constraints, triggers and procedures).

## Setup (once)

PowerShell, from the `backend` folder:

```powershell
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements.txt
copy .env.example .env
```

Open `.env` and replace `YOUR_PASSWORD` with your postgres password, and `NL_PASSWORD` with the `nl_assistant` password (needed only for the Ask page). `.env` is git-ignored, so the passwords never reach GitHub.

The Ask and Upload pages also need **Ollama** running with `qwen2.5:7b` and `nomic-embed-text` (`ollama pull qwen2.5:7b`, `ollama pull nomic-embed-text`).

## Run

```powershell
.venv\Scripts\python -m uvicorn main:app --reload
```

- API: http://127.0.0.1:8000
- Interactive docs (try every endpoint in the browser): http://127.0.0.1:8000/docs

`--reload` restarts the server automatically when a `.py` file changes.

## Endpoints

| Method | Path | What it does | Database object |
|---|---|---|---|
| GET | `/api/health` | API is up and can reach the DB | |
| GET | `/api/port-calls` | all port calls with vessel, agent, berth | `port_call` + joins |
| GET | `/api/port-calls/summary` | count of calls per status | `port_call` |
| POST | `/api/port-calls/{call_id}/allocate` | book the earliest suitable berth | `allocate_berth()` |
| GET | `/api/berths` | who is at each berth now, who is next | `v_berth_occupancy` |
| GET | `/api/waiting-times` | waiting time, delays, ETA errors | `v_waiting_time` |
| GET | `/api/customs/pending` | uncleared filings, riskiest first | `v_pending_customs` |
| POST | `/api/customs/{filing_no}/clear` | clear a filing (body: `{"duty": 345000}`) | `clear_customs()` |
| POST | `/api/ask` | plain-English question -> SQL -> rows (body: `{"question": "..."}`) | local LLM + `nl_assistant` role |
| GET | `/api/ask/info` | which LLM model is used | |
| POST | `/api/documents/extract` | upload a B/L PDF (multipart `file`) -> fields, checks, HS suggestions (nothing saved) | read-only checks |
| POST | `/api/documents/confirm` | insert the reviewed shipment (one transaction) | `company`, `shipment`, `container`, `shipment_container` |
| GET | `/api/documents/hs-suggest?q=` | HS code suggestions for a description | `data/hs_codes.csv` |
| GET | `/api/documents/samples` | list / download the sample B/L PDFs | `data/sample_docs/` |

When the database rejects a change (trigger, CHECK, or procedure error), the API returns **HTTP 400** with the database's own message, e.g. `"Port call 5 already has berth B05"`. The transaction has already been rolled back.

## Files

| File | Contents |
|---|---|
| `main.py` | app setup, CORS, routers |
| `db.py` | connection pool, `fetch_all` / `fetch_one`, DB error → HTTP 400 |
| `routers/port_calls.py`, `berths.py`, `customs.py`, `ask.py` | the endpoints |
| `services/llm.py` | Ollama calls shared by the NLP features (chat with JSON schema, embeddings) |
| `services/nl_query.py` | NL assistant: prompt, SQL safety check, read-only execution |
| `services/documents.py` | B/L upload: PDF text, LLM + regex extraction, checks, transactional insert |
| `services/hs_suggest.py` | HS code suggestion by embedding similarity |
| `eval_nl.py` | NL assistant evaluation (accuracy + safety); see `docs/nl_assistant.md` |
| `eval_docs.py` | document extraction + HS suggestion evaluation; see `docs/document_upload.md` |
