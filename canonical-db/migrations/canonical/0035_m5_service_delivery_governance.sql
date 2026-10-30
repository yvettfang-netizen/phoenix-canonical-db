BEGIN;

-- V2.0 M5 governs Service delivery metadata and review history. Document
-- content remains in docs/object storage; this schema stores references only.

CREATE TABLE service.milestone_templates (
  milestone_template_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(milestone_template_id)),
  template_code text NOT NULL CHECK (template_code ~ '^[A-Z0-9][A-Z0-9_-]{2,39}$'),
  version_no integer NOT NULL CHECK (version_no>0),
  business_domain text NOT NULL CHECK (business_domain IN (
    'EDUCATION','IDENTITY','WEALTH','HEALTH','GLOBAL_LIVING','HERITAGE','MULTI_DOMAIN'
  )),
  template_title text NOT NULL CHECK (length(btrim(template_title)) BETWEEN 1 AND 300),
  status text NOT NULL CHECK (status IN ('ACTIVE','RETIRED')),
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  retired_by_principal_id uuid REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  retired_at timestamptz,
  UNIQUE(template_code,version_no),
  CHECK ((status='ACTIVE' AND retired_by_principal_id IS NULL AND retired_at IS NULL)
    OR (status='RETIRED' AND retired_by_principal_id IS NOT NULL AND retired_at IS NOT NULL))
);

ALTER TABLE service.task_events
  DROP CONSTRAINT task_events_event_kind_check,
  ADD CONSTRAINT task_events_event_kind_check CHECK (event_kind IN (
    'CREATED','STATUS_CHANGED','ASSIGNED','DUE_CHANGED','TRANSFERRED'
  )),
  ADD COLUMN from_assignee_principal_id uuid REFERENCES auth.principals,
  ADD COLUMN to_assignee_principal_id uuid REFERENCES auth.principals,
  ADD CONSTRAINT task_events_transfer_shape_check CHECK (
    (event_kind='TRANSFERRED' AND from_assignee_principal_id IS DISTINCT FROM to_assignee_principal_id
      AND to_assignee_principal_id IS NOT NULL)
    OR (event_kind<>'TRANSFERRED' AND from_assignee_principal_id IS NULL
      AND to_assignee_principal_id IS NULL)
  );

ALTER TABLE service.project_milestones
  ADD COLUMN milestone_template_id uuid REFERENCES service.milestone_templates;

ALTER TABLE docs.document_versions
  ADD CONSTRAINT document_versions_version_document_uq UNIQUE(version_id,document_id);

ALTER TABLE service.deliverables
  DROP CONSTRAINT deliverables_status_check,
  DROP CONSTRAINT deliverables_delivery_time_check,
  ADD COLUMN document_version_id uuid,
  ADD COLUMN submission_round integer NOT NULL DEFAULT 0 CHECK (submission_round>=0),
  ADD COLUMN reviewed_by_principal_id uuid REFERENCES auth.principals,
  ADD COLUMN reviewed_at timestamptz,
  ADD COLUMN accepted_by_principal_id uuid REFERENCES auth.principals,
  ADD COLUMN accepted_at timestamptz,
  ADD COLUMN delivery_governance_version integer NOT NULL DEFAULT 1,
  ADD CONSTRAINT deliverables_status_check CHECK (status IN (
    'DRAFT','READY','DELIVERED','UNDER_REVIEW','CHANGES_REQUESTED',
    'REVIEW_APPROVED','ACCEPTED','WITHDRAWN'
  )),
  ADD CONSTRAINT deliverables_document_version_fk FOREIGN KEY(document_version_id,document_id)
    REFERENCES docs.document_versions(version_id,document_id),
  ADD CONSTRAINT deliverables_delivery_time_check CHECK (
    (status IN ('DELIVERED','ACCEPTED') AND delivered_at IS NOT NULL)
    OR (status IN ('DRAFT','READY','UNDER_REVIEW','CHANGES_REQUESTED','REVIEW_APPROVED')
      AND delivered_at IS NULL)
    OR status='WITHDRAWN'
  ),
  ADD CONSTRAINT deliverables_review_shape_check CHECK (
    (reviewed_by_principal_id IS NULL)=(reviewed_at IS NULL)
  ),
  ADD CONSTRAINT deliverables_acceptance_shape_check CHECK (
    (status='ACCEPTED' AND accepted_by_principal_id IS NOT NULL AND accepted_at IS NOT NULL)
    OR (status<>'ACCEPTED' AND accepted_by_principal_id IS NULL AND accepted_at IS NULL)
  ),
  ADD CONSTRAINT deliverables_governance_check CHECK (
    (delivery_governance_version=1)
    OR (delivery_governance_version=2 AND document_id IS NOT NULL AND document_version_id IS NOT NULL)
  );
