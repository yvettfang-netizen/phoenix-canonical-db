BEGIN;

INSERT INTO core.people(person_id,display_name) VALUES
 ('01940000-0000-7000-8000-000000000101','Synthetic Parent A'),
 ('01940000-0000-7000-8000-000000000102','Synthetic Student A'),
 ('01940000-0000-7000-8000-000000000103','Synthetic Sibling A'),
 ('01940000-0000-7000-8000-000000000104','Synthetic Parent B'),
 ('01940000-0000-7000-8000-000000000105','Synthetic Student B'),
 ('01940000-0000-7000-8000-000000000106','Synthetic Advisor'),
 ('01940000-0000-7000-8000-000000000107','Synthetic Partner');
INSERT INTO core.families(family_id,display_name) VALUES
 ('01940000-0000-7000-8000-000000000001','Synthetic Family A'),
 ('01940000-0000-7000-8000-000000000002','Synthetic Family B');
INSERT INTO core.family_memberships(membership_id,family_id,person_id,membership_role,valid_from) VALUES
 ('01940000-0000-7000-8000-000000000301','01940000-0000-7000-8000-000000000001','01940000-0000-7000-8000-000000000101','PRIMARY','2025-01-01 UTC'),
 ('01940000-0000-7000-8000-000000000302','01940000-0000-7000-8000-000000000001','01940000-0000-7000-8000-000000000102','MEMBER','2025-01-01 UTC'),
 ('01940000-0000-7000-8000-000000000303','01940000-0000-7000-8000-000000000001','01940000-0000-7000-8000-000000000103','MEMBER','2025-01-01 UTC'),
 ('01940000-0000-7000-8000-000000000304','01940000-0000-7000-8000-000000000002','01940000-0000-7000-8000-000000000104','PRIMARY','2025-01-01 UTC'),
 ('01940000-0000-7000-8000-000000000305','01940000-0000-7000-8000-000000000002','01940000-0000-7000-8000-000000000105','MEMBER','2025-01-01 UTC');
INSERT INTO core.student_profiles VALUES
 ('01940000-0000-7000-8000-000000000102',DEFAULT),
 ('01940000-0000-7000-8000-000000000103',DEFAULT),
 ('01940000-0000-7000-8000-000000000105',DEFAULT);
INSERT INTO core.guardian_authorities(authority_id,family_id,guardian_person_id,subject_person_id,evidence_level,scope,valid_from,valid_until) VALUES
 ('01940000-0000-7000-8000-000000000401','01940000-0000-7000-8000-000000000001','01940000-0000-7000-8000-000000000101','01940000-0000-7000-8000-000000000102','VERIFIED','IDENTITY','2025-01-01 UTC','2035-01-01 UTC');

INSERT INTO auth.principals(principal_id,person_id,principal_kind,status) VALUES
 ('01940000-0000-7000-8000-000000000201','01940000-0000-7000-8000-000000000101','FAMILY','ACTIVE'),
 ('01940000-0000-7000-8000-000000000202','01940000-0000-7000-8000-000000000104','FAMILY','ACTIVE'),
 ('01940000-0000-7000-8000-000000000203','01940000-0000-7000-8000-000000000106','ADVISOR','ACTIVE'),
 ('01940000-0000-7000-8000-000000000204','01940000-0000-7000-8000-000000000107','CHANNEL','ACTIVE');

INSERT INTO education.applications(application_id,family_id,student_person_id,institution_label,program_label,cycle_label,status) VALUES
 ('01940000-0000-7000-8000-000000000501','01940000-0000-7000-8000-000000000001','01940000-0000-7000-8000-000000000102','Synthetic University A','Synthetic Program A','2030','DRAFT'),
 ('01940000-0000-7000-8000-000000000502','01940000-0000-7000-8000-000000000002','01940000-0000-7000-8000-000000000105','Synthetic University B','Synthetic Program B','2030','DRAFT');
