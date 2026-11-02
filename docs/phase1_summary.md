# Phase 1: PostgreSQL Core (Summary)

Marine Vessel Traffic & Port Logistics Tracking System, database side.
Owner: Avyaya S Yekkar (1RV24CS057). Completed 2026-10-22.

---

## 1. At a glance

| Item | Count | Where |
|---|---|---|
| Tables | 10 | `database/schema.sql` |
| Triggers | 6 (5 trigger functions) | `database/triggers.sql` |
| Stored procedures | 2 | `database/procedures.sql` |
| Views | 3 | `database/views.sql` |
| Transaction with rollback demo | 1 | `clear_customs()` + `database/demo_transaction.sql` |
| Database roles | 2 (`port_readonly`, `nl_assistant`) | `database/roles.sql` |
| Automated tests | **90**, in 9 files | `database/tests/` |
| Normalization write-up | 8 of 10 tables in BCNF, 2 deliberate exceptions | `docs/normalization.md` |

Run everything: `rebuild.sql` (builds the database) and `run_tests.sql` (runs all 90 tests). See section 13.

---

## 2. In simple words

> This section explains Phase 1 without jargon. Read it first, then the detailed sections.

**What is this project?** A computer system for **one sea port**. It keeps track of which ships are coming, where they park, what cargo they carry, and whether customs has checked that cargo.

**What did Phase 1 build?** The **database**: the place where all this information is stored, plus the **rules** that stop wrong information from getting in. Everything else in the project (maps, ML models, website) will read from and write to this database.

**The main things the database stores:**
- **Ships** (name, length, how deep they sit in the water).
- **Berths**: the parking spots for ships at the dock. Each has a maximum ship length and depth.
- **Port calls**: one visit by one ship. When it is expected, when it actually arrived, which berth it got, when it left.
- **Companies**: shipping agents, senders (shippers) and receivers (consignees).
- **Shipments and containers**: what cargo came in, packed in which boxes.
- **Customs filings and inspections**: the paperwork to clear cargo, and the officers' checks.

**The rules the database enforces by itself** (even if the website has a bug):
1. **No double parking.** Two ships can't be booked on the same berth at overlapping times.
2. **Ship must fit.** A ship that is too long or too deep for a berth is refused.
3. **Status updates itself.** When a ship arrives, docks or leaves, its status (Expected → Waiting → Berthed → Departed) changes automatically.
4. **Right company for the right job.** Only an agent can be a ship's agent; only a shipper can send cargo, and so on.
5. **Data must look real.** Ship IDs must pass a check-digit test, container numbers must have the right format, risk scores must be between 0 and 1, and more.

**Smart helpers:**
- **`allocate_berth`** finds the earliest free berth that suits a ship and books it, like an automatic parking assistant.
- **`clear_customs`** clears cargo through customs in **one go**: mark the paperwork as cleared, record the tax, release the containers. If any part fails, **nothing** changes. This is called a **transaction**.

**Ready-made reports (views):** waiting times at anchor, which ship is at which berth, and the customs officers' to-do list sorted by risk.

**Safety for the AI feature:** later, an AI will turn plain-English questions into database queries. It connects as a special **read-only** user that can look but never change anything.

**Good design (normalization):** each fact is stored in one place only, so it can't contradict itself. Two small, deliberate exceptions are protected so they can never go wrong.

**Proof it works:** 90 automatic tests. Each one tries something (allowed or not allowed) and checks the database reacts correctly.

---

## 3. Files

```
database/
  schema.sql            10 tables, domain, IMO check function, constraints, indexes
  triggers.sql          6 triggers (T1-T5)
  procedures.sql        allocate_berth(), clear_customs()
  views.sql             v_waiting_time, v_berth_occupancy, v_pending_customs
  roles.sql             read-only user for the NL assistant
  sample_data.sql       hand-written sample rows (one port call in each status)
  rebuild.sql           runs all of the above in order (psql)
  run_tests.sql         runs all 9 test files (psql)
  demo_transaction.sql  narrated rollback demo for the viva (psql)
  tests/                9 self-checking test files
  README.md             how to run
docs/
  normalization.md      full normalization write-up
  phase1_summary.md     this file
  er_diagram.jpeg, relational_schema.jpeg
```

