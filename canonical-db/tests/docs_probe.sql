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
CREATE TABLE acceptance_probe.document_controls (
  document_id integer PRIMARY KEY,
  withdrawn boolean NOT NULL DEFAULT false,
  legal_hold boolean NOT NULL DEFAULT false
);
CREATE TABLE acceptance_probe.mock_storage_objects (
  object_key text PRIMARY KEY,
  document_id integer NOT NULL REFERENCES acceptance_probe.document_controls
);
CREATE TABLE acceptance_probe.submissions (
  submission_id integer PRIMARY KEY,
  status text NOT NULL CHECK (status IN ('PREPARING','SUBMITTED'))
);
CREATE TABLE acceptance_probe.submission_items (
  submission_id integer NOT NULL REFERENCES acceptance_probe.submissions,
  item_no integer NOT NULL,
  version_id integer NOT NULL REFERENCES acceptance_probe.document_versions ON DELETE RESTRICT,
  pinned_sha256 char(64) NOT NULL,
  PRIMARY KEY (submission_id, item_no)
);
CREATE FUNCTION acceptance_probe.reject_version_change() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
  RAISE EXCEPTION 'document version is immutable';
END
$fn$;
CREATE TRIGGER immutable_version BEFORE UPDATE OR DELETE ON acceptance_probe.document_versions
  FOR EACH ROW EXECUTE FUNCTION acceptance_probe.reject_version_change();
CREATE FUNCTION acceptance_probe.protect_submission() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
  IF TG_OP = 'DELETE' OR OLD.status = 'SUBMITTED' THEN
    RAISE EXCEPTION 'submitted submission cannot be changed or removed';
  END IF;
  IF NEW.status = 'SUBMITTED' AND EXISTS (
    SELECT 1 FROM acceptance_probe.submission_items i
    JOIN acceptance_probe.document_versions v ON v.version_id = i.version_id
    JOIN acceptance_probe.document_controls c ON c.document_id = v.document_id
    WHERE i.submission_id = NEW.submission_id AND c.withdrawn
  ) THEN
    RAISE EXCEPTION 'withdrawn document cannot enter a new submitted manifest';
  END IF;
  RETURN NEW;
END
$fn$;
CREATE TRIGGER immutable_submitted_submission BEFORE UPDATE OR DELETE ON acceptance_probe.submissions
  FOR EACH ROW EXECUTE FUNCTION acceptance_probe.protect_submission();
CREATE FUNCTION acceptance_probe.protect_submission_item() RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE
  target_submission integer;
  expected_digest char(64);
BEGIN
  target_submission := CASE WHEN TG_OP = 'INSERT' THEN NEW.submission_id ELSE OLD.submission_id END;
  IF EXISTS (SELECT 1 FROM acceptance_probe.submissions WHERE submission_id = target_submission AND status = 'SUBMITTED') THEN
    RAISE EXCEPTION 'submitted manifest is immutable';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  IF EXISTS (SELECT 1 FROM acceptance_probe.submissions WHERE submission_id = NEW.submission_id AND status = 'SUBMITTED') THEN
    RAISE EXCEPTION 'cannot move item into submitted manifest';
  END IF;
  SELECT sha256 INTO expected_digest FROM acceptance_probe.document_versions WHERE version_id = NEW.version_id;
  IF expected_digest IS NULL THEN RETURN NEW; END IF;
  IF expected_digest IS DISTINCT FROM NEW.pinned_sha256 THEN
    RAISE EXCEPTION 'manifest digest does not match pinned version';
  END IF;
  IF EXISTS (
    SELECT 1 FROM acceptance_probe.document_versions v
    JOIN acceptance_probe.document_controls c ON c.document_id = v.document_id
    WHERE v.version_id = NEW.version_id AND c.withdrawn
  ) THEN
    RAISE EXCEPTION 'withdrawn document cannot be added to a new manifest';
  END IF;
  RETURN NEW;
END
$fn$;
CREATE TRIGGER immutable_submitted_item BEFORE INSERT OR UPDATE OR DELETE ON acceptance_probe.submission_items
  FOR EACH ROW EXECUTE FUNCTION acceptance_probe.protect_submission_item();
CREATE FUNCTION acceptance_probe.protect_mock_object() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
  IF EXISTS (SELECT 1 FROM acceptance_probe.document_controls WHERE document_id = OLD.document_id AND legal_hold) THEN
    RAISE EXCEPTION 'legal hold prevents mock object purge';
  END IF;
  RETURN OLD;