INSERT INTO identity.cases(identity_case_id,family_id,subject_person_id,case_kind,status) VALUES
 ('01940000-0000-7000-8000-000000000601','01940000-0000-7000-8000-000000000001','01940000-0000-7000-8000-000000000102','SYNTHETIC_IDENTITY_A','DRAFT'),
 ('01940000-0000-7000-8000-000000000602','01940000-0000-7000-8000-000000000001','01940000-0000-7000-8000-000000000103','SYNTHETIC_IDENTITY_SIBLING','DRAFT'),
 ('01940000-0000-7000-8000-000000000603','01940000-0000-7000-8000-000000000002','01940000-0000-7000-8000-000000000105','SYNTHETIC_IDENTITY_B','DRAFT');
INSERT INTO casework.cases(case_id,family_id,subject_person_id,title,status,resource_kind,resource_id) VALUES
 ('01940000-0000-7000-8000-000000000701','01940000-0000-7000-8000-000000000001','01940000-0000-7000-8000-000000000102','Synthetic advisory case','OPEN','EDUCATION_APPLICATION','01940000-0000-7000-8000-000000000501');
INSERT INTO casework.advisor_assignments(assignment_id,case_id,advisor_person_id,valid_from,valid_until) VALUES
 ('01940000-0000-7000-8000-000000000801','01940000-0000-7000-8000-000000000701','01940000-0000-7000-8000-000000000106','2025-01-01 UTC','2035-01-01 UTC');

INSERT INTO consent.grants(consent_id,family_id,grantor_person_id,grantee_person_id,subject_person_id,purpose,data_class,status,granted_at,expires_at) VALUES
 ('01940000-0000-7000-8000-000000000901','01940000-0000-7000-8000-000000000001','01940000-0000-7000-8000-000000000102','01940000-0000-7000-8000-000000000101','01940000-0000-7000-8000-000000000102','DOCUMENT_READ','IDENTITY_SENSITIVE','ACTIVE','2025-01-01 UTC','2035-01-01 UTC'),
 ('01940000-0000-7000-8000-000000000902','01940000-0000-7000-8000-000000000001','01940000-0000-7000-8000-000000000102','01940000-0000-7000-8000-000000000106','01940000-0000-7000-8000-000000000102','EDUCATION_CASE','EDUCATION','ACTIVE','2025-01-01 UTC','2035-01-01 UTC'),
 ('01940000-0000-7000-8000-000000000903','01940000-0000-7000-8000-000000000001','01940000-0000-7000-8000-000000000102','01940000-0000-7000-8000-000000000107','01940000-0000-7000-8000-000000000102','IDENTITY_CASE','IDENTITY_SENSITIVE','ACTIVE','2025-01-01 UTC','2035-01-01 UTC');
INSERT INTO integration.channel_grants(channel_grant_id,principal_id,family_id,subject_person_id,channel,valid_from,valid_until) VALUES
 ('01940000-0000-7000-8000-000000000a01','01940000-0000-7000-8000-000000000204','01940000-0000-7000-8000-000000000001','01940000-0000-7000-8000-000000000102','PARTNER','2025-01-01 UTC','2035-01-01 UTC');

INSERT INTO integration.public_ids(entity_kind,public_id,canonical_id) VALUES
 ('PERSON','per_00000000000000000000000000000101','01940000-0000-7000-8000-000000000101'),
 ('FAMILY','fam_00000000000000000000000000000001','01940000-0000-7000-8000-000000000001');
INSERT INTO integration.legacy_id_mappings(mapping_id,source_system,entity_kind,legacy_id,canonical_id,mapping_status,evidence_ref,decided_by,decided_at) VALUES
 ('01940000-0000-7000-8000-000000000a11','synthetic-a','PERSON','same-visible-id','01940000-0000-7000-8000-000000000101','VERIFIED','synthetic-evidence','01940000-0000-7000-8000-000000000101',clock_timestamp()),
 ('01940000-0000-7000-8000-000000000a12','synthetic-b','PERSON','same-visible-id','01940000-0000-7000-8000-000000000104','VERIFIED','synthetic-evidence','01940000-0000-7000-8000-000000000104',clock_timestamp());

