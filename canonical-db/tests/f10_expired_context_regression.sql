\set ON_ERROR_STOP on
BEGIN;
SELECT pg_sleep(2);
DO $test$
BEGIN
  IF core.create_family('018f0000-0000-7000-8000-000000000006','Expired Context Family') IS NOT FALSE THEN RAISE EXCEPTION 'expired context wrote family'; END IF;
  RAISE NOTICE 'PASS expired trusted context denied within an open transaction';
END
$test$;
COMMIT;
DO $test$
BEGIN
  IF auth.current_family_id() IS NOT NULL THEN RAISE EXCEPTION 'expired context remained active'; END IF;
  RAISE NOTICE 'PASS expired trusted context absent after transaction';
END
$test$;
SELECT auth.clear_context();
DO $test$
BEGIN
  IF auth.current_family_id() IS NOT NULL THEN RAISE EXCEPTION 'clear_context failed'; END IF;
  RAISE NOTICE 'PASS clear_context removed binding';
END
$test$;

