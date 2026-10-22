-- =====================================================================
-- demo_transaction.sql : live demo of the customs clearance transaction.
-- psql only.  Leaves the data exactly as it was (every part rolls back).
--
--   psql -U postgres -d port_logistics -f database/demo_transaction.sql
--
-- Part 1  manual transaction:   BEGIN ... ROLLBACK by hand
-- Part 2  automatic rollback:   an error in step 3 undoes steps 1-2
-- Part 3  successful clearance: all three changes together
-- =====================================================================

\set QUIET on
\pset footer off

-- one row per container, with its filing's status and duty
\set show 'SELECT cf.filing_no, cf.filing_status, cf.duty_amount, sc.container_no, sc.container_status FROM customs_filing cf JOIN shipment_container sc ON sc.shipment_no = cf.shipment_no WHERE cf.filing_no = '

\echo
\echo '=================================================================='
\echo ' PART 1: manual transaction, undone with ROLLBACK'
\echo '=================================================================='
\echo 'Before:'
:show 'BE-2026-000104';

BEGIN;
UPDATE customs_filing     SET filing_status = 'Cleared', duty_amount = 345000
WHERE filing_no = 'BE-2026-000104';
UPDATE shipment_container SET container_status = 'Released'
WHERE shipment_no = 'BL-RTM-260005';
\echo 'Inside the transaction (changes visible to this session only):'
:show 'BE-2026-000104';
ROLLBACK;
\echo 'After ROLLBACK (back to the original values):'
:show 'BE-2026-000104';

\echo
\echo '=================================================================='
\echo ' PART 2: failure in step 3 rolls back steps 1-2 automatically'
\echo '=================================================================='
\echo 'Before: BE-2026-000103 has one container still on board (Loaded):'
:show 'BE-2026-000103';
\echo 'CALL clear_customs(BE-2026-000103, 1500000) -> expect an ERROR:'
CALL clear_customs('BE-2026-000103', 1500000);
\echo 'After the error: status, duty and OOLU5544332 are all unchanged,'
\echo 'even though the procedure had already updated them before failing:'
:show 'BE-2026-000103';

\echo
\echo '=================================================================='
\echo ' PART 3: successful clearance (all three changes at once)'
\echo '=================================================================='
BEGIN;
CALL clear_customs('BE-2026-000104', 345000);
\echo 'After clear_customs: Cleared + duty recorded + container Released:'
:show 'BE-2026-000104';
\echo 'Pending customs queue no longer lists BE-2026-000104:'
SELECT filing_no, filing_status, risk_score FROM v_pending_customs;
ROLLBACK;   -- in real use this would be COMMIT; rolled back to keep the demo repeatable

\echo
\echo 'Demo finished. Data is unchanged.'
