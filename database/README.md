# database/

PostgreSQL side of the project. Requires PostgreSQL 16+.

## Quick start (psql)

From the project root (PowerShell). psql is not on PATH by default, so use its full path:

```powershell
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d port_logistics -f database/rebuild.sql
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d port_logistics -f database/run_tests.sql
```

`rebuild.sql` drops and recreates everything (tables, triggers, procedures, views, roles, sample data).
`run_tests.sql` runs every test script; every line should say `PASS`. Each test script rolls back, so the data is left unchanged.

Transaction demo for the viva (narrated, leaves the data unchanged):

```powershell
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d port_logistics -f database/demo_transaction.sql
```

Create the database once beforehand: `createdb -U postgres port_logistics` (or in pgAdmin: Databases -> Create -> Database).

## Load order (pgAdmin)

pgAdmin cannot run `rebuild.sql` (it uses psql's `\ir`). Open the Query Tool on `port_logistics` and run these in order:

1. `schema.sql`
2. `triggers.sql`
3. `procedures.sql`
4. `views.sql`
5. `roles.sql`
6. `sample_data.sql`

Then any file in `tests/`.

## Files

| File | Contents |
|---|---|
| `schema.sql` | `cargo_category` domain, `is_valid_imo()` function, 10 tables with all PK/FK/UNIQUE/NOT NULL/CHECK constraints, indexes |
| `triggers.sql` | `check_berth_overlap`: rejects overlapping bookings on the same berth; `check_berth_fit`: rejects a vessel whose LOA/draft exceeds the berth limits; `set_call_status`: derives `call_status` from `ata` / `atb` / `atd`; `check_company_role` / `lock_company_type`: agents, shippers and consignees are used only in their own role |
| `procedures.sql` | `allocate_berth(call_id [, stay])`: books the earliest free berth that fits the vessel; `clear_customs(filing_no, duty)`: customs clearance as one all-or-nothing transaction |
| `views.sql` | `v_waiting_time`, `v_berth_occupancy`, `v_pending_customs` |
| `roles.sql` | read-only login `nl_assistant` (via group role `port_readonly`) for the NL query assistant |
| `sample_data.sql` | 5-10 hand-written rows per table (one port call in each status) |
| `rebuild.sql` / `run_tests.sql` | psql scripts that run everything above / every test |
| `demo_transaction.sql` | psql script: narrated rollback demo of `clear_customs` |
| `tests/` | self-checking SQL tests (one file per feature) |

## NL assistant login

The password is not stored in the repo. Set it once (as `postgres`):

```sql
ALTER ROLE nl_assistant PASSWORD 'choose-a-password';
```

Put it in the backend's `.env` file (ignored by Git), never in code.

Constraints are declared inline in `schema.sql`, so a separate `constraints.sql` isn't needed.
