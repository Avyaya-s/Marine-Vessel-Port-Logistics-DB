# frontend/

React + Vite web app. It talks only to the FastAPI backend (`/api/...`), never to PostgreSQL directly.

## Run

The backend must be running first (see `backend/README.md`). Then, from the `frontend` folder:

```powershell
npm install        # once, or after package.json changes
npm run dev
```

Open http://localhost:5173. Vite forwards every `/api/...` request to the backend on port 8000 (see `vite.config.js`).

## Login

The app starts at a login page (demo accounts listed on it; see `backend/README.md`). The token is kept in `sessionStorage` (gone when the tab closes) and sent with every request; a 401 logs you out. Pages and buttons a role can't use are hidden, but **the backend is what enforces the rules**: hiding a button is only convenience.

## Pages

| Page | Shows | Database objects behind it |
|---|---|---|
| Dashboard | calls per status, berth occupancy, waiting times | `port_call`, `v_berth_occupancy`, `v_waiting_time` |
| Port Calls | every visit; **Allocate berth** button for calls with no berth | `allocate_berth()` |
| Customs | uncleared filings, riskiest first; **Clear** with a duty amount | `v_pending_customs`, `clear_customs()` |
| Ask the Database | plain-English question -> generated SQL + results | `/api/ask` (local LLM, read-only `nl_assistant`) |
| Upload B/L | upload a Bill of Lading PDF, review the extracted fields and HS suggestion, confirm to insert. `/upload?sample=<file>` runs a sample directly (demo link) | `/api/documents/*` |
| Live Map | placeholder for Phases 3-4 (MongoDB) | |

When the database rejects an action (trigger, CHECK or procedure error), the page shows the database's own message in a red banner.

## Files

| File | Contents |
|---|---|
| `src/App.jsx` | layout, sidebar, routes |
| `src/api.js` | `get` / `post` helpers; adds the login token; turns API errors into readable messages |
| `src/auth.jsx` | login state, `login` / `logout`, which role may see which page or button |
| `src/pages/Login.jsx` | login page |
| `src/useFetch.js` | load data when a page opens, `reload()` after a change |
| `src/format.js` | times in IST, durations, INR amounts |
| `src/components.jsx` | status and risk badges, notices, sections |
| `src/charts.jsx` | berth timeline, segmented bar, ranked bars, meter list, tooltips (plain HTML/CSS, no chart library) |
| `src/pages/` | one file per page |
| `src/styles.css` | all styling; light and dark theme via CSS variables |
