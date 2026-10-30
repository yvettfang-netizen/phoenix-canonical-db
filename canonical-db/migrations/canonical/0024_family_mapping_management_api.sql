BEGIN;

-- Founder-approved FM-1..FM-8. This forward migration adds a controlled,
-- append-preserving lifecycle for real PHOENIX_FAMILY_OS family mappings.
-- It creates no mapping and does not change any historical migration.
ALTER TABLE integration.legacy_id_mappings
  ADD COLUMN managed_lifecycle_version text,
  ADD COLUMN proposed_by_principal_id uuid REFERENCES auth.principals,
  ADD COLUMN proposed_at timestamptz,
  ADD COLUMN proposal_request_nonce uuid,
  ADD COLUMN application_ownership_evidence_ref text,
  ADD COLUMN application_ownership_evidence_sha256 text,
  ADD COLUMN canonical_membership_evidence_ref text,
  ADD COLUMN canonical_membership_evidence_sha256 text,
  ADD COLUMN founder_approval_evidence_ref text,
  ADD COLUMN founder_approval_evidence_sha256 text,
  ADD COLUMN decided_by_principal_id uuid REFERENCES auth.principals,
  ADD COLUMN verification_request_nonce uuid,
  ADD COLUMN revoked_by_principal_id uuid REFERENCES auth.principals,
  ADD COLUMN revoked_at timestamptz,
  ADD COLUMN revoke_request_nonce uuid,
  ADD COLUMN superseded_by_mapping_id uuid REFERENCES integration.legacy_id_mappings,
  ADD COLUMN supersession_request_nonce uuid;

-- The original VERIFIED check attributed a decision to a natural person.
-- FM_V1 decisions are made by accountable personless SERVICE principals, so
-- retain the old rule for unmanaged historical rows and use principal-based
-- attribution for the new lifecycle.
DO $drop_old_verified_check$
DECLARE v_name text;
BEGIN
  SELECT c.conname INTO v_name
    FROM pg_constraint c
   WHERE c.conrelid='integration.legacy_id_mappings'::regclass
     AND c.contype='c'
     AND pg_get_constraintdef(c.oid) LIKE '%mapping_status%VERIFIED%decided_by%decided_at%'
   ORDER BY c.oid
   LIMIT 1;
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'LEGACY_MAPPING_VERIFIED_CHECK_NOT_FOUND';
  END IF;
  EXECUTE format('ALTER TABLE integration.legacy_id_mappings DROP CONSTRAINT %I',v_name);
END
$drop_old_verified_check$;

ALTER TABLE integration.legacy_id_mappings
  ADD CONSTRAINT family_mapping_managed_version_check
    CHECK (managed_lifecycle_version IS NULL OR managed_lifecycle_version='FM_V1'),
  ADD CONSTRAINT family_mapping_managed_lifecycle_check CHECK (
    (
      managed_lifecycle_version IS NULL
      AND ((mapping_status='VERIFIED')=(decided_by IS NOT NULL AND decided_at IS NOT NULL))
    )
    OR
    (
      managed_lifecycle_version='FM_V1'
      AND source_system='PHOENIX_FAMILY_OS'
      AND entity_kind='FAMILY'
      AND legacy_id ~ '^fam_[0-9a-f]{32}$'
      AND decided_by IS NULL
      AND proposed_by_principal_id IS NOT NULL
      AND proposed_at IS NOT NULL
      AND proposal_request_nonce IS NOT NULL
      AND application_ownership_evidence_ref ~ '^evidence://[A-Za-z0-9][A-Za-z0-9._/-]*$'
      AND length(application_ownership_evidence_ref)<=911
      AND application_ownership_evidence_sha256 ~ '^[0-9a-f]{64}$'
      AND canonical_membership_evidence_ref ~ '^evidence://[A-Za-z0-9][A-Za-z0-9._/-]*$'
      AND length(canonical_membership_evidence_ref)<=911
      AND canonical_membership_evidence_sha256 ~ '^[0-9a-f]{64}$'
      AND founder_approval_evidence_ref ~ '^evidence://[A-Za-z0-9][A-Za-z0-9._/-]*$'
      AND length(founder_approval_evidence_ref)<=911
      AND founder_approval_evidence_sha256 ~ '^[0-9a-f]{64}$'
      AND (
        (mapping_status='PENDING'
          AND decided_by_principal_id IS NULL AND decided_at IS NULL
          AND verification_request_nonce IS NULL
          AND revoked_by_principal_id IS NULL AND revoked_at IS NULL
          AND revoke_request_nonce IS NULL
          AND superseded_by_mapping_id IS NULL AND supersession_request_nonce IS NULL)
        OR
        (mapping_status='VERIFIED'
          AND decided_by_principal_id IS NOT NULL AND decided_at IS NOT NULL
          AND verification_request_nonce IS NOT NULL
          AND decided_by_principal_id<>proposed_by_principal_id
          AND revoked_by_principal_id IS NULL AND revoked_at IS NULL
          AND revoke_request_nonce IS NULL
          AND superseded_by_mapping_id IS NULL AND supersession_request_nonce IS NULL)
        OR
        (mapping_status='REVOKED'
          AND revoked_by_principal_id IS NOT NULL AND revoked_at IS NOT NULL
          AND revoke_request_nonce IS NOT NULL
          AND superseded_by_mapping_id IS NULL AND supersession_request_nonce IS NULL
          AND (
            (decided_by_principal_id IS NULL AND decided_at IS NULL AND verification_request_nonce IS NULL)
            OR
            (decided_by_principal_id IS NOT NULL AND decided_at IS NOT NULL
             AND verification_request_nonce IS NOT NULL
             AND decided_by_principal_id<>proposed_by_principal_id)
          ))
        OR
        (mapping_status='SUPERSEDED'
          AND decided_by_principal_id IS NOT NULL AND decided_at IS NOT NULL
          AND verification_request_nonce IS NOT NULL
          AND decided_by_principal_id<>proposed_by_principal_id
          AND revoked_by_principal_id IS NULL AND revoked_at IS NULL
          AND revoke_request_nonce IS NULL
          AND superseded_by_mapping_id IS NOT NULL
          AND superseded_by_mapping_id<>mapping_id
          AND supersession_request_nonce IS NOT NULL)
      )
    )
  );

