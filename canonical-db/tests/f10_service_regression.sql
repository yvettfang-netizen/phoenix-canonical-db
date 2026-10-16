\set ON_ERROR_STOP on
DO $test$
BEGIN
  IF core.create_family('018f0000-0000-7000-8000-000000000003','Synthetic New Family') IS NOT TRUE THEN RAISE EXCEPTION 'create_family positive'; END IF;
  IF core.create_person('018f0000-0000-7000-8000-000000001011','Synthetic New Person',
    '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000003031','MEMBER') IS NOT TRUE THEN RAISE EXCEPTION 'create_person positive'; END IF;
  IF core.add_family_member('018f0000-0000-7000-8000-000000003032',
    '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001001','MEMBER') IS NOT TRUE THEN RAISE EXCEPTION 'add_family_member positive'; END IF;
  IF core.create_student_profile('018f0000-0000-7000-8000-000000001011') IS NOT TRUE THEN RAISE EXCEPTION 'student_profile positive'; END IF;
  IF docs.create_document('018f0000-0000-7000-8000-000000006001',
    '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001003',
    'EDUCATION','Synthetic Transcript',clock_timestamp()+interval '1 year') IS NOT TRUE THEN RAISE EXCEPTION 'document positive'; END IF;
  IF docs.append_document_version('018f0000-0000-7000-8000-000000006101',
    '018f0000-0000-7000-8000-000000006001',1,repeat('a',64)::char(64),
    'mock/synthetic/version-one',42) IS NOT TRUE THEN RAISE EXCEPTION 'version positive'; END IF;
  RAISE NOTICE 'PASS service create family/person/member/student/document/version';

  IF core.create_person('018f0000-0000-7000-8000-000000001012','Wrong Family',
    '018f0000-0000-7000-8000-000000000002','018f0000-0000-7000-8000-000000003033','MEMBER') IS NOT FALSE THEN RAISE EXCEPTION 'person cross family'; END IF;
  IF core.create_student_profile('018f0000-0000-7000-8000-000000001003') IS NOT FALSE THEN RAISE EXCEPTION 'duplicate student'; END IF;
  IF docs.create_document('018f0000-0000-7000-8000-000000006002',
    '018f0000-0000-7000-8000-000000000002','018f0000-0000-7000-8000-000000001003',
    'EDUCATION','Cross Family',clock_timestamp()+interval '1 year') IS NOT FALSE THEN RAISE EXCEPTION 'document cross family'; END IF;
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

