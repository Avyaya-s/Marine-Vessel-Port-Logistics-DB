# Interview Notes

All the "notes to write down" from building the project, step by step, in the order they were built.
Each step lists what was built, why, what alternatives were rejected, and the real issues faced.

Related documents: `docs/phase1_summary.md` (database overview), `docs/normalization.md`, `docs/nl_assistant.md`.

---

## Contents

1. [Setup: PostgreSQL and pgAdmin](#1-setup-postgresql-and-pgadmin)
2. [Step 1: Schema and double-booking trigger](#2-step-1-schema-and-double-booking-trigger)
3. [Git and GitHub](#3-git-and-github)
4. [Step 2a: Berth-fit trigger](#4-step-2a-berth-fit-trigger)
5. [Step 2b: allocate_berth() procedure](#5-step-2b-allocate_berth-procedure)
6. [Step 3: Status trigger and the atb column](#6-step-3-status-trigger-and-the-atb-column)
7. [Step 4: Views](#7-step-4-views)
8. [Step 5: Customs clearance transaction](#8-step-5-customs-clearance-transaction)
9. [Step 6: Read-only user and company roles](#9-step-6-read-only-user-and-company-roles)
10. [Step 7: Normalization](#10-step-7-normalization)
11. [Step F1: FastAPI backend](#11-step-f1-fastapi-backend)
12. [Step F2: React frontend and dashboard](#12-step-f2-react-frontend-and-dashboard)
13. [NLP: Natural-language query assistant](#13-nlp-natural-language-query-assistant)
14. [NLP: Document upload (Bill of Lading)](#14-nlp-document-upload-bill-of-lading)
15. [Login and roles](#15-login-and-roles)
16. [One database, many stakeholders](#16-one-database-many-stakeholders)
17. [All issues faced (quick list)](#17-all-issues-faced-quick-list)

---

## 1. Setup: PostgreSQL and pgAdmin

1. **PostgreSQL 18** on Windows (the project needs 16+).
2. **PostgreSQL is the server**: a background Windows service listening on **port 5432**. **pgAdmin 4** (graphical) and **psql** (command line) are **clients** that connect to it.
3. **Stack Builder** is an optional add-on installer; not needed.
4. `postgres` is the default **superuser**. The `postgres` *database* is the default system database; project data goes in its own database, `port_logistics`.
5. pgAdmin's **Query Tool** runs SQL (F5). Results appear in **Data Output**, success/error/NOTICE messages in **Messages**.
6. **`public` is the default schema**: a namespace inside the database. Full name of a table: `port_logistics.public.vessel`.
7. **`information_schema`** is the database describing itself: built-in views listing every table, column and constraint (part of the SQL standard). The NL assistant uses it to tell the LLM which tables and columns exist.
8. **Load order matters**: tables before triggers, triggers before data. Parent tables must exist before child tables reference them.
9. The first run of `schema.sql` prints "does not exist, skipping" NOTICEs. That's normal: the script drops old objects before creating them, which makes it **re-runnable**.
10. If new tables don't appear in pgAdmin's tree: right-click → **Refresh**.

---

## 2. Step 1: Schema and double-booking trigger

### Design decisions
1. **Constraints first, triggers only when needed.** "At most 2 manifests per port call" is just `UNIQUE (call_id, manifest_type)`: with only two types (IGM, EGM), a third manifest always repeats one.
   > "I use a trigger only when a constraint can't express the rule. Constraints are faster, can't be bypassed, and the optimizer can use them."
2. **IMO number check digit** validated by `is_valid_imo()` inside a CHECK: digits 1-6 × 7,6,5,4,3,2; the last digit of the sum must equal digit 7. Marked `IMMUTABLE` because PostgreSQL only allows immutable functions in a CHECK.
3. **IMO and MMSI stored as text**, not integers: they are identifiers (no arithmetic), and text keeps leading zeros and fixed length.
4. **A `DOMAIN` called `cargo_category`** is shared by `vessel.vessel_type` and `berth.cargo_type`, so both use the same words and ships can be matched to berths.
5. **`TIMESTAMPTZ` everywhere**: AIS data is UTC, the port runs on IST. PostgreSQL stores UTC internally and converts for display.
6. **Foreign keys are not indexed automatically** (primary keys and UNIQUE are). Added `port_call(berth_number, berth_start)` because the overlap trigger and `allocate_berth` search on it.
7. **Weak entity**: INSPECTION's key is `(filing_no, inspection_no)` with `ON DELETE CASCADE`, because an inspection can't exist without its filing.
8. **1:1 relationship**: `customs_filing.shipment_no` is a FK with `UNIQUE`.
9. **Real formats validated**: container number (4 letters + 7 digits, ISO 6346), UN/LOCODE origin port (`CNSHA`), HS code (6 or 8 digits; India uses 8-digit ITC-HS), IEC (10 characters).
10. **Foreign keys store IDs; JOINs bring back names.** Copying names into `port_call` would duplicate data and cause **update anomalies**.

### The double-booking trigger
11. **Why a trigger, not a CHECK**: a CHECK sees only one row; overlap needs comparing against *other* rows.
12. **Overlap test**: `A.start < B.end AND B.start < A.end`, with half-open windows `[start, end)`, so back-to-back bookings (leave 10:00, arrive 10:00) are allowed. A booking with no end is open-ended: `COALESCE(berth_end, 'infinity')`.
13. **Race condition (strong interview point)**: two transactions could both check, see no clash, and both insert. Fixed by locking the berth row first (`SELECT ... FOR UPDATE`), so bookings for the same berth run one at a time.
14. **Alternative**: `EXCLUDE USING gist (berth_number WITH =, tstzrange(berth_start, berth_end) WITH &&)` with `btree_gist`: declarative and concurrency-safe. Chose a trigger because the lab asks for one and it gives a readable error naming the clashing call.

### Testing
15. Tests are SQL scripts inside **`BEGIN ... ROLLBACK`**; helper functions catch the expected exception and print PASS/FAIL. They test both **rejections** (negative cases) and **acceptances** (positive cases), and can be re-run without changing data.
16. **Demo tip**: show a rejected double booking live. A readable error ("already booked by call 2 from ... to ...") demos better than a generic constraint error.

### Issues faced
17. **Sequences don't roll back**: after a rolled-back test, the next call_id was 12, not 7. Sequence numbers are handed out outside transactions so concurrent inserts never wait on each other. Gaps are normal; IDs carry no meaning.
18. **Times showed in UTC** (`08:30+00` instead of `14:00+05:30`). The stored instant was correct; fixed the display with `ALTER DATABASE ... SET timezone TO 'Asia/Kolkata'`.

---

## 3. Git and GitHub

1. **`.gitignore`** stops files being tracked. Most important line: **`.env`** (passwords and API keys must never reach GitHub; public repos are scanned by bots within minutes). Large rebuildable files (`node_modules`, models, datasets) are excluded too.
2. **Schema as code**: the SQL files are the source of truth, not the database. Anyone can rebuild the exact database by running them.
3. **Commit after each working step**, with a message saying what changed. A clean history shows how the project evolved and lets you go back.
4. **`main`** is the default branch. Later each person can work on a feature branch and merge.
5. **`-u` (upstream)**: the first `git push -u origin main` links the local branch to the remote; afterwards plain `git push` / `git pull` work.
6. **`git mv`** renames a file and records the rename in one step (history shows a rename, not delete + add).

### Issues faced
7. **`.gitignore.txt`**: Windows Notepad added a hidden `.txt` extension, so Git ignored nothing. Caught with `git ls-files`. Lesson: turn on file extensions in Explorer and check what's actually committed.
8. **"Repository moved"** on push: the username's capitalisation differed in the URL. Fixed with `git remote set-url`.

---

## 4. Step 2a: Berth-fit trigger

1. **What it does**: rejects a booking if the ship's LOA > berth `max_loa` or draft > `max_draft`. A ship exactly at the limit is allowed (`>` not `>=`); a test checks this edge case.
2. **Why a trigger, not a CHECK**: the rule needs data from two other tables (`vessel`, `berth`).
3. **Only physical limits, not cargo type**: a ship that's too big physically cannot fit; cargo type is a **planning preference** handled by `allocate_berth()`. *Separate hard rules (the database refuses) from soft rules (the planner prefers).*
4. **Fires on `imo_number` too**: swapping the ship on an existing booking must be re-checked. Think about every way the data can change.
5. **Trigger firing order**: triggers for the same event fire in **alphabetical order by name**, so `check_berth_fit` runs before `check_berth_overlap`.
6. **Known limitation**: editing `vessel.loa` or `berth.max_loa` later doesn't re-check existing bookings (the trigger watches `port_call` only). In real ports, draft limits also need a safety margin (**under-keel clearance**).

### Issues faced
7. **Regression**: the new trigger made an old test fail. That test had always put a 300 m ship on a 200 m berth; nothing checked it before. Re-running *all* tests after a change catches hidden bad data.
8. **Copy-paste glitches**: duplicated lines caused `syntax error at or near "INSERT"`. A missing closing `$q$` swallows everything after it.
9. **A syntax error stops the whole script**: Postgres parses the whole batch before running any of it. A *runtime* error is different: earlier statements have run, and inside `BEGIN` the transaction is aborted until `ROLLBACK`.
10. **`$q$ ... $q$` is dollar quoting**: a string that can contain single quotes without escaping.

---

## 5. Step 2b: allocate_berth() procedure

1. **What it does**: books the earliest free berth matching the ship's cargo type, LOA and draft. Ties go to the **smallest suitable berth** (best fit), keeping big berths free for big ships.
2. **Key algorithm idea**: the earliest free slot always starts either when the ship is ready or when an existing booking ends, so only those few start times are checked, not every minute.
3. **Order of trust for arrival time**: `ata` (arrived) > `predicted_eta` (ML) > `eta` (agent). A **SQL–ML integration point**: a better ETA model gives better berth plans.
4. **Procedure vs function**: a `PROCEDURE` is run with `CALL`, performs an action, returns results through `INOUT` parameters and can manage transactions. A `FUNCTION` is used inside queries to compute a value.
5. **Concurrency**: the call row is locked (`FOR UPDATE`); candidate berths are locked **in a fixed order** (`ORDER BY berth_number`). A fixed lock order prevents **deadlocks** (two sessions each holding one lock, waiting forever for the other's).
6. **Defence in depth**: the procedure *chooses* a slot; the triggers still *guarantee* the rules on the final UPDATE.
7. **SQL features used**: `CROSS JOIN LATERAL` (a subquery run once per row), `UNION` (merge candidate lists without duplicates), `NOT EXISTS` (anti-join), `ORDER BY ... LIMIT 1` (pick the best), `COALESCE` (fallbacks).
8. **Savepoints in tests**: `SAVEPOINT` / `ROLLBACK TO SAVEPOINT` undo one test's changes without ending the transaction, so every test starts from the same data.
9. **Limitations**: stay length is a parameter (default 24 h), not predicted; no tides, cranes or priority ships; it's a **greedy** first-come-first-served algorithm, not a global optimum.

### Issues faced
10. **False-positive tests**: error tests "passed" because of an unrelated error (`o_berth is an output parameter but corresponding argument is not writable`; in PL/pgSQL, INOUT arguments must be variables). Lesson: **error tests must check *which* error happened.**
11. **Copying code out of the terminal corrupted it**: long lines were cut at ~50 characters and chunks duplicated, giving `syntax error at or near "ready"`. Found with `diff`; fixed by writing files directly. When errors look impossible, check the file contains what you think. **Error line numbers point to where the parser got confused, not always to the mistake.**

---

## 6. Step 3: Status trigger and the atb column

1. **Design problem**: a trigger fires on **data changes, not on clock time**. "Set Berthed at berth_start" can't work, because `berth_start` is filled when the berth is *booked*, not when the ship arrives.
2. **Solution: separate plans from facts.** Plans (`eta`, `predicted_eta`, `berth_start`, `berth_end`) can change or be missed. Facts (`ata`, `atb`, `atd`) are recorded when events happen. Added **`atb` (Actual Time of Berthing)**, a standard port term (ETA/ATA, ETB/ATB, ETD/ATD).
3. **Status derived from facts**: `atd` → Departed, else `atb` → Berthed, else `ata` → Waiting, else Expected.
4. **CHECKs compare facts with facts**: `ata ≤ atb ≤ atd` must always hold. A ship arriving later than planned is normal, not an integrity violation.
5. **`call_status` is controlled redundancy**: it could be computed, but it's stored so dashboards can filter and index it cheaply; the trigger guarantees it never disagrees with the facts.
   > "Denormalization is fine when the database itself enforces consistency."
6. **Reject rather than silently override**: a manual status that contradicts the facts raises an error with a HINT.
7. **New metrics**: waiting time = `atb − ata`; berthing delay = `atb − berth_start`.
8. **`IS DISTINCT FROM`**: NULL-safe "not equal" (`NULL <> 'x'` is NULL/unknown; `NULL IS DISTINCT FROM 'x'` is TRUE).
9. **`TG_OP`**: trigger variable holding `'INSERT'`, `'UPDATE'` or `'DELETE'`.

### Issue faced
10. Two Step 1 CHECKs compared plans with facts (`berth_start >= ata`, `atd >= berth_end`) and would have rejected every late ship. Caught while designing this step and replaced.

---

## 7. Step 4: Views

1. **A view is a stored query, not stored data**: it re-runs on every SELECT, so derived values are never stale and never stored twice. That's why `waiting_time` lives in a view.
2. **Why views**: simplicity (frontend runs `SELECT * FROM v_pending_customs`, not a 6-table join), one definition of each metric, and security (the read-only user can be limited to views).
3. **View vs materialized view**: a view recomputes every time (always fresh); a materialized view stores the result and needs `REFRESH` (fast, can be stale). Freshness matters more at this data size.
4. **`LEFT JOIN LATERAL ... LIMIT 1`** picks one related row per berth (current ship, next ship); `LEFT` keeps berths with no ship.
5. **`LEFT JOIN` vs `JOIN`**: a filing with no inspections must still appear; a plain `JOIN` would silently drop it (classic bug, tested).
6. **`ORDER BY ... DESC NULLS LAST`**: riskiest first, unscored last. `ORDER BY` inside a view is only a default.
7. **Intervals vs numbers**: `atb − ata` is an `INTERVAL` (`02:50:00`); `EXTRACT(EPOCH FROM ...)/3600` gives hours (`2.83`) for charts and ML.
8. **`DROP TABLE ... CASCADE` drops dependent views**, so `views.sql` must be re-run after `schema.sql`.
9. **psql vs pgAdmin**: `\ir` (include a file) is psql-only, so `rebuild.sql` and `run_tests.sql` run in the terminal, not pgAdmin.

---

## 8. Step 5: Customs clearance transaction

1. **ACID with this project**:
   - **Atomicity**: filing Cleared + duty recorded + containers Released, all or nothing.
   - **Consistency**: never a "Cleared" filing with stuck containers.
   - **Isolation**: changes are visible only to the session until COMMIT.
   - **Durability**: committed data survives a crash (written to the **WAL**, write-ahead log, first).
2. **A procedure call is automatically one transaction**: if `CALL` raises an error, every change it made is rolled back.
3. **The failure is checked after the updates on purpose**: steps 1-2 run, step 3 finds a container still on board, and atomicity undoes 1-2. That proves atomicity undoes work that *already happened*.
4. **Validate up front vs rely on atomicity**: cheap checks first for clear messages; atomicity is the real guarantee for unexpected errors.
5. **`FOR UPDATE` row lock** prevents a **lost update** when two officers clear the same filing at once.
6. **`GET DIAGNOSTICS ... = ROW_COUNT`** returns how many rows the last UPDATE changed.
7. **Business rules**: a pending/failed inspection blocks clearance; a Held filing clears after a new Clear inspection; exports (Shipping Bills) don't release containers.
8. **Testing atomicity**: check state **before**, the call **fails with the right message**, and state **after** is identical.

### Issue faced
9. A Windows path in a Python string was corrupted: `\b` is the backspace escape. Use raw strings `r"..."` or forward slashes.

---

## 9. Step 6: Read-only user and company roles

### Read-only user (nl_assistant)
1. **Never trust LLM-generated SQL**: the account it runs under is the real guarantee. **Principle of least privilege.**
2. **Defence in depth, three layers**: SELECT-only privileges; read-only transactions by default; 5 s statement timeout + 5 connection limit.
3. **Group role vs login role**: privileges go to `port_readonly` (NOLOGIN); `nl_assistant` is a member. A second read-only app just joins the group.
4. **Roles belong to the server; grants belong to objects**: dropping tables drops their grants, so `rebuild.sql` re-runs `roles.sql`; `ALTER DEFAULT PRIVILEGES` covers future tables.
5. **Procedures are executable by `PUBLIC` by default**; revoked so only admins can allocate berths or clear customs.
6. **`statement_timeout`** stops a runaway LLM query (accidental cross join) from hogging the server (a denial-of-service concern).
7. **Secrets never go in Git**: the password lives in `.env`.

### Company roles (triggers T4, T5)
8. **A foreign key checks existence, not meaning**: `agent_id → company` doesn't prove the company is an agent. Needs a trigger.
9. **Enforce rules from both sides**: T4 checks the referencing tables; T5 stops a used company's type from changing.
10. **Declarative alternative**: a constant generated column + **composite foreign key** `(agent_id, agent_type) → company(company_id, company_type)`. Enforces both directions without triggers but adds columns.
11. **NULL trick**: `NULL <> 'agent'` isn't TRUE, so a missing company skips the check and the foreign key reports it.

---

## 10. Step 7: Normalization

1. **Normal forms**: 1NF atomic values, no repeating groups; 2NF no partial dependency on a composite key; 3NF no transitive dependency; BCNF every determinant is a candidate key.
2. **Result**: 8 of 10 tables in BCNF; CONTAINER and PORT_CALL are 2NF **by design**, with the database guaranteeing consistency.
3. **Transitive dependency found**: `container_no → iso_type → size` (first character of the ISO code: 2 = 20 ft, 4 = 40 ft, L = 45 ft).
4. **Fix used: a generated column**: `size GENERATED ALWAYS AS (CASE left(iso_type,1) ...) STORED`. It can't be inserted or updated by hand, so it can never be wrong.
5. **Why it removes the anomalies**: the rule lives once, in the schema, not repeated in data, so no update anomaly (can't be typed wrong), no insertion anomaly (new codes work immediately), no deletion anomaly (deleting containers loses nothing).
6. **Not strictly 3NF**: the FD `iso_type → size` still exists inside CONTAINER, but the redundancy is computed by the database, so it's harmless.
7. **Alternative (saved in `git stash` for later)**: an ISO_TYPE lookup table. Textbook 3NF: **lossless** (join attribute is the key of the new table) and **dependency-preserving**, can store a description per type; costs an extra table and ER entity.
8. **Controlled redundancy**: `call_status` depends on `ata/atb/atd` but is stored for fast filtering, kept correct by a trigger.
9. **Derived attributes aren't stored**: waiting time, delays, ETA errors, days pending are all in views.
10. **Two candidate keys**: VESSEL (IMO and MMSI), SHIPPING_MANIFEST (manifest_no, and call_id + manifest_type).
11. **Entity count**: 11 entity types (9 in PostgreSQL, 2 in MongoDB). SHIPMENT_CONTAINER is a **relationship** (M:N COVERS), not an entity.
12. **In ER terms**, a generated column is a **derived attribute** (dashed oval), like `waiting_time`.
13. **Git stash** saves uncommitted work outside history (`git stash push -m`, `git stash list`, `git stash apply`).

### Issue faced
14. With `size NOT NULL`, a bad code (`9XG1`) failed with the misleading "null value in column size", because **PostgreSQL checks NOT NULL before CHECK constraints**. Removed NOT NULL (the iso_type CHECK already guarantees a valid size), so the real error shows. Caught because the test checks *which* error occurs.

---

## 11. Step F1: FastAPI backend

1. **Why a backend**: a browser can't safely connect to PostgreSQL (the password would be in the page). The API holds the password server-side and exposes only specific operations.
2. **Thin backend**: business rules live in the database; the API just calls views and procedures, so every client gets the same rules.
3. **Connection pool**: opening a connection is slow; the pool keeps a few open and lends one per request.
4. **One request = one transaction**: `with pool.connection()` commits on success, rolls back on error.
5. **Errors map to HTTP codes**: database rule violation → **400** with the DB's own message; invalid input (negative duty) → **422** (FastAPI validates before the database).
6. **CORS**: the React dev server (5173) and API (8000) are different origins; the API must allow the frontend's origin.
7. **SQL injection prevented** by passing values as parameters (`%s`), never pasting them into the SQL string.
8. **`.env` + `.env.example`**: the real secrets file is git-ignored; the example shows teammates which settings exist.
9. **FastAPI `/docs`** is generated automatically (OpenAPI/Swagger): the API documents and tests itself.

### Issues faced
10. `procedure clear_customs(unknown, double precision) does not exist`: Python sent the duty as a float, and PostgreSQL doesn't implicitly convert float → numeric when choosing a procedure. **Fix**: `Decimal` for money (floats can't store 0.1 exactly) + explicit cast `%s::numeric`.
11. **The hidden `.txt` extension struck twice** (`.gitignore.txt`, then `.env.txt`), and the second time nearly **leaked the database password**: `.gitignore` matches exact names. Check secrets with `git check-ignore -v <file>` before committing.
12. A cleanup command would have killed **every Python process** on the machine; the safety check blocked it. Stop only the exact process, by its PID (`netstat -ano`).

---

## 12. Step F2: React frontend and dashboard

1. **Architecture**: React (browser) → FastAPI → PostgreSQL. The frontend has no business rules; it displays what the database decides.
2. **Vite dev proxy**: the page calls `/api/...`; Vite forwards to port 8000, so no CORS issues and no hard-coded API URL.
3. **React basics used**: components (one file per page), `useState`, `useEffect`, and a custom hook `useFetch` (loading, errors, `reload()`).
4. **After a change, reload from the database**: the database is the **single source of truth**; the page never guesses the new state.
5. **Errors surface to the user**: DB error → HTTP 400 → `api.js` throws → red banner. The rollback is visible.
6. **Times**: the API sends ISO timestamps; the frontend always formats them in `Asia/Kolkata`.
7. **Placeholder pages** ("soon") show the roadmap inside the product.

### Dashboard redesign (after a reference template)
8. **Pick the chart by the data's job, not looks**: a **timeline** for the berth schedule, **ranked bars** for waiting times, **meters** for risk scores, a **segmented bar** for the status split (not a donut; donuts are poor for comparing parts).
9. **No chart library**: charts are HTML `div`s positioned with percentages (`left = (start − from) / span × 100%`). Fewer dependencies, full control, easy to explain.
10. **Accessibility**: colour plus a word or icon everywhere; a table view for the timeline; tooltips on hover **and** keyboard focus; colours checked for colour-blind safety with a validator script.
11. **Theme tokens**: all colours are CSS variables; dark mode only swaps values (`data-theme="dark"`); the choice is saved in `localStorage` inside `try/catch`.
12. **Refresh by remounting**: bumping a React `key` remounts the page so it re-fetches everything.
13. **Timeline talking point**: bars on a berth row can never overlap, because the double-booking trigger forbids it.

---

## 13. NLP: Natural-language query assistant

1. **Pipeline**: question → prompt (live schema + glossary + value hints + rules + 3 examples) → local LLM → extract SQL → safety check → run as read-only role → self-correct once on a SQL error → show SQL + results.
2. **Never trust the LLM; three safety layers**: prompt rules, a Python safety check (one statement, SELECT/WITH only, no write keywords), and the **database role itself** (the real guarantee). Deliberately **no fallback** to the admin connection.
3. **Why local (Ollama)**: free, no API key, works offline, data never leaves the machine.
4. **Why qwen2.5:7b over 14b**: 7b fits entirely in the 8 GB GPU (~4 s/question); 14b spills to CPU (~15 s), and 7b scored higher (**86% vs 79%**). Bigger isn't automatically better.
5. **Prompt engineering, measured**: baseline 64% → 71% (glossary for "waiting", real code values) → 86% (keep queries simple). Each change fixed an observed failure.
6. **Schema from `information_schema`**: the prompt is built from the live database, so it never goes stale.
7. **Value hints**: the model guessed Rotterdam as `NLDRT`; giving it the real values (`NLRTM`) fixed it. LLMs can't guess your data's codes.
8. **Ambiguity is the hardest part**: "waiting" = a status (at anchor now) *and* a duration (waiting time). INSPECTION is a weak entity, so it needs `filing_no` to be identified.
9. **Evaluation**: *execution accuracy* (compare result rows with a hand-written gold query) on questions **held out** from the prompt's examples, plus an adversarial safety test checking row counts before/after.
10. **Temperature 0**: deterministic output, so the demo and evaluation are repeatable.
11. **Showing the generated SQL**: users and examiners can check *how* an answer was produced (trust).

### Issues faced
12. The 14b model was very slow: it didn't fit the GPU, and the first (cold) load took 2 minutes.
13. A prompt-edit script silently wrote nothing (escaping bug); noticed because the second evaluation's numbers were identical to the first.
14. `.env` changes need a **server restart**: `--reload` only watches `.py` files.

---

## 14. NLP: Document upload (Bill of Lading)

1. **Pipeline**: PDF → pdfplumber text → LLM fields (JSON schema) + regex containers → Python normalisation → database checks → HS suggestion → user confirms → one transaction.
2. **Hybrid extraction, each tool where it's reliable**: the LLM reads messy, varied layouts; **regex** finds container numbers (exact format, can't be invented); **Python** does arithmetic (tonnes → kg). *"The LLM reads, the code computes."*
3. **Structured output**: the model is forced to reply with JSON matching a schema (fixed fields and types), so it's parsed safely.
4. **Human in the loop**: nothing is inserted until a person reviews and confirms; the page shows every check and the raw text.
5. **Checks against the database**: duplicate B/L, companies matched to existing IDs (or flagged as new), wrong-type companies, manifest found from the vessel name, format checks (UN/LOCODE, ISO type).
6. **One transaction on confirm**: companies + shipment + containers + links. Tested: a bad container number made the whole insert roll back, with no new companies left behind. The database's CHECKs and triggers still validate every row.
7. **HS suggestion = semantic search**: embeddings (`nomic-embed-text`) of the description vs a reference list; cosine similarity ranks the top 3. It only ranks **existing** codes, so it **can't hallucinate** a code (unlike asking a chat model). Meaning, not exact words: "spanners and wrenches" → "Adjustable hand spanners".
8. **Embeddings**: text → vector of numbers (768 here); similar meanings give vectors pointing the same way; **cosine similarity** measures that angle.
9. **Printed HS code cross-check**: if a printed code disagrees with the description's suggestions, the user is warned.
10. **Results**: field accuracy **29/29 (100%)** on two layouts; HS hit@1 **9/9**; about 7-8 s per document.
11. **Fix in code, not in prompts**: a 7b model kept merging "240 CARTONS" into the description; a small regex fixed it reliably where more prompting didn't.
12. **Limitation**: semantically close but wrong codes happen ("used tyres" → "new tyres"), which is why the code is a suggestion the user confirms. Scanned PDFs need OCR (not installed yet).

### Issues faced
13. **Windows `localhost` = IPv6 first**: every call to Ollama lost ~2 s waiting for the IPv4 fallback. Switching to `127.0.0.1` took HS suggestion from 2,073 ms to ~40 ms. Found by comparing the server's own timing (49 ms) with the client's.
14. **React StrictMode runs effects twice in development**: the demo link uploaded the sample twice. Fixed with a `useRef` guard.
15. **A `--reload` server crashes on new imports** until the packages are installed in its virtual environment.

---

## 15. Login and roles

1. **Application-level authentication**: users in `backend/users.json` (git-ignored), no database change. Chosen to keep the schema unchanged; the upgrade path is a users table + PostgreSQL **row-level security**.
2. **Authentication vs authorization**: authentication = *who are you?* (login); authorization = *what may you do?* (role checks).
3. **Passwords are never stored**, only **bcrypt hashes**. bcrypt is **salted** (the same password gives a different hash each time, so precomputed "rainbow tables" don't work) and **deliberately slow** (brute force is impractical).
4. **JWT (JSON Web Token)**: after login the server returns a signed token (username, role, company, expiry). The browser sends it as `Authorization: Bearer <token>`. Anyone can *read* a JWT, but nobody can *change* the role inside it without the secret: the HMAC-SHA256 signature would no longer match (tested: a forged token gets 401).
5. **Stateless**: the server doesn't store sessions; the signature proves the token is genuine. Tokens expire after 8 hours.
6. **401 vs 403**: 401 = not logged in / bad token; 403 = logged in but your role may not do this.
7. **Roles**: admin (everything), operations (port calls, allocate berth, upload, view customs), customs (customs queue, clear filings), agent (own port calls, upload to own manifests).
8. **Per-row filtering for agents**: `WHERE (company IS NULL OR pc.agent_id = company)`; the company id comes from the signed token, never from the request, and is passed as a query parameter (no SQL injection).
9. **The backend enforces, the frontend only hides**: hiding a button is convenience; every endpoint checks the role itself (tested with direct API calls). Never trust the client.
10. **Agents can't use the Ask page**: LLM-generated SQL can read every table, so it would bypass the per-agent filter. Security decisions must consider every path to the data.
11. **Login security details**: the same error for unknown user and wrong password, and bcrypt runs even for unknown users, so neither the message nor the response time reveals which usernames exist (**user enumeration**).
12. **Token storage**: `sessionStorage` (cleared when the tab closes). Trade-off: any script on the page could read it (XSS risk); httpOnly cookies avoid that but need CSRF protection.
13. **Design note**: berth occupancy (including other agents' vessel names) is visible to agents on purpose; real ports publish berth schedules.

### Issues faced
14. **Headless screenshots can't log in**: drove Edge through the **DevTools protocol** (a small Node script) to log in as each role and capture each view; it also revealed a cramped top bar on phone widths, now fixed.

---

## 16. One database, many stakeholders

1. **The core idea of the project**: several stakeholders with different goals (operations, customs, agents, harbour master) share **one database**, each through **its own view**. A fact like a ship's arrival time is stored once and appears as a planning input, a progress step and a waiting-time start. **No redundancy, no inconsistency, one source of truth**: what a DBMS gives over separate spreadsheets per department.
2. **Three-schema architecture (ANSI/SPARC)**: external level (one view per stakeholder), conceptual level (the 10 tables), internal level (storage, indexes).
3. **Data independence**: *logical*: screens depend on views, so tables can change and only the views need updating; *physical*: indexes change speed, not results.
4. **Stakeholder views**: `v_berth_queue` (operations: not-yet-berthed calls in ready order, queue state, how many berths fit, 0 = escalate), `v_customs_workload` (customs counts), `v_agent_calls` (each call's progress, manifests, customs status of its cargo).
5. **UI follows the user's goal, not the tables**: operations gets an action queue + Gantt, customs an inbox workbench, agents a parcel-tracking style progress bar, the admin the port-wide dashboard.
6. **`record_inspection()`**: locks the filing, computes the next `inspection_no` (weak entity partial key), inserts, and updates the filing status (Discrepancy → Held, Pending/Clear → Under Review), all in one transaction. The lock stops two officers from getting the same number.
7. **Identity from the token**: the inspecting officer's name is taken from the login token, never from the request body, so nobody can record an inspection in someone else's name.
8. **Same rule in one place**: the ready-time rule (`ata` → `predicted_eta` → `eta`) is used by both `allocate_berth()` and `v_berth_queue`, so the queue order matches what the allocator does.
9. **Tests**: 14 new (`test_role_views.sql`); full suite 104.

---

## 17. All issues faced (quick list)

| # | Issue | Lesson |
|---|---|---|
| 1 | IDs jumped after rolled-back tests | Sequences don't roll back; IDs carry no meaning |
| 2 | Times shown in UTC | Set the database time zone; storage is UTC anyway |
| 3 | `.gitignore.txt` | Hidden extensions; check with `git ls-files` |
| 4 | "Repository moved" on push | Store the exact remote URL |
| 5 | Copy-paste duplicated lines | A missing `$q$` swallows the rest of the file |
| 6 | New trigger broke an old test | Regression testing catches hidden bad data |
| 7 | Terminal truncated long lines | Verify file contents with `diff` |
| 8 | Error tests passed for the wrong reason | Check *which* error occurred |
| 9 | CHECKs compared plans with facts | Facts vs facts only |
| 10 | `\b` in a Windows path | Raw strings / forward slashes |
| 11 | NOT NULL masked the real CHECK error | NOT NULL is checked before CHECK |
| 12 | float vs numeric procedure lookup | `Decimal` for money + explicit casts |
| 13 | `.env.txt` nearly leaked a password | `git check-ignore -v` before committing |
| 14 | Overly broad process kill | Stop processes by exact PID |
| 15 | 14b model too slow | Match model size to GPU memory |
| 16 | Edit script silently wrote nothing | Sanity-check results that don't change |
| 17 | `.env` change not picked up | Restart the server after config changes |
| 18 | `localhost` cost ~2 s per LLM call | On Windows use `127.0.0.1` (IPv6 tried first) |
| 19 | LLM merged table columns into a field | Fix deterministic problems in code, not prompts |
| 20 | StrictMode ran the upload twice | Guard one-off effects with `useRef` |
| 21 | Backend crashed after a code change | Install new requirements in the venv |
| 22 | Couldn't screenshot logged-in pages headlessly | Drive the browser via the DevTools protocol |
| 23 | `printf` turned `\echo` into an escape character | Shell escapes: append text with an editor, not printf |
