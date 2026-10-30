BEGIN;

CREATE SCHEMA service;
REVOKE ALL ON SCHEMA service FROM PUBLIC;
GRANT USAGE,CREATE ON SCHEMA service TO phoenix_canonical_migrator;
GRANT USAGE ON SCHEMA service TO phoenix_canonical_app;

ALTER TABLE crm.deals ADD CONSTRAINT deals_id_client_family_uq
  UNIQUE(deal_id,client_id,family_id);

CREATE TABLE service.projects (
  service_project_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(service_project_id)),
  client_id uuid NOT NULL,
  family_id uuid NOT NULL,
  deal_id uuid,
  project_code text NOT NULL UNIQUE CHECK (project_code ~ '^[A-Z0-9][A-Z0-9_-]{2,39}$'),
  project_name text NOT NULL CHECK (length(btrim(project_name)) BETWEEN 1 AND 300),
  project_status text NOT NULL CHECK (project_status IN (
    'DRAFT','PLANNED','ACTIVE','ON_HOLD','COMPLETED','CANCELLED'
  )),
  primary_domain text NOT NULL CHECK (primary_domain IN (
    'EDUCATION','IDENTITY','WEALTH','HEALTH','GLOBAL_LIVING','HERITAGE','MULTI_DOMAIN'
  )),
  start_at timestamptz,
  target_completion_at timestamptz,
  completed_at timestamptz,
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  updated_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  FOREIGN KEY(client_id,family_id) REFERENCES crm.clients(client_id,family_id),
  FOREIGN KEY(deal_id,client_id,family_id) REFERENCES crm.deals(deal_id,client_id,family_id),
  CHECK (target_completion_at IS NULL OR start_at IS NULL OR target_completion_at>=start_at),
  CHECK ((project_status IN ('COMPLETED','CANCELLED'))=(completed_at IS NOT NULL))
);
CREATE INDEX projects_family_status_idx ON service.projects(family_id,project_status,updated_at DESC);
CREATE INDEX projects_client_status_idx ON service.projects(client_id,project_status);

CREATE TABLE service.project_parties (
  project_party_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(project_party_id)),
  service_project_id uuid NOT NULL REFERENCES service.projects,
  party_role text NOT NULL CHECK (party_role IN (
    'PAYER','CONTRACTING_PARTY','FAMILY_ADMIN','AUTHORIZED_VIEWER'
  )),
  person_id uuid REFERENCES core.people,
  organization_id uuid REFERENCES core.organizations,
  valid_from timestamptz NOT NULL,
  valid_until timestamptz,
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  CHECK ((person_id IS NOT NULL)<>(organization_id IS NOT NULL)),
  CHECK (valid_until IS NULL OR valid_until>valid_from)
);
CREATE INDEX project_parties_project_role_idx ON service.project_parties(service_project_id,party_role);

CREATE TABLE service.project_subjects (
  project_subject_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(project_subject_id)),
  service_project_id uuid NOT NULL REFERENCES service.projects,
  family_id uuid NOT NULL REFERENCES core.families,
  subject_person_id uuid NOT NULL REFERENCES core.people,
  subject_role text NOT NULL CHECK (subject_role IN ('SERVICE_RECIPIENT')),
  data_scope text NOT NULL CHECK (data_scope IN (
    'GENERAL','EDUCATION','IDENTITY','WEALTH','HEALTH','GLOBAL_LIVING'
  )),
  access_status text NOT NULL DEFAULT 'REFERENCE_ONLY'
    CHECK (access_status='REFERENCE_ONLY'),
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  UNIQUE(service_project_id,subject_person_id,data_scope),
  UNIQUE(project_subject_id,service_project_id)
);
CREATE INDEX project_subjects_family_person_idx ON service.project_subjects(family_id,subject_person_id);