ALTER TABLE service.deliverables ALTER COLUMN delivery_governance_version SET DEFAULT 2;

CREATE TABLE service.delivery_events (
  delivery_event_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(delivery_event_id)),
  deliverable_id uuid NOT NULL REFERENCES service.deliverables,
  event_kind text NOT NULL CHECK (event_kind IN (
    'CREATED','SUBMITTED','REVIEW_APPROVED','CHANGES_REQUESTED',
    'ACCEPTED','WITHDRAWN','RESUBMITTED'
  )),
  from_status text,
  to_status text NOT NULL,
  submission_round integer NOT NULL CHECK (submission_round>=0),
  reason_code text NOT NULL CHECK (reason_code ~ '^[A-Z0-9_]{2,80}$'),
  document_version_id uuid NOT NULL REFERENCES docs.document_versions,
  actor_principal_id uuid NOT NULL REFERENCES auth.principals,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX delivery_events_deliverable_time_idx
  ON service.delivery_events(deliverable_id,occurred_at,delivery_event_id);

CREATE FUNCTION service.protect_milestone_template() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $fn$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'SERVICE_MILESTONE_TEMPLATE_IMMUTABLE'; END IF;
  IF OLD.status='RETIRED' THEN RAISE EXCEPTION 'SERVICE_MILESTONE_TEMPLATE_TERMINAL'; END IF;
  IF ROW(NEW.milestone_template_id,NEW.template_code,NEW.version_no,NEW.business_domain,
      NEW.template_title,NEW.created_by_principal_id,NEW.created_at)
     IS DISTINCT FROM
     ROW(OLD.milestone_template_id,OLD.template_code,OLD.version_no,OLD.business_domain,
      OLD.template_title,OLD.created_by_principal_id,OLD.created_at)
     OR NEW.status<>'RETIRED' OR NEW.retired_by_principal_id IS NULL OR NEW.retired_at IS NULL THEN
    RAISE EXCEPTION 'SERVICE_MILESTONE_TEMPLATE_IMMUTABLE';
  END IF;
  RETURN NEW;
END
$fn$;
CREATE TRIGGER milestone_templates_terminal BEFORE UPDATE OR DELETE ON service.milestone_templates
  FOR EACH ROW EXECUTE FUNCTION service.protect_milestone_template();
CREATE TRIGGER reject_delivery_event_change BEFORE UPDATE OR DELETE ON service.delivery_events
  FOR EACH ROW EXECUTE FUNCTION service.reject_event_change();

CREATE FUNCTION service.protect_deliverable_governance() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $fn$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'SERVICE_DELIVERABLE_HISTORY_IMMUTABLE'; END IF;
  IF OLD.status IN ('ACCEPTED','WITHDRAWN') THEN RAISE EXCEPTION 'SERVICE_DELIVERABLE_TERMINAL'; END IF;
  IF ROW(NEW.deliverable_id,NEW.service_project_id,NEW.project_subject_id,NEW.document_id,
      NEW.document_version_id,NEW.deliverable_kind,NEW.due_at,NEW.created_by_principal_id,
      NEW.created_at,NEW.delivery_governance_version)
     IS DISTINCT FROM
     ROW(OLD.deliverable_id,OLD.service_project_id,OLD.project_subject_id,OLD.document_id,
      OLD.document_version_id,OLD.deliverable_kind,OLD.due_at,OLD.created_by_principal_id,
      OLD.created_at,OLD.delivery_governance_version)
     OR NEW.submission_round<OLD.submission_round THEN
    RAISE EXCEPTION 'SERVICE_DELIVERABLE_HISTORY_IMMUTABLE';
  END IF;
  RETURN NEW;
END
$fn$;
CREATE TRIGGER deliverables_governance BEFORE UPDATE OR DELETE ON service.deliverables
  FOR EACH ROW EXECUTE FUNCTION service.protect_deliverable_governance();

