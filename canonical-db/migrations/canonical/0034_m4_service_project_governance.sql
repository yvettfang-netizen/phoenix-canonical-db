BEGIN;

-- V2.0 M4 governs the existing Service Project authority. It adds project-
-- scoped authorization evidence; it does not create a second Consent master.

ALTER TABLE service.project_parties
  DROP CONSTRAINT project_parties_party_role_check,
  ADD CONSTRAINT project_parties_party_role_check CHECK (party_role IN (
    'PAYER','CONTRACTING_PARTY','FAMILY_ADMIN','AUTHORIZED_VIEWER',
    'CLIENT_REPRESENTATIVE','SERVICE_PROVIDER','REFERRING_PARTNER'
  )),
  ADD COLUMN status text NOT NULL DEFAULT 'ACTIVE'
    CHECK (status IN ('ACTIVE','ENDED')),
  ADD COLUMN ended_by_principal_id uuid REFERENCES auth.principals,
  ADD CONSTRAINT project_parties_terminal_check CHECK (
    (status='ACTIVE' AND ended_by_principal_id IS NULL)
    OR (status='ENDED' AND valid_until IS NOT NULL AND ended_by_principal_id IS NOT NULL)
  );

CREATE TABLE service.project_subject_authorizations (
  project_subject_authorization_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(project_subject_authorization_id)),
  service_project_id uuid NOT NULL REFERENCES service.projects,
  family_id uuid NOT NULL REFERENCES core.families,
  subject_person_id uuid NOT NULL REFERENCES core.people,
  authorization_kind text NOT NULL CHECK (authorization_kind IN ('PATIENT_SELF','LEGAL_GUARDIAN')),
  data_scope text NOT NULL CHECK (data_scope='HEALTH'),
  authorizer_person_id uuid NOT NULL REFERENCES core.people,
  evidence_sha256 text NOT NULL CHECK (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  status text NOT NULL CHECK (status IN ('ACTIVE','REVOKED')),
  valid_from timestamptz NOT NULL,
  valid_until timestamptz NOT NULL,
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  revoked_by_principal_id uuid REFERENCES auth.principals,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  CHECK (valid_until>valid_from),
  CHECK ((status='REVOKED')=(revoked_by_principal_id IS NOT NULL AND revoked_at IS NOT NULL)),
  UNIQUE(project_subject_authorization_id,service_project_id,subject_person_id)
);
CREATE INDEX project_subject_authorizations_current_idx
  ON service.project_subject_authorizations(service_project_id,subject_person_id,status,valid_until);

ALTER TABLE service.project_subjects
  DROP CONSTRAINT project_subjects_service_project_id_subject_person_id_data__key,
  ADD COLUMN status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','ENDED')),
  ADD COLUMN valid_from timestamptz NOT NULL DEFAULT transaction_timestamp(),
  ADD COLUMN valid_until timestamptz,
  ADD COLUMN authorization_id uuid,
  ADD COLUMN ended_by_principal_id uuid REFERENCES auth.principals,
  ADD CONSTRAINT project_subjects_validity_check CHECK (valid_until IS NULL OR valid_until>valid_from),
  ADD CONSTRAINT project_subjects_terminal_check CHECK (
    (status='ACTIVE' AND ended_by_principal_id IS NULL)
    OR (status='ENDED' AND valid_until IS NOT NULL AND ended_by_principal_id IS NOT NULL)
  ),
  ADD CONSTRAINT project_subjects_authorization_fk FOREIGN KEY(
    authorization_id,service_project_id,subject_person_id
  ) REFERENCES service.project_subject_authorizations(
    project_subject_authorization_id,service_project_id,subject_person_id
  );
CREATE UNIQUE INDEX project_subjects_current_uq
  ON service.project_subjects(service_project_id,subject_person_id,data_scope)
  WHERE status='ACTIVE';