---

## 4. Schema (10 tables)

Created parents-first so every foreign key target already exists.

| # | Table | Key | Notes |
|---|---|---|---|
| 1 | `vessel` | imo_number | IMO check digit validated by `is_valid_imo()`; `mmsi` UNIQUE (links to MongoDB AIS data) |
| 2 | `company` | company_id | `company_type` = agent / shipper / consignee; `iec_code` UNIQUE |
| 3 | `berth` | berth_number | max_loa, max_draft, cargo_type |
| 4 | `port_call` | call_id | plan columns (eta, predicted_eta, berth_start, berth_end) + fact columns (ata, atb, atd) + call_status |
| 5 | `shipping_manifest` | manifest_no | UNIQUE (call_id, manifest_type): at most one IGM + one EGM per call |
| 6 | `shipment` | shipment_no | one Bill of Lading; shipper ≠ consignee |
| 7 | `container` | container_no | `size` is a GENERATED column from `iso_type` |
| 8 | `shipment_container` | (shipment_no, container_no) | M:N junction (COVERS) |
| 9 | `customs_filing` | filing_no | `shipment_no` UNIQUE (1:1); risk_score 0-1 |
| 10 | `inspection` | (filing_no, inspection_no) | weak entity, ON DELETE CASCADE |

MongoDB (Phase 3) holds `ship_location` and `weather_log`, so the ER model has **11 entity types**.

**Constraint highlights**
- **Domain** `cargo_category` shared by `vessel.vessel_type` and `berth.cargo_type`, so ships and berths use the same words.
- **Format checks:** IMO (7 digits + check digit), MMSI (9 digits), container number (4 letters + 7 digits), UN/LOCODE origin port (`CNSHA`), HS code (6 or 8 digits), IEC (10 chars).
- **Fact-order checks:** `ata ≤ atb ≤ atd`; `atb` needs a berth.
- **Indexes:** `port_call(berth_number, berth_start)`, `shipment(hs_code)`, `customs_filing(filing_status)`.
- **All timestamps are `TIMESTAMPTZ`**, displayed in IST (`Asia/Kolkata`).

---

## 5. Triggers

| # | Trigger | On | What it does |
|---|---|---|---|
| T1 | `check_berth_overlap` | port_call | Rejects a booking that overlaps another on the same berth |
| T2 | `check_berth_fit` | port_call | Rejects a ship whose LOA or draft exceeds the berth limits |
| T3 | `set_call_status` | port_call | Sets call_status from ata / atb / atd; rejects a contradicting manual status |
| T4 | `check_company_role` | port_call, shipment | agent_id must be an agent; shipper_id a shipper; consignee_id a consignee |
| T5 | `lock_company_type` | company | A company's type can't change while it is used in that role |

**Key design points**
- **T1:** overlap test `A.start < B.end AND B.start < A.end`, half-open windows (back-to-back bookings allowed), open-ended bookings treated as infinite. Locks the berth row (`FOR UPDATE`) so two simultaneous bookings can't both slip through.
- **T2:** only physical limits (LOA, draft). Cargo type is a planning preference handled by `allocate_berth`. Also fires when the vessel on a booking is swapped.
- **T3:** a trigger fires on data changes, not on clock time, so status follows **facts** (ata/atb/atd), not plans.
- **T4 + T5:** a rule enforced from **both sides** (the referencing table and the referenced table).
- Triggers on the same table fire in **alphabetical order** by name.

---

## 6. Stored procedures