INSERT INTO docs.documents(document_id,family_id,subject_person_id,data_class,document_kind,retention_until) VALUES
 ('01940000-0000-7000-8000-000000000b01','01940000-0000-7000-8000-000000000001','01940000-0000-7000-8000-000000000102','IDENTITY_SENSITIVE','SYNTHETIC_ID','2035-01-01 UTC');
INSERT INTO docs.document_versions(version_id,document_id,version_no,content_sha256,storage_key,size_bytes) VALUES
 ('01940000-0000-7000-8000-000000000b02','01940000-0000-7000-8000-000000000b01',1,repeat('a',64),'synthetic/private/object/version-1',100);
INSERT INTO docs.submission_manifests(submission_id,family_id,subject_person_id,target_kind,target_id,status,prepared_by) VALUES
 ('01940000-0000-7000-8000-000000000b03','01940000-0000-7000-8000-000000000001','01940000-0000-7000-8000-000000000102','IDENTITY_CASE','01940000-0000-7000-8000-000000000601','PREPARING','01940000-0000-7000-8000-000000000101');
INSERT INTO docs.submission_items VALUES
 ('01940000-0000-7000-8000-000000000b03',1,'01940000-0000-7000-8000-000000000b02',repeat('a',64));
UPDATE docs.submission_manifests
 SET confirmed_by='01940000-0000-7000-8000-000000000101',confirmed_at=clock_timestamp()
 WHERE submission_id='01940000-0000-7000-8000-000000000b03';
UPDATE docs.submission_manifests
 SET status='SUBMITTED',
     submitted_by='01940000-0000-7000-8000-000000000106',submitted_at=clock_timestamp()
 WHERE submission_id='01940000-0000-7000-8000-000000000b03';

DO $test$
DECLARE blocked boolean;
BEGIN
  blocked := false;
  BEGIN
    INSERT INTO core.people(person_id,display_name) VALUES ('01940000-0000-4000-8000-000000000999','Invalid v4');
  EXCEPTION WHEN check_violation THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'non-v7 Canonical key accepted'; END IF;

  blocked := false;
  BEGIN
    INSERT INTO integration.legacy_id_mappings(mapping_id,source_system,entity_kind,legacy_id,canonical_id,mapping_status,evidence_ref,decided_by,decided_at)
    VALUES ('01940000-0000-7000-8000-000000000a13','synthetic-a','PERSON','same-visible-id','01940000-0000-7000-8000-000000000102','VERIFIED','synthetic-evidence','01940000-0000-7000-8000-000000000101',clock_timestamp());
  EXCEPTION WHEN unique_violation THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'duplicate verified source mapping accepted'; END IF;

  blocked := false;
  BEGIN
    UPDATE docs.document_versions SET content_sha256=repeat('b',64) WHERE version_id='01940000-0000-7000-8000-000000000b02';
  EXCEPTION WHEN raise_exception THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'document version overwrite accepted'; END IF;

  blocked := false;
  BEGIN
    DELETE FROM docs.submission_items WHERE submission_id='01940000-0000-7000-8000-000000000b03';
  EXCEPTION WHEN raise_exception THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'submitted manifest item deletion accepted'; END IF;
END
$test$;

SET ROLE phoenix_canonical_context_binder;
SELECT auth.issue_context_ticket(
 '01940000-0000-7000-8000-000000000201','01940000-0000-7000-8000-000000000101',
 '01940000-0000-7000-8000-000000000001','FAMILY',clock_timestamp()+interval '45 seconds',
 '01940000-0000-7000-8000-000000000c01','01940000-0000-7000-8000-000000000201') AS context_ticket \gset