ALTER TABLE service.project_events DROP CONSTRAINT project_events_event_kind_check;
ALTER TABLE service.project_events ADD CONSTRAINT project_events_event_kind_check CHECK (event_kind IN (
  'CREATED','STATUS_CHANGED','PARTY_ADDED','PARTY_ENDED','SUBJECT_AUTHORIZED','SUBJECT_AUTHORIZATION_REVOKED',
  'SUBJECT_ADDED','SUBJECT_ENDED','DOMAIN_ADDED','ASSIGNED','ASSIGNMENT_ENDED',
  'TASK_CREATED','MILESTONE_CREATED','MILESTONE_CHANGED','DELIVERABLE_CHANGED'
));

CREATE FUNCTION service.protect_m4_terminal_row() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $fn$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'SERVICE_PROJECT_HISTORY_TERMINAL'; END IF;
  IF OLD.status='ENDED' THEN RAISE EXCEPTION 'SERVICE_PROJECT_HISTORY_TERMINAL'; END IF;
  IF NEW.status<>'ENDED' OR NEW.valid_until IS NULL OR NEW.ended_by_principal_id IS NULL THEN
    RAISE EXCEPTION 'SERVICE_PROJECT_TERMINAL_TRANSITION_INVALID';
  END IF;
  RETURN NEW;
END
$fn$;

CREATE FUNCTION service.protect_project_authorization() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $fn$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'SERVICE_PROJECT_AUTHORIZATION_IMMUTABLE'; END IF;
  IF OLD.status='REVOKED' THEN RAISE EXCEPTION 'SERVICE_PROJECT_AUTHORIZATION_TERMINAL'; END IF;
  IF ROW(NEW.project_subject_authorization_id,NEW.service_project_id,NEW.family_id,
      NEW.subject_person_id,NEW.authorization_kind,NEW.data_scope,NEW.authorizer_person_id,
      NEW.evidence_sha256,NEW.valid_from,NEW.valid_until,NEW.created_by_principal_id)
     IS DISTINCT FROM
     ROW(OLD.project_subject_authorization_id,OLD.service_project_id,OLD.family_id,
      OLD.subject_person_id,OLD.authorization_kind,OLD.data_scope,OLD.authorizer_person_id,
      OLD.evidence_sha256,OLD.valid_from,OLD.valid_until,OLD.created_by_principal_id)
     OR NEW.status<>'REVOKED' OR NEW.revoked_by_principal_id IS NULL OR NEW.revoked_at IS NULL THEN
    RAISE EXCEPTION 'SERVICE_PROJECT_AUTHORIZATION_IMMUTABLE';
  END IF;
  RETURN NEW;
END
$fn$;

CREATE TRIGGER project_parties_terminal BEFORE UPDATE OR DELETE ON service.project_parties
  FOR EACH ROW EXECUTE FUNCTION service.protect_m4_terminal_row();
CREATE TRIGGER project_subjects_terminal BEFORE UPDATE OR DELETE ON service.project_subjects
  FOR EACH ROW EXECUTE FUNCTION service.protect_m4_terminal_row();
CREATE TRIGGER project_assignments_terminal BEFORE UPDATE OR DELETE ON service.project_assignments
  FOR EACH ROW EXECUTE FUNCTION service.protect_m4_terminal_row();
CREATE TRIGGER project_subject_authorizations_terminal
  BEFORE UPDATE OR DELETE ON service.project_subject_authorizations
  FOR EACH ROW EXECUTE FUNCTION service.protect_project_authorization();

