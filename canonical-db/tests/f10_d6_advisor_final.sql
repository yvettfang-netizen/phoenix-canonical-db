\set ON_ERROR_STOP on
DO $test$
BEGIN
  IF education.record_external_fact('018f0000-0000-7000-8000-000000008101',
    '018f0000-0000-7000-8000-000000004001','DECISION','Synthetic Institution',
    'SYNTHETIC-EDU-DECISION',clock_timestamp()+interval '1 hour') IS NOT FALSE
    THEN RAISE EXCEPTION 'future education fact'; END IF;
  IF education.record_external_fact('018f0000-0000-7000-8000-000000008102',
    '018f0000-0000-7000-8000-000000004001','DECISION','Synthetic Institution',
    'SYNTHETIC-EDU-DECISION',clock_timestamp()) IS NOT TRUE
    THEN RAISE EXCEPTION 'education decision fact'; END IF;
  IF identity.record_external_fact('018f0000-0000-7000-8000-000000008103',
    '018f0000-0000-7000-8000-000000004002','DECISION','Synthetic Office',
    'SYNTHETIC-ID-DECISION',clock_timestamp()) IS NOT TRUE
    THEN RAISE EXCEPTION 'identity decision fact'; END IF;
  IF education.advance_application('018f0000-0000-7000-8000-000000004001','DECIDED') IS NOT TRUE
    THEN RAISE EXCEPTION 'education decided with fact'; END IF;
  IF identity.advance_case('018f0000-0000-7000-8000-000000004002','RESOLVED') IS NOT TRUE
    THEN RAISE EXCEPTION 'identity resolved with fact'; END IF;
  IF docs.submit_manifest('018f0000-0000-7000-8000-000000007001') IS NOT TRUE
    THEN RAISE EXCEPTION 'advisor submit family confirmed manifest'; END IF;
  IF docs.submit_manifest('018f0000-0000-7000-8000-000000007005') IS NOT TRUE
    THEN RAISE EXCEPTION 'advisor submit separately confirmed manifest'; END IF;
  RAISE NOTICE 'PASS D13/D14 official decision facts, advisor state changes and separate confirmation/submission';
END $test$;
