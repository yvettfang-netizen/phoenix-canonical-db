BEGIN;

CREATE SCHEMA IF NOT EXISTS canonical_migrations;
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS consent;
CREATE SCHEMA IF NOT EXISTS audit;
CREATE SCHEMA IF NOT EXISTS integration;
CREATE SCHEMA IF NOT EXISTS docs;
CREATE SCHEMA IF NOT EXISTS casework;

CREATE TABLE IF NOT EXISTS canonical_migrations.applied (
    migration_name text PRIMARY KEY,
    sha256 char(64) NOT NULL,
    applied_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

DO $roles$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'phoenix_canonical_migrator') THEN
        CREATE ROLE phoenix_canonical_migrator NOLOGIN NOINHERIT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'phoenix_canonical_app') THEN
        CREATE ROLE phoenix_canonical_app NOLOGIN NOINHERIT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'phoenix_canonical_reader') THEN
        CREATE ROLE phoenix_canonical_reader NOLOGIN NOINHERIT;
    END IF;
END
$roles$;

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA canonical_migrations FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA canonical_migrations FROM PUBLIC;
GRANT USAGE ON SCHEMA canonical_migrations TO phoenix_canonical_migrator;
GRANT SELECT, INSERT ON canonical_migrations.applied TO phoenix_canonical_migrator;

DO $database_grants$
BEGIN
    EXECUTE format('REVOKE CONNECT ON DATABASE %I FROM PUBLIC', current_database());
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO phoenix_canonical_migrator, phoenix_canonical_app, phoenix_canonical_reader', current_database());
END
$database_grants$;
GRANT USAGE, CREATE ON SCHEMA core, consent, audit, integration, docs, casework TO phoenix_canonical_migrator;
GRANT USAGE ON SCHEMA core, consent, audit, integration, docs, casework TO phoenix_canonical_app, phoenix_canonical_reader;

-- Future tables must grant privileges explicitly in their own reviewed migrations.
-- No identity, family, guardian, consent grant, file, or case master tables are created here.
COMMIT;
