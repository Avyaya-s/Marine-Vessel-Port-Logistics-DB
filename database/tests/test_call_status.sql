-- =====================================================================
-- test_call_status.sql : checks the set_call_status trigger and the
-- arrive -> berth -> depart CHECK constraints.
-- Run after sample_data.sql.  Everything is rolled back at the end;
-- each test runs inside its own savepoint so tests are independent.
--
-- Starting state (from sample_data.sql):
--   call 1 Departed, call 2 Berthed, call 3 Waiting,
--   calls 4, 5, 6 Expected (call 5 has no berth)
-- =====================================================================

BEGIN;

-- PASS if the statement succeeds and call p_call ends up in exp_status
CREATE FUNCTION pg_temp.expect_status(label TEXT, stmt TEXT, p_call INT, exp_status TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    got TEXT;
BEGIN
    EXECUTE stmt;
    SELECT call_status INTO got FROM port_call WHERE call_id = p_call;
    IF got = exp_status THEN
        RAISE NOTICE 'PASS  %  -> %', label, got;
    ELSE
        RAISE NOTICE 'FAIL  %  -> got %, expected %', label, got, exp_status;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'FAIL  %  -> %', label, SQLERRM;
END;
$$;

-- PASS if the statement fails with an error whose message contains exp_msg
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

-- 0. Sample data: statuses were derived on INSERT, none were typed in.
DO $$
DECLARE
    got TEXT;
BEGIN
    SELECT string_agg(call_id || '=' || call_status, ', ' ORDER BY call_id) INTO got
    FROM port_call;
    IF got = '1=Departed, 2=Berthed, 3=Waiting, 4=Expected, 5=Expected, 6=Expected' THEN
        RAISE NOTICE 'PASS  0. sample data statuses derived on INSERT  -> %', got;
    ELSE
        RAISE NOTICE 'FAIL  0. sample data statuses derived on INSERT  -> %', got;
    END IF;
END $$;

-- Normal life cycle ---------------------------------------------------

SAVEPOINT t;
SELECT pg_temp.expect_status('1. ata recorded -> Waiting',
  $q$UPDATE port_call SET ata = '2026-10-18 01:30+05:30' WHERE call_id = 4$q$,
  4, 'Waiting');
ROLLBACK TO SAVEPOINT t;

SAVEPOINT t;
SELECT pg_temp.expect_status('2. atb recorded -> Berthed',
  $q$UPDATE port_call SET atb = '2026-10-16 18:10+05:30' WHERE call_id = 3$q$,
  3, 'Berthed');
ROLLBACK TO SAVEPOINT t;

SAVEPOINT t;
SELECT pg_temp.expect_status('3. atd recorded -> Departed',
  $q$UPDATE port_call SET atd = '2026-10-17 03:00+05:30' WHERE call_id = 2$q$,
  2, 'Departed');
ROLLBACK TO SAVEPOINT t;

SAVEPOINT t;
SELECT pg_temp.expect_status('4. new call with no actual times -> Expected',
  $q$INSERT INTO port_call (call_id, imo_number, agent_id, eta)
     VALUES (101, '9705122', 2, '2026-10-25 00:00+05:30')$q$,
  101, 'Expected');
ROLLBACK TO SAVEPOINT t;

SAVEPOINT t;
SELECT pg_temp.expect_status('5. INSERT ignores a wrong typed-in status',
  $q$INSERT INTO port_call (call_id, imo_number, agent_id, eta, ata, call_status)
     VALUES (101, '9705122', 2, '2026-10-25 00:00+05:30', '2026-10-25 01:00+05:30', 'Departed')$q$,
  101, 'Waiting');
ROLLBACK TO SAVEPOINT t;

-- Plans vs facts ------------------------------------------------------

-- Call 4 is planned to berth at 10-18 04:00; the ship turns up at 06:00.
SAVEPOINT t;
SELECT pg_temp.expect_status('6. arriving after the planned berth_start is allowed',
  $q$UPDATE port_call SET ata = '2026-10-18 06:00+05:30' WHERE call_id = 4$q$,
  4, 'Waiting');
ROLLBACK TO SAVEPOINT t;

-- A data-entry mistake is corrected by clearing atd.
SAVEPOINT t;
SELECT pg_temp.expect_status('7. clearing atd moves the status back to Berthed',
  $q$UPDATE port_call SET atd = NULL WHERE call_id = 1$q$,
  1, 'Berthed');
ROLLBACK TO SAVEPOINT t;

-- Manual status changes -----------------------------------------------

SELECT pg_temp.expect_error('8. setting a status that contradicts the facts',
  $q$UPDATE port_call SET call_status = 'Departed' WHERE call_id = 4$q$,
  'cannot be set to Departed');

SAVEPOINT t;
SELECT pg_temp.expect_status('9. setting the status it already has is fine',
  $q$UPDATE port_call SET call_status = 'Waiting' WHERE call_id = 3$q$,
  3, 'Waiting');
ROLLBACK TO SAVEPOINT t;

-- Fact-order CHECK constraints ----------------------------------------

SELECT pg_temp.expect_error('10. berthing before arriving',
  $q$UPDATE port_call SET atb = '2026-10-16 07:00+05:30' WHERE call_id = 3$q$,
  'chk_berth_after_arrival');

SELECT pg_temp.expect_error('11. departing before berthing',
  $q$UPDATE port_call SET atd = '2026-10-15 14:00+05:30' WHERE call_id = 2$q$,
  'chk_departure_after_berth');

SELECT pg_temp.expect_error('12. berthing without an assigned berth',
  $q$UPDATE port_call SET ata = '2026-10-19 11:00+05:30',
                          atb = '2026-10-19 12:00+05:30' WHERE call_id = 5$q$,
  'chk_atb_needs_berth');

ROLLBACK;
