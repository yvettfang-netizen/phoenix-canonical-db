\set ON_ERROR_STOP on
DO $test$
BEGIN
  IF education.advance_application('018f0000-0000-7000-8000-000000004001','SUBMITTED') IS NOT TRUE THEN RAISE EXCEPTION 'education submitted'; END IF;
  IF education.advance_application('018f0000-0000-7000-8000-000000004001','DECIDED') IS NOT TRUE THEN RAISE EXCEPTION 'education decided'; END IF;
  IF education.advance_application('018f0000-0000-7000-8000-000000004001','WITHDRAWN') IS NOT FALSE THEN RAISE EXCEPTION 'decided withdrawal'; END IF;
  IF education.advance_application('018f0000-0000-7000-8000-000000004003','WITHDRAWN') IS NOT TRUE THEN RAISE EXCEPTION 'draft withdrawal'; END IF;
  IF identity.advance_case('018f0000-0000-7000-8000-000000004002','UNDER_REVIEW') IS NOT TRUE THEN RAISE EXCEPTION 'identity review'; END IF;
  IF identity.advance_case('018f0000-0000-7000-8000-000000004002','RESOLVED') IS NOT TRUE THEN RAISE EXCEPTION 'identity resolved'; END IF;
  IF identity.advance_case('018f0000-0000-7000-8000-000000004002','DRAFT') IS NOT FALSE THEN RAISE EXCEPTION 'identity rollback'; END IF;
  RAISE NOTICE 'PASS education and identity legal state flow, no rollback or decided withdrawal';

  IF docs.add_submission_item('018f0000-0000-7000-8000-000000007001',1,
    '018f0000-0000-7000-8000-000000006101') IS NOT TRUE THEN RAISE EXCEPTION 'manifest add item'; END IF;
  IF docs.add_submission_item('018f0000-0000-7000-8000-000000007001',1,
    '018f0000-0000-7000-8000-000000006101') IS NOT FALSE THEN RAISE EXCEPTION 'manifest duplicate item'; END IF;
  IF docs.submit_manifest('018f0000-0000-7000-8000-000000007001') IS NOT TRUE THEN RAISE EXCEPTION 'manifest submit'; END IF;
  IF docs.submit_manifest('018f0000-0000-7000-8000-000000007001') IS NOT FALSE THEN RAISE EXCEPTION 'manifest repeat submit'; END IF;
  IF docs.add_submission_item('018f0000-0000-7000-8000-000000007001',2,
    '018f0000-0000-7000-8000-000000006101') IS NOT FALSE THEN RAISE EXCEPTION 'manifest post-submit add'; END IF;
  RAISE NOTICE 'PASS manifest prepare, pin, submit and immutable post-submit';
END
$test$;

