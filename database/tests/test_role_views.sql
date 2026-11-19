-- =====================================================================
-- test_role_views.sql : checks the stakeholder views (v_berth_queue,
-- v_agent_calls, v_customs_workload) and record_inspection().
-- Run after sample_data.sql.  Everything is rolled back at the end.
-- =====================================================================

BEGIN;

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

CREATE FUNCTION pg_temp.expect_error(label TEXT, stmt TEXT, exp_msg TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE stmt;
    RAISE NOTICE 'FAIL  %  (statement was accepted)', label;
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%' || exp_msg || '%' THEN
        RAISE NOTICE 'PASS  %  -> %', label, SQLERRM;
    ELSE
        RAISE NOTICE 'FAIL  %  -> wrong error: %', label, SQLERRM;
    END IF;
END;
$$;

-- v_berth_queue (operations) -------------------------------------------
-- Not yet berthed: 3 Waiting (B03), 4 Expected (B04), 5 Expected (no berth), 6 Expected (B02).

SELECT pg_temp.expect('1. queue holds only calls that have not berthed, in ready order',
  $q$SELECT string_agg(call_id || ':' || queue_state, ', ' ORDER BY ready_time) FROM v_berth_queue$q$,
  '3:Waiting for berth, 6:Booked, 4:Booked, 5:Needs berth');

SELECT pg_temp.expect('2. ready_time follows the allocate_berth rule (ata, then predicted_eta, then eta)',
  $q$SELECT ready_time = '2026-10-16 07:10+05:30' FROM v_berth_queue WHERE call_id = 3$q$,
  'true');

SELECT pg_temp.expect('3. suitable_berths counts berths the ship physically fits',
  $q$SELECT string_agg(call_id || '=' || suitable_berths, ' ' ORDER BY call_id) FROM v_berth_queue$q$,
  '3=1 4=1 5=1 6=2');

-- A ship no berth can take shows 0 suitable berths (escalation case).
SAVEPOINT t;
INSERT INTO vessel VALUES ('9156230', '419999001', 'Giant Max', 'India', 'Container', 400.00, 16.00);
INSERT INTO port_call (call_id, imo_number, agent_id, eta) VALUES (101, '9156230', 1, '2026-10-20 00:00+05:30');
SELECT pg_temp.expect('4. a ship too big for every berth shows 0 suitable berths',
  $q$SELECT suitable_berths::text FROM v_berth_queue WHERE call_id = 101$q$, '0');
ROLLBACK TO SAVEPOINT t;

-- v_agent_calls (agent) -------------------------------------------------

SELECT pg_temp.expect('5. call 1: both manifests, 3 shipments, 2 cleared and 1 pending',
  $q$SELECT concat_ws(' ', import_manifest, export_manifest, shipments, customs_cleared, customs_pending)
     FROM v_agent_calls WHERE call_id = 1$q$,
  'IGM-2026-0001 EGM-2026-0001 3 2 1');

SELECT pg_temp.expect('6. a call with no manifest still appears, with zero cargo',
  $q$SELECT coalesce(import_manifest, 'none') || ' ' || shipments FROM v_agent_calls WHERE call_id = 5$q$,
  'none 0');

SELECT pg_temp.expect('7. filtering by agent gives Seaways (company 1) its 2 calls',
  $q$SELECT string_agg(call_id::text, ',' ORDER BY call_id) FROM v_agent_calls WHERE agent_id = 1$q$,
  '1,4');

-- v_customs_workload (customs) ------------------------------------------
-- Pending: BE-102 Held 0.87 (latest inspection Pending), BE-103 Under Review, BE-104 Filed (unscored).

SELECT pg_temp.expect('8. workload counts',
  $q$SELECT concat_ws(' ', pending_total, filed, under_review, held, high_risk, unscored, awaiting_inspection, cleared_total)
     FROM v_customs_workload$q$,
  '3 1 1 1 1 1 1 2');

-- record_inspection() ---------------------------------------------------

SAVEPOINT t;
CALL record_inspection('BE-2026-000104', 'A. Khan', 'Discrepancy', 'Weight 20% over declared');
SELECT pg_temp.expect('9. discrepancy: inspection #1 recorded and filing Held',
  $q$SELECT i.inspection_no || ' ' || i.result || ' ' || cf.filing_status
     FROM inspection i JOIN customs_filing cf USING (filing_no) WHERE filing_no = 'BE-2026-000104'$q$,
  '1 Discrepancy Held');
ROLLBACK TO SAVEPOINT t;

SAVEPOINT t;
CALL record_inspection('BE-2026-000102', 'S. Iyer', 'Clear', 'Revised invoice accepted');
SELECT pg_temp.expect('10. next number for a weak entity (BE-102 already has 1 and 2), Held -> Under Review',
  $q$SELECT max(i.inspection_no) || ' ' || min(cf.filing_status)
     FROM inspection i JOIN customs_filing cf USING (filing_no) WHERE filing_no = 'BE-2026-000102'$q$,
  '3 Under Review');
SELECT pg_temp.expect('11. after a Clear re-inspection the filing can be cleared',
  $q$SELECT 'ok' FROM (SELECT 1) x WHERE (SELECT result FROM inspection WHERE filing_no = 'BE-2026-000102'
     ORDER BY inspection_no DESC LIMIT 1) = 'Clear'$q$, 'ok');
ROLLBACK TO SAVEPOINT t;

SELECT pg_temp.expect_error('12. a cleared filing cannot be inspected',
  $q$CALL record_inspection('BE-2026-000101', 'A. Khan', 'Clear')$q$, 'already cleared');
SELECT pg_temp.expect_error('13. an unknown result is rejected',
  $q$CALL record_inspection('BE-2026-000104', 'A. Khan', 'Maybe')$q$, 'Result must be');
SELECT pg_temp.expect_error('14. an unknown filing is rejected',
  $q$CALL record_inspection('BE-2026-999999', 'A. Khan', 'Clear')$q$, 'does not exist');

ROLLBACK;
