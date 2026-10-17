-- =====================================================================
-- test_berth_overlap.sql : checks the double-booking trigger.
-- Run after sample_data.sql.  Everything is rolled back at the end.
-- Each case prints PASS or FAIL as a NOTICE.
-- =====================================================================

BEGIN;

-- expect_reject(sql): PASS if the statement is rejected by the trigger
CREATE FUNCTION pg_temp.expect_reject(label TEXT, stmt TEXT) RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE stmt;
    RAISE NOTICE 'FAIL  %  (statement was accepted)', label;
EXCEPTION WHEN exclusion_violation THEN
    RAISE NOTICE 'PASS  %  -> %', label, SQLERRM;
END;
$$;

-- expect_accept(sql): PASS if the statement succeeds
CREATE FUNCTION pg_temp.expect_accept(label TEXT, stmt TEXT) RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE stmt;
    RAISE NOTICE 'PASS  %', label;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'FAIL  %  -> %', label, SQLERRM;
END;
$$;

-- Call 2 holds B01 from 10-15 14:00 to 10-17 02:00.
SELECT pg_temp.expect_reject('1. new booking inside an existing window',
  $q$INSERT INTO port_call (imo_number, agent_id, berth_number, berth_start, berth_end, eta)
     VALUES ('9876543', 1, 'B01', '2026-10-16 00:00+05:30', '2026-10-16 12:00+05:30',
             '2026-10-15 22:00+05:30')$q$);

SELECT pg_temp.expect_reject('2. new booking that starts before and ends inside',
  $q$INSERT INTO port_call (imo_number, agent_id, berth_number, berth_start, berth_end, eta)
     VALUES ('9876543', 1, 'B01', '2026-10-15 06:00+05:30', '2026-10-15 15:00+05:30',
             '2026-10-15 04:00+05:30')$q$);

SELECT pg_temp.expect_reject('3. new booking that fully covers an existing one',
  $q$INSERT INTO port_call (imo_number, agent_id, berth_number, berth_start, berth_end, eta)
     VALUES ('9876543', 1, 'B01', '2026-10-15 00:00+05:30', '2026-10-18 00:00+05:30',
             '2026-10-14 22:00+05:30')$q$);

SELECT pg_temp.expect_accept('4. back-to-back booking (starts exactly when call 2 ends)',
  $q$INSERT INTO port_call (imo_number, agent_id, berth_number, berth_start, berth_end, eta)
     VALUES ('9876543', 1, 'B01', '2026-10-17 02:00+05:30', '2026-10-17 20:00+05:30',
             '2026-10-17 00:00+05:30')$q$);

SELECT pg_temp.expect_accept('5. same time window on a different berth',
  $q$INSERT INTO port_call (imo_number, agent_id, berth_number, berth_start, berth_end, eta)
     VALUES ('9321483', 1, 'B05', '2026-10-16 00:00+05:30', '2026-10-16 12:00+05:30',
             '2026-10-15 22:00+05:30')$q$);

-- Call 6 holds B02 10-17 08:00 to 10-18 08:00; try to move it onto call 2's B01 window.
SELECT pg_temp.expect_reject('6. UPDATE that moves a booking onto an occupied berth',
  $q$UPDATE port_call SET berth_number = 'B01', berth_start = '2026-10-16 08:00+05:30',
                          berth_end = '2026-10-16 20:00+05:30'
     WHERE call_id = 6$q$);

SELECT pg_temp.expect_accept('7. UPDATE that extends a booking without hitting anyone (self excluded)',
  $q$UPDATE port_call SET berth_end = '2026-10-17 01:00+05:30' WHERE call_id = 2$q$);

-- Open-ended booking: ship alongside, departure unknown.
SELECT pg_temp.expect_accept('8. open-ended booking (no berth_end) on B03 after call 3',
  $q$INSERT INTO port_call (imo_number, agent_id, berth_number, berth_start, eta)
     VALUES ('9527817', 1, 'B03', '2026-10-19 12:00+05:30', '2026-10-19 08:00+05:30')$q$);

SELECT pg_temp.expect_reject('9. any later booking on B03 clashes with the open-ended one',
  $q$INSERT INTO port_call (imo_number, agent_id, berth_number, berth_start, berth_end, eta)
     VALUES ('9527817', 1, 'B03', '2026-10-25 00:00+05:30', '2026-10-26 00:00+05:30',
             '2026-10-24 22:00+05:30')$q$);

SELECT pg_temp.expect_accept('10. calls with no berth are never checked',
  $q$INSERT INTO port_call (imo_number, agent_id, eta)
     VALUES ('9705122', 2, '2026-10-30 00:00+05:30')$q$);

ROLLBACK;
