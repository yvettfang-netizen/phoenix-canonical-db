\set ON_ERROR_STOP on
DO $test$
BEGIN
  IF education.advance_application('018f0000-0000-7000-8000-000000004001','SUBMITTED') IS NOT TRUE THEN RAISE EXCEPTION 'education submitted'; END IF;
  IF education.advance_application('018f0000-0000-7000-8000-000000004001','DECIDED') IS NOT FALSE THEN RAISE EXCEPTION 'family decided without official fact'; END IF;
  IF education.advance_application('018f0000-0000-7000-8000-000000004003','WITHDRAWN') IS NOT TRUE THEN RAISE EXCEPTION 'draft withdrawal'; END IF;
  IF identity.advance_case('018f0000-0000-7000-8000-000000004002','UNDER_REVIEW') IS NOT TRUE THEN RAISE EXCEPTION 'identity review'; END IF;
  IF identity.advance_case('018f0000-0000-7000-8000-000000004002','RESOLVED') IS NOT FALSE THEN RAISE EXCEPTION 'family resolved without official fact'; END IF;
  IF identity.advance_case('018f0000-0000-7000-8000-000000004002','DRAFT') IS NOT FALSE THEN RAISE EXCEPTION 'identity rollback'; END IF;
  RAISE NOTICE 'PASS C5 family cannot decide or resolve without official fact';

  IF docs.add_submission_item('018f0000-0000-7000-8000-000000007001',1,
    '018f0000-0000-7000-8000-000000006101') IS NOT TRUE THEN RAISE EXCEPTION 'manifest add item'; END IF;
  IF docs.add_submission_item('018f0000-0000-7000-8000-000000007001',1,
    '018f0000-0000-7000-8000-000000006101') IS NOT FALSE THEN RAISE EXCEPTION 'manifest duplicate item'; END IF;
  IF docs.submit_manifest('018f0000-0000-7000-8000-000000007001') IS NOT FALSE THEN RAISE EXCEPTION 'unconfirmed manifest submit'; END IF;
  IF docs.confirm_manifest('018f0000-0000-7000-8000-000000007001') IS NOT TRUE THEN RAISE EXCEPTION 'guardian manifest confirmation'; END IF;
  IF docs.add_submission_item('018f0000-0000-7000-8000-000000007001',2,
    '018f0000-0000-7000-8000-000000006101') IS NOT FALSE THEN RAISE EXCEPTION 'manifest post-submit add'; END IF;
  IF docs.submit_manifest('018f0000-0000-7000-8000-000000007001') IS NOT FALSE THEN RAISE EXCEPTION 'family submit after confirmation'; END IF;
  IF docs.confirm_manifest('018f0000-0000-7000-8000-000000007005') IS NOT TRUE THEN RAISE EXCEPTION 'guardian confirms advisor manifest'; END IF;
  RAISE NOTICE 'PASS C8 separate family confirmation, locked items and family submit denial';
END
$test$;

