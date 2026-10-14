BEGIN;

CREATE TABLE docs.documents (
  document_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(document_id)),
  family_id uuid NOT NULL REFERENCES core.families,
  subject_person_id uuid NOT NULL REFERENCES core.people,
  data_class text NOT NULL CHECK (data_class IN ('GENERAL','EDUCATION','IDENTITY_SENSITIVE')),
  document_kind text NOT NULL CHECK (length(btrim(document_kind)) BETWEEN 1 AND 100),
  retention_until timestamptz NOT NULL,
  withdrawn_at timestamptz,
  legal_hold boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp()
);
CREATE TABLE docs.document_versions (
  version_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(version_id)),
  document_id uuid NOT NULL REFERENCES docs.documents,
  version_no integer NOT NULL CHECK (version_no > 0),
  content_sha256 char(64) NOT NULL CHECK (content_sha256 ~ '^[0-9a-f]{64}$'),
  storage_key text NOT NULL CHECK (storage_key !~ '^(https?|file)://' AND length(storage_key) BETWEEN 10 AND 500),
  size_bytes bigint NOT NULL CHECK (size_bytes >= 0),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  UNIQUE (document_id, version_no),
  UNIQUE (storage_key)
);
CREATE TABLE docs.submission_manifests (
  submission_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(submission_id)),
  family_id uuid NOT NULL REFERENCES core.families,
  subject_person_id uuid NOT NULL REFERENCES core.people,
  target_kind text NOT NULL CHECK (target_kind IN ('EDUCATION_APPLICATION','IDENTITY_CASE')),
  target_id uuid NOT NULL CHECK (core.is_uuid_v7(target_id)),
  status text NOT NULL CHECK (status IN ('PREPARING','SUBMITTED')),
  prepared_by uuid NOT NULL REFERENCES core.people,
  confirmed_by uuid REFERENCES core.people,
  submitted_by uuid REFERENCES core.people,
  prepared_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  submitted_at timestamptz,
  CHECK (
    (status = 'PREPARING' AND submitted_by IS NULL AND submitted_at IS NULL)
    OR (status = 'SUBMITTED' AND confirmed_by IS NOT NULL AND submitted_by IS NOT NULL AND submitted_at IS NOT NULL)
  )
);
CREATE TABLE docs.submission_items (
  submission_id uuid NOT NULL REFERENCES docs.submission_manifests,
  item_no integer NOT NULL CHECK (item_no > 0),
  version_id uuid NOT NULL REFERENCES docs.document_versions,
  pinned_sha256 char(64) NOT NULL CHECK (pinned_sha256 ~ '^[0-9a-f]{64}$'),
  PRIMARY KEY (submission_id, item_no),
  UNIQUE (submission_id, version_id)
);