CREATE TABLE service.project_domains (
  project_domain_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(project_domain_id)),
  service_project_id uuid NOT NULL REFERENCES service.projects,
  business_domain text NOT NULL CHECK (business_domain IN (
    'EDUCATION','IDENTITY','WEALTH','HEALTH','GLOBAL_LIVING','HERITAGE'
  )),
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  UNIQUE(service_project_id,business_domain)
);

CREATE TABLE service.project_assignments (
  project_assignment_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(project_assignment_id)),
  service_project_id uuid NOT NULL REFERENCES service.projects,
  principal_id uuid NOT NULL REFERENCES auth.principals,
  assignment_role text NOT NULL CHECK (assignment_role IN (
    'PROJECT_OWNER','PROJECT_MANAGER','SPECIALIST','COORDINATOR','OBSERVER'
  )),
  status text NOT NULL CHECK (status IN ('ACTIVE','ENDED')),
  valid_from timestamptz NOT NULL,
  valid_until timestamptz,
  assigned_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  ended_by_principal_id uuid REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  CHECK (valid_until IS NULL OR valid_until>valid_from),
  CHECK ((status='ACTIVE' AND valid_until IS NULL AND ended_by_principal_id IS NULL)
      OR (status='ENDED' AND valid_until IS NOT NULL AND ended_by_principal_id IS NOT NULL))
);
CREATE UNIQUE INDEX project_assignment_current_uq
  ON service.project_assignments(service_project_id,principal_id,assignment_role)
  WHERE status='ACTIVE' AND valid_until IS NULL;

CREATE TABLE service.tasks (
  task_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(task_id)),
  service_project_id uuid NOT NULL REFERENCES service.projects,
  task_type text NOT NULL CHECK (task_type ~ '^[A-Z][A-Z0-9_]{2,79}$'),
  task_title text NOT NULL CHECK (length(btrim(task_title)) BETWEEN 1 AND 300),
  task_status text NOT NULL CHECK (task_status IN (
    'PENDING','IN_PROGRESS','BLOCKED','COMPLETED','CANCELLED'
  )),
  priority text NOT NULL CHECK (priority IN ('LOW','MEDIUM','HIGH','URGENT')),
  assigned_principal_id uuid REFERENCES auth.principals,
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  updated_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  due_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  CHECK ((task_status='COMPLETED')=(completed_at IS NOT NULL))
);
CREATE INDEX tasks_project_status_idx ON service.tasks(service_project_id,task_status,due_at);
CREATE INDEX tasks_assignee_status_idx ON service.tasks(assigned_principal_id,task_status,due_at);

CREATE TABLE service.task_events (
  task_event_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(task_event_id)),
  task_id uuid NOT NULL REFERENCES service.tasks,
  event_kind text NOT NULL CHECK (event_kind IN ('CREATED','STATUS_CHANGED','ASSIGNED','DUE_CHANGED')),
  from_status text,
  to_status text,
  reason_code text NOT NULL CHECK (reason_code ~ '^[A-Z0-9_]{2,80}$'),
  actor_principal_id uuid NOT NULL REFERENCES auth.principals,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX task_events_task_time_idx ON service.task_events(task_id,occurred_at,task_event_id);

CREATE TABLE service.project_milestones (
  project_milestone_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(project_milestone_id)),
  service_project_id uuid NOT NULL REFERENCES service.projects,
  milestone_code text NOT NULL CHECK (milestone_code ~ '^[A-Z0-9][A-Z0-9_-]{2,39}$'),
  milestone_title text NOT NULL CHECK (length(btrim(milestone_title)) BETWEEN 1 AND 300),
  status text NOT NULL CHECK (status IN ('PENDING','ACHIEVED','CANCELLED')),
  target_at timestamptz,
  achieved_at timestamptz,
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  UNIQUE(service_project_id,milestone_code),
  CHECK ((status='ACHIEVED')=(achieved_at IS NOT NULL))
);

