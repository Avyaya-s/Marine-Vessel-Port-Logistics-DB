-- =====================================================================
-- rebuild.sql : drop and recreate the whole database in one go.
-- psql only (\ir is a psql command, pgAdmin cannot run this file).
--
--   psql -U postgres -d port_logistics -f database/rebuild.sql
-- =====================================================================

\set ON_ERROR_STOP on
\set QUIET on
SET client_min_messages = warning;   -- hide the "does not exist, skipping" notices

\echo '1/6 schema.sql'
\ir schema.sql
\echo '2/6 triggers.sql'
\ir triggers.sql
\echo '3/6 procedures.sql'
\ir procedures.sql
\echo '4/6 views.sql'
\ir views.sql
\echo '5/6 roles.sql'
\ir roles.sql
\echo '6/6 sample_data.sql'
\ir sample_data.sql

\echo 'Rebuild complete.'
