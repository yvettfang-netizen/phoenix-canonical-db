BEGIN;

-- R-8: health's reader may inspect the migration ledger without DDL rights.
GRANT USAGE ON SCHEMA canonical_migrations TO phoenix_canonical_reader;

COMMIT;