CREATE TABLE service.deliverables (
  deliverable_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(deliverable_id)),
  service_project_id uuid NOT NULL REFERENCES service.projects,
  project_subject_id uuid,
  document_id uuid REFERENCES docs.documents,
  deliverable_kind text NOT NULL CHECK (deliverable_kind ~ '^[A-Z][A-Z0-9_]{2,79}$'),
  status text NOT NULL CHECK (status IN ('DRAFT','READY','DELIVERED','ACCEPTED','WITHDRAWN')),
  due_at timestamptz,
  delivered_at timestamptz,
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  updated_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  FOREIGN KEY(project_subject_id,service_project_id)
    REFERENCES service.project_subjects(project_subject_id,service_project_id),
  CHECK ((status IN ('DELIVERED','ACCEPTED'))=(delivered_at IS NOT NULL))
);
CREATE INDEX deliverables_project_status_idx ON service.deliverables(service_project_id,status,due_at);

CREATE TABLE service.project_events (
  project_event_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(project_event_id)),
  service_project_id uuid NOT NULL REFERENCES service.projects,
  event_kind text NOT NULL CHECK (event_kind IN (
    'CREATED','STATUS_CHANGED','SUBJECT_ADDED','DOMAIN_ADDED','ASSIGNED','TASK_CREATED','DELIVERABLE_CHANGED'
  )),
  from_status text,
  to_status text,
  reason_code text NOT NULL CHECK (reason_code ~ '^[A-Z0-9_]{2,80}$'),
  actor_principal_id uuid NOT NULL REFERENCES auth.principals,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX project_events_project_time_idx ON service.project_events(service_project_id,occurred_at,project_event_id);

CREATE FUNCTION service.is_service_management_service() RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth
RETURN coalesce(auth.is_internal_service() AND EXISTS (
  SELECT 1 FROM auth.principals p WHERE p.principal_id=auth.current_principal_id()
    AND p.principal_kind='SERVICE' AND p.person_id IS NULL AND p.status='ACTIVE'
    AND p.service_label='canonical_service_v2'
),false);

CREATE FUNCTION service.reject_event_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,service AS $fn$
BEGIN RAISE EXCEPTION 'SERVICE_EVENT_IMMUTABLE'; END
$fn$;
CREATE TRIGGER reject_task_event_change BEFORE UPDATE OR DELETE ON service.task_events
FOR EACH ROW EXECUTE FUNCTION service.reject_event_change();
CREATE TRIGGER reject_project_event_change BEFORE UPDATE OR DELETE ON service.project_events
FOR EACH ROW EXECUTE FUNCTION service.reject_event_change();

CREATE FUNCTION service.record_project_event(
  p_event uuid,p_project uuid,p_kind text,p_from text,p_to text,p_reason text
) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service AS $fn$
BEGIN
  IF (service.is_service_management_service() AND core.is_uuid_v7(p_event)
      AND p_kind IN ('CREATED','STATUS_CHANGED','SUBJECT_ADDED','DOMAIN_ADDED','ASSIGNED','TASK_CREATED','DELIVERABLE_CHANGED')
      AND p_reason ~ '^[A-Z0-9_]{2,80}$') IS NOT TRUE THEN RAISE EXCEPTION 'PROJECT_EVENT_DENIED'; END IF;
  INSERT INTO service.project_events(project_event_id,service_project_id,event_kind,from_status,to_status,reason_code,actor_principal_id)
  VALUES(p_event,p_project,p_kind,p_from,p_to,p_reason,auth.current_principal_id());
END $fn$;

CREATE FUNCTION service.record_task_event(
  p_event uuid,p_task uuid,p_kind text,p_from text,p_to text,p_reason text
) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service AS $fn$
BEGIN
  IF (service.is_service_management_service() AND core.is_uuid_v7(p_event)
      AND p_kind IN ('CREATED','STATUS_CHANGED','ASSIGNED','DUE_CHANGED')
      AND p_reason ~ '^[A-Z0-9_]{2,80}$') IS NOT TRUE THEN RAISE EXCEPTION 'TASK_EVENT_DENIED'; END IF;
  INSERT INTO service.task_events(task_event_id,task_id,event_kind,from_status,to_status,reason_code,actor_principal_id)
  VALUES(p_event,p_task,p_kind,p_from,p_to,p_reason,auth.current_principal_id());
