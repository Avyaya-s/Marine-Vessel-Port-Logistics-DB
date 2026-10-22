-- =====================================================================
-- test_clear_customs.sql : checks the clear_customs() transaction.
-- Run after sample_data.sql.  Everything is rolled back at the end;
-- each test runs inside its own savepoint so tests are independent.
--
-- Filings in sample_data.sql:
--   BE-101 Cleared                          (BL-SZX-260001)
--   BE-102 Held, latest inspection Pending  (BL-SZX-260002, CMAU9988776 Held)
--   BE-103 Under Review                     (BL-RTM-260004, OOLU5544332 Discharged,
--                                                           HLXU1122334 Loaded)
--   BE-104 Filed                            (BL-RTM-260005, TGHU3456789 Discharged)
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

-- one line summarising a filing and its containers
CREATE FUNCTION pg_temp.state(p_filing TEXT) RETURNS TEXT
LANGUAGE sql AS $$
    SELECT cf.filing_status || ' duty=' || coalesce(cf.duty_amount::text, 'null') || ' | '
           || coalesce(string_agg(sc.container_no || '=' || sc.container_status, ' '
                                  ORDER BY sc.container_no), 'no containers')
    FROM customs_filing cf
    LEFT JOIN shipment_container sc ON sc.shipment_no = cf.shipment_no
    WHERE cf.filing_no = p_filing
    GROUP BY cf.filing_status, cf.duty_amount;
$$;

-- Success -------------------------------------------------------------

SAVEPOINT t;
CALL clear_customs('BE-2026-000104', 345000);
SELECT pg_temp.expect('1. all three changes applied together',
  $q$SELECT pg_temp.state('BE-2026-000104')$q$,
  'Cleared duty=345000.00 | TGHU3456789=Released');
SELECT pg_temp.expect('2. cleared filing leaves the pending-customs queue',
  $q$SELECT count(*)::text FROM v_pending_customs WHERE filing_no = 'BE-2026-000104'$q$,
  '0');
ROLLBACK TO SAVEPOINT t;

-- Atomicity: failure after steps 1-2 have already run -----------------

SAVEPOINT t;
SELECT pg_temp.expect('3a. before: BE-103 under review, one container still aboard',
  $q$SELECT pg_temp.state('BE-2026-000103')$q$,
  'Under Review duty=null | HLXU1122334=Loaded OOLU5544332=Discharged');
SELECT pg_temp.expect_error('3b. clearing fails at step 3 (container on board)',
  $q$CALL clear_customs('BE-2026-000103', 1500000)$q$,
  'HLXU1122334 still on board');
SELECT pg_temp.expect('3c. after: NOTHING changed (status, duty and OOLU all rolled back)',
  $q$SELECT pg_temp.state('BE-2026-000103')$q$,
  'Under Review duty=null | HLXU1122334=Loaded OOLU5544332=Discharged');
ROLLBACK TO SAVEPOINT t;

-- Once the last container is discharged, the same call succeeds.
SAVEPOINT t;
UPDATE shipment_container SET container_status = 'Discharged' WHERE container_no = 'HLXU1122334';
CALL clear_customs('BE-2026-000103', 1500000);
SELECT pg_temp.expect('4. same filing clears once every container is discharged',
  $q$SELECT pg_temp.state('BE-2026-000103')$q$,
  'Cleared duty=1500000.00 | HLXU1122334=Released OOLU5544332=Released');
ROLLBACK TO SAVEPOINT t;

-- Rejected up front ---------------------------------------------------

SELECT pg_temp.expect_error('5. latest inspection still pending',
  $q$CALL clear_customs('BE-2026-000102', 200000)$q$,
  'latest inspection is Pending');

SELECT pg_temp.expect_error('6. filing already cleared',
  $q$CALL clear_customs('BE-2026-000101', 850000)$q$,
  'already cleared');

SELECT pg_temp.expect_error('7. filing that does not exist',
  $q$CALL clear_customs('BE-2026-999999', 100)$q$,
  'does not exist');

SELECT pg_temp.expect_error('8. negative duty',
  $q$CALL clear_customs('BE-2026-000104', -5)$q$,
  'Duty must be zero or more');

-- A held filing can be cleared once a new inspection comes back Clear.
SAVEPOINT t;
INSERT INTO inspection (filing_no, inspection_no, inspection_date, officer_name, result, remarks)
VALUES ('BE-2026-000102', 3, '2026-10-15', 'S. Iyer', 'Clear', 'Revised invoice accepted');
CALL clear_customs('BE-2026-000102', 230000);
SELECT pg_temp.expect('9. held filing clears after a Clear re-inspection (Held -> Released)',
  $q$SELECT pg_temp.state('BE-2026-000102')$q$,
  'Cleared duty=230000.00 | CMAU9988776=Released');
ROLLBACK TO SAVEPOINT t;

-- Exports: filing cleared, containers untouched.
SAVEPOINT t;
UPDATE customs_filing SET filing_status = 'Filed', duty_amount = NULL
WHERE filing_no = 'SB-2026-000201';
CALL clear_customs('SB-2026-000201', 0);
SELECT pg_temp.expect('10. shipping bill (export): containers are not released',
  $q$SELECT pg_temp.state('SB-2026-000201')$q$,
  'Cleared duty=0.00 | TCLU6677889=Loaded');
ROLLBACK TO SAVEPOINT t;

ROLLBACK;