CREATE OR REPLACE FUNCTION service.record_project_event(
  p_event uuid,p_project uuid,p_kind text,p_from text,p_to text,p_reason text
) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service AS $fn$
BEGIN
  IF (service.is_service_management_service() AND core.is_uuid_v7(p_event)
      AND p_kind IN ('CREATED','STATUS_CHANGED','PARTY_ADDED','PARTY_ENDED','SUBJECT_AUTHORIZED',
        'SUBJECT_AUTHORIZATION_REVOKED','SUBJECT_ADDED','SUBJECT_ENDED','DOMAIN_ADDED','ASSIGNED',
        'ASSIGNMENT_ENDED','TASK_CREATED','MILESTONE_CREATED','MILESTONE_CHANGED','DELIVERABLE_CHANGED')
      AND p_reason ~ '^[A-Z0-9_]{2,80}$') IS NOT TRUE THEN
    RAISE EXCEPTION 'PROJECT_EVENT_DENIED';
  END IF;
  INSERT INTO service.project_events(project_event_id,service_project_id,event_kind,from_status,
    to_status,reason_code,actor_principal_id)
  VALUES(p_event,p_project,p_kind,p_from,p_to,p_reason,auth.current_principal_id());
END
$fn$;

CREATE OR REPLACE FUNCTION service.add_project_party(
  p_id uuid,p_project uuid,p_role text,p_person uuid,p_organization uuid,
  p_valid_until timestamptz,p_event uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service,audit AS $fn$
DECLARE v service.projects%ROWTYPE;
BEGIN
  SELECT * INTO v FROM service.projects WHERE service_project_id=p_project;
  IF (FOUND AND service.is_service_management_service() AND auth.current_family_id()=v.family_id
      AND v.project_status NOT IN ('COMPLETED','CANCELLED')
      AND core.is_uuid_v7(p_id) AND core.is_uuid_v7(p_event)
      AND p_role IN ('PAYER','CONTRACTING_PARTY','FAMILY_ADMIN','AUTHORIZED_VIEWER',
        'CLIENT_REPRESENTATIVE','SERVICE_PROVIDER','REFERRING_PARTNER')
      AND ((p_person IS NOT NULL)<>(p_organization IS NOT NULL))
      AND (p_valid_until IS NULL OR p_valid_until>clock_timestamp())
      AND (p_person IS NULL OR EXISTS(SELECT 1 FROM core.family_memberships
        WHERE family_id=v.family_id AND person_id=p_person AND valid_from<=clock_timestamp()
          AND (valid_until IS NULL OR valid_until>clock_timestamp())))
      AND (p_organization IS NULL OR EXISTS(SELECT 1 FROM core.organizations
        WHERE organization_id=p_organization AND status='ACTIVE'))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADD','SERVICE_PROJECT_PARTY',p_id,false,
      'SERVICE_PROJECT_PARTY_SCOPE_OR_INPUT_DENIED');
  END IF;
  INSERT INTO service.project_parties(
    project_party_id,service_project_id,party_role,person_id,organization_id,
    valid_from,valid_until,created_by_principal_id
  ) VALUES(p_id,p_project,p_role,p_person,p_organization,clock_timestamp(),p_valid_until,
    auth.current_principal_id());
  PERFORM service.record_project_event(p_event,p_project,'PARTY_ADDED',NULL,'ACTIVE',
    'SERVICE_PROJECT_PARTY_ADDED');
  RETURN audit.record_write_decision('ADD','SERVICE_PROJECT_PARTY',p_id,true,
    'SERVICE_PROJECT_PARTY_ADDED');
END
$fn$;

CREATE FUNCTION service.register_project_subject_authorization(
  p_id uuid,p_project uuid,p_subject uuid,p_kind text,p_authorizer uuid,
  p_evidence text,p_valid_until timestamptz,p_event uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,service,audit AS $fn$
DECLARE p service.projects%ROWTYPE;
BEGIN
  SELECT * INTO p FROM service.projects WHERE service_project_id=p_project FOR UPDATE;
  IF (FOUND AND service.is_service_management_service() AND auth.current_family_id()=p.family_id
      AND p.project_status NOT IN ('COMPLETED','CANCELLED')
      AND core.is_uuid_v7(p_id) AND core.is_uuid_v7(p_event)
      AND p_kind IN ('PATIENT_SELF','LEGAL_GUARDIAN') AND p_evidence ~ '^[0-9a-f]{64}$'
      AND p_valid_until>clock_timestamp()
      AND EXISTS(SELECT 1 FROM core.family_memberships WHERE family_id=p.family_id
        AND person_id=p_subject AND valid_from<=clock_timestamp()
        AND (valid_until IS NULL OR valid_until>clock_timestamp()))
      AND ((p_kind='PATIENT_SELF' AND p_authorizer=p_subject)
        OR (p_kind='LEGAL_GUARDIAN' AND EXISTS(SELECT 1 FROM core.guardian_authorities
          WHERE family_id=p.family_id AND guardian_person_id=p_authorizer
            AND subject_person_id=p_subject AND evidence_level='VERIFIED'
            AND scope IN ('GENERAL','HEALTH') AND valid_from<=clock_timestamp()
            AND valid_until>clock_timestamp() AND revoked_at IS NULL)))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('AUTHORIZE','SERVICE_PROJECT_SUBJECT',p_id,false,
      'SERVICE_PROJECT_PATIENT_AUTHORITY_OR_INPUT_DENIED');
  END IF;
  INSERT INTO service.project_subject_authorizations(
    project_subject_authorization_id,service_project_id,family_id,subject_person_id,
    authorization_kind,data_scope,authorizer_person_id,evidence_sha256,status,valid_from,
    valid_until,created_by_principal_id
  ) VALUES(p_id,p_project,p.family_id,p_subject,p_kind,'HEALTH',p_authorizer,p_evidence,
    'ACTIVE',clock_timestamp(),p_valid_until,auth.current_principal_id());
  PERFORM service.record_project_event(p_event,p_project,'SUBJECT_AUTHORIZED',NULL,'ACTIVE',
    'HEALTH_SUBJECT_AUTHORIZED');
  RETURN audit.record_write_decision('AUTHORIZE','SERVICE_PROJECT_SUBJECT',p_id,true,
    'HEALTH_SUBJECT_AUTHORIZED');
EXCEPTION WHEN unique_violation THEN
  RETURN audit.record_write_decision('AUTHORIZE','SERVICE_PROJECT_SUBJECT',p_id,false,
    'AUTHORIZATION_ALREADY_EXISTS');
END
$fn$;

CREATE FUNCTION service.revoke_project_subject_authorization(
  p_id uuid,p_event uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,service,audit AS $fn$
DECLARE a service.project_subject_authorizations%ROWTYPE; p service.projects%ROWTYPE;
BEGIN
  SELECT * INTO a FROM service.project_subject_authorizations
    WHERE project_subject_authorization_id=p_id FOR UPDATE;
  SELECT * INTO p FROM service.projects WHERE service_project_id=a.service_project_id FOR UPDATE;
  IF (a.project_subject_authorization_id IS NOT NULL AND a.status='ACTIVE'
      AND service.is_service_management_service() AND auth.current_family_id()=a.family_id
      AND p.project_status NOT IN ('COMPLETED','CANCELLED') AND core.is_uuid_v7(p_event)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('REVOKE','SERVICE_PROJECT_SUBJECT',p_id,false,
      'SERVICE_PROJECT_AUTHORIZATION_SCOPE_OR_STATE_DENIED');
  END IF;
  UPDATE service.project_subject_authorizations SET status='REVOKED',
    revoked_by_principal_id=auth.current_principal_id(),revoked_at=clock_timestamp()
   WHERE project_subject_authorization_id=p_id;
  UPDATE service.project_subjects SET status='ENDED',valid_until=clock_timestamp(),
    ended_by_principal_id=auth.current_principal_id()
   WHERE authorization_id=p_id AND status='ACTIVE';
  PERFORM service.record_project_event(p_event,a.service_project_id,'SUBJECT_AUTHORIZATION_REVOKED',
    'ACTIVE','REVOKED','HEALTH_SUBJECT_AUTHORIZATION_REVOKED');
  RETURN audit.record_write_decision('REVOKE','SERVICE_PROJECT_SUBJECT',p_id,true,
    'HEALTH_SUBJECT_AUTHORIZATION_REVOKED');
END
$fn$;

CREATE FUNCTION service.add_project_subject_authorized(
  p_id uuid,p_project uuid,p_person uuid,p_scope text,p_authorization uuid,p_event uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,service,audit AS $fn$
DECLARE v service.projects%ROWTYPE;
BEGIN
  SELECT * INTO v FROM service.projects WHERE service_project_id=p_project FOR UPDATE;
  IF (FOUND AND service.is_service_management_service() AND auth.current_family_id()=v.family_id
      AND v.project_status NOT IN ('COMPLETED','CANCELLED')
      AND core.is_uuid_v7(p_id) AND core.is_uuid_v7(p_event)
      AND p_scope IN ('GENERAL','EDUCATION','IDENTITY','WEALTH','HEALTH','GLOBAL_LIVING')
      AND EXISTS(SELECT 1 FROM core.family_memberships WHERE family_id=v.family_id AND person_id=p_person
        AND valid_from<=clock_timestamp() AND (valid_until IS NULL OR valid_until>clock_timestamp()))
      AND ((p_scope<>'HEALTH' AND p_authorization IS NULL)
        OR (p_scope='HEALTH' AND EXISTS(SELECT 1 FROM service.project_subject_authorizations a
          WHERE a.project_subject_authorization_id=p_authorization
            AND a.service_project_id=p_project AND a.subject_person_id=p_person
            AND a.family_id=v.family_id AND a.data_scope='HEALTH' AND a.status='ACTIVE'
            AND a.valid_from<=clock_timestamp() AND a.valid_until>clock_timestamp())))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADD','SERVICE_PROJECT_SUBJECT',p_id,false,
      'SERVICE_PROJECT_FAMILY_SUBJECT_OR_AUTHORIZATION_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM service.project_subjects WHERE service_project_id=p_project
      AND subject_person_id=p_person AND data_scope=p_scope AND status='ACTIVE') THEN
    RETURN audit.record_write_decision('ADD','SERVICE_PROJECT_SUBJECT',p_id,false,
      'PROJECT_SUBJECT_ALREADY_ACTIVE');
  END IF;
  INSERT INTO service.project_subjects(
    project_subject_id,service_project_id,family_id,subject_person_id,subject_role,
    data_scope,created_by_principal_id,authorization_id
  ) VALUES(p_id,p_project,v.family_id,p_person,'SERVICE_RECIPIENT',p_scope,
    auth.current_principal_id(),p_authorization);
  PERFORM service.record_project_event(p_event,p_project,'SUBJECT_ADDED',NULL,'ACTIVE',
    CASE WHEN p_scope='HEALTH' THEN 'AUTHORIZED_HEALTH_SUBJECT_ADDED' ELSE 'PROJECT_SUBJECT_ADDED' END);
  RETURN audit.record_write_decision('ADD','SERVICE_PROJECT_SUBJECT',p_id,true,
    CASE WHEN p_scope='HEALTH' THEN 'AUTHORIZED_HEALTH_SUBJECT_ADDED' ELSE 'PROJECT_SUBJECT_ADDED' END);
END
$fn$;

CREATE FUNCTION service.end_project_party(p_id uuid,p_event uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service,audit AS $fn$
DECLARE v service.project_parties%ROWTYPE; p service.projects%ROWTYPE;
BEGIN
  SELECT * INTO v FROM service.project_parties WHERE project_party_id=p_id FOR UPDATE;
  SELECT * INTO p FROM service.projects WHERE service_project_id=v.service_project_id;
  IF (v.project_party_id IS NOT NULL AND v.status='ACTIVE' AND service.is_service_management_service()
      AND auth.current_family_id()=p.family_id AND p.project_status NOT IN ('COMPLETED','CANCELLED')
      AND core.is_uuid_v7(p_event)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('END','SERVICE_PROJECT_PARTY',p_id,false,'PROJECT_PARTY_SCOPE_OR_STATE_DENIED');
  END IF;
  UPDATE service.project_parties SET status='ENDED',valid_until=clock_timestamp(),
    ended_by_principal_id=auth.current_principal_id() WHERE project_party_id=p_id;
  PERFORM service.record_project_event(p_event,v.service_project_id,'PARTY_ENDED','ACTIVE','ENDED','PROJECT_PARTY_ENDED');
  RETURN audit.record_write_decision('END','SERVICE_PROJECT_PARTY',p_id,true,'PROJECT_PARTY_ENDED');
END
$fn$;

CREATE FUNCTION service.end_project_subject(p_id uuid,p_event uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service,audit AS $fn$
DECLARE v service.project_subjects%ROWTYPE; p service.projects%ROWTYPE;
BEGIN
  SELECT * INTO v FROM service.project_subjects WHERE project_subject_id=p_id FOR UPDATE;
  SELECT * INTO p FROM service.projects WHERE service_project_id=v.service_project_id;
  IF (v.project_subject_id IS NOT NULL AND v.status='ACTIVE' AND service.is_service_management_service()
      AND auth.current_family_id()=p.family_id AND p.project_status NOT IN ('COMPLETED','CANCELLED')
      AND core.is_uuid_v7(p_event)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('END','SERVICE_PROJECT_SUBJECT',p_id,false,'PROJECT_SUBJECT_SCOPE_OR_STATE_DENIED');
  END IF;
  UPDATE service.project_subjects SET status='ENDED',valid_until=clock_timestamp(),
    ended_by_principal_id=auth.current_principal_id() WHERE project_subject_id=p_id;
  PERFORM service.record_project_event(p_event,v.service_project_id,'SUBJECT_ENDED','ACTIVE','ENDED','PROJECT_SUBJECT_ENDED');
  RETURN audit.record_write_decision('END','SERVICE_PROJECT_SUBJECT',p_id,true,'PROJECT_SUBJECT_ENDED');
END
$fn$;

CREATE FUNCTION service.end_project_assignment(p_id uuid,p_event uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service,audit AS $fn$
DECLARE v service.project_assignments%ROWTYPE; p service.projects%ROWTYPE;
BEGIN
  SELECT * INTO v FROM service.project_assignments WHERE project_assignment_id=p_id FOR UPDATE;
  SELECT * INTO p FROM service.projects WHERE service_project_id=v.service_project_id;
  IF (v.project_assignment_id IS NOT NULL AND v.status='ACTIVE' AND service.is_service_management_service()
      AND auth.current_family_id()=p.family_id AND p.project_status NOT IN ('COMPLETED','CANCELLED')
      AND core.is_uuid_v7(p_event)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('END','SERVICE_PROJECT_ASSIGNMENT',p_id,false,
      'PROJECT_ASSIGNMENT_SCOPE_OR_STATE_DENIED');
  END IF;
  UPDATE service.project_assignments SET status='ENDED',valid_until=clock_timestamp(),
    ended_by_principal_id=auth.current_principal_id() WHERE project_assignment_id=p_id;
  PERFORM service.record_project_event(p_event,v.service_project_id,'ASSIGNMENT_ENDED','ACTIVE','ENDED',
    'PROJECT_ASSIGNMENT_ENDED');
  RETURN audit.record_write_decision('END','SERVICE_PROJECT_ASSIGNMENT',p_id,true,
    'PROJECT_ASSIGNMENT_ENDED');
END
$fn$;

CREATE OR REPLACE FUNCTION service.transition_project(p_id uuid,p_next text,p_event uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service,audit AS $fn$
DECLARE v service.projects%ROWTYPE; allowed boolean; t timestamptz;
BEGIN
  SELECT * INTO v FROM service.projects WHERE service_project_id=p_id FOR UPDATE;
  allowed:=FOUND AND service.is_service_management_service() AND auth.current_family_id()=v.family_id
    AND core.is_uuid_v7(p_event) AND (
      (v.project_status='DRAFT' AND p_next IN ('PLANNED','CANCELLED'))
      OR (v.project_status='PLANNED' AND p_next IN ('ACTIVE','CANCELLED'))
      OR (v.project_status='ACTIVE' AND p_next IN ('ON_HOLD','COMPLETED','CANCELLED'))
      OR (v.project_status='ON_HOLD' AND p_next IN ('ACTIVE','CANCELLED')));
  IF allowed IS NOT TRUE THEN
    RETURN audit.record_write_decision('TRANSITION','SERVICE_PROJECT',p_id,false,'SERVICE_SCOPE_OR_STATE_DENIED');
  END IF;
  t:=clock_timestamp();
  IF p_next IN ('COMPLETED','CANCELLED') THEN
    UPDATE service.project_subject_authorizations SET status='REVOKED',
      revoked_by_principal_id=auth.current_principal_id(),revoked_at=t
     WHERE service_project_id=p_id AND status='ACTIVE';
    UPDATE service.project_parties SET status='ENDED',valid_until=t,
      ended_by_principal_id=auth.current_principal_id()
     WHERE service_project_id=p_id AND status='ACTIVE';
    UPDATE service.project_subjects SET status='ENDED',valid_until=coalesce(valid_until,t),
      ended_by_principal_id=auth.current_principal_id()
     WHERE service_project_id=p_id AND status='ACTIVE';
    UPDATE service.project_assignments SET status='ENDED',valid_until=t,
      ended_by_principal_id=auth.current_principal_id()
     WHERE service_project_id=p_id AND status='ACTIVE';
  END IF;
  UPDATE service.projects SET project_status=p_next,
    completed_at=CASE WHEN p_next IN ('COMPLETED','CANCELLED') THEN t END,
    updated_by_principal_id=auth.current_principal_id(),updated_at=t WHERE service_project_id=p_id;
  PERFORM service.record_project_event(p_event,p_id,'STATUS_CHANGED',v.project_status,p_next,'PROJECT_STATUS_CHANGED');
  RETURN audit.record_write_decision('TRANSITION','SERVICE_PROJECT',p_id,true,'PROJECT_STATUS_CHANGED');
END
$fn$;

ALTER TABLE service.project_subject_authorizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE service.project_subject_authorizations FORCE ROW LEVEL SECURITY;
CREATE POLICY project_subject_authorizations_service ON service.project_subject_authorizations
  FOR ALL TO phoenix_canonical_app
  USING (service.is_service_management_service() AND family_id=auth.current_family_id()
    AND EXISTS(SELECT 1 FROM service.projects p WHERE p.service_project_id=project_subject_authorizations.service_project_id
      AND p.project_status NOT IN ('COMPLETED','CANCELLED')))
  WITH CHECK (service.is_service_management_service() AND family_id=auth.current_family_id()
    AND EXISTS(SELECT 1 FROM service.projects p WHERE p.service_project_id=project_subject_authorizations.service_project_id
      AND p.project_status NOT IN ('COMPLETED','CANCELLED')));

REVOKE ALL ON service.project_subject_authorizations FROM PUBLIC,phoenix_canonical_app,
  phoenix_canonical_reader,phoenix_canonical_context_binder;
REVOKE EXECUTE ON FUNCTION service.add_project_subject(uuid,uuid,uuid,text,uuid)
  FROM phoenix_canonical_app;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA service FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
  service.register_project_subject_authorization(uuid,uuid,uuid,text,uuid,text,timestamptz,uuid),
  service.revoke_project_subject_authorization(uuid,uuid),
  service.add_project_subject_authorized(uuid,uuid,uuid,text,uuid,uuid),
  service.end_project_party(uuid,uuid),
  service.end_project_subject(uuid,uuid),
  service.end_project_assignment(uuid,uuid)
TO phoenix_canonical_app;

COMMIT;