END $fn$;

CREATE FUNCTION service.create_project(
  p_id uuid,p_client uuid,p_family uuid,p_deal uuid,p_code text,p_name text,
  p_primary_domain text,p_start timestamptz,p_target timestamptz,p_event uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,crm,service,audit AS $fn$
BEGIN
  IF (service.is_service_management_service() AND auth.current_family_id()=p_family
      AND core.is_uuid_v7(p_id) AND core.is_uuid_v7(p_event)
      AND p_code ~ '^[A-Z0-9][A-Z0-9_-]{2,39}$'
      AND length(btrim(p_name)) BETWEEN 1 AND 300
      AND p_primary_domain IN ('EDUCATION','IDENTITY','WEALTH','HEALTH','GLOBAL_LIVING','HERITAGE','MULTI_DOMAIN')
      AND (p_target IS NULL OR p_start IS NULL OR p_target>=p_start)
      AND EXISTS(SELECT 1 FROM crm.clients WHERE client_id=p_client AND family_id=p_family
        AND lifecycle_status IN ('ACTIVE','PAUSED'))
      AND (p_deal IS NULL OR EXISTS(SELECT 1 FROM crm.deals
        WHERE deal_id=p_deal AND client_id=p_client AND family_id=p_family
          AND deal_status NOT IN ('LOST','CANCELLED')))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','SERVICE_PROJECT',p_id,false,'SERVICE_CLIENT_DEAL_SCOPE_OR_INPUT_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM service.projects WHERE service_project_id=p_id OR project_code=p_code) THEN
    RETURN audit.record_write_decision('CREATE','SERVICE_PROJECT',p_id,false,'SERVICE_PROJECT_ALREADY_EXISTS');
  END IF;
  INSERT INTO service.projects(service_project_id,client_id,family_id,deal_id,project_code,
    project_name,project_status,primary_domain,start_at,target_completion_at,
    created_by_principal_id,updated_by_principal_id)
  VALUES(p_id,p_client,p_family,p_deal,p_code,btrim(p_name),'DRAFT',p_primary_domain,p_start,p_target,
    auth.current_principal_id(),auth.current_principal_id());
  PERFORM service.record_project_event(p_event,p_id,'CREATED',NULL,'DRAFT','SERVICE_PROJECT_CREATED');
  RETURN audit.record_write_decision('CREATE','SERVICE_PROJECT',p_id,true,'SERVICE_PROJECT_CREATED');
END $fn$;

CREATE FUNCTION service.transition_project(p_id uuid,p_next text,p_event uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service,audit AS $fn$
DECLARE v service.projects%ROWTYPE; allowed boolean;
BEGIN
  SELECT * INTO v FROM service.projects WHERE service_project_id=p_id FOR UPDATE;
  allowed:=FOUND AND service.is_service_management_service() AND auth.current_family_id()=v.family_id
    AND core.is_uuid_v7(p_event) AND (
      (v.project_status='DRAFT' AND p_next IN ('PLANNED','CANCELLED'))
      OR (v.project_status='PLANNED' AND p_next IN ('ACTIVE','CANCELLED'))
      OR (v.project_status='ACTIVE' AND p_next IN ('ON_HOLD','COMPLETED','CANCELLED'))
      OR (v.project_status='ON_HOLD' AND p_next IN ('ACTIVE','CANCELLED')));
  IF allowed IS NOT TRUE THEN RETURN audit.record_write_decision('TRANSITION','SERVICE_PROJECT',p_id,false,'SERVICE_SCOPE_OR_STATE_DENIED'); END IF;
  UPDATE service.projects SET project_status=p_next,
    completed_at=CASE WHEN p_next IN ('COMPLETED','CANCELLED') THEN clock_timestamp() END,
    updated_by_principal_id=auth.current_principal_id(),updated_at=clock_timestamp()
   WHERE service_project_id=p_id;
  PERFORM service.record_project_event(p_event,p_id,'STATUS_CHANGED',v.project_status,p_next,'PROJECT_STATUS_CHANGED');
  RETURN audit.record_write_decision('TRANSITION','SERVICE_PROJECT',p_id,true,'PROJECT_STATUS_CHANGED');
END $fn$;

CREATE FUNCTION service.add_project_subject(
  p_id uuid,p_project uuid,p_person uuid,p_scope text,p_event uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service,audit AS $fn$
DECLARE v service.projects%ROWTYPE;
BEGIN
  SELECT * INTO v FROM service.projects WHERE service_project_id=p_project FOR UPDATE;
  IF (FOUND AND service.is_service_management_service() AND auth.current_family_id()=v.family_id
      AND v.project_status NOT IN ('COMPLETED','CANCELLED') AND core.is_uuid_v7(p_id) AND core.is_uuid_v7(p_event)
      AND p_scope IN ('GENERAL','EDUCATION','IDENTITY','WEALTH','HEALTH','GLOBAL_LIVING')
      AND EXISTS(SELECT 1 FROM core.family_memberships WHERE family_id=v.family_id AND person_id=p_person
        AND valid_from<=clock_timestamp() AND (valid_until IS NULL OR valid_until>clock_timestamp()))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADD','SERVICE_PROJECT_SUBJECT',p_id,false,'SERVICE_PROJECT_FAMILY_OR_SUBJECT_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM service.project_subjects WHERE service_project_id=p_project AND subject_person_id=p_person AND data_scope=p_scope) THEN
    RETURN audit.record_write_decision('ADD','SERVICE_PROJECT_SUBJECT',p_id,false,'PROJECT_SUBJECT_ALREADY_EXISTS');
  END IF;
  INSERT INTO service.project_subjects(project_subject_id,service_project_id,family_id,subject_person_id,
    subject_role,data_scope,created_by_principal_id)
  VALUES(p_id,p_project,v.family_id,p_person,'SERVICE_RECIPIENT',p_scope,auth.current_principal_id());
  PERFORM service.record_project_event(p_event,p_project,'SUBJECT_ADDED',NULL,NULL,'REFERENCE_ONLY_SUBJECT_ADDED');
  RETURN audit.record_write_decision('ADD','SERVICE_PROJECT_SUBJECT',p_id,true,'REFERENCE_ONLY_SUBJECT_ADDED');
END $fn$;

CREATE FUNCTION service.add_project_domain(p_id uuid,p_project uuid,p_domain text,p_event uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service,audit AS $fn$
DECLARE v service.projects%ROWTYPE;
BEGIN
  SELECT * INTO v FROM service.projects WHERE service_project_id=p_project;
  IF (FOUND AND service.is_service_management_service() AND auth.current_family_id()=v.family_id
      AND v.project_status NOT IN ('COMPLETED','CANCELLED') AND core.is_uuid_v7(p_id) AND core.is_uuid_v7(p_event)
      AND p_domain IN ('EDUCATION','IDENTITY','WEALTH','HEALTH','GLOBAL_LIVING','HERITAGE')) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADD','SERVICE_PROJECT_DOMAIN',p_id,false,'SERVICE_PROJECT_SCOPE_OR_DOMAIN_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM service.project_domains WHERE service_project_id=p_project AND business_domain=p_domain) THEN
    RETURN audit.record_write_decision('ADD','SERVICE_PROJECT_DOMAIN',p_id,false,'PROJECT_DOMAIN_ALREADY_EXISTS');
  END IF;
  INSERT INTO service.project_domains(project_domain_id,service_project_id,business_domain,created_by_principal_id)
  VALUES(p_id,p_project,p_domain,auth.current_principal_id());
  PERFORM service.record_project_event(p_event,p_project,'DOMAIN_ADDED',NULL,NULL,'PROJECT_DOMAIN_ADDED');
  RETURN audit.record_write_decision('ADD','SERVICE_PROJECT_DOMAIN',p_id,true,'PROJECT_DOMAIN_ADDED');
END $fn$;

CREATE FUNCTION service.assign_project(
  p_id uuid,p_project uuid,p_principal uuid,p_role text,p_event uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service,audit AS $fn$
DECLARE v service.projects%ROWTYPE;
BEGIN
  SELECT * INTO v FROM service.projects WHERE service_project_id=p_project;
  IF (FOUND AND service.is_service_management_service() AND auth.current_family_id()=v.family_id
      AND v.project_status NOT IN ('COMPLETED','CANCELLED') AND core.is_uuid_v7(p_id) AND core.is_uuid_v7(p_event)
      AND p_role IN ('PROJECT_OWNER','PROJECT_MANAGER','SPECIALIST','COORDINATOR','OBSERVER')
      AND EXISTS(SELECT 1 FROM auth.principals WHERE principal_id=p_principal AND status='ACTIVE'
        AND principal_kind IN ('ADVISOR','CHANNEL','SERVICE'))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ASSIGN','SERVICE_PROJECT',p_id,false,'SERVICE_PROJECT_PRINCIPAL_OR_ROLE_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM service.project_assignments WHERE service_project_id=p_project
      AND principal_id=p_principal AND assignment_role=p_role AND status='ACTIVE') THEN
    RETURN audit.record_write_decision('ASSIGN','SERVICE_PROJECT',p_id,false,'PROJECT_ASSIGNMENT_ALREADY_ACTIVE');
  END IF;
  INSERT INTO service.project_assignments(project_assignment_id,service_project_id,principal_id,
    assignment_role,status,valid_from,assigned_by_principal_id)
  VALUES(p_id,p_project,p_principal,p_role,'ACTIVE',clock_timestamp(),auth.current_principal_id());
  PERFORM service.record_project_event(p_event,p_project,'ASSIGNED',NULL,NULL,'PROJECT_PRINCIPAL_ASSIGNED');
  RETURN audit.record_write_decision('ASSIGN','SERVICE_PROJECT',p_id,true,'PROJECT_PRINCIPAL_ASSIGNED');
END $fn$;

CREATE FUNCTION service.create_task(
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
      AND (p_assignee IS NULL OR EXISTS(SELECT 1 FROM auth.principals WHERE principal_id=p_assignee AND status='ACTIVE'))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','SERVICE_TASK',p_id,false,'SERVICE_PROJECT_STATE_SCOPE_OR_INPUT_DENIED');
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
END $fn$;

CREATE FUNCTION service.transition_task(p_id uuid,p_next text,p_reason text,p_event uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,service,audit AS $fn$
DECLARE v service.tasks%ROWTYPE; p service.projects%ROWTYPE; allowed boolean;
BEGIN
  SELECT * INTO v FROM service.tasks WHERE task_id=p_id FOR UPDATE;
  SELECT * INTO p FROM service.projects WHERE service_project_id=v.service_project_id;
  allowed:=v.task_id IS NOT NULL AND p.service_project_id IS NOT NULL
    AND service.is_service_management_service() AND auth.current_family_id()=p.family_id
    AND p.project_status NOT IN ('COMPLETED','CANCELLED') AND core.is_uuid_v7(p_event)
    AND p_reason ~ '^[A-Z0-9_]{2,80}$' AND (
      (v.task_status='PENDING' AND p_next IN ('IN_PROGRESS','BLOCKED','CANCELLED'))
      OR (v.task_status='IN_PROGRESS' AND p_next IN ('BLOCKED','COMPLETED','CANCELLED'))
      OR (v.task_status='BLOCKED' AND p_next IN ('IN_PROGRESS','CANCELLED')));
  IF allowed IS NOT TRUE THEN RETURN audit.record_write_decision('TRANSITION','SERVICE_TASK',p_id,false,'SERVICE_PROJECT_SCOPE_OR_TASK_STATE_DENIED'); END IF;
  UPDATE service.tasks SET task_status=p_next,
    completed_at=CASE WHEN p_next='COMPLETED' THEN clock_timestamp() END,
    updated_by_principal_id=auth.current_principal_id(),updated_at=clock_timestamp()
   WHERE task_id=p_id;
  PERFORM service.record_task_event(p_event,p_id,'STATUS_CHANGED',v.task_status,p_next,p_reason);
  RETURN audit.record_write_decision('TRANSITION','SERVICE_TASK',p_id,true,'SERVICE_TASK_STATUS_CHANGED');
END $fn$;

ALTER TABLE service.projects ENABLE ROW LEVEL SECURITY; ALTER TABLE service.projects FORCE ROW LEVEL SECURITY;
ALTER TABLE service.project_parties ENABLE ROW LEVEL SECURITY; ALTER TABLE service.project_parties FORCE ROW LEVEL SECURITY;
ALTER TABLE service.project_subjects ENABLE ROW LEVEL SECURITY; ALTER TABLE service.project_subjects FORCE ROW LEVEL SECURITY;
ALTER TABLE service.project_domains ENABLE ROW LEVEL SECURITY; ALTER TABLE service.project_domains FORCE ROW LEVEL SECURITY;
ALTER TABLE service.project_assignments ENABLE ROW LEVEL SECURITY; ALTER TABLE service.project_assignments FORCE ROW LEVEL SECURITY;
ALTER TABLE service.tasks ENABLE ROW LEVEL SECURITY; ALTER TABLE service.tasks FORCE ROW LEVEL SECURITY;
ALTER TABLE service.task_events ENABLE ROW LEVEL SECURITY; ALTER TABLE service.task_events FORCE ROW LEVEL SECURITY;
ALTER TABLE service.project_milestones ENABLE ROW LEVEL SECURITY; ALTER TABLE service.project_milestones FORCE ROW LEVEL SECURITY;
ALTER TABLE service.deliverables ENABLE ROW LEVEL SECURITY; ALTER TABLE service.deliverables FORCE ROW LEVEL SECURITY;
ALTER TABLE service.project_events ENABLE ROW LEVEL SECURITY; ALTER TABLE service.project_events FORCE ROW LEVEL SECURITY;

CREATE POLICY projects_service_scope ON service.projects FOR ALL TO phoenix_canonical_app
  USING (service.is_service_management_service() AND family_id=auth.current_family_id())
  WITH CHECK (service.is_service_management_service() AND family_id=auth.current_family_id());
CREATE POLICY project_parties_service ON service.project_parties FOR ALL TO phoenix_canonical_app
  USING (service.is_service_management_service() AND EXISTS (
    SELECT 1 FROM service.projects p WHERE p.service_project_id=project_parties.service_project_id
      AND p.family_id=auth.current_family_id()))
  WITH CHECK (service.is_service_management_service() AND EXISTS (
    SELECT 1 FROM service.projects p WHERE p.service_project_id=project_parties.service_project_id
      AND p.family_id=auth.current_family_id()));
CREATE POLICY project_subjects_service_scope ON service.project_subjects FOR ALL TO phoenix_canonical_app
  USING (service.is_service_management_service() AND family_id=auth.current_family_id())
  WITH CHECK (service.is_service_management_service() AND family_id=auth.current_family_id());
CREATE POLICY project_domains_service ON service.project_domains FOR ALL TO phoenix_canonical_app
  USING (service.is_service_management_service() AND EXISTS (
    SELECT 1 FROM service.projects p WHERE p.service_project_id=project_domains.service_project_id
      AND p.family_id=auth.current_family_id()))
  WITH CHECK (service.is_service_management_service() AND EXISTS (
    SELECT 1 FROM service.projects p WHERE p.service_project_id=project_domains.service_project_id
      AND p.family_id=auth.current_family_id()));
CREATE POLICY project_assignments_service ON service.project_assignments FOR ALL TO phoenix_canonical_app
  USING (service.is_service_management_service() AND EXISTS (
    SELECT 1 FROM service.projects p WHERE p.service_project_id=project_assignments.service_project_id
      AND p.family_id=auth.current_family_id()))
  WITH CHECK (service.is_service_management_service() AND EXISTS (
    SELECT 1 FROM service.projects p WHERE p.service_project_id=project_assignments.service_project_id
      AND p.family_id=auth.current_family_id()));
CREATE POLICY tasks_service ON service.tasks FOR ALL TO phoenix_canonical_app
  USING (service.is_service_management_service() AND EXISTS (
    SELECT 1 FROM service.projects p WHERE p.service_project_id=tasks.service_project_id
      AND p.family_id=auth.current_family_id()))
  WITH CHECK (service.is_service_management_service() AND EXISTS (
    SELECT 1 FROM service.projects p WHERE p.service_project_id=tasks.service_project_id
      AND p.family_id=auth.current_family_id()));
CREATE POLICY task_events_service ON service.task_events FOR ALL TO phoenix_canonical_app
  USING (service.is_service_management_service() AND EXISTS (
    SELECT 1 FROM service.tasks t JOIN service.projects p USING(service_project_id)
     WHERE t.task_id=task_events.task_id AND p.family_id=auth.current_family_id()))
  WITH CHECK (service.is_service_management_service() AND EXISTS (
    SELECT 1 FROM service.tasks t JOIN service.projects p USING(service_project_id)
     WHERE t.task_id=task_events.task_id AND p.family_id=auth.current_family_id()));
CREATE POLICY milestones_service ON service.project_milestones FOR ALL TO phoenix_canonical_app
  USING (service.is_service_management_service() AND EXISTS (
    SELECT 1 FROM service.projects p WHERE p.service_project_id=project_milestones.service_project_id
      AND p.family_id=auth.current_family_id()))
  WITH CHECK (service.is_service_management_service() AND EXISTS (
    SELECT 1 FROM service.projects p WHERE p.service_project_id=project_milestones.service_project_id
      AND p.family_id=auth.current_family_id()));
CREATE POLICY deliverables_service ON service.deliverables FOR ALL TO phoenix_canonical_app
  USING (service.is_service_management_service() AND EXISTS (
    SELECT 1 FROM service.projects p WHERE p.service_project_id=deliverables.service_project_id
      AND p.family_id=auth.current_family_id()))
  WITH CHECK (service.is_service_management_service() AND EXISTS (
    SELECT 1 FROM service.projects p WHERE p.service_project_id=deliverables.service_project_id
      AND p.family_id=auth.current_family_id()));
CREATE POLICY project_events_service ON service.project_events FOR ALL TO phoenix_canonical_app
  USING (service.is_service_management_service() AND EXISTS (
    SELECT 1 FROM service.projects p WHERE p.service_project_id=project_events.service_project_id
      AND p.family_id=auth.current_family_id()))
  WITH CHECK (service.is_service_management_service() AND EXISTS (
    SELECT 1 FROM service.projects p WHERE p.service_project_id=project_events.service_project_id
      AND p.family_id=auth.current_family_id()));

REVOKE ALL ON ALL TABLES IN SCHEMA service
  FROM PUBLIC,phoenix_canonical_app,phoenix_canonical_reader,phoenix_canonical_context_binder;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA service FROM PUBLIC;
GRANT EXECUTE ON FUNCTION service.is_service_management_service(),
  service.create_project(uuid,uuid,uuid,uuid,text,text,text,timestamptz,timestamptz,uuid),
  service.transition_project(uuid,text,uuid),
  service.add_project_subject(uuid,uuid,uuid,text,uuid),
  service.add_project_domain(uuid,uuid,text,uuid),
  service.assign_project(uuid,uuid,uuid,text,uuid),
  service.create_task(uuid,uuid,text,text,text,uuid,timestamptz,uuid),
  service.transition_task(uuid,text,text,uuid)
TO phoenix_canonical_app;

COMMIT;
