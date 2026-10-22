-- =====================================================================
-- run_tests.sql : run every test script (each one rolls back).
-- psql only.  Look for FAIL in the output; every line should say PASS.
--
--   psql -U postgres -d port_logistics -f database/run_tests.sql
-- =====================================================================

\set QUIET on
\pset tuples_only on
\pset format unaligned

\echo '== test_berth_overlap'
\ir tests/test_berth_overlap.sql
\echo '== test_berth_fit'
\ir tests/test_berth_fit.sql
\echo '== test_allocate_berth'
\ir tests/test_allocate_berth.sql
\echo '== test_call_status'
\ir tests/test_call_status.sql
\echo '== test_views'
\ir tests/test_views.sql
\echo '== test_clear_customs'
\ir tests/test_clear_customs.sql
\echo '== test_company_roles'
\ir tests/test_company_roles.sql
\echo '== test_roles'
\ir tests/test_roles.sql
