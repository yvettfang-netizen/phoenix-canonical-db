\set ON_ERROR_STOP on
DO $test$
BEGIN
  IF consent.withdraw_grant('018f0000-0000-7000-8000-000000008012') IS NOT TRUE
    THEN RAISE EXCEPTION 'unverified subject withdrawal'; END IF;
  RAISE NOTICE 'PASS D12 unverified subject can withdraw earlier self consent';
END $test$;
