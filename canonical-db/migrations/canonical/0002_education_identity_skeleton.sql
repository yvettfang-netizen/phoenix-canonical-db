BEGIN;

-- Phase 2A namespace only. No Person, Student, Guardian, application or case tables.
CREATE SCHEMA IF NOT EXISTS education;
CREATE SCHEMA IF NOT EXISTS identity;

REVOKE ALL ON SCHEMA education, identity FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA education, identity TO phoenix_canonical_migrator;
GRANT USAGE ON SCHEMA education, identity TO phoenix_canonical_app, phoenix_canonical_reader;

COMMIT;