CREATE FUNCTION docs.can_read_document(p_subject_person_id uuid, p_data_class text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, consent, integration
RETURN
  consent.has_active_consent(p_subject_person_id, 'DOCUMENT_READ', p_data_class)
  AND CASE auth.current_channel()
    WHEN 'FAMILY' THEN (
      auth.current_actor_person_id() = p_subject_person_id
      OR core.has_verified_guardian_authority(
        p_subject_person_id,
        CASE WHEN p_data_class = 'IDENTITY_SENSITIVE' THEN 'IDENTITY' ELSE 'GENERAL' END
      )
    )
    WHEN 'ADVISOR' THEN true
    WHEN 'PARTNER' THEN integration.has_active_channel_grant(p_subject_person_id)
    ELSE false
  END;

CREATE FUNCTION docs.protect_document_version() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
  RAISE EXCEPTION 'DOCUMENT_VERSION_IMMUTABLE';
END
$fn$;
CREATE TRIGGER immutable_document_version BEFORE UPDATE OR DELETE ON docs.document_versions
FOR EACH ROW EXECUTE FUNCTION docs.protect_document_version();

CREATE FUNCTION docs.validate_submission_item() RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE
  manifest_status text;
  expected_digest char(64);
  withdrawn timestamptz;
  version_family uuid;
  manifest_family uuid;
BEGIN
  IF TG_OP IN ('UPDATE','DELETE') THEN
    SELECT status INTO manifest_status FROM docs.submission_manifests WHERE submission_id = OLD.submission_id;
    IF manifest_status = 'SUBMITTED' THEN RAISE EXCEPTION 'SUBMITTED_MANIFEST_IMMUTABLE'; END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  END IF;
  SELECT m.status, m.family_id INTO manifest_status, manifest_family
    FROM docs.submission_manifests m WHERE m.submission_id = NEW.submission_id;
  IF manifest_status = 'SUBMITTED' THEN RAISE EXCEPTION 'SUBMITTED_MANIFEST_IMMUTABLE'; END IF;
  SELECT v.content_sha256, d.withdrawn_at, d.family_id
    INTO expected_digest, withdrawn, version_family
    FROM docs.document_versions v JOIN docs.documents d ON d.document_id = v.document_id
    WHERE v.version_id = NEW.version_id;
  IF expected_digest IS NULL OR expected_digest <> NEW.pinned_sha256 THEN RAISE EXCEPTION 'PINNED_DIGEST_MISMATCH'; END IF;
  IF withdrawn IS NOT NULL THEN RAISE EXCEPTION 'WITHDRAWN_DOCUMENT_NEW_USE_DENIED'; END IF;
  IF version_family <> manifest_family THEN RAISE EXCEPTION 'DOCUMENT_FAMILY_MISMATCH'; END IF;
  RETURN NEW;
END
$fn$;
CREATE TRIGGER validate_submission_item BEFORE INSERT OR UPDATE OR DELETE ON docs.submission_items
FOR EACH ROW EXECUTE FUNCTION docs.validate_submission_item();

CREATE FUNCTION docs.protect_submission_manifest() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
  IF TG_OP = 'DELETE' OR OLD.status = 'SUBMITTED' THEN
    RAISE EXCEPTION 'SUBMITTED_MANIFEST_IMMUTABLE';
  END IF;
  IF NEW.status = 'SUBMITTED' THEN
    IF NOT EXISTS (SELECT 1 FROM docs.submission_items WHERE submission_id = NEW.submission_id) THEN
      RAISE EXCEPTION 'SUBMISSION_ITEMS_REQUIRED';
    END IF;
    IF EXISTS (
      SELECT 1 FROM docs.submission_items i
      JOIN docs.document_versions v ON v.version_id = i.version_id
      JOIN docs.documents d ON d.document_id = v.document_id
      WHERE i.submission_id = NEW.submission_id AND d.withdrawn_at IS NOT NULL
    ) THEN
      RAISE EXCEPTION 'WITHDRAWN_DOCUMENT_NEW_USE_DENIED';
    END IF;
  END IF;
  RETURN NEW;
END
$fn$;
CREATE TRIGGER protect_submission_manifest BEFORE UPDATE OR DELETE ON docs.submission_manifests
FOR EACH ROW EXECUTE FUNCTION docs.protect_submission_manifest();

CREATE FUNCTION docs.can_purge_document(p_document_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, docs
RETURN EXISTS (
  SELECT 1 FROM docs.documents d
  WHERE d.document_id = p_document_id
    AND d.retention_until <= transaction_timestamp()
    AND NOT d.legal_hold
    AND NOT EXISTS (
      SELECT 1 FROM docs.document_versions v
      JOIN docs.submission_items i ON i.version_id = v.version_id
      JOIN docs.submission_manifests m ON m.submission_id = i.submission_id
      WHERE v.document_id = d.document_id AND m.status = 'SUBMITTED'
    )
);

ALTER TABLE docs.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE docs.document_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE docs.submission_manifests ENABLE ROW LEVEL SECURITY;
ALTER TABLE docs.submission_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY documents_read ON docs.documents FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (family_id = auth.current_family_id() AND docs.can_read_document(subject_person_id, data_class));
CREATE POLICY document_versions_read ON docs.document_versions FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (EXISTS (SELECT 1 FROM docs.documents d WHERE d.document_id = document_versions.document_id));
CREATE POLICY manifests_read ON docs.submission_manifests FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (family_id = auth.current_family_id() AND docs.can_read_document(subject_person_id, CASE WHEN target_kind = 'IDENTITY_CASE' THEN 'IDENTITY_SENSITIVE' ELSE 'EDUCATION' END));
CREATE POLICY manifest_items_read ON docs.submission_items FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (EXISTS (SELECT 1 FROM docs.submission_manifests m WHERE m.submission_id = submission_items.submission_id));

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA docs FROM PUBLIC;
GRANT EXECUTE ON FUNCTION docs.can_read_document(uuid,text) TO phoenix_canonical_app, phoenix_canonical_reader;
GRANT SELECT ON docs.documents, docs.document_versions, docs.submission_manifests, docs.submission_items TO phoenix_canonical_app, phoenix_canonical_reader;

COMMIT;