RESET ROLE;
SET ROLE phoenix_canonical_app;
SELECT auth.redeem_context_ticket(:'context_ticket','01940000-0000-7000-8000-000000000201');
DO $test$
BEGIN
  IF (SELECT count(*) FROM core.families) <> 1 THEN RAISE EXCEPTION 'family RLS leaked cross-family row'; END IF;
  IF EXISTS (SELECT 1 FROM education.applications WHERE application_id='01940000-0000-7000-8000-000000000502') THEN RAISE EXCEPTION 'family RLS leaked application'; END IF;
  IF NOT docs.authorize_document_read('01940000-0000-7000-8000-000000000b01') OR
     NOT EXISTS (SELECT 1 FROM docs.documents WHERE document_id='01940000-0000-7000-8000-000000000b01') THEN
    RAISE EXCEPTION 'valid guardian document access denied';
  END IF;
  BEGIN
    PERFORM auth.bind_context(
      '01940000-0000-7000-8000-000000000202','01940000-0000-7000-8000-000000000104',
      '01940000-0000-7000-8000-000000000002','FAMILY',clock_timestamp()+interval '1 hour',
      '01940000-0000-7000-8000-000000000c02');
    RAISE EXCEPTION 'application forged trusted context';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$test$;
SELECT auth.clear_context();
RESET ROLE;

SET ROLE phoenix_canonical_context_binder;
SELECT auth.issue_context_ticket(
 '01940000-0000-7000-8000-000000000203','01940000-0000-7000-8000-000000000106',
 '01940000-0000-7000-8000-000000000001','ADVISOR',clock_timestamp()+interval '45 seconds',
 '01940000-0000-7000-8000-000000000c03','01940000-0000-7000-8000-000000000203') AS context_ticket \gset
RESET ROLE;
SET ROLE phoenix_canonical_app;
SELECT auth.redeem_context_ticket(:'context_ticket','01940000-0000-7000-8000-000000000203');
DO $test$
BEGIN
  IF NOT education.authorize_application_read('01940000-0000-7000-8000-000000000501') OR
     NOT EXISTS (SELECT 1 FROM education.applications WHERE application_id='01940000-0000-7000-8000-000000000501') THEN
    RAISE EXCEPTION 'authorized advisor application access denied';
  END IF;
  IF identity.authorize_case_read('01940000-0000-7000-8000-000000000601') OR
     EXISTS (SELECT 1 FROM identity.cases WHERE identity_case_id='01940000-0000-7000-8000-000000000601') THEN
    RAISE EXCEPTION 'advisor accessed unassigned identity case';
  END IF;
  IF education.authorize_application_read('01940000-0000-7000-8000-000000000502') THEN
    RAISE EXCEPTION 'advisor crossed family boundary';
  END IF;
END
$test$;
RESET ROLE;
UPDATE consent.grants SET status='WITHDRAWN',withdrawn_at=clock_timestamp()
 WHERE consent_id='01940000-0000-7000-8000-000000000902';
SET ROLE phoenix_canonical_app;
DO $test$
BEGIN
  IF education.authorize_application_read('01940000-0000-7000-8000-000000000501') OR
     EXISTS (SELECT 1 FROM education.applications WHERE application_id='01940000-0000-7000-8000-000000000501') THEN
    RAISE EXCEPTION 'withdrawn advisor consent remained effective';
  END IF;
END
$test$;
SELECT auth.clear_context();
RESET ROLE;

SET ROLE phoenix_canonical_context_binder;
SELECT auth.issue_context_ticket(
 '01940000-0000-7000-8000-000000000204','01940000-0000-7000-8000-000000000107',
 '01940000-0000-7000-8000-000000000001','PARTNER',clock_timestamp()+interval '45 seconds',
 '01940000-0000-7000-8000-000000000c04','01940000-0000-7000-8000-000000000204') AS context_ticket \gset