CREATE UNIQUE INDEX one_verified_phoenix_family_per_canonical
  ON integration.legacy_id_mappings(canonical_id)
  WHERE source_system='PHOENIX_FAMILY_OS'
    AND entity_kind='FAMILY'
    AND mapping_status='VERIFIED';

CREATE FUNCTION integration.protect_managed_family_mapping() RETURNS trigger
LANGUAGE plpgsql
SET search_path=pg_catalog,integration
AS $fn$
BEGIN
  IF TG_OP='DELETE' THEN
    IF OLD.managed_lifecycle_version='FM_V1' THEN
      RAISE EXCEPTION 'MANAGED_FAMILY_MAPPING_DELETE_DENIED';
    END IF;
    RETURN OLD;
  END IF;
  IF TG_OP='UPDATE' AND OLD.managed_lifecycle_version IS DISTINCT FROM NEW.managed_lifecycle_version THEN
    RAISE EXCEPTION 'MANAGED_FAMILY_MAPPING_VERSION_IMMUTABLE';
  END IF;
  IF TG_OP='UPDATE' AND OLD.managed_lifecycle_version='FM_V1' THEN
    IF ROW(NEW.mapping_id,NEW.source_system,NEW.entity_kind,NEW.legacy_id,NEW.canonical_id,
           NEW.evidence_ref,NEW.managed_lifecycle_version,NEW.proposed_by_principal_id,
           NEW.proposed_at,NEW.proposal_request_nonce,
           NEW.application_ownership_evidence_ref,NEW.application_ownership_evidence_sha256,
           NEW.canonical_membership_evidence_ref,NEW.canonical_membership_evidence_sha256,
           NEW.founder_approval_evidence_ref,NEW.founder_approval_evidence_sha256)
       IS DISTINCT FROM
       ROW(OLD.mapping_id,OLD.source_system,OLD.entity_kind,OLD.legacy_id,OLD.canonical_id,
           OLD.evidence_ref,OLD.managed_lifecycle_version,OLD.proposed_by_principal_id,
           OLD.proposed_at,OLD.proposal_request_nonce,
           OLD.application_ownership_evidence_ref,OLD.application_ownership_evidence_sha256,
           OLD.canonical_membership_evidence_ref,OLD.canonical_membership_evidence_sha256,
           OLD.founder_approval_evidence_ref,OLD.founder_approval_evidence_sha256) THEN
      RAISE EXCEPTION 'MANAGED_FAMILY_MAPPING_IMMUTABLE_FIELDS';
    END IF;
    IF OLD.mapping_status IN ('REVOKED','SUPERSEDED') THEN
      RAISE EXCEPTION 'MANAGED_FAMILY_MAPPING_TERMINAL';
    END IF;
    IF OLD.mapping_status='PENDING' AND NEW.mapping_status NOT IN ('VERIFIED','REVOKED') THEN
      RAISE EXCEPTION 'MANAGED_FAMILY_MAPPING_TRANSITION_INVALID';
    END IF;
    IF OLD.mapping_status='VERIFIED' AND NEW.mapping_status NOT IN ('REVOKED','SUPERSEDED') THEN
      RAISE EXCEPTION 'MANAGED_FAMILY_MAPPING_TRANSITION_INVALID';
    END IF;
  END IF;
  RETURN NEW;
