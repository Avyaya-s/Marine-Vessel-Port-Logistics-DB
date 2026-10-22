-- =====================================================================
-- test_company_roles.sql : checks triggers T4 (company plays the right
-- role) and T5 (a used company cannot change type).
-- Run after sample_data.sql.  Everything is rolled back at the end.
--
-- Companies: 1-3 agents, 4 5 6 10 shippers, 7 8 9 consignees.
-- All ten are already used by sample port calls / shipments.
-- =====================================================================

BEGIN;

CREATE FUNCTION pg_temp.expect_reject(label TEXT, stmt TEXT, exp_msg TEXT)
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

CREATE FUNCTION pg_temp.expect_accept(label TEXT, stmt TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE stmt;
    RAISE NOTICE 'PASS  %', label;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'FAIL  %  -> %', label, SQLERRM;
END;
$$;

-- T4: port_call.agent_id must be an agent ------------------------------

SELECT pg_temp.expect_reject('1. shipper used as a port call agent',
  $q$INSERT INTO port_call (imo_number, agent_id, eta)
     VALUES ('9705122', 4, '2026-10-25 00:00+05:30')$q$,
  'is of type shipper, not agent');

SELECT pg_temp.expect_accept('2. real agent is accepted',
  $q$INSERT INTO port_call (imo_number, agent_id, eta)
     VALUES ('9705122', 1, '2026-10-25 00:00+05:30')$q$);

SELECT pg_temp.expect_reject('3. UPDATE swapping in a consignee as agent',
  $q$UPDATE port_call SET agent_id = 7 WHERE call_id = 1$q$,
  'is of type consignee, not agent');

SELECT pg_temp.expect_reject('4. non-existent company is left to the foreign key',
  $q$UPDATE port_call SET agent_id = 999 WHERE call_id = 1$q$,
  'foreign key');

-- T4: shipment shipper / consignee -------------------------------------

SELECT pg_temp.expect_reject('5. consignee used as a shipper',
  $q$INSERT INTO shipment VALUES ('BL-TEST-1', 'IGM-2026-0001', 7, 8, 'Test cargo',
                                  'CNSZX', '85076000', 1, 1)$q$,
  'is of type consignee, not shipper');

SELECT pg_temp.expect_reject('6. agent used as a consignee',
  $q$INSERT INTO shipment VALUES ('BL-TEST-1', 'IGM-2026-0001', 4, 1, 'Test cargo',
                                  'CNSZX', '85076000', 1, 1)$q$,
  'is of type agent, not consignee');

SELECT pg_temp.expect_accept('7. shipper -> consignee is accepted',
  $q$INSERT INTO shipment VALUES ('BL-TEST-1', 'IGM-2026-0001', 4, 8, 'Test cargo',
                                  'CNSZX', '85076000', 1, 1)$q$);

-- T5: the other direction ----------------------------------------------

SELECT pg_temp.expect_reject('8. agent in use cannot be re-typed as a shipper',
  $q$UPDATE company SET company_type = 'shipper' WHERE company_id = 1$q$,
  'cannot change from agent to shipper');

SELECT pg_temp.expect_reject('9. shipper in use cannot be re-typed as a consignee',
  $q$UPDATE company SET company_type = 'consignee' WHERE company_id = 10$q$,
  'cannot change from shipper to consignee');

INSERT INTO company (company_id, company_name, company_type) VALUES (101, 'Unused Co', 'shipper');
SELECT pg_temp.expect_accept('10. unused company can change type',
  $q$UPDATE company SET company_type = 'consignee' WHERE company_id = 101$q$);

SELECT pg_temp.expect_accept('11. renaming a used company is not blocked',
  $q$UPDATE company SET company_name = 'Seaways Shipping Agency Ltd' WHERE company_id = 1$q$);

ROLLBACK;
