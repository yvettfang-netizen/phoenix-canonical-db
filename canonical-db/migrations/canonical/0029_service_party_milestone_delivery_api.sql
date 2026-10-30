BEGIN;

ALTER TABLE service.project_events
  DROP CONSTRAINT project_events_event_kind_check;
ALTER TABLE service.project_events
  ADD CONSTRAINT project_events_event_kind_check CHECK (event_kind IN (
    'CREATED','STATUS_CHANGED','PARTY_ADDED','SUBJECT_ADDED','DOMAIN_ADDED','ASSIGNED',
    'TASK_CREATED','MILESTONE_CREATED','MILESTONE_CHANGED','DELIVERABLE_CHANGED'
  ));

ALTER TABLE service.deliverables DROP CONSTRAINT deliverables_check;
ALTER TABLE service.deliverables ADD CONSTRAINT deliverables_delivery_time_check CHECK (
  (status IN ('DELIVERED','ACCEPTED') AND delivered_at IS NOT NULL)
  OR (status IN ('DRAFT','READY') AND delivered_at IS NULL)
  OR status='WITHDRAWN'
);

CREATE OR REPLACE FUNCTION service.record_project_event(
  p_event uuid,p_project uuid,p_kind text,p_from text,p_to text,p_reason text
) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service AS $fn$
BEGIN
  IF (service.is_service_management_service() AND core.is_uuid_v7(p_event)
      AND p_kind IN ('CREATED','STATUS_CHANGED','PARTY_ADDED','SUBJECT_ADDED','DOMAIN_ADDED','ASSIGNED',
        'TASK_CREATED','MILESTONE_CREATED','MILESTONE_CHANGED','DELIVERABLE_CHANGED')
      AND p_reason ~ '^[A-Z0-9_]{2,80}$') IS NOT TRUE THEN
    RAISE EXCEPTION 'PROJECT_EVENT_DENIED';
  END IF;
  INSERT INTO service.project_events(project_event_id,service_project_id,event_kind,from_status,
    to_status,reason_code,actor_principal_id)
  VALUES(p_event,p_project,p_kind,p_from,p_to,p_reason,auth.current_principal_id());
END
$fn$;

