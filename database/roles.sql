-- =====================================================================
-- roles.sql : read-only database user for the NL query assistant
-- (run after views.sql; safe to re-run).
--
-- The NL assistant sends LLM-generated SQL to the database.  The app
-- only allows SELECT, but the real guarantee is here: the account it
-- connects with cannot change anything, whatever SQL it is given.
--
--   port_readonly  group role (NOLOGIN): holds the privileges
--   nl_assistant   login role: member of port_readonly, used by the app
--
-- Roles belong to the whole PostgreSQL server, not to one database, so
-- schema.sql dropping the tables does not drop them.  The table GRANTs
-- are lost when tables are recreated, which is why rebuild.sql re-runs
-- this file and why ALTER DEFAULT PRIVILEGES is set below.
--
-- The password is NOT stored in this file (it is committed to Git).
-- Set it once by hand:
--   ALTER ROLE nl_assistant PASSWORD 'choose-a-password';
-- Until then the role cannot log in with a password.
-- =====================================================================

-- CREATE ROLE has no IF NOT EXISTS, so check first
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'port_readonly') THEN
        CREATE ROLE port_readonly NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nl_assistant') THEN
        CREATE ROLE nl_assistant LOGIN;
    END IF;
END $$;

GRANT port_readonly TO nl_assistant;

-- privileges go to the group role, never directly to the login role
DO $$
BEGIN
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO port_readonly', current_database());
END $$;
GRANT USAGE  ON SCHEMA public                TO port_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public  TO port_readonly;   -- includes views

-- tables and views created later (by this user) get SELECT automatically
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO port_readonly;

-- procedures are executable by everyone by default; only admins should
-- allocate berths or clear customs
REVOKE EXECUTE ON PROCEDURE allocate_berth(INTEGER, INTERVAL, VARCHAR, TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC;
REVOKE EXECUTE ON PROCEDURE clear_customs(VARCHAR, NUMERIC, INTEGER) FROM PUBLIC;

-- defence in depth for LLM-generated SQL:
--   every transaction is read-only even if a GRANT is ever too wide,
--   a runaway query (e.g. an accidental cross join) is killed after 5 s,
--   and the app cannot open more than 5 connections.
ALTER ROLE nl_assistant SET default_transaction_read_only = on;
ALTER ROLE nl_assistant SET statement_timeout = '5s';
ALTER ROLE nl_assistant CONNECTION LIMIT 5;
