# database/

PostgreSQL side of the project. Requires PostgreSQL 16+.

## Load order

```bash
createdb -U postgres port_logistics
psql -U postgres -d port_logistics -v ON_ERROR_STOP=1 -f schema.sql
psql -U postgres -d port_logistics -v ON_ERROR_STOP=1 -f triggers.sql
psql -U postgres -d port_logistics -v ON_ERROR_STOP=1 -f sample_data.sql
```

`schema.sql` drops and recreates everything, so re-running the three files resets the database.
In pgAdmin: open the Query Tool on `port_logistics` and run each file in the same order.

## Tests

```bash
psql -U postgres -d port_logistics -f tests/test_berth_overlap.sql
```

Each case prints `NOTICE: PASS ...` or `NOTICE: FAIL ...`. The script rolls back, so it leaves the data unchanged.

## Files

| File | Contents |
|---|---|
| `schema.sql` | `cargo_category` domain, `is_valid_imo()` function, 10 tables with all PK/FK/UNIQUE/NOT NULL/CHECK constraints, indexes |
| `triggers.sql` | `check_berth_overlap`: rejects overlapping bookings on the same berth |
| `sample_data.sql` | 5-10 hand-written rows per table (one port call in each status) |
| `tests/` | self-checking SQL tests |

Constraints are declared inline in `schema.sql`, so a separate `constraints.sql` isn't needed.
