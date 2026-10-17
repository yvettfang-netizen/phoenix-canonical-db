\set ON_ERROR_STOP on
DO $test$
BEGIN
  IF core.create_person('018f0000-0000-7000-8000-000000001011','Synthetic New Person',
    '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000003031','MEMBER') IS NOT TRUE THEN RAISE EXCEPTION 'create_person positive'; END IF;
  IF core.create_student_profile('018f0000-0000-7000-8000-000000001011') IS NOT TRUE THEN RAISE EXCEPTION 'student_profile positive'; END IF;
  IF docs.create_document('018f0000-0000-7000-8000-000000006001',
    '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001003',
    'EDUCATION','Synthetic Transcript',clock_timestamp()+interval '1 year') IS NOT TRUE THEN RAISE EXCEPTION 'document positive'; END IF;
  IF docs.append_document_version('018f0000-0000-7000-8000-000000006101',
    '018f0000-0000-7000-8000-000000006001',1,repeat('a',64)::char(64),
    'mock/synthetic/version-one',42) IS NOT TRUE THEN RAISE EXCEPTION 'version positive'; END IF;
  RAISE NOTICE 'PASS service create person/student/document/version without a natural-person SERVICE actor';

  IF core.create_person('018f0000-0000-7000-8000-000000001012','Wrong Family',
    '018f0000-0000-7000-8000-000000000002','018f0000-0000-7000-8000-000000003033','MEMBER') IS NOT FALSE THEN RAISE EXCEPTION 'person cross family'; END IF;
  IF core.create_student_profile('018f0000-0000-7000-8000-000000001003') IS NOT FALSE THEN RAISE EXCEPTION 'duplicate student'; END IF;
  IF docs.create_document('018f0000-0000-7000-8000-000000006002',
    '018f0000-0000-7000-8000-000000000002','018f0000-0000-7000-8000-000000001003',
    'EDUCATION','Cross Family',clock_timestamp()+interval '1 year') IS NOT FALSE THEN RAISE EXCEPTION 'document cross family'; END IF;
  IF casework.create_case('018f0000-0000-7000-8000-000000009931',
    '018f0000-0000-7000-8000-000000000002','018f0000-0000-7000-8000-000000001006',
    'Cross family',NULL,NULL) IS NOT FALSE THEN RAISE EXCEPTION 'case cross family'; END IF;
  IF core.create_guardian_authority('018f0000-0000-7000-8000-000000009932',
    '018f0000-0000-7000-8000-000000000002','018f0000-0000-7000-8000-000000001002',
    '018f0000-0000-7000-8000-000000001006','VERIFIED','GENERAL',
    clock_timestamp()+interval '1 day','synthetic/cross-family') IS NOT FALSE THEN RAISE EXCEPTION 'guardian cross family'; END IF;
  IF integration.create_channel_grant('018f0000-0000-7000-8000-000000009933',
    '018f0000-0000-7000-8000-000000002005','018f0000-0000-7000-8000-000000000002',
    '018f0000-0000-7000-8000-000000001006',clock_timestamp()+interval '1 day') IS NOT FALSE THEN RAISE EXCEPTION 'grant cross family'; END IF;
  IF auth.create_login_principal('018f0000-0000-7000-8000-000000009934',
    '018f0000-0000-7000-8000-000000001006','FAMILY') IS NOT FALSE THEN RAISE EXCEPTION 'principal cross family'; END IF;
  IF docs.append_document_version('018f0000-0000-7000-8000-000000006102',
    '018f0000-0000-7000-8000-000000006001',1,repeat('b',64)::char(64),
    'mock/synthetic/version-two',42) IS NOT FALSE THEN RAISE EXCEPTION 'version duplicate number'; END IF;
  IF docs.append_document_version('018f0000-0000-7000-8000-000000006105',
    '018f0000-0000-7000-8000-000000006001',3,repeat('b',64)::char(64),
    'mock/synthetic/version-three',42) IS NOT FALSE THEN RAISE EXCEPTION 'version sequence skipped'; END IF;
  IF docs.append_document_version('018f0000-0000-7000-8000-000000006103',
    '018f0000-0000-7000-8000-000000006001',2,repeat('b',64)::char(64),
    'https://example.invalid/not-mock',42) IS NOT FALSE THEN RAISE EXCEPTION 'version non-mock key'; END IF;
  RAISE NOTICE 'PASS C6/C7 service cross-family, duplicate, skipped version and non-Mock denials';
END
$test$;

