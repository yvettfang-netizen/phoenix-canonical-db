BEGIN;

-- R-7: evidence is a historical fact. Replacing an authority requires a new row.
CREATE FUNCTION core.reject_guardian_evidence_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, core
AS $fn$
BEGIN
  IF NEW.evidence_level IS DISTINCT FROM OLD.evidence_level THEN
    RAISE EXCEPTION 'GUARDIAN_EVIDENCE_IMMUTABLE';
  END IF;
  RETURN NEW;
END
$fn$;
CREATE TRIGGER reject_guardian_evidence_change
BEFORE UPDATE OF evidence_level ON core.guardian_authorities
FOR EACH ROW EXECUTE FUNCTION core.reject_guardian_evidence_change();

CREATE FUNCTION core.audit_guardian_authority_history() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, core, audit
AS $fn$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM audit.record_access_event('CREATE','GUARDIAN_AUTHORITY',NEW.authority_id,
      'ALLOW','GUARDIAN_AUTHORITY_CREATED');
  ELSIF OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL THEN
    PERFORM audit.record_access_event('REVOKE','GUARDIAN_AUTHORITY',NEW.authority_id,
      'ALLOW','GUARDIAN_AUTHORITY_REVOKED');
  ELSIF OLD.lifecycle_status = 'ACTIVE' AND NEW.lifecycle_status = 'EXPIRED' THEN
    PERFORM audit.record_access_event('EXPIRE','GUARDIAN_AUTHORITY',NEW.authority_id,
      'ALLOW','GUARDIAN_AUTHORITY_EXPIRED');
  END IF;
  RETURN NEW;
END
$fn$;
CREATE TRIGGER audit_guardian_authority_history
AFTER INSERT OR UPDATE ON core.guardian_authorities
FOR EACH ROW EXECUTE FUNCTION core.audit_guardian_authority_history();

-- Only definer-owned write functions can call these helpers. A missing or expired
-- trusted context produces false, including when a SQL boolean would be NULL.
CREATE FUNCTION auth.write_context_is_live() RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth
RETURN EXISTS (
  SELECT 1 FROM auth.session_contexts s
   WHERE s.backend_pid = pg_backend_pid()
     AND s.backend_start = auth.current_backend_start()
     AND s.expires_at > clock_timestamp()
);

CREATE FUNCTION auth.is_internal_service() RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth
RETURN coalesce(auth.write_context_is_live()
  AND auth.current_channel() = 'INTERNAL'
  AND auth.current_family_id() IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM auth.principals p
     WHERE p.principal_id = auth.current_principal_id()
       AND p.person_id = auth.current_actor_person_id()
       AND p.principal_kind = 'SERVICE' AND p.status = 'ACTIVE'
  ), false);

CREATE FUNCTION core.actor_can_manage_subject(p_subject_person_id uuid, p_scope text)
RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core
RETURN coalesce(
  auth.write_context_is_live()
  AND auth.current_channel() = 'FAMILY'
  AND core.current_actor_is_family_member()
  AND core.person_in_current_family(p_subject_person_id)
  AND (auth.current_actor_person_id() = p_subject_person_id
       OR core.has_verified_guardian_authority(p_subject_person_id, p_scope)), false);

