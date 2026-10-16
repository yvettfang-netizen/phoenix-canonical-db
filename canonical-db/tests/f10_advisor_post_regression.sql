\set ON_ERROR_STOP on
DO $test$
BEGIN
  IF education.advance_application('018f0000-0000-7000-8000-000000004001','READY') IS NOT TRUE THEN RAISE EXCEPTION 'advisor education with consent'; END IF;
  IF identity.advance_case('018f0000-0000-7000-8000-000000004002','EVIDENCE_PENDING') IS NOT TRUE THEN RAISE EXCEPTION 'advisor identity with consent'; END IF;
  IF education.create_application('018f0000-0000-7000-8000-000000004005',
    '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001003',
    'Synthetic Advisor Institution','Synthetic Advisor Programme','2027') IS NOT TRUE THEN RAISE EXCEPTION 'assigned advisor education create'; END IF;
  IF identity.create_case('018f0000-0000-7000-8000-000000004006',
    '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001003',
    'Synthetic Advisor Case') IS NOT TRUE THEN RAISE EXCEPTION 'assigned advisor identity create'; END IF;
  IF education.create_application('018f0000-0000-7000-8000-000000004007',
    '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001003',
    'Unassigned Institution','Unassigned Programme','2027') IS NOT FALSE THEN RAISE EXCEPTION 'unassigned advisor created application'; END IF;
  IF docs.create_submission_manifest('018f0000-0000-7000-8000-000000007005',
    '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001003',
    'EDUCATION_APPLICATION','018f0000-0000-7000-8000-000000004005') IS NOT TRUE THEN RAISE EXCEPTION 'advisor manifest prepare'; END IF;
  IF docs.add_submission_item('018f0000-0000-7000-8000-000000007005',1,
    '018f0000-0000-7000-8000-000000006101') IS NOT TRUE THEN RAISE EXCEPTION 'advisor manifest item with document consent'; END IF;
  IF docs.submit_manifest('018f0000-0000-7000-8000-000000007005') IS NOT FALSE THEN RAISE EXCEPTION 'advisor unconfirmed manifest submit'; END IF;
  RAISE NOTICE 'PASS assigned advisor writes only with Consent';
END
$test$;

