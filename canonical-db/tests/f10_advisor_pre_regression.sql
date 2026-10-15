\set ON_ERROR_STOP on
DO $test$
BEGIN
  IF education.advance_application('018f0000-0000-7000-8000-000000004001','READY') IS NOT FALSE THEN RAISE EXCEPTION 'advisor education without consent'; END IF;
  IF identity.advance_case('018f0000-0000-7000-8000-000000004002','EVIDENCE_PENDING') IS NOT FALSE THEN RAISE EXCEPTION 'advisor identity without consent'; END IF;
  IF consent.create_grant('018f0000-0000-7000-8000-000000005099',
    '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001004',
    '018f0000-0000-7000-8000-000000001003','EDUCATION_CASE','EDUCATION',
    clock_timestamp()+interval '1 day') IS NOT FALSE THEN RAISE EXCEPTION 'advisor self-granted consent'; END IF;
  RAISE NOTICE 'PASS advisor write denied without Consent and cannot grant itself';
END
$test$;