RESET ROLE;
SET ROLE phoenix_canonical_app;
SELECT auth.redeem_context_ticket(:'context_ticket','01940000-0000-7000-8000-000000000204');
DO $test$
BEGIN
  IF NOT identity.authorize_case_read('01940000-0000-7000-8000-000000000601') OR
     NOT EXISTS (SELECT 1 FROM identity.cases WHERE identity_case_id='01940000-0000-7000-8000-000000000601') THEN
    RAISE EXCEPTION 'authorized subject-specific channel access denied';
  END IF;
  IF identity.authorize_case_read('01940000-0000-7000-8000-000000000602') OR
     EXISTS (SELECT 1 FROM identity.cases WHERE identity_case_id='01940000-0000-7000-8000-000000000602') THEN
    RAISE EXCEPTION 'channel crossed subject boundary';
  END IF;
  IF identity.authorize_case_read('01940000-0000-7000-8000-000000000603') THEN
    RAISE EXCEPTION 'channel crossed family boundary';
  END IF;
END
$test$;
SELECT auth.clear_context();
RESET ROLE;

UPDATE core.guardian_authorities SET valid_until=clock_timestamp()-interval '1 minute'
 WHERE authority_id='01940000-0000-7000-8000-000000000401';
SET ROLE phoenix_canonical_context_binder;
SELECT auth.issue_context_ticket(
 '01940000-0000-7000-8000-000000000201','01940000-0000-7000-8000-000000000101',
 '01940000-0000-7000-8000-000000000001','FAMILY',clock_timestamp()+interval '45 seconds',
 '01940000-0000-7000-8000-000000000c05','01940000-0000-7000-8000-000000000201') AS context_ticket \gset
RESET ROLE;
SET ROLE phoenix_canonical_app;
SELECT auth.redeem_context_ticket(:'context_ticket','01940000-0000-7000-8000-000000000201');
DO $test$
BEGIN
  IF docs.authorize_document_read('01940000-0000-7000-8000-000000000b01') OR
     EXISTS (SELECT 1 FROM docs.documents WHERE document_id='01940000-0000-7000-8000-000000000b01') THEN
    RAISE EXCEPTION 'expired guardian authority remained effective';
  END IF;
END
$test$;
SELECT auth.clear_context();
RESET ROLE;

UPDATE docs.documents SET withdrawn_at=clock_timestamp(),legal_hold=true
 WHERE document_id='01940000-0000-7000-8000-000000000b01';
INSERT INTO docs.submission_manifests(submission_id,family_id,subject_person_id,target_kind,target_id,status,prepared_by) VALUES
 ('01940000-0000-7000-8000-000000000b04','01940000-0000-7000-8000-000000000001','01940000-0000-7000-8000-000000000102','IDENTITY_CASE','01940000-0000-7000-8000-000000000601','PREPARING','01940000-0000-7000-8000-000000000101');
DO $test$
DECLARE blocked boolean := false;
BEGIN
  BEGIN
    INSERT INTO docs.submission_items VALUES
      ('01940000-0000-7000-8000-000000000b04',1,'01940000-0000-7000-8000-000000000b02',repeat('a',64));
  EXCEPTION WHEN raise_exception THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'withdrawn document entered new manifest'; END IF;
  IF docs.can_purge_document('01940000-0000-7000-8000-000000000b01') THEN
    RAISE EXCEPTION 'legal hold or submitted evidence allowed purge';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM docs.submission_items
    WHERE submission_id='01940000-0000-7000-8000-000000000b03' AND pinned_sha256=repeat('a',64)
  ) THEN RAISE EXCEPTION 'existing submitted snapshot was not preserved'; END IF;
  IF (SELECT count(*) FROM audit.access_events WHERE decision='DENY') < 6 THEN
    RAISE EXCEPTION 'denial audit events missing';
  END IF;
END
$test$;

ROLLBACK;