### `allocate_berth(call_id [, stay])`
Books the earliest free berth matching cargo type, LOA and draft.
- Ready time = `ata`, else ML `predicted_eta`, else agent `eta`.
- Candidate start times = the ready time plus the end of every booking on that berth (the earliest free slot always starts at one of these).
- Ties go to the **smallest** suitable berth (best fit).
- Locks the call and the candidate berths (in a fixed order, so no deadlocks). The triggers still check the final UPDATE (defence in depth).
- SQL used: `CROSS JOIN LATERAL`, `UNION`, `NOT EXISTS`, `ORDER BY ... LIMIT 1`, INOUT parameters.

### `clear_customs(filing_no, duty)`
Customs clearance as one all-or-nothing transaction (section 8).

---

## 7. Views

| View | One row per | Main columns |
|---|---|---|
| `v_waiting_time` | arrived port call | waiting_time (`atb - ata`), berthing_delay (`atb - berth_start`), agent_eta_error, model_eta_error |
| `v_berth_occupancy` | berth | ship alongside now, next booked ship, number of upcoming bookings |
| `v_pending_customs` | uncleared filing | riskiest first; cargo, HS code, consignee, vessel, containers, latest inspection |

The ETA-error columns are how the ML ETA model will be compared against the agent's ETA. Views store no data, so they are always up to date.

---

## 8. Transaction: customs clearance

`CALL clear_customs('BE-2026-000104', 345000);` does three things together:
1. filing → `Cleared`
2. duty recorded
3. containers → `Released` (imports only)

If a container is still on the ship, it raises an error **after** steps 1-2 have run, and PostgreSQL undoes them automatically. `demo_transaction.sql` shows this live in three parts: a manual BEGIN/ROLLBACK, the automatic rollback, and a successful clearance.

Other rules: the filing can't be cleared twice, the duty can't be negative, and the latest inspection must not be Pending or Discrepancy. The filing row is locked so two officers can't clear it at once.

---

## 9. Security: read-only user

- `port_readonly` (group role, no login) has SELECT on all tables and views. `nl_assistant` (login) is a member.
- Three layers: **privileges** (SELECT only), **read-only transactions by default**, **5 s statement timeout + 5 connections max**.
- Procedures' default EXECUTE-for-everyone was revoked.
- The password is never in Git: set with `ALTER ROLE nl_assistant PASSWORD '...'`, kept in `.env`.
- `ALTER DEFAULT PRIVILEGES` gives SELECT on future tables automatically.

---

## 10. Normalization

Full details in `docs/normalization.md`.

- All tables in 1NF (atomic values; M:N via a junction table; inspections as rows).
- **8 of 10 tables in BCNF.**
- **CONTAINER:** `container_no → iso_type → size` is transitive. `size` is a **generated column**, so it can't be set by hand or be wrong. (Alternative: an ISO_TYPE lookup table, saved in `git stash` to explore later.)
- **PORT_CALL:** `ata, atb, atd → call_status` is transitive. Kept for fast filtering; the T3 trigger guarantees it always matches.
- Derived values (waiting time, delays, days pending) are computed in views, never stored.

---

## 11. Testing

- 9 test files, **90 tests**, run with `run_tests.sql`.
- Each file runs inside `BEGIN ... ROLLBACK`, and each test inside a `SAVEPOINT`, so tests are independent and never change the data.
- Helper functions print `PASS` / `FAIL`. Error tests check **which** error occurred, not just that one occurred.
- Both directions are tested: things that must be **rejected** and things that must be **accepted**.

| File | Tests | Covers |
|---|---|---|
| test_berth_overlap | 10 | T1 |
| test_berth_fit | 7 | T2 |
| test_allocate_berth | 10 | allocate_berth |
| test_call_status | 13 | T3 + fact-order CHECKs |
| test_views | 10 | the 3 views |
| test_clear_customs | 12 | the transaction |
| test_company_roles | 11 | T4, T5 |
| test_roles | 11 | read-only user |
| test_container_size | 6 | generated column |

---

## 12. Design decisions: why this, why not that

