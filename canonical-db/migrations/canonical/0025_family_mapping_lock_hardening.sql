BEGIN;

-- Forward hardening for 0024: an untrusted app connection must not be able to
-- acquire and retain the family-mapping serialization lock. Validate the live
-- INTERNAL SERVICE context, family scope and request nonce first, then enter
-- the short transaction-locked critical section.
CREATE OR REPLACE FUNCTION integration.propose_family_mapping(
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
  PERFORM pg_advisory_xact_lock(2202,25);

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

CREATE OR REPLACE FUNCTION integration.verify_family_mapping(
  p_mapping_id uuid,p_request_nonce uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,integration,audit
AS $fn$
DECLARE v_mapping integration.legacy_id_mappings%ROWTYPE;
BEGIN
  SELECT * INTO v_mapping FROM integration.legacy_id_mappings WHERE mapping_id=p_mapping_id;
  IF (
    v_mapping.mapping_id IS NOT NULL
    AND auth.is_internal_service()
    AND auth.current_family_id()=v_mapping.canonical_id
    AND auth.current_request_nonce()=p_request_nonce
  ) IS NOT TRUE THEN
    RETURN audit.record_write_decision('VERIFY','FAMILY_MAPPING',p_mapping_id,false,'SERVICE_FAMILY_OR_NONCE_DENIED');
  END IF;
  PERFORM pg_advisory_xact_lock(2202,25);
  SELECT * INTO v_mapping FROM integration.legacy_id_mappings
   WHERE mapping_id=p_mapping_id FOR UPDATE;
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

CREATE OR REPLACE FUNCTION integration.revoke_family_mapping(
  p_mapping_id uuid,p_request_nonce uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,integration,audit
AS $fn$
DECLARE v_mapping integration.legacy_id_mappings%ROWTYPE;
BEGIN
  SELECT * INTO v_mapping FROM integration.legacy_id_mappings WHERE mapping_id=p_mapping_id;
  IF (
    v_mapping.mapping_id IS NOT NULL
    AND auth.is_internal_service()
    AND auth.current_family_id()=v_mapping.canonical_id
    AND auth.current_request_nonce()=p_request_nonce
  ) IS NOT TRUE THEN
    RETURN audit.record_write_decision('REVOKE','FAMILY_MAPPING',p_mapping_id,false,'SERVICE_FAMILY_OR_NONCE_DENIED');
  END IF;
  PERFORM pg_advisory_xact_lock(2202,25);
  SELECT * INTO v_mapping FROM integration.legacy_id_mappings
   WHERE mapping_id=p_mapping_id FOR UPDATE;
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

CREATE OR REPLACE FUNCTION integration.supersede_family_mapping(
  p_current_mapping_id uuid,p_replacement_mapping_id uuid,p_request_nonce uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,integration,audit
AS $fn$
DECLARE
  v_current integration.legacy_id_mappings%ROWTYPE;
  v_replacement integration.legacy_id_mappings%ROWTYPE;
BEGIN
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
  PERFORM pg_advisory_xact_lock(2202,25);
  PERFORM 1 FROM integration.legacy_id_mappings
   WHERE mapping_id IN (p_current_mapping_id,p_replacement_mapping_id)
   ORDER BY mapping_id FOR UPDATE;
  SELECT * INTO v_current FROM integration.legacy_id_mappings WHERE mapping_id=p_current_mapping_id;
  SELECT * INTO v_replacement FROM integration.legacy_id_mappings WHERE mapping_id=p_replacement_mapping_id;
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

REVOKE EXECUTE ON FUNCTION
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
