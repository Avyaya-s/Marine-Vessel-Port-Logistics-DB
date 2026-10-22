-- =====================================================================
-- test_roles.sql : checks that nl_assistant can read but never write.
-- Run after rebuild (roles.sql must have run).  Rolled back at the end.
--
-- SET LOCAL ROLE makes the rest of the transaction run with
-- nl_assistant's privileges, exactly as the app would.
-- =====================================================================

BEGIN;

CREATE FUNCTION pg_temp.expect_denied(label TEXT, stmt TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE stmt;
    RAISE NOTICE 'FAIL  %  (statement was accepted)', label;
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS  %  -> %', label, SQLERRM;
WHEN OTHERS THEN
    RAISE NOTICE 'FAIL  %  -> wrong error: %', label, SQLERRM;
END;
$$;

CREATE FUNCTION pg_temp.expect_allowed(label TEXT, stmt TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    n BIGINT;
BEGIN
    EXECUTE stmt INTO n;
    RAISE NOTICE 'PASS  %  -> % row(s)', label, n;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'FAIL  %  -> %', label, SQLERRM;
END;
$$;

-- Role settings (checked as the admin, before switching) ----------------
DO $$
DECLARE
    cfg TEXT;
BEGIN
    SELECT array_to_string(rolconfig, ', ') INTO cfg FROM pg_roles WHERE rolname = 'nl_assistant';
    IF cfg LIKE '%default_transaction_read_only=on%' AND cfg LIKE '%statement_timeout=5s%' THEN
        RAISE NOTICE 'PASS  0. nl_assistant is read-only by default with a 5 s timeout  -> %', cfg;
    ELSE
        RAISE NOTICE 'FAIL  0. nl_assistant settings  -> %', cfg;
    END IF;
END $$;

SET LOCAL ROLE nl_assistant;

-- Reading is allowed ----------------------------------------------------
SELECT pg_temp.expect_allowed('1. SELECT from a table',
  $q$SELECT count(*) FROM port_call$q$);
SELECT pg_temp.expect_allowed('2. SELECT from a view',
  $q$SELECT count(*) FROM v_pending_customs$q$);
SELECT pg_temp.expect_allowed('3. JOIN across tables',
  $q$SELECT count(*) FROM shipment s JOIN company c ON c.company_id = s.consignee_id$q$);

-- Everything else is denied ---------------------------------------------
SELECT pg_temp.expect_denied('4. INSERT',
  $q$INSERT INTO berth VALUES ('B99', 100, 5, 'Bulk')$q$);
SELECT pg_temp.expect_denied('5. UPDATE',
  $q$UPDATE customs_filing SET filing_status = 'Cleared'$q$);
SELECT pg_temp.expect_denied('6. DELETE',
  $q$DELETE FROM inspection$q$);
SELECT pg_temp.expect_denied('7. DROP TABLE',
  $q$DROP TABLE vessel$q$);
SELECT pg_temp.expect_denied('8. CREATE TABLE in the public schema',
  $q$CREATE TABLE public.hack (x INT)$q$);
SELECT pg_temp.expect_denied('9. CALL a procedure that writes',
  $q$CALL allocate_berth(5)$q$);
SELECT pg_temp.expect_denied('10. TRUNCATE',
  $q$TRUNCATE shipment_container$q$);

ROLLBACK;