| Decision | Why | Alternative not chosen |
|---|---|---|
| Single port, no PORT table | The system *is* the port | A PORT table would be unused |
| One berth per visit (FK in port_call) | Simple; matches how small ports work | A BERTH_ALLOCATION table for multi-berth visits |
| Plan vs fact time columns (added `atb`) | Triggers can't react to clock time; status must follow facts | Overwriting `berth_start` (loses the planned time) |
| Constraints before triggers | Faster, can't be bypassed, visible to the optimizer | Triggers for everything |
| Trigger for berth overlap | Lab requirement; readable error naming the clashing call | `EXCLUDE USING gist` with `btree_gist` (declarative, also concurrency-safe) |
| Triggers for company roles | No extra columns | Composite FK `(agent_id, 'agent')` → `company(company_id, company_type)` |
| Normal views | Always fresh; data is small | Materialized views (faster, can be stale) |
| Generated column for size | No new table; size can't be wrong | ISO_TYPE lookup table (strict 3NF), saved for later |
| IMO/MMSI as text | Identifiers, not numbers; keeps leading zeros | INTEGER |
| TIMESTAMPTZ everywhere | AIS is UTC, port runs on IST | TIMESTAMP without time zone |

---

## 13. How to run

PowerShell, from the project root (psql is not on PATH, so use the full path):

```powershell
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d port_logistics -f database/rebuild.sql
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d port_logistics -f database/run_tests.sql
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d port_logistics -f database/demo_transaction.sql
```

Expected: `Rebuild complete.`, then 90 lines of PASS and no FAIL, then the 3-part demo. pgAdmin users: run `schema → triggers → procedures → views → roles → sample_data` one by one.

---

## 14. Issues faced (and what I learned)

| # | Issue | Fix / lesson |
|---|---|---|
| 1 | IDs jumped (call 12, 20) after rolled-back tests | Sequences don't roll back; gaps are normal, IDs carry no meaning |
| 2 | Times shown in UTC | `ALTER DATABASE ... SET timezone TO 'Asia/Kolkata'`; storage is UTC anyway |
| 3 | `.gitignore` saved as `.gitignore.txt` | Windows hides extensions; checked with `git ls-files` |
| 4 | "Repository moved" on push | Username case; fixed with `git remote set-url` |
| 5 | New fit trigger broke an old test | The old test put a 300 m ship on a 200 m berth; re-running all tests catches hidden bad data (regression) |
| 6 | Code copied from the terminal was cut off / duplicated | The terminal truncates long lines; switched to writing files directly and checking with `diff` |
| 7 | Error tests "passed" for the wrong reason | INOUT arguments must be variables in PL/pgSQL; error tests now check the message |
| 8 | Two CHECKs compared plans with facts | A late ship would have been rejected; CHECKs now compare facts with facts only |
| 9 | Windows path corrupted in a Python string | `\b` is an escape code; use raw strings `r"..."` |
| 10 | Generated `size NOT NULL` gave a misleading error | NOT NULL is checked before CHECK; removed NOT NULL so the real error shows |

---

## 15. Likely interview questions

**Why PostgreSQL and MongoDB both?** Structured, related, transactional data (calls, customs) fits PostgreSQL. High-volume time-stamped GPS points and weather readings fit MongoDB time-series collections with geospatial indexes.

**Why a trigger and not a CHECK for the berth overlap?** A CHECK sees only one row; overlap needs to compare against other rows.

**How do you stop two people booking the same berth at the same moment?** The trigger locks the berth row with `SELECT ... FOR UPDATE`, so bookings for one berth run one after another.

**What is a deadlock and how did you avoid it?** Two sessions each hold a lock the other needs and wait forever. `allocate_berth` always locks berths in the same order (`ORDER BY berth_number`).

**Explain ACID with your project.** Atomicity: clear_customs is all-or-nothing. Consistency: no cleared filing with stuck containers. Isolation: changes are invisible to others until COMMIT. Durability: committed data survives a crash (write-ahead log).

