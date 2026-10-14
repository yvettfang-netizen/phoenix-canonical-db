BEGIN;

CREATE FUNCTION education.authorize_application_read(p_application_id uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, consent, casework, education, audit
AS $fn$
DECLARE
  item education.applications%ROWTYPE;
  allowed boolean := false;
  reason text := 'RESOURCE_NOT_FOUND';
BEGIN
  SELECT * INTO item FROM education.applications WHERE application_id = p_application_id;
  IF FOUND THEN
    IF auth.current_family_id() IS NULL THEN reason := 'NO_TRUSTED_CONTEXT';
    ELSIF item.family_id <> auth.current_family_id() THEN reason := 'CROSS_FAMILY_DENIED';
    ELSIF core.current_actor_is_family_member() THEN allowed := true; reason := 'FAMILY_MEMBER_ALLOWED';
    ELSIF casework.has_active_advisor_assignment('EDUCATION_APPLICATION', item.application_id)
      AND consent.has_active_consent(item.student_person_id, 'EDUCATION_CASE', 'EDUCATION')
      THEN allowed := true; reason := 'ADVISOR_CONSENT_ALLOWED';
    ELSE reason := 'ADVISOR_OR_CONSENT_DENIED';
    END IF;
  END IF;
  PERFORM audit.record_access_event('READ','EDUCATION_APPLICATION',p_application_id,CASE WHEN allowed THEN 'ALLOW' ELSE 'DENY' END,reason);
  RETURN allowed;
END
$fn$;

CREATE FUNCTION identity.authorize_case_read(p_identity_case_id uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, consent, casework, integration, identity, audit
AS $fn$
DECLARE
  item identity.cases%ROWTYPE;
  allowed boolean := false;
  reason text := 'RESOURCE_NOT_FOUND';
BEGIN
  SELECT * INTO item FROM identity.cases WHERE identity_case_id = p_identity_case_id;
  IF FOUND THEN
    IF auth.current_family_id() IS NULL THEN reason := 'NO_TRUSTED_CONTEXT';
    ELSIF item.family_id <> auth.current_family_id() THEN reason := 'CROSS_FAMILY_DENIED';
    ELSIF core.current_actor_is_family_member() THEN allowed := true; reason := 'FAMILY_MEMBER_ALLOWED';
    ELSIF casework.has_active_advisor_assignment('IDENTITY_CASE', item.identity_case_id)
      AND consent.has_active_consent(item.subject_person_id, 'IDENTITY_CASE', 'IDENTITY_SENSITIVE')
      THEN allowed := true; reason := 'ADVISOR_CONSENT_ALLOWED';
    ELSIF integration.has_active_channel_grant(item.subject_person_id)
      AND consent.has_active_consent(item.subject_person_id, 'IDENTITY_CASE', 'IDENTITY_SENSITIVE')
      THEN allowed := true; reason := 'CHANNEL_CONSENT_ALLOWED';
    ELSE reason := 'CHANNEL_ADVISOR_OR_CONSENT_DENIED';
    END IF;
  END IF;
  PERFORM audit.record_access_event('READ','IDENTITY_CASE',p_identity_case_id,CASE WHEN allowed THEN 'ALLOW' ELSE 'DENY' END,reason);
  RETURN allowed;
END
$fn$;

CREATE FUNCTION docs.authorize_document_read(p_document_id uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, docs, audit
AS $fn$
DECLARE
  item docs.documents%ROWTYPE;
  allowed boolean := false;
  reason text := 'RESOURCE_NOT_FOUND';
BEGIN
  SELECT * INTO item FROM docs.documents WHERE document_id = p_document_id;
  IF FOUND THEN
    IF auth.current_family_id() IS NULL THEN reason := 'NO_TRUSTED_CONTEXT';
    ELSIF item.family_id <> auth.current_family_id() THEN reason := 'CROSS_FAMILY_DENIED';
    ELSIF docs.can_read_document(item.subject_person_id, item.data_class) THEN allowed := true; reason := 'CONSENT_AND_AUTHORITY_ALLOWED';
    ELSE reason := 'CONSENT_AUTHORITY_OR_CHANNEL_DENIED';
    END IF;
  END IF;
  PERFORM audit.record_access_event('READ','DOCUMENT',p_document_id,CASE WHEN allowed THEN 'ALLOW' ELSE 'DENY' END,reason);
  RETURN allowed;
END
$fn$;

REVOKE ALL ON FUNCTION education.authorize_application_read(uuid), identity.authorize_case_read(uuid), docs.authorize_document_read(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION education.authorize_application_read(uuid), identity.authorize_case_read(uuid), docs.authorize_document_read(uuid) TO phoenix_canonical_app;

COMMIT;