CREATE FUNCTION service.add_project_party(
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
      AND p_role IN ('PAYER','CONTRACTING_PARTY','FAMILY_ADMIN','AUTHORIZED_VIEWER')
      AND ((p_person IS NOT NULL)<>(p_organization IS NOT NULL))
      AND (p_valid_until IS NULL OR p_valid_until>clock_timestamp())
      AND (p_person IS NULL OR EXISTS(SELECT 1 FROM core.family_memberships
        WHERE family_id=v.family_id AND person_id=p_person AND valid_from<=clock_timestamp()
          AND (valid_until IS NULL OR valid_until>clock_timestamp())))
      AND (p_organization IS NULL OR EXISTS(SELECT 1 FROM core.organizations
        WHERE organization_id=p_organization AND status='ACTIVE'))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADD','SERVICE_PROJECT_PARTY',p_id,false,'SERVICE_PROJECT_PARTY_SCOPE_OR_INPUT_DENIED');
  END IF;
  INSERT INTO service.project_parties(project_party_id,service_project_id,party_role,person_id,
    organization_id,valid_from,valid_until,created_by_principal_id)
  VALUES(p_id,p_project,p_role,p_person,p_organization,clock_timestamp(),p_valid_until,
    auth.current_principal_id());
  PERFORM service.record_project_event(p_event,p_project,'PARTY_ADDED',NULL,NULL,'SERVICE_PROJECT_PARTY_ADDED');
  RETURN audit.record_write_decision('ADD','SERVICE_PROJECT_PARTY',p_id,true,'SERVICE_PROJECT_PARTY_ADDED');
END
$fn$;

CREATE FUNCTION service.create_milestone(
  p_id uuid,p_project uuid,p_code text,p_title text,p_target timestamptz,p_event uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service,audit AS $fn$
DECLARE v service.projects%ROWTYPE;
BEGIN
  SELECT * INTO v FROM service.projects WHERE service_project_id=p_project;
  IF (FOUND AND service.is_service_management_service() AND auth.current_family_id()=v.family_id
      AND v.project_status NOT IN ('COMPLETED','CANCELLED')
      AND core.is_uuid_v7(p_id) AND core.is_uuid_v7(p_event)
      AND p_code ~ '^[A-Z0-9][A-Z0-9_-]{2,39}$'
      AND length(btrim(p_title)) BETWEEN 1 AND 300) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','SERVICE_MILESTONE',p_id,false,'SERVICE_MILESTONE_SCOPE_OR_INPUT_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM service.project_milestones
      WHERE service_project_id=p_project AND milestone_code=p_code) THEN
    RETURN audit.record_write_decision('CREATE','SERVICE_MILESTONE',p_id,false,'SERVICE_MILESTONE_ALREADY_EXISTS');
  END IF;
  INSERT INTO service.project_milestones(project_milestone_id,service_project_id,milestone_code,
    milestone_title,status,target_at,created_by_principal_id)
  VALUES(p_id,p_project,p_code,btrim(p_title),'PENDING',p_target,auth.current_principal_id());
  PERFORM service.record_project_event(p_event,p_project,'MILESTONE_CREATED',NULL,'PENDING','SERVICE_MILESTONE_CREATED');
  RETURN audit.record_write_decision('CREATE','SERVICE_MILESTONE',p_id,true,'SERVICE_MILESTONE_CREATED');
END
$fn$;

CREATE FUNCTION service.transition_milestone(p_id uuid,p_next text,p_event uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service,audit AS $fn$
DECLARE v service.project_milestones%ROWTYPE; p service.projects%ROWTYPE;
BEGIN
  SELECT * INTO v FROM service.project_milestones WHERE project_milestone_id=p_id FOR UPDATE;
  SELECT * INTO p FROM service.projects WHERE service_project_id=v.service_project_id;
  IF (v.project_milestone_id IS NOT NULL AND p.service_project_id IS NOT NULL
      AND service.is_service_management_service() AND auth.current_family_id()=p.family_id
      AND p.project_status NOT IN ('COMPLETED','CANCELLED') AND v.status='PENDING'
      AND p_next IN ('ACHIEVED','CANCELLED') AND core.is_uuid_v7(p_event)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('TRANSITION','SERVICE_MILESTONE',p_id,false,'SERVICE_MILESTONE_SCOPE_OR_STATE_DENIED');
  END IF;
  UPDATE service.project_milestones SET status=p_next,
    achieved_at=CASE WHEN p_next='ACHIEVED' THEN clock_timestamp() END,
    updated_at=clock_timestamp() WHERE project_milestone_id=p_id;
  PERFORM service.record_project_event(p_event,v.service_project_id,'MILESTONE_CHANGED',v.status,p_next,'SERVICE_MILESTONE_STATUS_CHANGED');
  RETURN audit.record_write_decision('TRANSITION','SERVICE_MILESTONE',p_id,true,'SERVICE_MILESTONE_STATUS_CHANGED');
END
$fn$;

CREATE FUNCTION service.create_deliverable(
  p_id uuid,p_project uuid,p_subject uuid,p_document uuid,p_kind text,
  p_due timestamptz,p_event uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,docs,service,audit AS $fn$
DECLARE v service.projects%ROWTYPE;
BEGIN
  SELECT * INTO v FROM service.projects WHERE service_project_id=p_project;
  IF (FOUND AND service.is_service_management_service() AND auth.current_family_id()=v.family_id
      AND v.project_status IN ('PLANNED','ACTIVE','ON_HOLD')
      AND core.is_uuid_v7(p_id) AND core.is_uuid_v7(p_event)
      AND p_kind ~ '^[A-Z][A-Z0-9_]{2,79}$'
      AND (p_subject IS NULL OR EXISTS(SELECT 1 FROM service.project_subjects
        WHERE project_subject_id=p_subject AND service_project_id=p_project))
      AND (p_document IS NULL OR EXISTS(SELECT 1 FROM docs.documents d
        WHERE d.document_id=p_document AND d.family_id=v.family_id AND d.withdrawn_at IS NULL
          AND (p_subject IS NULL OR EXISTS(SELECT 1 FROM service.project_subjects ps
            WHERE ps.project_subject_id=p_subject AND ps.service_project_id=p_project
              AND ps.subject_person_id=d.subject_person_id))))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','SERVICE_DELIVERABLE',p_id,false,'SERVICE_DELIVERABLE_SCOPE_OR_INPUT_DENIED');
  END IF;
  INSERT INTO service.deliverables(deliverable_id,service_project_id,project_subject_id,document_id,
    deliverable_kind,status,due_at,created_by_principal_id,updated_by_principal_id)
  VALUES(p_id,p_project,p_subject,p_document,p_kind,'DRAFT',p_due,
    auth.current_principal_id(),auth.current_principal_id());
  PERFORM service.record_project_event(p_event,p_project,'DELIVERABLE_CHANGED',NULL,'DRAFT','SERVICE_DELIVERABLE_CREATED');
  RETURN audit.record_write_decision('CREATE','SERVICE_DELIVERABLE',p_id,true,'SERVICE_DELIVERABLE_CREATED');
END
$fn$;

CREATE FUNCTION service.transition_deliverable(p_id uuid,p_next text,p_event uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service,audit AS $fn$
DECLARE v service.deliverables%ROWTYPE; p service.projects%ROWTYPE; allowed boolean;
BEGIN
  SELECT * INTO v FROM service.deliverables WHERE deliverable_id=p_id FOR UPDATE;
  SELECT * INTO p FROM service.projects WHERE service_project_id=v.service_project_id;
  allowed:=v.deliverable_id IS NOT NULL AND p.service_project_id IS NOT NULL
    AND service.is_service_management_service() AND auth.current_family_id()=p.family_id
    AND p.project_status NOT IN ('COMPLETED','CANCELLED') AND core.is_uuid_v7(p_event) AND (
      (v.status='DRAFT' AND p_next IN ('READY','WITHDRAWN'))
      OR (v.status='READY' AND p_next IN ('DRAFT','DELIVERED','WITHDRAWN'))
      OR (v.status='DELIVERED' AND p_next IN ('ACCEPTED','WITHDRAWN')));
  IF allowed IS NOT TRUE THEN
    RETURN audit.record_write_decision('TRANSITION','SERVICE_DELIVERABLE',p_id,false,'SERVICE_DELIVERABLE_SCOPE_OR_STATE_DENIED');
  END IF;
  UPDATE service.deliverables SET status=p_next,
    delivered_at=CASE WHEN p_next='DELIVERED' THEN clock_timestamp() ELSE delivered_at END,
    updated_by_principal_id=auth.current_principal_id(),updated_at=clock_timestamp()
   WHERE deliverable_id=p_id;
  PERFORM service.record_project_event(p_event,v.service_project_id,'DELIVERABLE_CHANGED',v.status,p_next,'SERVICE_DELIVERABLE_STATUS_CHANGED');
  RETURN audit.record_write_decision('TRANSITION','SERVICE_DELIVERABLE',p_id,true,'SERVICE_DELIVERABLE_STATUS_CHANGED');
END
$fn$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA service FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
  service.add_project_party(uuid,uuid,text,uuid,uuid,timestamptz,uuid),
  service.create_milestone(uuid,uuid,text,text,timestamptz,uuid),
  service.transition_milestone(uuid,text,uuid),
  service.create_deliverable(uuid,uuid,uuid,uuid,text,timestamptz,uuid),
  service.transition_deliverable(uuid,text,uuid)
TO phoenix_canonical_app;

COMMIT;
