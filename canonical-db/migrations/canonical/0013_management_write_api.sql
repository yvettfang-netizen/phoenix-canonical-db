BEGIN;

-- D-10: management calls are made by a SERVICE principal through an INTERNAL
-- ticket. The installer alone can install or disable that principal.
ALTER TABLE auth.principals ADD COLUMN created_by_principal_id uuid REFERENCES auth.principals;
ALTER TABLE auth.principals ADD COLUMN disabled_by_principal_id uuid REFERENCES auth.principals;
ALTER TABLE casework.cases ADD COLUMN created_by_principal_id uuid REFERENCES auth.principals;
ALTER TABLE casework.cases ADD COLUMN closed_by_principal_id uuid REFERENCES auth.principals;
ALTER TABLE casework.advisor_assignments ADD COLUMN assigned_by_principal_id uuid REFERENCES auth.principals;
ALTER TABLE casework.advisor_assignments ADD COLUMN revoked_by_principal_id uuid REFERENCES auth.principals;
ALTER TABLE core.guardian_authorities ADD COLUMN evidence_ref text;
ALTER TABLE core.guardian_authorities ADD COLUMN verified_by_principal_id uuid REFERENCES auth.principals;
ALTER TABLE core.guardian_authorities ADD COLUMN revoked_by_principal_id uuid REFERENCES auth.principals;
ALTER TABLE integration.channel_grants ADD COLUMN granted_by_principal_id uuid REFERENCES auth.principals;
ALTER TABLE integration.channel_grants ADD COLUMN revoked_by_principal_id uuid REFERENCES auth.principals;

