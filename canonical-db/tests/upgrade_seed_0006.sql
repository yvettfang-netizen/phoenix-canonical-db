-- Synthetic data for the 0006 -> latest upgrade-path acceptance (bootstrap, 0006 schema).
-- Covers every business table that exists at 0006. No real people, documents or IDs.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core.people(person_id,display_name) VALUES
  ('018f0000-0000-7000-8000-0000000e0001','Upgrade Guardian'),
  ('018f0000-0000-7000-8000-0000000e0002','Upgrade Student'),
  ('018f0000-0000-7000-8000-0000000e0003','Upgrade Advisor');
INSERT INTO core.families(family_id,display_name) VALUES ('018f0000-0000-7000-8000-0000000e0010','Upgrade Family');
INSERT INTO core.family_memberships(membership_id,family_id,person_id,membership_role,valid_from) VALUES
  ('018f0000-0000-7000-8000-0000000e0011','018f0000-0000-7000-8000-0000000e0010','018f0000-0000-7000-8000-0000000e0001','PRIMARY',now()-interval '30 days'),
  ('018f0000-0000-7000-8000-0000000e0012','018f0000-0000-7000-8000-0000000e0010','018f0000-0000-7000-8000-0000000e0002','MEMBER',now()-interval '30 days');
INSERT INTO core.student_profiles(person_id) VALUES ('018f0000-0000-7000-8000-0000000e0002');
INSERT INTO auth.principals(principal_id,person_id,principal_kind,status) VALUES
  ('018f0000-0000-7000-8000-0000000e0021','018f0000-0000-7000-8000-0000000e0001','FAMILY','ACTIVE'),
  ('018f0000-0000-7000-8000-0000000e0022','018f0000-0000-7000-8000-0000000e0002','FAMILY','ACTIVE'),
  ('018f0000-0000-7000-8000-0000000e0023','018f0000-0000-7000-8000-0000000e0003','ADVISOR','ACTIVE');
INSERT INTO core.guardian_authorities(authority_id,family_id,guardian_person_id,subject_person_id,evidence_level,scope,valid_from,valid_until) VALUES
  ('018f0000-0000-7000-8000-0000000e0031','018f0000-0000-7000-8000-0000000e0010','018f0000-0000-7000-8000-0000000e0001','018f0000-0000-7000-8000-0000000e0002','VERIFIED','EDUCATION',now()-interval '30 days',now()+interval '365 days');
INSERT INTO consent.grants(consent_id,family_id,grantor_person_id,grantee_person_id,subject_person_id,purpose,data_class,status,granted_at,expires_at) VALUES
  ('018f0000-0000-7000-8000-0000000e0041','018f0000-0000-7000-8000-0000000e0010','018f0000-0000-7000-8000-0000000e0001','018f0000-0000-7000-8000-0000000e0003','018f0000-0000-7000-8000-0000000e0002','EDUCATION_CASE','EDUCATION','ACTIVE',now()-interval '1 day',now()+interval '30 days');
INSERT INTO education.applications(application_id,family_id,student_person_id,institution_label,program_label,cycle_label,status) VALUES
  ('018f0000-0000-7000-8000-0000000e0051','018f0000-0000-7000-8000-0000000e0010','018f0000-0000-7000-8000-0000000e0002','Upgrade Institution','Upgrade Programme','2027','DRAFT');
INSERT INTO identity.cases(identity_case_id,family_id,subject_person_id,case_kind,status) VALUES
  ('018f0000-0000-7000-8000-0000000e0052','018f0000-0000-7000-8000-0000000e0010','018f0000-0000-7000-8000-0000000e0002','Upgrade case kind','DRAFT');
INSERT INTO casework.cases(case_id,family_id,subject_person_id,title,status,resource_kind,resource_id) VALUES
  ('018f0000-0000-7000-8000-0000000e0061','018f0000-0000-7000-8000-0000000e0010','018f0000-0000-7000-8000-0000000e0002','Upgrade case','OPEN','EDUCATION_APPLICATION','018f0000-0000-7000-8000-0000000e0051');
INSERT INTO casework.advisor_assignments(assignment_id,case_id,advisor_person_id,valid_from,valid_until) VALUES
  ('018f0000-0000-7000-8000-0000000e0062','018f0000-0000-7000-8000-0000000e0061','018f0000-0000-7000-8000-0000000e0003',now()-interval '1 day',now()+interval '30 days');
INSERT INTO docs.documents(document_id,family_id,subject_person_id,data_class,document_kind,retention_until) VALUES
  ('018f0000-0000-7000-8000-0000000e0071','018f0000-0000-7000-8000-0000000e0010','018f0000-0000-7000-8000-0000000e0002','EDUCATION','Upgrade transcript',now()+interval '365 days');
INSERT INTO docs.document_versions(version_id,document_id,version_no,content_sha256,storage_key,size_bytes) VALUES
  ('018f0000-0000-7000-8000-0000000e0072','018f0000-0000-7000-8000-0000000e0071',1,repeat('e',64),'mock/upgrade/version-one',10);
INSERT INTO docs.submission_manifests(submission_id,family_id,subject_person_id,target_kind,target_id,status,prepared_by) VALUES
  ('018f0000-0000-7000-8000-0000000e0081','018f0000-0000-7000-8000-0000000e0010','018f0000-0000-7000-8000-0000000e0002','EDUCATION_APPLICATION','018f0000-0000-7000-8000-0000000e0051','PREPARING','018f0000-0000-7000-8000-0000000e0001');
INSERT INTO docs.submission_items(submission_id,item_no,version_id,pinned_sha256) VALUES
  ('018f0000-0000-7000-8000-0000000e0081',1,'018f0000-0000-7000-8000-0000000e0072',repeat('e',64));
COMMIT;
SELECT 'seeded_0006=ok';
