-- =====================================================================
-- test_berth_fit.sql : checks the berth-fit (LOA / draft) trigger.
-- Run after sample_data.sql.  Everything is rolled back at the end.
-- =====================================================================

BEGIN;

CREATE FUNCTION pg_temp.expect_reject(label TEXT, stmt TEXT) RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE stmt;
    RAISE NOTICE 'FAIL  %  (statement was accepted)', label;
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS  %  -> %', label, SQLERRM;
END;
$$;

CREATE FUNCTION pg_temp.expect_accept(label TEXT, stmt TEXT) RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE stmt;
    RAISE NOTICE 'PASS  %', label;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'FAIL  %  -> %', label, SQLERRM;
END;
$$;

-- Coral Trader: LOA 335 m.  B02: max LOA 300 m.
SELECT pg_temp.expect_reject('1. vessel too long for the berth',
  $q$INSERT INTO port_call (imo_number, agent_id, berth_number, berth_start, berth_end, eta)
     VALUES ('9412347', 1, 'B02', '2026-10-13 00:00+05:30', '2026-10-13 12:00+05:30',
             '2026-10-12 22:00+05:30')$q$);

-- Ganga Spirit: draft 13.8 m.  B03: max draft 13.0 m (LOA 250 <= 260 is fine).
SELECT pg_temp.expect_reject('2. vessel too deep for the berth',
  $q$INSERT INTO port_call (imo_number, agent_id, berth_number, berth_start, berth_end, eta)
     VALUES ('9633070', 1, 'B03', '2026-10-13 00:00+05:30', '2026-10-13 12:00+05:30',
             '2026-10-12 22:00+05:30')$q$);

-- Malta Express: 270 m / 12.8 m.  B02: 300 m / 13.5 m.
SELECT pg_temp.expect_accept('3. vessel that fits comfortably',
  $q$INSERT INTO port_call (imo_number, agent_id, berth_number, berth_start, berth_end, eta)
     VALUES ('9876543', 1, 'B02', '2026-10-13 00:00+05:30', '2026-10-13 12:00+05:30',
             '2026-10-12 22:00+05:30')$q$);

-- A vessel exactly at B02's limits (300.00 m / 13.50 m) must be allowed.
INSERT INTO vessel VALUES ('9156230', '419999001', 'Exact Fit', 'India', 'Container', 300.00, 13.50);
SELECT pg_temp.expect_accept('4. vessel exactly at the berth limits',
  $q$INSERT INTO port_call (imo_number, agent_id, berth_number, berth_start, berth_end, eta)
     VALUES ('9156230', 1, 'B02', '2026-10-14 00:00+05:30', '2026-10-14 12:00+05:30',
             '2026-10-13 22:00+05:30')$q$);

-- Call 6 is Malta Express on B02; swap in Coral Trader (335 m).
SELECT pg_temp.expect_reject('5. UPDATE that swaps in a bigger vessel',
  $q$UPDATE port_call SET imo_number = '9412347' WHERE call_id = 6$q$);

-- Call 4 is Ganga Spirit on B04; move it to B03 (too shallow).
SELECT pg_temp.expect_reject('6. UPDATE that moves a vessel to a shallower berth',
  $q$UPDATE port_call SET berth_number = 'B03' WHERE call_id = 4$q$);
SELECT pg_temp.expect_accept('7. call with no berth is never checked',
  $q$INSERT INTO port_call (imo_number, agent_id, eta)
     VALUES ('9412347', 2, '2026-10-30 00:00+05:30')$q$);

ROLLBACK;