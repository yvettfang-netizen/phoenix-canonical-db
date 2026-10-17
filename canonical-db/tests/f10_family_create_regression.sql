\set ON_ERROR_STOP on
DO $test$
BEGIN
  IF core.create_family('018f0000-0000-7000-8000-000000000004','Forbidden Family') IS NOT FALSE THEN RAISE EXCEPTION 'family principal created family'; END IF;
  IF casework.create_case('018f0000-0000-7000-8000-000000009940',
    '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001003',
    'Family denied',NULL,NULL) IS NOT FALSE THEN RAISE EXCEPTION 'family principal created case'; END IF;
  IF casework.close_case('018f0000-0000-7000-8000-000000004011') IS NOT FALSE THEN RAISE EXCEPTION 'family principal closed case'; END IF;
  IF casework.create_advisor_assignment('018f0000-0000-7000-8000-000000009941',
    '018f0000-0000-7000-8000-000000004011','018f0000-0000-7000-8000-000000001004',
    clock_timestamp()+interval '1 day') IS NOT FALSE THEN RAISE EXCEPTION 'family principal assigned advisor'; END IF;
  IF casework.revoke_advisor_assignment('018f0000-0000-7000-8000-000000004021') IS NOT FALSE THEN RAISE EXCEPTION 'family principal revoked advisor'; END IF;
  IF core.create_guardian_authority('018f0000-0000-7000-8000-000000009942',
    '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001002',
    '018f0000-0000-7000-8000-000000001003','VERIFIED','GENERAL',
    clock_timestamp()+interval '1 day','synthetic/unauthorized') IS NOT FALSE THEN RAISE EXCEPTION 'family principal verified guardian'; END IF;
  IF core.revoke_guardian_authority('018f0000-0000-7000-8000-000000003011') IS NOT FALSE THEN RAISE EXCEPTION 'family principal revoked guardian'; END IF;
  IF integration.create_channel_grant('018f0000-0000-7000-8000-000000009943',
    '018f0000-0000-7000-8000-000000002005','018f0000-0000-7000-8000-000000000001',
    '018f0000-0000-7000-8000-000000001002',clock_timestamp()+interval '1 day') IS NOT FALSE THEN RAISE EXCEPTION 'family principal granted channel'; END IF;
  IF integration.revoke_channel_grant('018f0000-0000-7000-8000-000000004031') IS NOT FALSE THEN RAISE EXCEPTION 'family principal revoked channel'; END IF;
  IF auth.create_login_principal('018f0000-0000-7000-8000-000000009944',
    '018f0000-0000-7000-8000-000000001011','FAMILY') IS NOT FALSE THEN RAISE EXCEPTION 'family principal created login'; END IF;
  IF auth.disable_login_principal('018f0000-0000-7000-8000-000000002003') IS NOT FALSE THEN RAISE EXCEPTION 'family principal disabled login'; END IF;
  IF core.add_family_member('018f0000-0000-7000-8000-000000003034',
    '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001004','MEMBER') IS NOT FALSE THEN RAISE EXCEPTION 'family principal added member'; END IF;
  IF docs.create_document('018f0000-0000-7000-8000-000000006004',
    '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001003',
    'EDUCATION','Forbidden Upload',clock_timestamp()+interval '1 year') IS NOT FALSE THEN RAISE EXCEPTION 'family principal uploaded'; END IF;
  IF docs.append_document_version('018f0000-0000-7000-8000-000000006104',
    '018f0000-0000-7000-8000-000000006001',2,repeat('c',64)::char(64),
    'mock/synthetic/unauthorized',42) IS NOT FALSE THEN RAISE EXCEPTION 'family principal appended'; END IF;
  RAISE NOTICE 'PASS family actor cannot use internal service APIs';

  IF education.create_application('018f0000-0000-7000-8000-000000004001',
    '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001003',
    'Synthetic Institution','Synthetic Programme','2027') IS NOT TRUE THEN RAISE EXCEPTION 'education create'; END IF;
  IF education.create_application('018f0000-0000-7000-8000-000000004003',
    '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001003',
    'Synthetic Institution','Synthetic Programme','2028') IS NOT TRUE THEN RAISE EXCEPTION 'education create 2'; END IF;
  IF identity.create_case('018f0000-0000-7000-8000-000000004002',
    '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001003',
    'Synthetic Identity Request') IS NOT TRUE THEN RAISE EXCEPTION 'identity create'; END IF;
  IF identity.create_case('018f0000-0000-7000-8000-000000004004',
    '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001003',
    'Synthetic Second Request') IS NOT TRUE THEN RAISE EXCEPTION 'identity create 2'; END IF;
  RAISE NOTICE 'PASS family creates education and identity records';

  IF education.advance_application('018f0000-0000-7000-8000-000000004003','SUBMITTED') IS NOT FALSE THEN RAISE EXCEPTION 'education skipped status'; END IF;
  IF identity.advance_case('018f0000-0000-7000-8000-000000004004','CLOSED') IS NOT TRUE THEN RAISE EXCEPTION 'identity draft close'; END IF;
  RAISE NOTICE 'PASS education state skipping denied and identity DRAFT close allowed';

  IF docs.create_submission_manifest('018f0000-0000-7000-8000-000000007001',
    '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001003',
    'EDUCATION_APPLICATION','018f0000-0000-7000-8000-000000004001') IS NOT TRUE THEN RAISE EXCEPTION 'manifest prepare'; END IF;
  IF docs.add_submission_item('018f0000-0000-7000-8000-000000007001',1,
    '018f0000-0000-7000-8000-000000006101') IS NOT FALSE THEN RAISE EXCEPTION 'document without consent pinned'; END IF;
  RAISE NOTICE 'PASS manifest item denied before document Consent';
END
$test$;

