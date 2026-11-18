# frontend/

React + Vite web app. It talks only to the FastAPI backend (`/api/...`), never to PostgreSQL directly.

## Run

The backend must be running first (see `backend/README.md`). Then, from the `frontend` folder:

```powershell
npm install        # once, or after package.json changes
npm run dev
```

Open http://localhost:5173. Vite forwards every `/api/...` request to the backend on port 8000 (see `vite.config.js`).

## Pages

| Page | Shows | Database objects behind it |
|---|---|---|
| Dashboard | calls per status, berth occupancy, waiting times | `port_call`, `v_berth_occupancy`, `v_waiting_time` |
| Port Calls | every visit; **Allocate berth** button for calls with no berth | `allocate_berth()` |
| Customs | uncleared filings, riskiest first; **Clear** with a duty amount | `v_pending_customs`, `clear_customs()` |
| Ask the Database | plain-English question -> generated SQL + results | `/api/ask` (local LLM, read-only `nl_assistant`) |
| Live Map, Upload | placeholders for Phases 3-4 (MongoDB) and 7 (document extraction) | |

When the database rejects an action (trigger, CHECK or procedure error), the page shows the database's own message in a red banner.

## Files

| File | Contents |
|---|---|
| `src/App.jsx` | layout, sidebar, routes |
| `src/api.js` | `get` / `post` helpers; turns API errors into readable messages |
| `src/useFetch.js` | load data when a page opens, `reload()` after a change |
| `src/format.js` | times in IST, durations, INR amounts |
| `src/components.jsx` | status and risk badges, notices, sections |
| `src/charts.jsx` | berth timeline, segmented bar, ranked bars, meter list, tooltips (plain HTML/CSS, no chart library) |
| `src/pages/` | one file per page |
| `src/styles.css` | all styling; light and dark theme via CSS variables |