CREATE OR REPLACE FUNCTION service.record_task_event(
  p_event uuid,p_task uuid,p_kind text,p_from text,p_to text,p_reason text
) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service AS $fn$
BEGIN
  IF (service.is_service_management_service() AND core.is_uuid_v7(p_event)
      AND p_kind IN ('CREATED','STATUS_CHANGED','ASSIGNED','DUE_CHANGED')
      AND p_reason ~ '^[A-Z0-9_]{2,80}$') IS NOT TRUE THEN RAISE EXCEPTION 'TASK_EVENT_DENIED'; END IF;
  INSERT INTO service.task_events(task_event_id,task_id,event_kind,from_status,to_status,
    reason_code,actor_principal_id)
  VALUES(p_event,p_task,p_kind,p_from,p_to,p_reason,auth.current_principal_id());
END
$fn$;

CREATE FUNCTION service.record_task_transfer_event(
  p_event uuid,p_task uuid,p_from_assignee uuid,p_to_assignee uuid,p_reason text
) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service AS $fn$
BEGIN
  IF (service.is_service_management_service() AND core.is_uuid_v7(p_event)
      AND p_from_assignee IS DISTINCT FROM p_to_assignee AND p_to_assignee IS NOT NULL
      AND p_reason ~ '^[A-Z0-9_]{2,80}$') IS NOT TRUE THEN RAISE EXCEPTION 'TASK_TRANSFER_EVENT_DENIED'; END IF;
  INSERT INTO service.task_events(task_event_id,task_id,event_kind,from_assignee_principal_id,
    to_assignee_principal_id,reason_code,actor_principal_id)
  VALUES(p_event,p_task,'TRANSFERRED',p_from_assignee,p_to_assignee,p_reason,
    auth.current_principal_id());
END
$fn$;

CREATE FUNCTION service.record_delivery_event(
  p_event uuid,p_deliverable uuid,p_kind text,p_from text,p_to text,p_round integer,
  p_reason text,p_version uuid
) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service AS $fn$
BEGIN
  IF (service.is_service_management_service() AND core.is_uuid_v7(p_event)
      AND p_kind IN ('CREATED','SUBMITTED','REVIEW_APPROVED','CHANGES_REQUESTED',
        'ACCEPTED','WITHDRAWN','RESUBMITTED')
      AND p_round>=0 AND p_reason ~ '^[A-Z0-9_]{2,80}$') IS NOT TRUE THEN
    RAISE EXCEPTION 'DELIVERY_EVENT_DENIED';
  END IF;
  INSERT INTO service.delivery_events(delivery_event_id,deliverable_id,event_kind,from_status,
    to_status,submission_round,reason_code,document_version_id,actor_principal_id)
  VALUES(p_event,p_deliverable,p_kind,p_from,p_to,p_round,p_reason,p_version,
    auth.current_principal_id());
END
$fn$;

CREATE FUNCTION service.register_milestone_template(
  p_id uuid,p_code text,p_version integer,p_domain text,p_title text
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service,audit AS $fn$
BEGIN
  IF (service.is_service_management_service() AND core.is_uuid_v7(p_id)
      AND p_code ~ '^[A-Z0-9][A-Z0-9_-]{2,39}$' AND p_version>0
      AND p_domain IN ('EDUCATION','IDENTITY','WEALTH','HEALTH','GLOBAL_LIVING','HERITAGE','MULTI_DOMAIN')
      AND length(btrim(p_title)) BETWEEN 1 AND 300) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','SERVICE_MILESTONE_TEMPLATE',p_id,false,
      'MILESTONE_TEMPLATE_INPUT_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM service.milestone_templates
      WHERE milestone_template_id=p_id OR (template_code=p_code AND version_no=p_version)) THEN
    RETURN audit.record_write_decision('CREATE','SERVICE_MILESTONE_TEMPLATE',p_id,false,
      'MILESTONE_TEMPLATE_ALREADY_EXISTS');
  END IF;
  INSERT INTO service.milestone_templates(milestone_template_id,template_code,version_no,
    business_domain,template_title,status,created_by_principal_id)
  VALUES(p_id,p_code,p_version,p_domain,btrim(p_title),'ACTIVE',auth.current_principal_id());
  RETURN audit.record_write_decision('CREATE','SERVICE_MILESTONE_TEMPLATE',p_id,true,
    'MILESTONE_TEMPLATE_CREATED');
END
$fn$;

