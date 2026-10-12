-- Disposable synthetic integrity probe. This is not the approved docs schema.
BEGIN;
CREATE SCHEMA acceptance_probe;
CREATE TABLE acceptance_probe.document_versions (
  version_id integer PRIMARY KEY,
  document_id integer NOT NULL,
  version_no integer NOT NULL CHECK (version_no > 0),
  sha256 char(64) NOT NULL,
  storage_ref text NOT NULL,
  UNIQUE (document_id, version_no)
);
CREATE TABLE acceptance_probe.submissions (
  submission_id integer PRIMARY KEY,
  status text NOT NULL CHECK (status IN ('PREPARING','SUBMITTED'))
);
CREATE TABLE acceptance_probe.submission_items (
  submission_id integer NOT NULL REFERENCES acceptance_probe.submissions,
  item_no integer NOT NULL,
  version_id integer NOT NULL REFERENCES acceptance_probe.document_versions ON DELETE RESTRICT,
  PRIMARY KEY (submission_id, item_no)
);
CREATE FUNCTION acceptance_probe.reject_version_change() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
  RAISE EXCEPTION 'document version is immutable';
END
$fn$;
CREATE TRIGGER immutable_version BEFORE UPDATE OR DELETE ON acceptance_probe.document_versions
  FOR EACH ROW EXECUTE FUNCTION acceptance_probe.reject_version_change();
CREATE FUNCTION acceptance_probe.reject_submitted_item_change() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
  IF EXISTS (SELECT 1 FROM acceptance_probe.submissions WHERE submission_id = OLD.submission_id AND status = 'SUBMITTED') THEN
    RAISE EXCEPTION 'submitted manifest is immutable';
  END IF;
  RETURN OLD;
END
$fn$;
CREATE TRIGGER immutable_submitted_item BEFORE UPDATE OR DELETE ON acceptance_probe.submission_items
  FOR EACH ROW EXECUTE FUNCTION acceptance_probe.reject_submitted_item_change();
INSERT INTO acceptance_probe.document_versions VALUES
  (1, 10, 1, repeat('a',64), 'mock/key/v1'),
  (2, 10, 2, repeat('b',64), 'mock/key/v2');
INSERT INTO acceptance_probe.submissions VALUES (20,'PREPARING');
INSERT INTO acceptance_probe.submissions VALUES (21,'PREPARING');
INSERT INTO acceptance_probe.submission_items VALUES (20,1,1);
UPDATE acceptance_probe.submissions SET status = 'SUBMITTED' WHERE submission_id = 20;
DO $test$
DECLARE blocked boolean;
BEGIN
  blocked := false;
  BEGIN
    UPDATE acceptance_probe.document_versions SET sha256 = repeat('c',64) WHERE version_id = 1;
  EXCEPTION WHEN raise_exception THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'silent version overwrite allowed'; END IF;

  blocked := false;
  BEGIN
    UPDATE acceptance_probe.submission_items SET version_id = 2 WHERE submission_id = 20 AND item_no = 1;
  EXCEPTION WHEN raise_exception THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'submitted manifest rewrite allowed'; END IF;

  blocked := false;
  BEGIN
    DELETE FROM acceptance_probe.submission_items WHERE submission_id = 20 AND item_no = 1;
  EXCEPTION WHEN raise_exception THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'submitted manifest deletion allowed'; END IF;

  blocked := false;
  BEGIN
    INSERT INTO acceptance_probe.document_versions VALUES (3,10,1,repeat('d',64),'mock/key/duplicate');
  EXCEPTION WHEN unique_violation THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'duplicate document version number allowed'; END IF;

  blocked := false;
  BEGIN
    INSERT INTO acceptance_probe.submission_items VALUES (21,1,999);
  EXCEPTION WHEN foreign_key_violation THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'manifest accepted a missing version'; END IF;

  IF (SELECT version_id FROM acceptance_probe.submission_items WHERE submission_id = 20 AND item_no = 1) <> 1 THEN
    RAISE EXCEPTION 'pinned version changed';
  END IF;
END
$test$;
ROLLBACK;
