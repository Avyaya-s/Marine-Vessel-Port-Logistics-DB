-- =====================================================================
-- test_allocate_berth.sql : checks the allocate_berth() procedure.
-- Run after sample_data.sql.  Everything is rolled back at the end;
-- each test also runs inside its own savepoint so tests are independent.
--
-- Current bookings (from sample_data.sql):
--   B01 Container 350 m  call 2: 10-15 14:00 -> 10-17 02:00
--   B02 Container 300 m  call 1: 10-10 08:00 -> 10-11 20:00
--                        call 6: 10-17 08:00 -> 10-18 08:00
--   B03 Bulk, B04 Tanker, B05 General Cargo
-- =====================================================================

BEGIN;

-- PASS if allocate_berth picks the expected berth and start time
CREATE FUNCTION pg_temp.expect_slot(label TEXT, p_call INT, p_stay INTERVAL,
                                    exp_berth TEXT, exp_start TIMESTAMPTZ) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
    b VARCHAR; s TIMESTAMPTZ; e TIMESTAMPTZ;
BEGIN
    CALL allocate_berth(p_call, p_stay, b, s, e);
    IF b = exp_berth AND s = exp_start THEN
        RAISE NOTICE 'PASS  %  -> % from % to %', label, b, s, e;
    ELSE
        RAISE NOTICE 'FAIL  %  -> got % at %, expected % at %', label, b, s, exp_berth, exp_start;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'FAIL  %  -> %', label, SQLERRM;
END;
$$;

-- PASS if allocate_berth raises an error whose message contains exp_msg.
-- Checking the message matters: any unrelated error would otherwise
-- count as a pass.
CREATE FUNCTION pg_temp.expect_error(label TEXT, p_call INT, exp_msg TEXT) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
    b VARCHAR; s TIMESTAMPTZ; e TIMESTAMPTZ;   -- INOUT args must be variables
BEGIN
    CALL allocate_berth(p_call, '24 hours', b, s, e);
    RAISE NOTICE 'FAIL  %  (no error raised)', label;
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%' || exp_msg || '%' THEN
        RAISE NOTICE 'PASS  %  -> %', label, SQLERRM;
    ELSE
        RAISE NOTICE 'FAIL  %  -> wrong error: %', label, SQLERRM;
    END IF;
END;
$$;

-- 1. Call 5: Blue Horizon (General Cargo, 160 m), eta 10-19 12:00. B05 is free.
SAVEPOINT t;
SELECT pg_temp.expect_slot('1. unallocated call gets the matching free berth',
       5, '24 hours', 'B05', '2026-10-19 12:00+05:30');
ROLLBACK TO SAVEPOINT t;

-- 2. Malta Express (270 m) ready 10-16 20:00, 12 h stay.
--    B02 is free 10-16 20:00 -> 10-17 08:00, exactly 12 h before call 6.
SAVEPOINT t;
INSERT INTO port_call (call_id, imo_number, agent_id, eta)
VALUES (101, '9876543', 1, '2026-10-16 20:00+05:30');
SELECT pg_temp.expect_slot('2. fills a gap that is exactly long enough',
       101, '12 hours', 'B02', '2026-10-16 20:00+05:30');
ROLLBACK TO SAVEPOINT t;

-- 3. Same ship, 24 h stay: the B02 gap is too short.
--    B01 frees up at 10-17 02:00, earlier than B02 after call 6 (10-18 08:00).
SAVEPOINT t;
INSERT INTO port_call (call_id, imo_number, agent_id, eta)
VALUES (101, '9876543', 1, '2026-10-16 20:00+05:30');
SELECT pg_temp.expect_slot('3. skips a gap that is too short',
       101, '24 hours', 'B01', '2026-10-17 02:00+05:30');
ROLLBACK TO SAVEPOINT t;

-- 4. Coral Trader (335 m) only fits B01; it must wait for call 2 to leave.
SAVEPOINT t;
INSERT INTO port_call (call_id, imo_number, agent_id, eta)
VALUES (101, '9412347', 1, '2026-10-16 00:00+05:30');
SELECT pg_temp.expect_slot('4. big ship waits for the only berth that fits',
       101, '24 hours', 'B01', '2026-10-17 02:00+05:30');
ROLLBACK TO SAVEPOINT t;

-- 5. predicted_eta (10-13) is used instead of the agent eta (10-12).
--    B01 and B02 are both free then; the smaller B02 wins the tie.
SAVEPOINT t;
INSERT INTO port_call (call_id, imo_number, agent_id, eta, predicted_eta)
VALUES (101, '9876543', 1, '2026-10-12 00:00+05:30', '2026-10-13 00:00+05:30');
SELECT pg_temp.expect_slot('5. uses predicted_eta, tie goes to the smaller berth',
       101, '12 hours', 'B02', '2026-10-13 00:00+05:30');
ROLLBACK TO SAVEPOINT t;

-- 6. Two allocations in a row: the second must see the first.
--    Malta Express takes the B02 gap; Ocean Pioneer (300 m) then gets B01.
SAVEPOINT t;
INSERT INTO port_call (call_id, imo_number, agent_id, eta)
VALUES (101, '9876543', 1, '2026-10-16 20:00+05:30'),
       (102, '9321483', 2, '2026-10-16 20:00+05:30');
SELECT pg_temp.expect_slot('6a. first ship takes the B02 gap',
       101, '12 hours', 'B02', '2026-10-16 20:00+05:30');
SELECT pg_temp.expect_slot('6b. second ship sees it and goes to B01',
       102, '12 hours', 'B01', '2026-10-17 02:00+05:30');
ROLLBACK TO SAVEPOINT t;

-- 7-9. Error cases
SELECT pg_temp.expect_error('7. call that already has a berth', 2, 'already has berth');
SELECT pg_temp.expect_error('8. call that does not exist', 999, 'does not exist');

SAVEPOINT t;
INSERT INTO vessel VALUES ('9156230', '419999001', 'Giant Max', 'India', 'Container', 400.00, 16.00);
INSERT INTO port_call (call_id, imo_number, agent_id, eta)
VALUES (101, '9156230', 1, '2026-10-20 00:00+05:30');
SELECT pg_temp.expect_error('9. vessel too big for every berth', 101, 'No suitable berth');
ROLLBACK TO SAVEPOINT t;

ROLLBACK;