CREATE FUNCTION service.retire_milestone_template(p_id uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,service,audit AS $fn$
DECLARE v service.milestone_templates%ROWTYPE;
BEGIN
  SELECT * INTO v FROM service.milestone_templates WHERE milestone_template_id=p_id FOR UPDATE;
  IF (FOUND AND service.is_service_management_service() AND v.status='ACTIVE') IS NOT TRUE THEN
    RETURN audit.record_write_decision('RETIRE','SERVICE_MILESTONE_TEMPLATE',p_id,false,
      'MILESTONE_TEMPLATE_STATE_DENIED');
  END IF;
  UPDATE service.milestone_templates SET status='RETIRED',
    retired_by_principal_id=auth.current_principal_id(),retired_at=clock_timestamp()
   WHERE milestone_template_id=p_id;
  RETURN audit.record_write_decision('RETIRE','SERVICE_MILESTONE_TEMPLATE',p_id,true,
    'MILESTONE_TEMPLATE_RETIRED');
END
$fn$;

CREATE FUNCTION service.create_milestone_from_template(
  p_id uuid,p_project uuid,p_template uuid,p_code text,p_target timestamptz,p_event uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service,audit AS $fn$
DECLARE p service.projects%ROWTYPE; t service.milestone_templates%ROWTYPE;
BEGIN
  SELECT * INTO p FROM service.projects WHERE service_project_id=p_project;
  SELECT * INTO t FROM service.milestone_templates WHERE milestone_template_id=p_template;
  IF (p.service_project_id IS NOT NULL AND t.milestone_template_id IS NOT NULL
      AND service.is_service_management_service() AND auth.current_family_id()=p.family_id
      AND p.project_status NOT IN ('COMPLETED','CANCELLED') AND t.status='ACTIVE'
      AND (p.primary_domain=t.business_domain OR p.primary_domain='MULTI_DOMAIN'
        OR t.business_domain='MULTI_DOMAIN')
      AND core.is_uuid_v7(p_id) AND core.is_uuid_v7(p_event)
      AND p_code ~ '^[A-Z0-9][A-Z0-9_-]{2,39}$') IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','SERVICE_MILESTONE',p_id,false,
      'SERVICE_MILESTONE_TEMPLATE_OR_SCOPE_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM service.project_milestones
      WHERE service_project_id=p_project AND milestone_code=p_code) THEN
    RETURN audit.record_write_decision('CREATE','SERVICE_MILESTONE',p_id,false,
      'SERVICE_MILESTONE_ALREADY_EXISTS');
  END IF;
  INSERT INTO service.project_milestones(project_milestone_id,service_project_id,
    milestone_template_id,milestone_code,milestone_title,status,target_at,created_by_principal_id)
  VALUES(p_id,p_project,p_template,p_code,t.template_title,'PENDING',p_target,
    auth.current_principal_id());
  PERFORM service.record_project_event(p_event,p_project,'MILESTONE_CREATED',NULL,'PENDING',
    'SERVICE_TEMPLATE_MILESTONE_CREATED');
  RETURN audit.record_write_decision('CREATE','SERVICE_MILESTONE',p_id,true,
    'SERVICE_TEMPLATE_MILESTONE_CREATED');
END
$fn$;

CREATE OR REPLACE FUNCTION service.create_task(
  p_id uuid,p_project uuid,p_type text,p_title text,p_priority text,p_assignee uuid,p_due timestamptz,p_event uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service,audit AS $fn$
DECLARE v service.projects%ROWTYPE;
BEGIN
  SELECT * INTO v FROM service.projects WHERE service_project_id=p_project;
  IF (FOUND AND service.is_service_management_service() AND auth.current_family_id()=v.family_id
      AND v.project_status IN ('PLANNED','ACTIVE','ON_HOLD') AND core.is_uuid_v7(p_id) AND core.is_uuid_v7(p_event)
      AND p_type ~ '^[A-Z][A-Z0-9_]{2,79}$' AND length(btrim(p_title)) BETWEEN 1 AND 300
      AND p_priority IN ('LOW','MEDIUM','HIGH','URGENT')
      AND (p_assignee IS NULL OR EXISTS(SELECT 1 FROM service.project_assignments
        WHERE service_project_id=p_project AND principal_id=p_assignee AND status='ACTIVE'
          AND (valid_until IS NULL OR valid_until>clock_timestamp())))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','SERVICE_TASK',p_id,false,
      'SERVICE_PROJECT_STATE_SCOPE_ASSIGNEE_OR_INPUT_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM service.tasks WHERE task_id=p_id) THEN
    RETURN audit.record_write_decision('CREATE','SERVICE_TASK',p_id,false,'SERVICE_TASK_ALREADY_EXISTS');
  END IF;
  INSERT INTO service.tasks(task_id,service_project_id,task_type,task_title,task_status,priority,
    assigned_principal_id,created_by_principal_id,updated_by_principal_id,due_at)
  VALUES(p_id,p_project,p_type,btrim(p_title),'PENDING',p_priority,p_assignee,
    auth.current_principal_id(),auth.current_principal_id(),p_due);
  PERFORM service.record_task_event(p_event,p_id,'CREATED',NULL,'PENDING','SERVICE_TASK_CREATED');
  PERFORM service.record_project_event(p_event,p_project,'TASK_CREATED',NULL,NULL,'SERVICE_TASK_CREATED');
  RETURN audit.record_write_decision('CREATE','SERVICE_TASK',p_id,true,'SERVICE_TASK_CREATED');
END
$fn$;

CREATE FUNCTION service.transfer_task(
  p_id uuid,p_new_assignee uuid,p_reason text,p_event uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service,audit AS $fn$
DECLARE v service.tasks%ROWTYPE; p service.projects%ROWTYPE;
BEGIN
  SELECT * INTO v FROM service.tasks WHERE task_id=p_id FOR UPDATE;
  SELECT * INTO p FROM service.projects WHERE service_project_id=v.service_project_id;
  IF (v.task_id IS NOT NULL AND p.service_project_id IS NOT NULL
      AND service.is_service_management_service() AND auth.current_family_id()=p.family_id
      AND p.project_status NOT IN ('COMPLETED','CANCELLED')
      AND v.task_status NOT IN ('COMPLETED','CANCELLED')
      AND core.is_uuid_v7(p_event) AND p_reason ~ '^[A-Z0-9_]{2,80}$'
      AND v.assigned_principal_id IS DISTINCT FROM p_new_assignee
      AND EXISTS(SELECT 1 FROM service.project_assignments
        WHERE service_project_id=v.service_project_id AND principal_id=p_new_assignee
          AND status='ACTIVE' AND (valid_until IS NULL OR valid_until>clock_timestamp()))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('TRANSFER','SERVICE_TASK',p_id,false,
      'SERVICE_TASK_TRANSFER_SCOPE_OR_ASSIGNEE_DENIED');
  END IF;
  UPDATE service.tasks SET assigned_principal_id=p_new_assignee,
    updated_by_principal_id=auth.current_principal_id(),updated_at=clock_timestamp()
   WHERE task_id=p_id;
  PERFORM service.record_task_transfer_event(p_event,p_id,v.assigned_principal_id,p_new_assignee,p_reason);
  RETURN audit.record_write_decision('TRANSFER','SERVICE_TASK',p_id,true,'SERVICE_TASK_TRANSFERRED');
END
$fn$;

CREATE FUNCTION service.create_versioned_deliverable(
  p_id uuid,p_project uuid,p_subject uuid,p_document uuid,p_version uuid,p_kind text,
  p_due timestamptz,p_event uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,docs,service,audit AS $fn$
DECLARE p service.projects%ROWTYPE;
BEGIN
  SELECT * INTO p FROM service.projects WHERE service_project_id=p_project;
  IF (FOUND AND service.is_service_management_service() AND auth.current_family_id()=p.family_id
      AND p.project_status IN ('PLANNED','ACTIVE','ON_HOLD')
      AND core.is_uuid_v7(p_id) AND core.is_uuid_v7(p_event)
      AND p_kind ~ '^[A-Z][A-Z0-9_]{2,79}$'
      AND EXISTS(SELECT 1 FROM service.project_subjects ps
        WHERE ps.project_subject_id=p_subject AND ps.service_project_id=p_project
          AND ps.status='ACTIVE' AND (ps.valid_until IS NULL OR ps.valid_until>clock_timestamp()))
      AND EXISTS(SELECT 1 FROM docs.documents d JOIN docs.document_versions dv USING(document_id)
        JOIN service.project_subjects ps ON ps.project_subject_id=p_subject
        WHERE d.document_id=p_document AND dv.version_id=p_version
          AND d.family_id=p.family_id AND d.withdrawn_at IS NULL
          AND d.subject_person_id=ps.subject_person_id)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','SERVICE_DELIVERABLE',p_id,false,
      'SERVICE_DELIVERABLE_VERSION_SCOPE_OR_INPUT_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM service.deliverables WHERE deliverable_id=p_id) THEN
    RETURN audit.record_write_decision('CREATE','SERVICE_DELIVERABLE',p_id,false,
      'SERVICE_DELIVERABLE_ALREADY_EXISTS');
  END IF;
  INSERT INTO service.deliverables(deliverable_id,service_project_id,project_subject_id,
    document_id,document_version_id,deliverable_kind,status,due_at,submission_round,
    delivery_governance_version,created_by_principal_id,updated_by_principal_id)
  VALUES(p_id,p_project,p_subject,p_document,p_version,p_kind,'DRAFT',p_due,0,2,
    auth.current_principal_id(),auth.current_principal_id());
  PERFORM service.record_delivery_event(p_event,p_id,'CREATED',NULL,'DRAFT',0,
    'SERVICE_DELIVERABLE_CREATED',p_version);
  PERFORM service.record_project_event(p_event,p_project,'DELIVERABLE_CHANGED',NULL,'DRAFT',
    'SERVICE_DELIVERABLE_CREATED');
  RETURN audit.record_write_decision('CREATE','SERVICE_DELIVERABLE',p_id,true,
    'SERVICE_DELIVERABLE_CREATED');
END
$fn$;

CREATE FUNCTION service.submit_deliverable(p_id uuid,p_event uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service,audit AS $fn$
DECLARE v service.deliverables%ROWTYPE; p service.projects%ROWTYPE; k text; r integer;
BEGIN
  SELECT * INTO v FROM service.deliverables WHERE deliverable_id=p_id FOR UPDATE;
  SELECT * INTO p FROM service.projects WHERE service_project_id=v.service_project_id;
  IF (v.deliverable_id IS NOT NULL AND p.service_project_id IS NOT NULL
      AND v.delivery_governance_version=2 AND service.is_service_management_service()
      AND auth.current_family_id()=p.family_id AND p.project_status NOT IN ('COMPLETED','CANCELLED')
      AND v.status IN ('DRAFT','CHANGES_REQUESTED') AND core.is_uuid_v7(p_event)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('SUBMIT','SERVICE_DELIVERABLE',p_id,false,
      'SERVICE_DELIVERABLE_SUBMIT_STATE_OR_SCOPE_DENIED');
  END IF;
  k:=CASE WHEN v.status='DRAFT' THEN 'SUBMITTED' ELSE 'RESUBMITTED' END;
  r:=v.submission_round+1;
  UPDATE service.deliverables SET status='UNDER_REVIEW',submission_round=r,
    reviewed_by_principal_id=NULL,reviewed_at=NULL,
    updated_by_principal_id=auth.current_principal_id(),updated_at=clock_timestamp()
   WHERE deliverable_id=p_id;
  PERFORM service.record_delivery_event(p_event,p_id,k,v.status,'UNDER_REVIEW',r,
    CASE WHEN k='SUBMITTED' THEN 'SERVICE_DELIVERABLE_SUBMITTED' ELSE 'SERVICE_DELIVERABLE_RESUBMITTED' END,
    v.document_version_id);
  PERFORM service.record_project_event(p_event,v.service_project_id,'DELIVERABLE_CHANGED',
    v.status,'UNDER_REVIEW','SERVICE_DELIVERABLE_SUBMITTED');
  RETURN audit.record_write_decision('SUBMIT','SERVICE_DELIVERABLE',p_id,true,
    'SERVICE_DELIVERABLE_SUBMITTED');
END
$fn$;

CREATE FUNCTION service.review_deliverable(
  p_id uuid,p_decision text,p_reason text,p_event uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service,audit AS $fn$
DECLARE v service.deliverables%ROWTYPE; p service.projects%ROWTYPE; n text; k text;
BEGIN
  SELECT * INTO v FROM service.deliverables WHERE deliverable_id=p_id FOR UPDATE;
  SELECT * INTO p FROM service.projects WHERE service_project_id=v.service_project_id;
  n:=CASE p_decision WHEN 'APPROVE' THEN 'REVIEW_APPROVED'
    WHEN 'REQUEST_CHANGES' THEN 'CHANGES_REQUESTED' END;
  k:=CASE p_decision WHEN 'APPROVE' THEN 'REVIEW_APPROVED'
    WHEN 'REQUEST_CHANGES' THEN 'CHANGES_REQUESTED' END;
  IF (v.deliverable_id IS NOT NULL AND p.service_project_id IS NOT NULL
      AND v.delivery_governance_version=2 AND service.is_service_management_service()
      AND auth.current_family_id()=p.family_id AND p.project_status NOT IN ('COMPLETED','CANCELLED')
      AND v.status='UNDER_REVIEW' AND n IS NOT NULL AND core.is_uuid_v7(p_event)
      AND p_reason ~ '^[A-Z0-9_]{2,80}$'
      AND auth.current_principal_id() IS DISTINCT FROM v.updated_by_principal_id
      AND EXISTS(SELECT 1 FROM service.project_assignments
        WHERE service_project_id=v.service_project_id AND principal_id=auth.current_principal_id()
          AND status='ACTIVE' AND (valid_until IS NULL OR valid_until>clock_timestamp()))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('REVIEW','SERVICE_DELIVERABLE',p_id,false,
      'SERVICE_DELIVERABLE_REVIEW_SEPARATION_OR_SCOPE_DENIED');
  END IF;
  UPDATE service.deliverables SET status=n,reviewed_by_principal_id=auth.current_principal_id(),
    reviewed_at=clock_timestamp(),updated_by_principal_id=auth.current_principal_id(),
    updated_at=clock_timestamp() WHERE deliverable_id=p_id;
  PERFORM service.record_delivery_event(p_event,p_id,k,'UNDER_REVIEW',n,v.submission_round,
    p_reason,v.document_version_id);
  PERFORM service.record_project_event(p_event,v.service_project_id,'DELIVERABLE_CHANGED',
    'UNDER_REVIEW',n,p_reason);
  RETURN audit.record_write_decision('REVIEW','SERVICE_DELIVERABLE',p_id,true,
    CASE WHEN n='REVIEW_APPROVED' THEN 'SERVICE_DELIVERABLE_REVIEW_APPROVED'
      ELSE 'SERVICE_DELIVERABLE_CHANGES_REQUESTED' END);
END
$fn$;

CREATE FUNCTION service.accept_deliverable(p_id uuid,p_event uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service,audit AS $fn$
DECLARE v service.deliverables%ROWTYPE; p service.projects%ROWTYPE; t timestamptz;
BEGIN
  SELECT * INTO v FROM service.deliverables WHERE deliverable_id=p_id FOR UPDATE;
  SELECT * INTO p FROM service.projects WHERE service_project_id=v.service_project_id;
  IF (v.deliverable_id IS NOT NULL AND p.service_project_id IS NOT NULL
      AND v.delivery_governance_version=2 AND service.is_service_management_service()
      AND auth.current_family_id()=p.family_id AND p.project_status NOT IN ('COMPLETED','CANCELLED')
      AND v.status='REVIEW_APPROVED' AND core.is_uuid_v7(p_event)
      AND auth.current_principal_id() IS DISTINCT FROM v.reviewed_by_principal_id
      AND EXISTS(SELECT 1 FROM service.project_assignments
        WHERE service_project_id=v.service_project_id AND principal_id=auth.current_principal_id()
          AND status='ACTIVE' AND (valid_until IS NULL OR valid_until>clock_timestamp()))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ACCEPT','SERVICE_DELIVERABLE',p_id,false,
      'SERVICE_DELIVERABLE_ACCEPTANCE_SEPARATION_OR_SCOPE_DENIED');
  END IF;
  t:=clock_timestamp();
  UPDATE service.deliverables SET status='ACCEPTED',delivered_at=t,
    accepted_by_principal_id=auth.current_principal_id(),accepted_at=t,
    updated_by_principal_id=auth.current_principal_id(),updated_at=t WHERE deliverable_id=p_id;
  PERFORM service.record_delivery_event(p_event,p_id,'ACCEPTED','REVIEW_APPROVED','ACCEPTED',
    v.submission_round,'SERVICE_DELIVERABLE_ACCEPTED',v.document_version_id);
  PERFORM service.record_project_event(p_event,v.service_project_id,'DELIVERABLE_CHANGED',
    'REVIEW_APPROVED','ACCEPTED','SERVICE_DELIVERABLE_ACCEPTED');
  RETURN audit.record_write_decision('ACCEPT','SERVICE_DELIVERABLE',p_id,true,
    'SERVICE_DELIVERABLE_ACCEPTED');
END
$fn$;

CREATE FUNCTION service.withdraw_deliverable(
  p_id uuid,p_reason text,p_event uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service,audit AS $fn$
DECLARE v service.deliverables%ROWTYPE; p service.projects%ROWTYPE;
BEGIN
  SELECT * INTO v FROM service.deliverables WHERE deliverable_id=p_id FOR UPDATE;
  SELECT * INTO p FROM service.projects WHERE service_project_id=v.service_project_id;
  IF (v.deliverable_id IS NOT NULL AND p.service_project_id IS NOT NULL
      AND v.delivery_governance_version=2 AND service.is_service_management_service()
      AND auth.current_family_id()=p.family_id AND p.project_status NOT IN ('COMPLETED','CANCELLED')
      AND v.status IN ('DRAFT','UNDER_REVIEW','CHANGES_REQUESTED','REVIEW_APPROVED')
      AND core.is_uuid_v7(p_event) AND p_reason ~ '^[A-Z0-9_]{2,80}$'
      AND EXISTS(SELECT 1 FROM service.project_assignments
        WHERE service_project_id=v.service_project_id AND principal_id=auth.current_principal_id()
          AND status='ACTIVE' AND (valid_until IS NULL OR valid_until>clock_timestamp()))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('WITHDRAW','SERVICE_DELIVERABLE',p_id,false,
      'SERVICE_DELIVERABLE_WITHDRAW_SCOPE_OR_STATE_DENIED');
  END IF;
  UPDATE service.deliverables SET status='WITHDRAWN',
    updated_by_principal_id=auth.current_principal_id(),updated_at=clock_timestamp()
   WHERE deliverable_id=p_id;
  PERFORM service.record_delivery_event(p_event,p_id,'WITHDRAWN',v.status,'WITHDRAWN',
    v.submission_round,p_reason,v.document_version_id);
  PERFORM service.record_project_event(p_event,v.service_project_id,'DELIVERABLE_CHANGED',
    v.status,'WITHDRAWN',p_reason);
  RETURN audit.record_write_decision('WITHDRAW','SERVICE_DELIVERABLE',p_id,true,
    'SERVICE_DELIVERABLE_WITHDRAWN');
END
$fn$;

ALTER TABLE service.milestone_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE service.milestone_templates FORCE ROW LEVEL SECURITY;
CREATE POLICY milestone_templates_service ON service.milestone_templates
  FOR ALL TO phoenix_canonical_app
  USING (service.is_service_management_service())
  WITH CHECK (service.is_service_management_service());

ALTER TABLE service.delivery_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE service.delivery_events FORCE ROW LEVEL SECURITY;
CREATE POLICY delivery_events_service ON service.delivery_events
  FOR ALL TO phoenix_canonical_app
  USING (service.is_service_management_service() AND EXISTS (
    SELECT 1 FROM service.deliverables d JOIN service.projects p USING(service_project_id)
     WHERE d.deliverable_id=delivery_events.deliverable_id
       AND p.family_id=auth.current_family_id()))
  WITH CHECK (service.is_service_management_service() AND EXISTS (
    SELECT 1 FROM service.deliverables d JOIN service.projects p USING(service_project_id)
     WHERE d.deliverable_id=delivery_events.deliverable_id
       AND p.family_id=auth.current_family_id()));

REVOKE ALL ON service.milestone_templates,service.delivery_events
  FROM PUBLIC,phoenix_canonical_app,phoenix_canonical_reader,phoenix_canonical_context_binder;
REVOKE EXECUTE ON FUNCTION
  service.create_milestone(uuid,uuid,text,text,timestamptz,uuid),
  service.create_deliverable(uuid,uuid,uuid,uuid,text,timestamptz,uuid),
  service.transition_deliverable(uuid,text,uuid)
FROM phoenix_canonical_app;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA service FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
  service.register_milestone_template(uuid,text,integer,text,text),
  service.retire_milestone_template(uuid),
  service.create_milestone_from_template(uuid,uuid,uuid,text,timestamptz,uuid),
  service.transfer_task(uuid,uuid,text,uuid),
  service.create_versioned_deliverable(uuid,uuid,uuid,uuid,uuid,text,timestamptz,uuid),
  service.submit_deliverable(uuid,uuid),
  service.review_deliverable(uuid,text,text,uuid),
  service.accept_deliverable(uuid,uuid),
  service.withdraw_deliverable(uuid,text,uuid)
TO phoenix_canonical_app;

COMMIT;
