-- =====================================================================
-- test_views.sql : checks the three views against sample_data.sql.
-- Read-only except test 7, which runs inside a savepoint; the whole
-- script is rolled back at the end.
-- Columns that depend on today's date (days_pending) are not checked.
-- =====================================================================

BEGIN;

-- PASS if query returns exactly the expected text
CREATE FUNCTION pg_temp.expect(label TEXT, query TEXT, expected TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    got TEXT;
BEGIN
    EXECUTE query INTO got;
    IF got IS NOT DISTINCT FROM expected THEN
        RAISE NOTICE 'PASS  %  -> %', label, got;
    ELSE
        RAISE NOTICE 'FAIL  %  -> got [%], expected [%]', label, got, expected;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'FAIL  %  -> %', label, SQLERRM;
END;
$$;

-- v_waiting_time ------------------------------------------------------
-- Call 1: ata 05:30, atb 08:20 (plan 08:00).  Call 2: ata 11:20, atb 14:35 (plan 14:00).
-- Call 3: arrived 07:10, not berthed yet.  Calls 4-6 have not arrived.

SELECT pg_temp.expect('1. only arrived calls are listed',
  $q$SELECT string_agg(call_id::text, ',' ORDER BY call_id) FROM v_waiting_time$q$,
  '1,2,3');

SELECT pg_temp.expect('2. waiting time = atb - ata',
  $q$SELECT string_agg(call_id || '=' || waiting_time, ', ' ORDER BY call_id)
     FROM v_waiting_time WHERE waiting_time IS NOT NULL$q$,
  '1=02:50:00, 2=03:15:00');

SELECT pg_temp.expect('3. waiting_hours is numeric for charts',
  $q$SELECT string_agg(call_id || '=' || waiting_hours, ', ' ORDER BY call_id)
     FROM v_waiting_time WHERE waiting_hours IS NOT NULL$q$,
  '1=2.83, 2=3.25');

SELECT pg_temp.expect('4. berthing delay = atb - planned berth_start',
  $q$SELECT string_agg(call_id || '=' || berthing_delay, ', ' ORDER BY call_id)
     FROM v_waiting_time WHERE berthing_delay IS NOT NULL$q$,
  '1=00:20:00, 2=00:35:00');

SELECT pg_temp.expect('5. agent vs model ETA error for call 3',
  $q$SELECT agent_eta_error || ' / ' || model_eta_error FROM v_waiting_time WHERE call_id = 3$q$,
  '01:10:00 / 00:25:00');

-- v_berth_occupancy ---------------------------------------------------
-- B01: Coral Trader alongside (call 2).  B02: call 1 left; call 6 next.
-- B03: call 3 next.  B04: call 4 next.  B05: empty.

SELECT pg_temp.expect('6. one row per berth with occupant and next ship',
  $q$SELECT string_agg(berth_number || ':' || coalesce(occupied_by, '-') || '/'
                       || coalesce(next_vessel, '-') || '/' || upcoming_bookings,
                       ' ' ORDER BY berth_number)
     FROM v_berth_occupancy$q$,
  'B01:Coral Trader/-/0 B02:-/Malta Express/1 B03:-/Iron Monarch/1 B04:-/Ganga Spirit/1 B05:-/-/0');

-- When call 3 actually berths, B03 becomes occupied and has no next ship.
SAVEPOINT t;
UPDATE port_call SET atb = '2026-10-16 18:10+05:30' WHERE call_id = 3;
SELECT pg_temp.expect('7. view reflects a new atb immediately (no refresh)',
  $q$SELECT occupied_by || ' since ' || occupied_since || ', next=' || coalesce(next_vessel, '-')
     FROM v_berth_occupancy WHERE berth_number = 'B03'$q$,
  'Iron Monarch since 2026-10-16 18:10:00+05:30, next=-');
ROLLBACK TO SAVEPOINT t;

-- v_pending_customs ---------------------------------------------------
-- Not cleared: BE-102 Held 0.870, BE-103 Under Review 0.310, BE-104 Filed (no score).

SELECT pg_temp.expect('8. only uncleared filings, riskiest first, unscored last',
  $q$SELECT string_agg(filing_no || '(' || coalesce(risk_score::text, 'null') || ')', ' ')
     FROM v_pending_customs$q$,
  'BE-2026-000102(0.870) BE-2026-000103(0.310) BE-2026-000104(null)');

SELECT pg_temp.expect('9. joins consignee, vessel, containers and inspections',
  $q$SELECT consignee || ' | ' || vessel_name || ' | ' || containers || ' cont | '
            || inspections || ' insp | last=' || coalesce(last_inspection_result, '-')
     FROM v_pending_customs WHERE filing_no = 'BE-2026-000102'$q$,
  'Nilgiri Trading Co | Ocean Pioneer | 1 cont | 2 insp | last=Pending');

SELECT pg_temp.expect('10. filing with no inspections still appears',
  $q$SELECT inspections || ' insp | last=' || coalesce(last_inspection_result, '-')
     FROM v_pending_customs WHERE filing_no = 'BE-2026-000103'$q$,
  '0 insp | last=-');

ROLLBACK;