END
$fn$;
CREATE TRIGGER prevent_held_mock_purge BEFORE DELETE ON acceptance_probe.mock_storage_objects
  FOR EACH ROW EXECUTE FUNCTION acceptance_probe.protect_mock_object();
INSERT INTO acceptance_probe.document_controls(document_id) VALUES (10);
INSERT INTO acceptance_probe.mock_storage_objects VALUES ('synthetic-object-10',10);
INSERT INTO acceptance_probe.document_versions VALUES
  (1, 10, 1, repeat('a',64), 'mock/key/v1'),
  (2, 10, 2, repeat('b',64), 'mock/key/v2');
INSERT INTO acceptance_probe.submissions VALUES (20,'PREPARING');
INSERT INTO acceptance_probe.submissions VALUES (21,'PREPARING');
INSERT INTO acceptance_probe.submission_items VALUES (20,1,1,repeat('a',64));
INSERT INTO acceptance_probe.submission_items VALUES (21,1,1,repeat('a',64));
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
    INSERT INTO acceptance_probe.submission_items VALUES (20,2,2,repeat('b',64));
  EXCEPTION WHEN raise_exception THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'submitted manifest append allowed'; END IF;

  blocked := false;
  BEGIN
    UPDATE acceptance_probe.submission_items SET submission_id = 20, item_no = 2 WHERE submission_id = 21 AND item_no = 1;
  EXCEPTION WHEN raise_exception THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'item moved into submitted manifest'; END IF;

  blocked := false;
  BEGIN
    UPDATE acceptance_probe.submissions SET status = 'PREPARING' WHERE submission_id = 20;
  EXCEPTION WHEN raise_exception THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'submitted status reverted'; END IF;

  blocked := false;
  BEGIN
    DELETE FROM acceptance_probe.submissions WHERE submission_id = 20;
  EXCEPTION WHEN raise_exception THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'submitted submission deleted'; END IF;

  blocked := false;
  BEGIN
    INSERT INTO acceptance_probe.document_versions VALUES (3,10,1,repeat('d',64),'mock/key/duplicate');
  EXCEPTION WHEN unique_violation THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'duplicate document version number allowed'; END IF;

  blocked := false;
  BEGIN
    INSERT INTO acceptance_probe.submission_items VALUES (21,2,999,repeat('e',64));
  EXCEPTION WHEN foreign_key_violation THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'manifest accepted a missing version'; END IF;

  blocked := false;
  BEGIN
    INSERT INTO acceptance_probe.submission_items VALUES (21,2,2,repeat('e',64));
  EXCEPTION WHEN raise_exception THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'manifest accepted a false snapshot digest'; END IF;

  IF (SELECT version_id FROM acceptance_probe.submission_items WHERE submission_id = 20 AND item_no = 1) <> 1 OR
     (SELECT pinned_sha256 FROM acceptance_probe.submission_items WHERE submission_id = 20 AND item_no = 1) <> repeat('a',64) OR
     (SELECT count(*) FROM acceptance_probe.submission_items WHERE version_id = 1) <> 2 THEN
    RAISE EXCEPTION 'pinned version changed';
  END IF;
END
$test$;
UPDATE acceptance_probe.document_controls SET withdrawn = true, legal_hold = true WHERE document_id = 10;
INSERT INTO acceptance_probe.submissions VALUES (22,'PREPARING');
DO $test$
DECLARE blocked boolean;
BEGIN
  blocked := false;
  BEGIN
    INSERT INTO acceptance_probe.submission_items VALUES (22,1,1,repeat('a',64));
  EXCEPTION WHEN raise_exception THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'withdrawn version added to new manifest'; END IF;

  blocked := false;
  BEGIN
    UPDATE acceptance_probe.submissions SET status = 'SUBMITTED' WHERE submission_id = 21;
  EXCEPTION WHEN raise_exception THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'draft with withdrawn version was submitted'; END IF;

  blocked := false;
  BEGIN
    DELETE FROM acceptance_probe.mock_storage_objects WHERE object_key = 'synthetic-object-10';
  EXCEPTION WHEN raise_exception THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'legal hold allowed mock object purge'; END IF;

  IF (SELECT status FROM acceptance_probe.submissions WHERE submission_id = 20) <> 'SUBMITTED' OR
     (SELECT pinned_sha256 FROM acceptance_probe.submission_items WHERE submission_id = 20 AND item_no = 1) <> repeat('a',64) OR
     NOT EXISTS (SELECT 1 FROM acceptance_probe.mock_storage_objects WHERE object_key = 'synthetic-object-10') THEN
    RAISE EXCEPTION 'existing submitted evidence was not preserved';
  END IF;
END
$test$;
ROLLBACK;