**Procedure vs function?** A procedure is run with CALL, does an action, returns results through INOUT parameters, and can control transactions. A function is used inside a query to compute a value.

**View vs materialized view?** A view re-runs its query every time (always fresh). A materialized view stores the result and needs REFRESH (faster, can be stale).

**Is your schema in 3NF?** 8 of 10 tables are BCNF. Two keep one derived column on purpose (container.size, port_call.call_status), and the database guarantees both are always correct.

**How is the AI query feature kept safe?** It uses a read-only role (SELECT only), read-only transactions by default, and a 5-second timeout, so even malicious generated SQL can't change data or hog the server.

**Why store call_status if it can be derived?** For fast filtering and indexing. The trigger guarantees it never disagrees with the timestamps (controlled redundancy).

---

## 16. Pending items

- [ ] **ER diagram:** add **ATB** to PORT_CALL; draw **Size** on CONTAINER as a derived attribute (dashed oval).
- [ ] **Relational schema diagram:** add `atb` to PORT_CALL.
- [ ] Explore option 1 (ISO_TYPE lookup table) from `git stash` later.
- [ ] Share CLAUDE.md and this file with Bhuvan before Phase 3.

**Next: Phase 2, synthetic data generator** (`data/generate_data.py`): hundreds of rows with planted customs risk patterns for the ML models.

---

## 17. Glossary in simple words

| Term | Simple meaning |
|---|---|
| **Table / relation** | A grid of rows and columns, like a spreadsheet sheet |
| **Primary key (PK)** | The column that uniquely identifies each row (like a roll number) |
| **Foreign key (FK)** | A column that points to a row in another table ("this port call belongs to *that* ship") |
| **Constraint** | A rule the database checks on every insert or update |
| **CHECK** | A rule about values in one row ("length must be > 0") |
| **UNIQUE** | No two rows can have the same value |
| **Trigger** | Code the database runs automatically when data changes |
| **Stored procedure** | A saved program inside the database, run with `CALL` |
| **View** | A saved query you can use like a table; it stores no data |
| **Transaction** | A group of changes that all happen or none happen |
| **Rollback** | Undo every change in the current transaction |
| **Commit** | Make the transaction's changes permanent |
| **Savepoint** | A checkpoint inside a transaction you can roll back to |
| **Lock (`FOR UPDATE`)** | "I'm editing this row, others wait until I'm done" |
| **Deadlock** | Two sessions each waiting for the other's lock, forever |
| **Index** | A lookup structure that makes searching a column fast (like a book's index) |
| **Normalization** | Organizing tables so each fact is stored once |
| **Functional dependency (A → B)** | Knowing A tells you B |
| **Transitive dependency** | A → B → C, so C depends on the key only through B |
| **Anomaly** | A problem caused by storing a fact more than once (update, insert or delete goes wrong) |
| **Generated column** | A column the database calculates itself from other columns |
| **Derived attribute** | A value that can be calculated from others (e.g. waiting time) |
| **Weak entity** | Something that can't exist on its own (an inspection needs its filing) |
| **Role** | A database user account or group of permissions |
| **Read-only** | Can look at data but never change it |
| **LOA** | Length overall: how long a ship is |
| **Draft** | How deep a ship sits below the water |
| **Berth** | A parking spot for a ship at the dock |
| **ETA / ATA / ATB / ATD** | Expected arrival / actual arrival / actual berthing / actual departure |
| **IMO / MMSI** | A ship's permanent ID number / its radio ID used in AIS tracking |
| **AIS** | The system ships use to broadcast their GPS position |
| **IGM / EGM** | Import / export cargo manifest (list of cargo on a ship) |
| **Bill of Lading** | The document for one shipment of cargo |
| **HS code** | The international code for a type of goods |
| **Bill of Entry / Shipping Bill** | Customs declaration for imports / exports |