CREATE FUNCTION auth.install_service_principal(p_id uuid,p_label text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,audit AS $fn$
BEGIN
  IF (core.is_uuid_v7(p_id) AND length(btrim(p_label)) BETWEEN 1 AND 200
      AND NOT EXISTS (SELECT 1 FROM auth.principals WHERE principal_id=p_id)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('INSTALL','SERVICE_PRINCIPAL',p_id,false,'INSTALL_INPUT_DENIED');
  END IF;
  INSERT INTO auth.principals(principal_id,person_id,principal_kind,status,service_label)
  VALUES(p_id,NULL,'SERVICE','ACTIVE',p_label);
  RETURN audit.record_write_decision('INSTALL','SERVICE_PRINCIPAL',p_id,true,'INSTALLER_CREATED');
END $fn$;
CREATE FUNCTION auth.disable_service_principal(p_id uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,audit AS $fn$
BEGIN
  UPDATE auth.principals SET status='DISABLED' WHERE principal_id=p_id
    AND principal_kind='SERVICE' AND status='ACTIVE';
  IF NOT FOUND THEN RETURN audit.record_write_decision('DISABLE','SERVICE_PRINCIPAL',p_id,false,'NOT_ACTIVE_SERVICE'); END IF;
  DELETE FROM auth.session_contexts WHERE principal_id=p_id;
  DELETE FROM auth.context_exchange_tickets WHERE principal_id=p_id;
  RETURN audit.record_write_decision('DISABLE','SERVICE_PRINCIPAL',p_id,true,'INSTALLER_DISABLED');
END $fn$;

CREATE OR REPLACE FUNCTION core.create_family(p_family_id uuid,p_display_name text) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,integration,audit AS $fn$
BEGIN
  IF (auth.is_internal_service() AND auth.current_family_id() IS NULL
      AND core.is_uuid_v7(p_family_id) AND length(btrim(p_display_name)) BETWEEN 1 AND 200) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','FAMILY',p_family_id,false,'UNBOUND_SERVICE_OR_INPUT_DENIED');
  END IF;
  IF EXISTS (SELECT 1 FROM core.families WHERE family_id=p_family_id) THEN
    RETURN audit.record_write_decision('CREATE','FAMILY',p_family_id,false,'ALREADY_EXISTS');
  END IF;
  INSERT INTO core.families(family_id,display_name) VALUES(p_family_id,p_display_name);
  INSERT INTO integration.public_ids(entity_kind,public_id,canonical_id)
    VALUES('FAMILY','fam_'||replace(p_family_id::text,'-',''),p_family_id);
  RETURN audit.record_write_decision('CREATE','FAMILY',p_family_id,true,'UNBOUND_SERVICE_CREATED');
END $fn$;

-- A global advisor or partner has no family membership merely because they
-- participate in one family case. This is installer-managed business master.
CREATE FUNCTION core.register_external_person(p_id uuid,p_name text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,integration,audit AS $fn$
BEGIN
  IF (auth.is_internal_service() AND auth.current_family_id() IS NULL
      AND core.is_uuid_v7(p_id) AND length(btrim(p_name)) BETWEEN 1 AND 200) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','EXTERNAL_PERSON',p_id,false,'UNBOUND_SERVICE_OR_INPUT_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM core.people WHERE person_id=p_id) THEN
    RETURN audit.record_write_decision('CREATE','EXTERNAL_PERSON',p_id,false,'ALREADY_EXISTS');
  END IF;
  INSERT INTO core.people(person_id,display_name) VALUES(p_id,p_name);
  INSERT INTO integration.public_ids(entity_kind,public_id,canonical_id)
    VALUES('PERSON','per_'||replace(p_id::text,'-',''),p_id);
  RETURN audit.record_write_decision('CREATE','EXTERNAL_PERSON',p_id,true,'EXTERNAL_PERSON_CREATED');
END $fn$;

CREATE FUNCTION auth.create_login_principal(p_id uuid,p_person_id uuid,p_kind text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,audit AS $fn$
BEGIN
  IF (auth.is_internal_service() AND core.is_uuid_v7(p_id)
      AND p_kind IN ('FAMILY','ADVISOR','CHANNEL')
      AND EXISTS(SELECT 1 FROM core.people WHERE person_id=p_person_id)
      AND (p_kind<>'FAMILY' OR (auth.current_family_id() IS NOT NULL
        AND core.person_in_current_family(p_person_id)))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','LOGIN_PRINCIPAL',p_id,false,'SERVICE_PERSON_KIND_OR_FAMILY_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM auth.principals WHERE principal_id=p_id OR person_id=p_person_id) THEN
    RETURN audit.record_write_decision('CREATE','LOGIN_PRINCIPAL',p_id,false,'ALREADY_EXISTS');
  END IF;
  INSERT INTO auth.principals(principal_id,person_id,principal_kind,status,created_by_principal_id)
    VALUES(p_id,p_person_id,p_kind,'ACTIVE',auth.current_principal_id());
  RETURN audit.record_write_decision('CREATE','LOGIN_PRINCIPAL',p_id,true,'SERVICE_CREATED');
END $fn$;
CREATE FUNCTION auth.disable_login_principal(p_id uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,audit AS $fn$
DECLARE v_person uuid; v_kind text;
BEGIN
  SELECT person_id,principal_kind INTO v_person,v_kind FROM auth.principals
    WHERE principal_id=p_id AND status='ACTIVE' FOR UPDATE;
  IF (FOUND AND auth.is_internal_service() AND v_kind IN ('FAMILY','ADVISOR','CHANNEL')
      AND (v_kind<>'FAMILY' OR core.person_in_current_family(v_person))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('DISABLE','LOGIN_PRINCIPAL',p_id,false,'SERVICE_FAMILY_OR_STATUS_DENIED');
  END IF;
  UPDATE auth.principals SET status='DISABLED',disabled_by_principal_id=auth.current_principal_id()
    WHERE principal_id=p_id;
  DELETE FROM auth.session_contexts WHERE principal_id=p_id;
  DELETE FROM auth.context_exchange_tickets WHERE principal_id=p_id;
  RETURN audit.record_write_decision('DISABLE','LOGIN_PRINCIPAL',p_id,true,'SERVICE_DISABLED');
END $fn$;

CREATE FUNCTION casework.create_case(p_id uuid,p_family_id uuid,p_subject_id uuid,
  p_title text,p_resource_kind text,p_resource_id uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,casework,audit AS $fn$
BEGIN
  IF (auth.is_internal_service() AND auth.current_family_id()=p_family_id
      AND core.is_uuid_v7(p_id) AND core.person_in_current_family(p_subject_id)
      AND length(btrim(p_title)) BETWEEN 1 AND 300
      AND ((p_resource_kind IS NULL AND p_resource_id IS NULL)
        OR (p_resource_kind IN ('EDUCATION_APPLICATION','IDENTITY_CASE') AND core.is_uuid_v7(p_resource_id)))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','CASEWORK_CASE',p_id,false,'SERVICE_FAMILY_OR_INPUT_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM casework.cases WHERE case_id=p_id) THEN
    RETURN audit.record_write_decision('CREATE','CASEWORK_CASE',p_id,false,'ALREADY_EXISTS');
  END IF;
  INSERT INTO casework.cases(case_id,family_id,subject_person_id,title,status,resource_kind,resource_id,created_by_principal_id)
    VALUES(p_id,p_family_id,p_subject_id,p_title,'OPEN',p_resource_kind,p_resource_id,auth.current_principal_id());
  RETURN audit.record_write_decision('CREATE','CASEWORK_CASE',p_id,true,'SERVICE_CREATED');
END $fn$;
CREATE FUNCTION casework.close_case(p_id uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,casework,audit AS $fn$
DECLARE v_case casework.cases%ROWTYPE;
BEGIN
  SELECT * INTO v_case FROM casework.cases WHERE case_id=p_id FOR UPDATE;
  IF (FOUND AND auth.is_internal_service() AND v_case.family_id=auth.current_family_id()
      AND v_case.status IN ('OPEN','PAUSED')) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CLOSE','CASEWORK_CASE',p_id,false,'SERVICE_FAMILY_OR_STATUS_DENIED');
  END IF;
  UPDATE casework.cases SET status='CLOSED',updated_at=clock_timestamp(),
    closed_by_principal_id=auth.current_principal_id() WHERE case_id=p_id;
  RETURN audit.record_write_decision('CLOSE','CASEWORK_CASE',p_id,true,'SERVICE_CLOSED');
END $fn$;

CREATE FUNCTION casework.create_advisor_assignment(p_id uuid,p_case_id uuid,p_advisor_id uuid,
  p_valid_until timestamptz) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,casework,audit AS $fn$
DECLARE v_case casework.cases%ROWTYPE;
BEGIN
  SELECT * INTO v_case FROM casework.cases WHERE case_id=p_case_id;
  IF (FOUND AND auth.is_internal_service() AND v_case.family_id=auth.current_family_id()
      AND v_case.status IN ('OPEN','PAUSED') AND core.is_uuid_v7(p_id)
      AND p_valid_until>clock_timestamp()
      AND EXISTS(SELECT 1 FROM auth.principals WHERE person_id=p_advisor_id
        AND principal_kind='ADVISOR' AND status='ACTIVE')) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ASSIGN','ADVISOR_ASSIGNMENT',p_id,false,'SERVICE_CASE_ADVISOR_OR_INPUT_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM casework.advisor_assignments WHERE assignment_id=p_id) THEN
    RETURN audit.record_write_decision('ASSIGN','ADVISOR_ASSIGNMENT',p_id,false,'ALREADY_EXISTS');
  END IF;
  INSERT INTO casework.advisor_assignments(assignment_id,case_id,advisor_person_id,valid_from,valid_until,assigned_by_principal_id)
    VALUES(p_id,p_case_id,p_advisor_id,clock_timestamp(),p_valid_until,auth.current_principal_id());
  RETURN audit.record_write_decision('ASSIGN','ADVISOR_ASSIGNMENT',p_id,true,'SERVICE_ASSIGNED');
END $fn$;
CREATE FUNCTION casework.revoke_advisor_assignment(p_id uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,casework,audit AS $fn$
DECLARE v_family uuid; v_until timestamptz; v_revoked timestamptz;
BEGIN
  SELECT c.family_id,a.valid_until,a.revoked_at INTO v_family,v_until,v_revoked
    FROM casework.advisor_assignments a JOIN casework.cases c ON c.case_id=a.case_id
    WHERE a.assignment_id=p_id FOR UPDATE OF a;
  IF (FOUND AND auth.is_internal_service() AND v_family=auth.current_family_id()
      AND v_revoked IS NULL AND v_until>clock_timestamp()) IS NOT TRUE THEN
    RETURN audit.record_write_decision('REVOKE','ADVISOR_ASSIGNMENT',p_id,false,'SERVICE_FAMILY_OR_STATUS_DENIED');
  END IF;
  UPDATE casework.advisor_assignments SET revoked_at=clock_timestamp(),
    revoked_by_principal_id=auth.current_principal_id() WHERE assignment_id=p_id;
  RETURN audit.record_write_decision('REVOKE','ADVISOR_ASSIGNMENT',p_id,true,'SERVICE_REVOKED');
END $fn$;

CREATE FUNCTION core.create_guardian_authority(p_id uuid,p_family_id uuid,p_guardian_id uuid,
  p_subject_id uuid,p_level text,p_scope text,p_until timestamptz,p_evidence_ref text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,audit AS $fn$
BEGIN
  IF (auth.is_internal_service() AND auth.current_family_id()=p_family_id
      AND core.is_uuid_v7(p_id) AND p_guardian_id<>p_subject_id
      AND core.person_in_current_family(p_guardian_id)
      AND core.person_in_current_family(p_subject_id)
      AND p_level='VERIFIED' AND p_scope IN ('GENERAL','EDUCATION','IDENTITY')
      AND p_until>clock_timestamp()
      AND length(btrim(p_evidence_ref)) BETWEEN 1 AND 500) IS NOT TRUE THEN
    RETURN audit.record_write_decision('VERIFY','GUARDIAN_AUTHORITY',p_id,false,'SERVICE_EVIDENCE_OR_FAMILY_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM core.guardian_authorities WHERE authority_id=p_id) THEN
    RETURN audit.record_write_decision('VERIFY','GUARDIAN_AUTHORITY',p_id,false,'ALREADY_EXISTS');
  END IF;
  INSERT INTO core.guardian_authorities(authority_id,family_id,guardian_person_id,subject_person_id,
    evidence_level,scope,valid_from,valid_until,evidence_ref,verified_by_principal_id)
    VALUES(p_id,p_family_id,p_guardian_id,p_subject_id,p_level,p_scope,clock_timestamp(),p_until,
      p_evidence_ref,auth.current_principal_id());
  RETURN audit.record_write_decision('VERIFY','GUARDIAN_AUTHORITY',p_id,true,'SERVICE_VERIFIED');
END $fn$;
CREATE FUNCTION core.revoke_guardian_authority(p_id uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,audit AS $fn$
DECLARE v_item core.guardian_authorities%ROWTYPE;
BEGIN
  SELECT * INTO v_item FROM core.guardian_authorities WHERE authority_id=p_id FOR UPDATE;
  IF (FOUND AND auth.is_internal_service() AND v_item.family_id=auth.current_family_id()
      AND v_item.revoked_at IS NULL AND v_item.valid_until>clock_timestamp()) IS NOT TRUE THEN
    RETURN audit.record_write_decision('REVOKE','GUARDIAN_AUTHORITY',p_id,false,'SERVICE_FAMILY_OR_STATUS_DENIED');
  END IF;
  UPDATE core.guardian_authorities SET revoked_at=clock_timestamp(),
    revoked_by_principal_id=auth.current_principal_id() WHERE authority_id=p_id;
  RETURN audit.record_write_decision('REVOKE','GUARDIAN_AUTHORITY',p_id,true,'SERVICE_REVOKED');
END $fn$;

CREATE FUNCTION integration.create_channel_grant(p_id uuid,p_principal_id uuid,
  p_family_id uuid,p_subject_id uuid,p_until timestamptz) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,integration,audit AS $fn$
BEGIN
  IF (auth.is_internal_service() AND auth.current_family_id()=p_family_id
      AND core.is_uuid_v7(p_id) AND core.person_in_current_family(p_subject_id)
      AND p_until>clock_timestamp()
      AND EXISTS(SELECT 1 FROM auth.principals WHERE principal_id=p_principal_id
        AND principal_kind='CHANNEL' AND status='ACTIVE')) IS NOT TRUE THEN
    RETURN audit.record_write_decision('GRANT','CHANNEL_SUBJECT',p_id,false,'SERVICE_FAMILY_SUBJECT_OR_CHANNEL_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM integration.channel_grants WHERE channel_grant_id=p_id
      OR (principal_id=p_principal_id AND family_id=p_family_id
      AND subject_person_id=p_subject_id AND channel='PARTNER' AND revoked_at IS NULL
      AND valid_until>clock_timestamp())) THEN
    RETURN audit.record_write_decision('GRANT','CHANNEL_SUBJECT',p_id,false,'ALREADY_ACTIVE');
  END IF;
  INSERT INTO integration.channel_grants(channel_grant_id,principal_id,family_id,subject_person_id,
    channel,valid_from,valid_until,granted_by_principal_id)
    VALUES(p_id,p_principal_id,p_family_id,p_subject_id,'PARTNER',clock_timestamp(),p_until,
      auth.current_principal_id());
  RETURN audit.record_write_decision('GRANT','CHANNEL_SUBJECT',p_id,true,'SERVICE_GRANTED');
END $fn$;
CREATE FUNCTION integration.revoke_channel_grant(p_id uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,integration,audit AS $fn$
DECLARE v_item integration.channel_grants%ROWTYPE;
BEGIN
  SELECT * INTO v_item FROM integration.channel_grants WHERE channel_grant_id=p_id FOR UPDATE;
  IF (FOUND AND auth.is_internal_service() AND v_item.family_id=auth.current_family_id()
      AND v_item.revoked_at IS NULL AND v_item.valid_until>clock_timestamp()) IS NOT TRUE THEN
    RETURN audit.record_write_decision('REVOKE','CHANNEL_SUBJECT',p_id,false,'SERVICE_FAMILY_OR_STATUS_DENIED');
  END IF;
  UPDATE integration.channel_grants SET revoked_at=clock_timestamp(),
    revoked_by_principal_id=auth.current_principal_id() WHERE channel_grant_id=p_id;
  RETURN audit.record_write_decision('REVOKE','CHANNEL_SUBJECT',p_id,true,'SERVICE_REVOKED');
END $fn$;

REVOKE EXECUTE ON FUNCTION auth.install_service_principal(uuid,text),
  auth.disable_service_principal(uuid),core.register_external_person(uuid,text),
  auth.create_login_principal(uuid,uuid,text),auth.disable_login_principal(uuid),
  casework.create_case(uuid,uuid,uuid,text,text,uuid),casework.close_case(uuid),
  casework.create_advisor_assignment(uuid,uuid,uuid,timestamptz),
  casework.revoke_advisor_assignment(uuid),
  core.create_guardian_authority(uuid,uuid,uuid,uuid,text,text,timestamptz,text),
  core.revoke_guardian_authority(uuid),
  integration.create_channel_grant(uuid,uuid,uuid,uuid,timestamptz),
  integration.revoke_channel_grant(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION auth.install_service_principal(uuid,text),
  auth.disable_service_principal(uuid) TO phoenix_canonical_migrator;
GRANT EXECUTE ON FUNCTION core.register_external_person(uuid,text),
  auth.create_login_principal(uuid,uuid,text),auth.disable_login_principal(uuid),
  casework.create_case(uuid,uuid,uuid,text,text,uuid),casework.close_case(uuid),
  casework.create_advisor_assignment(uuid,uuid,uuid,timestamptz),
  casework.revoke_advisor_assignment(uuid),
  core.create_guardian_authority(uuid,uuid,uuid,uuid,text,text,timestamptz,text),
  core.revoke_guardian_authority(uuid),
  integration.create_channel_grant(uuid,uuid,uuid,uuid,timestamptz),
  integration.revoke_channel_grant(uuid) TO phoenix_canonical_app;

COMMIT;
