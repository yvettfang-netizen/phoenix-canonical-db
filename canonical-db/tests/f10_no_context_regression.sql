\set ON_ERROR_STOP on
SET phoenix.family_id = '018f0000-0000-7000-8000-000000000001';
SET phoenix.channel = 'INTERNAL';
DO $test$
BEGIN
  IF core.create_family('018f0000-0000-7000-8000-000000000005','Forged Family') IS NOT FALSE THEN RAISE EXCEPTION 'forged family'; END IF;
  IF education.advance_application('018f0000-0000-7000-8000-000000004001','WITHDRAWN') IS NOT FALSE THEN RAISE EXCEPTION 'forged education'; END IF;
  IF identity.advance_case('018f0000-0000-7000-8000-000000004002','CLOSED') IS NOT FALSE THEN RAISE EXCEPTION 'forged identity'; END IF;
  IF docs.submit_manifest('018f0000-0000-7000-8000-000000007001') IS NOT FALSE THEN RAISE EXCEPTION 'forged manifest'; END IF;
  RAISE NOTICE 'PASS GUC forgery without trusted context denied';
END
$test$;
RESET phoenix.family_id;
RESET phoenix.channel;

