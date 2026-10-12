BEGIN;
CREATE SCHEMA acceptance_atomicity_probe;
CREATE TABLE acceptance_atomicity_probe.synthetic_only (id integer PRIMARY KEY);
INSERT INTO acceptance_atomicity_probe.synthetic_only VALUES (1);
DO $forced_failure$
BEGIN
  RAISE EXCEPTION 'SYNTHETIC FORCED MIGRATION FAILURE';
END
$forced_failure$;
COMMIT;