END
$fn$;

CREATE TRIGGER protect_managed_family_mapping
BEFORE UPDATE OR DELETE ON integration.legacy_id_mappings
FOR EACH ROW EXECUTE FUNCTION integration.protect_managed_family_mapping();

CREATE FUNCTION integration.propose_family_mapping(
  p_mapping_id uuid,
  p_source_system text,
  p_entity_kind text,
  p_application_family_id text,
  p_canonical_family_id uuid,
  p_application_ownership_evidence_ref text,
  p_application_ownership_evidence_sha256 text,
  p_canonical_membership_evidence_ref text,
  p_canonical_membership_evidence_sha256 text,
  p_founder_approval_evidence_ref text,
  p_founder_approval_evidence_sha256 text,
  p_request_nonce uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,integration,audit
AS $fn$
DECLARE v_existing integration.legacy_id_mappings%ROWTYPE;
BEGIN
  PERFORM pg_advisory_xact_lock(2202,24);
  IF (
    auth.is_internal_service()
    AND auth.current_family_id()=p_canonical_family_id
    AND auth.current_request_nonce()=p_request_nonce
    AND core.is_uuid_v7(p_mapping_id)
    AND core.is_uuid_v7(p_canonical_family_id)
    AND p_source_system='PHOENIX_FAMILY_OS'
    AND p_entity_kind='FAMILY'
    AND p_application_family_id ~ '^fam_[0-9a-f]{32}$'
    AND p_application_ownership_evidence_ref ~ '^evidence://[A-Za-z0-9][A-Za-z0-9._/-]*$'
    AND length(p_application_ownership_evidence_ref)<=911
    AND p_application_ownership_evidence_sha256 ~ '^[0-9a-f]{64}$'
    AND p_canonical_membership_evidence_ref ~ '^evidence://[A-Za-z0-9][A-Za-z0-9._/-]*$'
    AND length(p_canonical_membership_evidence_ref)<=911
    AND p_canonical_membership_evidence_sha256 ~ '^[0-9a-f]{64}$'
    AND p_founder_approval_evidence_ref ~ '^evidence://[A-Za-z0-9][A-Za-z0-9._/-]*$'
    AND length(p_founder_approval_evidence_ref)<=911
    AND p_founder_approval_evidence_sha256 ~ '^[0-9a-f]{64}$'
    AND EXISTS (SELECT 1 FROM core.families f WHERE f.family_id=p_canonical_family_id)
    AND EXISTS (
      SELECT 1 FROM core.family_memberships fm
       WHERE fm.family_id=p_canonical_family_id
         AND fm.valid_from<=clock_timestamp()
         AND (fm.valid_until IS NULL OR fm.valid_until>clock_timestamp())
    )
  ) IS NOT TRUE THEN
    RETURN audit.record_write_decision('PROPOSE','FAMILY_MAPPING',p_mapping_id,false,
      'SERVICE_SOURCE_FAMILY_EVIDENCE_OR_NONCE_DENIED');
  END IF;

  SELECT * INTO v_existing FROM integration.legacy_id_mappings
   WHERE mapping_id=p_mapping_id FOR UPDATE;
  IF FOUND THEN
    IF v_existing.managed_lifecycle_version='FM_V1'
       AND v_existing.mapping_status='PENDING'
       AND v_existing.source_system=p_source_system
       AND v_existing.entity_kind=p_entity_kind
       AND v_existing.legacy_id=p_application_family_id
       AND v_existing.canonical_id=p_canonical_family_id
       AND v_existing.proposed_by_principal_id=auth.current_principal_id()
       AND v_existing.proposal_request_nonce=p_request_nonce
       AND v_existing.application_ownership_evidence_ref=p_application_ownership_evidence_ref
       AND v_existing.application_ownership_evidence_sha256=p_application_ownership_evidence_sha256
       AND v_existing.canonical_membership_evidence_ref=p_canonical_membership_evidence_ref
       AND v_existing.canonical_membership_evidence_sha256=p_canonical_membership_evidence_sha256
       AND v_existing.founder_approval_evidence_ref=p_founder_approval_evidence_ref
       AND v_existing.founder_approval_evidence_sha256=p_founder_approval_evidence_sha256 THEN
      RETURN audit.record_write_decision('PROPOSE','FAMILY_MAPPING',p_mapping_id,true,'IDEMPOTENT_PROPOSAL');
    END IF;
    RETURN audit.record_write_decision('PROPOSE','FAMILY_MAPPING',p_mapping_id,false,'MAPPING_ID_EVIDENCE_DRIFT');
  END IF;

  IF EXISTS (
    SELECT 1 FROM integration.legacy_id_mappings m
     WHERE m.source_system='PHOENIX_FAMILY_OS' AND m.entity_kind='FAMILY'
       AND m.legacy_id=p_application_family_id
       AND m.mapping_status IN ('PENDING','VERIFIED')
  ) THEN
    RETURN audit.record_write_decision('PROPOSE','FAMILY_MAPPING',p_mapping_id,false,'APPLICATION_FAMILY_COLLISION');
  END IF;

  INSERT INTO integration.legacy_id_mappings(
    mapping_id,source_system,entity_kind,legacy_id,canonical_id,mapping_status,evidence_ref,
    managed_lifecycle_version,proposed_by_principal_id,proposed_at,proposal_request_nonce,
    application_ownership_evidence_ref,application_ownership_evidence_sha256,
    canonical_membership_evidence_ref,canonical_membership_evidence_sha256,
    founder_approval_evidence_ref,founder_approval_evidence_sha256
  ) VALUES (
    p_mapping_id,'PHOENIX_FAMILY_OS','FAMILY',p_application_family_id,p_canonical_family_id,
    'PENDING','evidence://family-mapping/FM_V1','FM_V1',auth.current_principal_id(),
    clock_timestamp(),p_request_nonce,
    p_application_ownership_evidence_ref,p_application_ownership_evidence_sha256,
    p_canonical_membership_evidence_ref,p_canonical_membership_evidence_sha256,
    p_founder_approval_evidence_ref,p_founder_approval_evidence_sha256
  );
  RETURN audit.record_write_decision('PROPOSE','FAMILY_MAPPING',p_mapping_id,true,'PROPOSAL_RECORDED');
END
$fn$;

CREATE FUNCTION integration.verify_family_mapping(
  p_mapping_id uuid,p_request_nonce uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,integration,audit
AS $fn$
DECLARE v_mapping integration.legacy_id_mappings%ROWTYPE;
BEGIN
  PERFORM pg_advisory_xact_lock(2202,24);
  SELECT * INTO v_mapping FROM integration.legacy_id_mappings
   WHERE mapping_id=p_mapping_id FOR UPDATE;
  IF (
    v_mapping.mapping_id IS NOT NULL
    AND auth.is_internal_service()
    AND auth.current_family_id()=v_mapping.canonical_id
    AND auth.current_request_nonce()=p_request_nonce
  ) IS NOT TRUE THEN
    RETURN audit.record_write_decision('VERIFY','FAMILY_MAPPING',p_mapping_id,false,'SERVICE_FAMILY_OR_NONCE_DENIED');
  END IF;
  IF v_mapping.mapping_status='VERIFIED'
     AND v_mapping.decided_by_principal_id=auth.current_principal_id()
     AND v_mapping.verification_request_nonce=p_request_nonce THEN
    RETURN audit.record_write_decision('VERIFY','FAMILY_MAPPING',p_mapping_id,true,'IDEMPOTENT_VERIFICATION');
  END IF;
  IF v_mapping.managed_lifecycle_version IS DISTINCT FROM 'FM_V1'
     OR v_mapping.mapping_status<>'PENDING'
     OR v_mapping.proposed_by_principal_id=auth.current_principal_id()
     OR NOT EXISTS (
       SELECT 1 FROM core.family_memberships fm
        WHERE fm.family_id=v_mapping.canonical_id
          AND fm.valid_from<=clock_timestamp()
          AND (fm.valid_until IS NULL OR fm.valid_until>clock_timestamp())
     ) THEN
    RETURN audit.record_write_decision('VERIFY','FAMILY_MAPPING',p_mapping_id,false,'STATE_REVIEWER_OR_MEMBERSHIP_DENIED');
  END IF;
  IF EXISTS (
    SELECT 1 FROM integration.legacy_id_mappings m
     WHERE m.mapping_id<>p_mapping_id
       AND m.source_system='PHOENIX_FAMILY_OS' AND m.entity_kind='FAMILY'
       AND m.mapping_status='VERIFIED'
       AND (m.legacy_id=v_mapping.legacy_id OR m.canonical_id=v_mapping.canonical_id)
  ) THEN
    RETURN audit.record_write_decision('VERIFY','FAMILY_MAPPING',p_mapping_id,false,'VERIFIED_MAPPING_COLLISION');
  END IF;
  UPDATE integration.legacy_id_mappings
     SET mapping_status='VERIFIED',decided_by_principal_id=auth.current_principal_id(),
         decided_at=clock_timestamp(),verification_request_nonce=p_request_nonce
   WHERE mapping_id=p_mapping_id;
  RETURN audit.record_write_decision('VERIFY','FAMILY_MAPPING',p_mapping_id,true,'DISTINCT_REVIEWER_VERIFIED');
END
$fn$;

CREATE FUNCTION integration.revoke_family_mapping(
  p_mapping_id uuid,p_request_nonce uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,integration,audit
AS $fn$
DECLARE v_mapping integration.legacy_id_mappings%ROWTYPE;
BEGIN
  PERFORM pg_advisory_xact_lock(2202,24);
  SELECT * INTO v_mapping FROM integration.legacy_id_mappings
   WHERE mapping_id=p_mapping_id FOR UPDATE;
  IF (
    v_mapping.mapping_id IS NOT NULL
    AND auth.is_internal_service()
    AND auth.current_family_id()=v_mapping.canonical_id
    AND auth.current_request_nonce()=p_request_nonce
  ) IS NOT TRUE THEN
    RETURN audit.record_write_decision('REVOKE','FAMILY_MAPPING',p_mapping_id,false,'SERVICE_FAMILY_OR_NONCE_DENIED');
  END IF;
  IF v_mapping.mapping_status='REVOKED'
     AND v_mapping.revoked_by_principal_id=auth.current_principal_id()
     AND v_mapping.revoke_request_nonce=p_request_nonce THEN
    RETURN audit.record_write_decision('REVOKE','FAMILY_MAPPING',p_mapping_id,true,'IDEMPOTENT_REVOCATION');
  END IF;
  IF v_mapping.managed_lifecycle_version IS DISTINCT FROM 'FM_V1'
     OR v_mapping.mapping_status NOT IN ('PENDING','VERIFIED') THEN
    RETURN audit.record_write_decision('REVOKE','FAMILY_MAPPING',p_mapping_id,false,'STATE_DENIED');
  END IF;
  UPDATE integration.legacy_id_mappings
     SET mapping_status='REVOKED',revoked_by_principal_id=auth.current_principal_id(),
         revoked_at=clock_timestamp(),revoke_request_nonce=p_request_nonce
   WHERE mapping_id=p_mapping_id;
  RETURN audit.record_write_decision('REVOKE','FAMILY_MAPPING',p_mapping_id,true,'ACCESS_REDUCING_REVOCATION');
END
$fn$;

CREATE FUNCTION integration.supersede_family_mapping(
  p_current_mapping_id uuid,p_replacement_mapping_id uuid,p_request_nonce uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,integration,audit
AS $fn$
DECLARE
  v_current integration.legacy_id_mappings%ROWTYPE;
  v_replacement integration.legacy_id_mappings%ROWTYPE;
BEGIN
  PERFORM pg_advisory_xact_lock(2202,24);
  PERFORM 1 FROM integration.legacy_id_mappings
   WHERE mapping_id IN (p_current_mapping_id,p_replacement_mapping_id)
   ORDER BY mapping_id FOR UPDATE;
  SELECT * INTO v_current FROM integration.legacy_id_mappings WHERE mapping_id=p_current_mapping_id;
  SELECT * INTO v_replacement FROM integration.legacy_id_mappings WHERE mapping_id=p_replacement_mapping_id;
  IF (
    v_current.mapping_id IS NOT NULL AND v_replacement.mapping_id IS NOT NULL
    AND auth.is_internal_service()
    AND auth.current_family_id()=v_current.canonical_id
    AND auth.current_request_nonce()=p_request_nonce
  ) IS NOT TRUE THEN
    RETURN audit.record_write_decision('SUPERSEDE','FAMILY_MAPPING',p_replacement_mapping_id,false,
      'SERVICE_FAMILY_OR_NONCE_DENIED');
  END IF;
  IF v_current.mapping_status='SUPERSEDED'
     AND v_current.superseded_by_mapping_id=p_replacement_mapping_id
     AND v_current.supersession_request_nonce=p_request_nonce
     AND v_replacement.mapping_status='VERIFIED'
     AND v_replacement.decided_by_principal_id=auth.current_principal_id()
     AND v_replacement.verification_request_nonce=p_request_nonce THEN
    RETURN audit.record_write_decision('SUPERSEDE','FAMILY_MAPPING',p_replacement_mapping_id,true,
      'IDEMPOTENT_SUPERSESSION');
  END IF;
  IF v_current.managed_lifecycle_version IS DISTINCT FROM 'FM_V1'
     OR v_replacement.managed_lifecycle_version IS DISTINCT FROM 'FM_V1'
     OR v_current.mapping_status<>'VERIFIED'
     OR v_replacement.mapping_status<>'PENDING'
     OR v_current.canonical_id<>v_replacement.canonical_id
     OR v_current.legacy_id=v_replacement.legacy_id
     OR v_replacement.proposed_by_principal_id=auth.current_principal_id()
     OR NOT EXISTS (
       SELECT 1 FROM core.family_memberships fm
        WHERE fm.family_id=v_current.canonical_id
          AND fm.valid_from<=clock_timestamp()
          AND (fm.valid_until IS NULL OR fm.valid_until>clock_timestamp())
     ) THEN
    RETURN audit.record_write_decision('SUPERSEDE','FAMILY_MAPPING',p_replacement_mapping_id,false,
      'STATE_REVIEWER_OR_MEMBERSHIP_DENIED');
  END IF;
  IF EXISTS (
    SELECT 1 FROM integration.legacy_id_mappings m
     WHERE m.mapping_id<>p_current_mapping_id
       AND m.source_system='PHOENIX_FAMILY_OS' AND m.entity_kind='FAMILY'
       AND m.mapping_status='VERIFIED'
       AND (m.legacy_id=v_replacement.legacy_id OR m.canonical_id=v_replacement.canonical_id)
  ) THEN
    RETURN audit.record_write_decision('SUPERSEDE','FAMILY_MAPPING',p_replacement_mapping_id,false,
      'VERIFIED_MAPPING_COLLISION');
  END IF;
  UPDATE integration.legacy_id_mappings
     SET mapping_status='SUPERSEDED',superseded_by_mapping_id=p_replacement_mapping_id,
         supersession_request_nonce=p_request_nonce
   WHERE mapping_id=p_current_mapping_id;
  UPDATE integration.legacy_id_mappings
     SET mapping_status='VERIFIED',decided_by_principal_id=auth.current_principal_id(),
         decided_at=clock_timestamp(),verification_request_nonce=p_request_nonce
   WHERE mapping_id=p_replacement_mapping_id;
  RETURN audit.record_write_decision('SUPERSEDE','FAMILY_MAPPING',p_replacement_mapping_id,true,
    'EXPLICIT_SUPERSESSION_VERIFIED');
END
$fn$;

REVOKE ALL ON integration.legacy_id_mappings
  FROM PUBLIC,phoenix_canonical_app,phoenix_canonical_reader,phoenix_canonical_context_binder;
REVOKE EXECUTE ON FUNCTION integration.protect_managed_family_mapping(),
  integration.propose_family_mapping(uuid,text,text,text,uuid,text,text,text,text,text,text,uuid),
  integration.verify_family_mapping(uuid,uuid),
  integration.revoke_family_mapping(uuid,uuid),
  integration.supersede_family_mapping(uuid,uuid,uuid)
  FROM PUBLIC,phoenix_canonical_reader,phoenix_canonical_context_binder;
GRANT EXECUTE ON FUNCTION
  integration.propose_family_mapping(uuid,text,text,text,uuid,text,text,text,text,text,text,uuid),
  integration.verify_family_mapping(uuid,uuid),
  integration.revoke_family_mapping(uuid,uuid),
  integration.supersede_family_mapping(uuid,uuid,uuid)
  TO phoenix_canonical_app;

COMMIT;