CREATE FUNCTION audit.record_write_decision(
  p_action text, p_resource_kind text, p_resource_id uuid,
  p_allowed boolean, p_reason_code text
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, audit
AS $fn$
BEGIN
  PERFORM audit.record_access_event(
    p_action, p_resource_kind, p_resource_id,
    CASE WHEN p_allowed IS TRUE THEN 'ALLOW' ELSE 'DENY' END,
    p_reason_code
  );
  RETURN p_allowed IS TRUE;
END
$fn$;

CREATE FUNCTION core.create_family(p_family_id uuid, p_display_name text)
RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, integration, audit
AS $fn$
BEGIN
  IF (auth.is_internal_service() AND core.is_uuid_v7(p_family_id)
      AND length(btrim(p_display_name)) BETWEEN 1 AND 200) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','FAMILY',p_family_id,false,'SERVICE_CONTEXT_OR_INPUT_DENIED');
  END IF;
  IF EXISTS (SELECT 1 FROM core.families WHERE family_id = p_family_id) THEN
    RETURN audit.record_write_decision('CREATE','FAMILY',p_family_id,false,'ALREADY_EXISTS');
  END IF;
  INSERT INTO core.families(family_id,display_name) VALUES (p_family_id,p_display_name);
  INSERT INTO integration.public_ids(entity_kind,public_id,canonical_id)
    VALUES ('FAMILY','fam_' || replace(p_family_id::text,'-',''),p_family_id);
  RETURN audit.record_write_decision('CREATE','FAMILY',p_family_id,true,'INTERNAL_SERVICE_CREATED');
END
$fn$;

CREATE FUNCTION core.create_person(
  p_person_id uuid, p_display_name text, p_family_id uuid,
  p_membership_id uuid, p_membership_role text
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, integration, audit
AS $fn$
BEGIN
  IF (auth.is_internal_service() AND auth.current_family_id() = p_family_id
      AND core.is_uuid_v7(p_person_id) AND core.is_uuid_v7(p_membership_id)
      AND length(btrim(p_display_name)) BETWEEN 1 AND 200
      AND p_membership_role IN ('PRIMARY','MEMBER')
      AND EXISTS (SELECT 1 FROM core.families WHERE family_id = p_family_id)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','PERSON',p_person_id,false,'SERVICE_FAMILY_OR_INPUT_DENIED');
  END IF;
  IF EXISTS (SELECT 1 FROM core.people WHERE person_id = p_person_id) THEN
    RETURN audit.record_write_decision('CREATE','PERSON',p_person_id,false,'ALREADY_EXISTS');
  END IF;
  INSERT INTO core.people(person_id,display_name) VALUES (p_person_id,p_display_name);
  INSERT INTO core.family_memberships(membership_id,family_id,person_id,membership_role,valid_from)
    VALUES (p_membership_id,p_family_id,p_person_id,p_membership_role,transaction_timestamp());
  INSERT INTO integration.public_ids(entity_kind,public_id,canonical_id)
    VALUES ('PERSON','per_' || replace(p_person_id::text,'-',''),p_person_id);
  RETURN audit.record_write_decision('CREATE','PERSON',p_person_id,true,'INTERNAL_SERVICE_CREATED');
END
$fn$;

CREATE FUNCTION core.add_family_member(
  p_membership_id uuid, p_family_id uuid, p_person_id uuid, p_membership_role text
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, audit
AS $fn$
BEGIN
  IF (auth.is_internal_service() AND auth.current_family_id() = p_family_id
      AND core.is_uuid_v7(p_membership_id) AND p_membership_role IN ('PRIMARY','MEMBER')
      AND EXISTS (SELECT 1 FROM core.people WHERE person_id = p_person_id)
      AND EXISTS (SELECT 1 FROM core.families WHERE family_id = p_family_id)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','FAMILY_MEMBERSHIP',p_membership_id,false,'SERVICE_FAMILY_OR_INPUT_DENIED');
  END IF;
  IF EXISTS (SELECT 1 FROM core.family_memberships WHERE family_id = p_family_id AND person_id = p_person_id) THEN
    RETURN audit.record_write_decision('CREATE','FAMILY_MEMBERSHIP',p_membership_id,false,'ALREADY_EXISTS');
  END IF;
  INSERT INTO core.family_memberships(membership_id,family_id,person_id,membership_role,valid_from)
    VALUES (p_membership_id,p_family_id,p_person_id,p_membership_role,transaction_timestamp());
  RETURN audit.record_write_decision('CREATE','FAMILY_MEMBERSHIP',p_membership_id,true,'INTERNAL_SERVICE_CREATED');
END
$fn$;

CREATE FUNCTION core.create_student_profile(p_person_id uuid)
RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, integration, audit
AS $fn$
BEGIN
  IF (auth.is_internal_service() AND core.person_in_current_family(p_person_id)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','STUDENT_PROFILE',p_person_id,false,'SERVICE_FAMILY_DENIED');
  END IF;
  IF EXISTS (SELECT 1 FROM core.student_profiles WHERE person_id = p_person_id) THEN
    RETURN audit.record_write_decision('CREATE','STUDENT_PROFILE',p_person_id,false,'ALREADY_EXISTS');
  END IF;
  INSERT INTO core.student_profiles(person_id) VALUES (p_person_id);
  INSERT INTO integration.public_ids(entity_kind,public_id,canonical_id)
    VALUES ('STUDENT_PROFILE','stu_' || replace(p_person_id::text,'-',''),p_person_id);
  RETURN audit.record_write_decision('CREATE','STUDENT_PROFILE',p_person_id,true,'INTERNAL_SERVICE_CREATED');
END
$fn$;

CREATE FUNCTION consent.actor_can_grant(
  p_subject_person_id uuid, p_purpose text, p_data_class text
) RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, consent
RETURN coalesce(
  p_purpose IN ('DOCUMENT_READ','EDUCATION_CASE','IDENTITY_CASE')
  AND p_data_class IN ('GENERAL','EDUCATION','IDENTITY_SENSITIVE')
  AND (p_purpose = 'DOCUMENT_READ'
       OR (p_purpose = 'EDUCATION_CASE' AND p_data_class = 'EDUCATION')
       OR (p_purpose = 'IDENTITY_CASE' AND p_data_class = 'IDENTITY_SENSITIVE'))
  AND core.actor_can_manage_subject(
    p_subject_person_id,
    CASE p_data_class WHEN 'EDUCATION' THEN 'EDUCATION'
      WHEN 'IDENTITY_SENSITIVE' THEN 'IDENTITY' ELSE 'GENERAL' END
  ), false);

CREATE FUNCTION consent.create_grant(
  p_consent_id uuid, p_family_id uuid, p_grantee_person_id uuid,
  p_subject_person_id uuid, p_purpose text, p_data_class text,
  p_expires_at timestamptz
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, consent, audit
AS $fn$
BEGIN
  IF (core.is_uuid_v7(p_consent_id) AND auth.current_family_id() = p_family_id
      AND consent.actor_can_grant(p_subject_person_id,p_purpose,p_data_class)
      AND p_expires_at > clock_timestamp()
      AND EXISTS (SELECT 1 FROM core.people WHERE person_id = p_grantee_person_id)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('GRANT','CONSENT',p_consent_id,false,'GRANTOR_AUTHORITY_OR_INPUT_DENIED');
  END IF;
  IF EXISTS (SELECT 1 FROM consent.grants WHERE family_id=p_family_id
      AND grantee_person_id=p_grantee_person_id AND subject_person_id=p_subject_person_id
      AND purpose=p_purpose AND data_class=p_data_class AND status='ACTIVE'
      AND expires_at > clock_timestamp()) THEN
    RETURN audit.record_write_decision('GRANT','CONSENT',p_consent_id,false,'ACTIVE_GRANT_EXISTS');
  END IF;
  INSERT INTO consent.grants(consent_id,family_id,grantor_person_id,grantee_person_id,
    subject_person_id,purpose,data_class,status,granted_at,expires_at)
    VALUES (p_consent_id,p_family_id,auth.current_actor_person_id(),p_grantee_person_id,
      p_subject_person_id,p_purpose,p_data_class,'ACTIVE',clock_timestamp(),p_expires_at);
  RETURN audit.record_write_decision('GRANT','CONSENT',p_consent_id,true,'AUTHORIZED_GRANT');
END
$fn$;

CREATE FUNCTION consent.withdraw_grant(p_consent_id uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, consent, audit
AS $fn$
DECLARE v_grant consent.grants%ROWTYPE;
BEGIN
  SELECT * INTO v_grant FROM consent.grants WHERE consent_id=p_consent_id FOR UPDATE;
  IF (FOUND AND v_grant.family_id=auth.current_family_id()
      AND v_grant.status='ACTIVE' AND v_grant.expires_at>clock_timestamp()
      AND consent.actor_can_grant(v_grant.subject_person_id,v_grant.purpose,v_grant.data_class)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('WITHDRAW','CONSENT',p_consent_id,false,'GRANTOR_AUTHORITY_OR_STATE_DENIED');
  END IF;
  UPDATE consent.grants SET status='WITHDRAWN', withdrawn_at=clock_timestamp()
   WHERE consent_id=p_consent_id;
  RETURN audit.record_write_decision('WITHDRAW','CONSENT',p_consent_id,true,'AUTHORIZED_WITHDRAWAL');
END
$fn$;

CREATE FUNCTION education.can_write_application(p_application_id uuid,p_student_person_id uuid)
RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, consent, casework, education
RETURN coalesce(
  (auth.write_context_is_live() AND auth.current_channel()='FAMILY'
    AND core.actor_can_manage_subject(p_student_person_id,'EDUCATION'))
  OR (auth.write_context_is_live() AND auth.current_channel()='ADVISOR'
    AND casework.has_active_advisor_assignment('EDUCATION_APPLICATION',p_application_id)
    AND consent.has_active_consent(p_student_person_id,'EDUCATION_CASE','EDUCATION')),
  false);

CREATE FUNCTION education.create_application(
  p_application_id uuid,p_family_id uuid,p_student_person_id uuid,
  p_institution_label text,p_program_label text,p_cycle_label text
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, education, audit
AS $fn$
BEGIN
  IF (core.is_uuid_v7(p_application_id) AND auth.current_family_id()=p_family_id
      AND core.person_in_current_family(p_student_person_id)
      AND education.can_write_application(p_application_id,p_student_person_id)
      AND length(btrim(p_institution_label)) BETWEEN 1 AND 300
      AND length(btrim(p_program_label)) BETWEEN 1 AND 300
      AND length(btrim(p_cycle_label)) BETWEEN 1 AND 100
      AND EXISTS (SELECT 1 FROM core.student_profiles WHERE person_id=p_student_person_id)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','EDUCATION_APPLICATION',p_application_id,false,'FAMILY_ADVISOR_CONSENT_OR_INPUT_DENIED');
  END IF;
  IF EXISTS (SELECT 1 FROM education.applications WHERE application_id=p_application_id) THEN
    RETURN audit.record_write_decision('CREATE','EDUCATION_APPLICATION',p_application_id,false,'ALREADY_EXISTS');
  END IF;
  INSERT INTO education.applications(application_id,family_id,student_person_id,
    institution_label,program_label,cycle_label,status)
    VALUES (p_application_id,p_family_id,p_student_person_id,
      p_institution_label,p_program_label,p_cycle_label,'DRAFT');
  RETURN audit.record_write_decision('CREATE','EDUCATION_APPLICATION',p_application_id,true,'AUTHORIZED_CREATE');
END
$fn$;

CREATE FUNCTION education.advance_application(p_application_id uuid,p_next_status text)
RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, education, audit
AS $fn$
DECLARE v_item education.applications%ROWTYPE; v_valid boolean;
BEGIN
  SELECT * INTO v_item FROM education.applications WHERE application_id=p_application_id FOR UPDATE;
  IF (FOUND AND v_item.family_id=auth.current_family_id()
      AND education.can_write_application(v_item.application_id,v_item.student_person_id)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADVANCE','EDUCATION_APPLICATION',p_application_id,false,'FAMILY_ADVISOR_OR_CONSENT_DENIED');
  END IF;
  v_valid := (v_item.status='DRAFT' AND p_next_status IN ('READY','WITHDRAWN'))
    OR (v_item.status='READY' AND p_next_status IN ('SUBMITTED','WITHDRAWN'))
    OR (v_item.status='SUBMITTED' AND p_next_status IN ('DECIDED','WITHDRAWN'));
  IF v_valid IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADVANCE','EDUCATION_APPLICATION',p_application_id,false,'STATE_TRANSITION_DENIED');
  END IF;
  UPDATE education.applications SET status=p_next_status WHERE application_id=p_application_id;
  RETURN audit.record_write_decision('ADVANCE','EDUCATION_APPLICATION',p_application_id,true,'STATE_TRANSITION_ALLOWED');
END
$fn$;

CREATE FUNCTION identity.can_write_case(p_identity_case_id uuid,p_subject_person_id uuid)
RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, consent, casework, identity
RETURN coalesce(
  (auth.write_context_is_live() AND auth.current_channel()='FAMILY'
    AND core.actor_can_manage_subject(p_subject_person_id,'IDENTITY'))
  OR (auth.write_context_is_live() AND auth.current_channel()='ADVISOR'
    AND casework.has_active_advisor_assignment('IDENTITY_CASE',p_identity_case_id)
    AND consent.has_active_consent(p_subject_person_id,'IDENTITY_CASE','IDENTITY_SENSITIVE')),
  false);

CREATE FUNCTION identity.create_case(
  p_identity_case_id uuid,p_family_id uuid,p_subject_person_id uuid,p_case_kind text
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, identity, audit
AS $fn$
BEGIN
  IF (core.is_uuid_v7(p_identity_case_id) AND auth.current_family_id()=p_family_id
      AND core.person_in_current_family(p_subject_person_id)
      AND identity.can_write_case(p_identity_case_id,p_subject_person_id)
      AND length(btrim(p_case_kind)) BETWEEN 1 AND 100) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','IDENTITY_CASE',p_identity_case_id,false,'FAMILY_ADVISOR_CONSENT_OR_INPUT_DENIED');
  END IF;
  IF EXISTS (SELECT 1 FROM identity.cases WHERE identity_case_id=p_identity_case_id) THEN
    RETURN audit.record_write_decision('CREATE','IDENTITY_CASE',p_identity_case_id,false,'ALREADY_EXISTS');
  END IF;
  INSERT INTO identity.cases(identity_case_id,family_id,subject_person_id,case_kind,status)
    VALUES (p_identity_case_id,p_family_id,p_subject_person_id,p_case_kind,'DRAFT');
  RETURN audit.record_write_decision('CREATE','IDENTITY_CASE',p_identity_case_id,true,'AUTHORIZED_CREATE');
END
$fn$;

CREATE FUNCTION identity.advance_case(p_identity_case_id uuid,p_next_status text)
RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, identity, audit
AS $fn$
DECLARE v_item identity.cases%ROWTYPE; v_valid boolean;
BEGIN
  SELECT * INTO v_item FROM identity.cases WHERE identity_case_id=p_identity_case_id FOR UPDATE;
  IF (FOUND AND v_item.family_id=auth.current_family_id()
      AND identity.can_write_case(v_item.identity_case_id,v_item.subject_person_id)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADVANCE','IDENTITY_CASE',p_identity_case_id,false,'FAMILY_ADVISOR_OR_CONSENT_DENIED');
  END IF;
  v_valid := (v_item.status='DRAFT' AND p_next_status='EVIDENCE_PENDING')
    OR (v_item.status='EVIDENCE_PENDING' AND p_next_status='UNDER_REVIEW')
    OR (v_item.status='UNDER_REVIEW' AND p_next_status IN ('RESOLVED','CLOSED'));
  IF v_valid IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADVANCE','IDENTITY_CASE',p_identity_case_id,false,'STATE_TRANSITION_DENIED');
  END IF;
  UPDATE identity.cases SET status=p_next_status WHERE identity_case_id=p_identity_case_id;
  RETURN audit.record_write_decision('ADVANCE','IDENTITY_CASE',p_identity_case_id,true,'STATE_TRANSITION_ALLOWED');
END
$fn$;

CREATE FUNCTION docs.create_document(
  p_document_id uuid,p_family_id uuid,p_subject_person_id uuid,
  p_data_class text,p_document_kind text,p_retention_until timestamptz
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, docs, audit
AS $fn$
BEGIN
  IF (auth.is_internal_service() AND auth.current_family_id()=p_family_id
      AND core.is_uuid_v7(p_document_id)
      AND core.person_in_current_family(p_subject_person_id)
      AND p_data_class IN ('GENERAL','EDUCATION','IDENTITY_SENSITIVE')
      AND length(btrim(p_document_kind)) BETWEEN 1 AND 100
      AND p_retention_until>clock_timestamp()) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','DOCUMENT',p_document_id,false,'UPLOAD_SERVICE_FAMILY_OR_INPUT_DENIED');
  END IF;
  IF EXISTS (SELECT 1 FROM docs.documents WHERE document_id=p_document_id) THEN
    RETURN audit.record_write_decision('CREATE','DOCUMENT',p_document_id,false,'ALREADY_EXISTS');
  END IF;
  INSERT INTO docs.documents(document_id,family_id,subject_person_id,data_class,document_kind,retention_until)
    VALUES (p_document_id,p_family_id,p_subject_person_id,p_data_class,p_document_kind,p_retention_until);
  RETURN audit.record_write_decision('CREATE','DOCUMENT',p_document_id,true,'MOCK_METADATA_CREATED');
END
$fn$;

CREATE FUNCTION docs.append_document_version(
  p_version_id uuid,p_document_id uuid,p_version_no integer,
  p_content_sha256 char(64),p_storage_key text,p_size_bytes bigint
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, docs, audit
AS $fn$
DECLARE v_doc docs.documents%ROWTYPE; v_next integer;
BEGIN
  SELECT * INTO v_doc FROM docs.documents WHERE document_id=p_document_id FOR UPDATE;
  IF (FOUND AND auth.is_internal_service() AND v_doc.family_id=auth.current_family_id()
      AND core.is_uuid_v7(p_version_id) AND v_doc.withdrawn_at IS NULL
      AND p_content_sha256 ~ '^[0-9a-f]{64}$'
      AND length(p_storage_key) BETWEEN 10 AND 500
      AND p_storage_key ~ '^mock/[A-Za-z0-9/_-]+$'
      AND p_size_bytes>=0) IS NOT TRUE THEN
    RETURN audit.record_write_decision('APPEND','DOCUMENT_VERSION',p_version_id,false,'MOCK_UPLOAD_SERVICE_OR_INPUT_DENIED');
  END IF;
  SELECT coalesce(max(version_no),0)+1 INTO v_next FROM docs.document_versions WHERE document_id=p_document_id;
  IF p_version_no IS DISTINCT FROM v_next OR EXISTS (SELECT 1 FROM docs.document_versions WHERE version_id=p_version_id OR storage_key=p_storage_key) THEN
    RETURN audit.record_write_decision('APPEND','DOCUMENT_VERSION',p_version_id,false,'VERSION_SEQUENCE_OR_KEY_DENIED');
  END IF;
  INSERT INTO docs.document_versions(version_id,document_id,version_no,content_sha256,storage_key,size_bytes)
    VALUES (p_version_id,p_document_id,p_version_no,p_content_sha256,p_storage_key,p_size_bytes);
  RETURN audit.record_write_decision('APPEND','DOCUMENT_VERSION',p_version_id,true,'MOCK_VERSION_APPENDED');
END
$fn$;

CREATE FUNCTION docs.can_manage_submission_target(
  p_family_id uuid,p_subject_person_id uuid,p_target_kind text,p_target_id uuid
) RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, consent, casework, education, identity, docs
RETURN coalesce(
  auth.write_context_is_live()
  AND auth.current_family_id()=p_family_id
  AND ((p_target_kind='EDUCATION_APPLICATION' AND EXISTS (
         SELECT 1 FROM education.applications a WHERE a.application_id=p_target_id
           AND a.family_id=p_family_id AND a.student_person_id=p_subject_person_id))
       OR (p_target_kind='IDENTITY_CASE' AND EXISTS (
         SELECT 1 FROM identity.cases c WHERE c.identity_case_id=p_target_id
           AND c.family_id=p_family_id AND c.subject_person_id=p_subject_person_id)))
  AND CASE p_target_kind
    WHEN 'EDUCATION_APPLICATION' THEN education.can_write_application(p_target_id,p_subject_person_id)
    WHEN 'IDENTITY_CASE' THEN identity.can_write_case(p_target_id,p_subject_person_id)
    ELSE false END, false);

CREATE FUNCTION docs.create_submission_manifest(
  p_submission_id uuid,p_family_id uuid,p_subject_person_id uuid,
  p_target_kind text,p_target_id uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, docs, audit
AS $fn$
BEGIN
  IF (core.is_uuid_v7(p_submission_id)
      AND docs.can_manage_submission_target(p_family_id,p_subject_person_id,p_target_kind,p_target_id)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','SUBMISSION_MANIFEST',p_submission_id,false,'TARGET_OR_OPERATOR_DENIED');
  END IF;
  IF EXISTS (SELECT 1 FROM docs.submission_manifests WHERE submission_id=p_submission_id) THEN
    RETURN audit.record_write_decision('CREATE','SUBMISSION_MANIFEST',p_submission_id,false,'ALREADY_EXISTS');
  END IF;
  INSERT INTO docs.submission_manifests(submission_id,family_id,subject_person_id,target_kind,target_id,status,prepared_by)
    VALUES (p_submission_id,p_family_id,p_subject_person_id,p_target_kind,p_target_id,'PREPARING',auth.current_actor_person_id());
  RETURN audit.record_write_decision('CREATE','SUBMISSION_MANIFEST',p_submission_id,true,'PREPARING_CREATED');
END
$fn$;

CREATE FUNCTION docs.add_submission_item(
  p_submission_id uuid,p_item_no integer,p_version_id uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, docs, audit
AS $fn$
DECLARE v_manifest docs.submission_manifests%ROWTYPE; v_digest char(64);
BEGIN
  SELECT * INTO v_manifest FROM docs.submission_manifests WHERE submission_id=p_submission_id FOR UPDATE;
  IF (FOUND AND v_manifest.status='PREPARING'
      AND docs.can_manage_submission_target(v_manifest.family_id,v_manifest.subject_person_id,
        v_manifest.target_kind,v_manifest.target_id)
      AND p_item_no>0) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADD_ITEM','SUBMISSION_MANIFEST',p_submission_id,false,'MANIFEST_OPERATOR_OR_STATE_DENIED');
  END IF;
  SELECT v.content_sha256 INTO v_digest
    FROM docs.document_versions v JOIN docs.documents d ON d.document_id=v.document_id
   WHERE v.version_id=p_version_id AND d.family_id=v_manifest.family_id
     AND d.subject_person_id=v_manifest.subject_person_id AND d.withdrawn_at IS NULL
     AND docs.can_read_document(d.subject_person_id,d.data_class);
  IF v_digest IS NULL OR EXISTS (SELECT 1 FROM docs.submission_items
      WHERE submission_id=p_submission_id AND (item_no=p_item_no OR version_id=p_version_id)) THEN
    RETURN audit.record_write_decision('ADD_ITEM','SUBMISSION_MANIFEST',p_submission_id,false,'DOCUMENT_OR_ITEM_DENIED');
  END IF;
  INSERT INTO docs.submission_items(submission_id,item_no,version_id,pinned_sha256)
    VALUES (p_submission_id,p_item_no,p_version_id,v_digest);
  RETURN audit.record_write_decision('ADD_ITEM','SUBMISSION_MANIFEST',p_submission_id,true,'VERSION_PINNED');
END
$fn$;

CREATE FUNCTION docs.submit_manifest(p_submission_id uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, docs, audit
AS $fn$
DECLARE v_manifest docs.submission_manifests%ROWTYPE;
BEGIN
  SELECT * INTO v_manifest FROM docs.submission_manifests WHERE submission_id=p_submission_id FOR UPDATE;
  IF (FOUND AND v_manifest.status='PREPARING'
      AND docs.can_manage_submission_target(v_manifest.family_id,v_manifest.subject_person_id,
        v_manifest.target_kind,v_manifest.target_id)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('SUBMIT','SUBMISSION_MANIFEST',p_submission_id,false,'MANIFEST_OPERATOR_OR_STATE_DENIED');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM docs.submission_items WHERE submission_id=p_submission_id)
     OR EXISTS (SELECT 1 FROM docs.submission_items i
       JOIN docs.document_versions v ON v.version_id=i.version_id
       JOIN docs.documents d ON d.document_id=v.document_id
       WHERE i.submission_id=p_submission_id AND (d.withdrawn_at IS NOT NULL
         OR d.family_id<>v_manifest.family_id OR d.subject_person_id<>v_manifest.subject_person_id
         OR docs.can_read_document(d.subject_person_id,d.data_class) IS NOT TRUE)) THEN
    RETURN audit.record_write_decision('SUBMIT','SUBMISSION_MANIFEST',p_submission_id,false,'ITEMS_INVALID_OR_WITHDRAWN');
  END IF;
  UPDATE docs.submission_manifests SET status='SUBMITTED',
    confirmed_by=auth.current_actor_person_id(),
    submitted_by=auth.current_actor_person_id(),submitted_at=clock_timestamp()
   WHERE submission_id=p_submission_id;
  RETURN audit.record_write_decision('SUBMIT','SUBMISSION_MANIFEST',p_submission_id,true,'SUBMITTED_IMMUTABLE');
END
$fn$;

REVOKE EXECUTE ON FUNCTION core.reject_guardian_evidence_change(),
  core.audit_guardian_authority_history(),
  auth.write_context_is_live(),auth.is_internal_service(),core.actor_can_manage_subject(uuid,text),
  audit.record_write_decision(text,text,uuid,boolean,text),
  consent.actor_can_grant(uuid,text,text),
  education.can_write_application(uuid,uuid),identity.can_write_case(uuid,uuid),
  docs.can_manage_submission_target(uuid,uuid,text,uuid)
FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION core.create_family(uuid,text),
  core.create_person(uuid,text,uuid,uuid,text),
  core.add_family_member(uuid,uuid,uuid,text),core.create_student_profile(uuid),
  consent.create_grant(uuid,uuid,uuid,uuid,text,text,timestamptz),
  consent.withdraw_grant(uuid),
  education.create_application(uuid,uuid,uuid,text,text,text),
  education.advance_application(uuid,text),
  identity.create_case(uuid,uuid,uuid,text),identity.advance_case(uuid,text),
  docs.create_document(uuid,uuid,uuid,text,text,timestamptz),
  docs.append_document_version(uuid,uuid,integer,character,text,bigint),
  docs.create_submission_manifest(uuid,uuid,uuid,text,uuid),
  docs.add_submission_item(uuid,integer,uuid),docs.submit_manifest(uuid)
FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core.create_family(uuid,text),
  core.create_person(uuid,text,uuid,uuid,text),
  core.add_family_member(uuid,uuid,uuid,text),core.create_student_profile(uuid),
  consent.create_grant(uuid,uuid,uuid,uuid,text,text,timestamptz),
  consent.withdraw_grant(uuid),
  education.create_application(uuid,uuid,uuid,text,text,text),
  education.advance_application(uuid,text),
  identity.create_case(uuid,uuid,uuid,text),identity.advance_case(uuid,text),
  docs.create_document(uuid,uuid,uuid,text,text,timestamptz),
  docs.append_document_version(uuid,uuid,integer,character,text,bigint),
  docs.create_submission_manifest(uuid,uuid,uuid,text,uuid),
  docs.add_submission_item(uuid,integer,uuid),docs.submit_manifest(uuid)
TO phoenix_canonical_app;

REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA auth, core, consent, audit,
  integration, docs, casework, education, identity FROM phoenix_canonical_app;

COMMIT;
