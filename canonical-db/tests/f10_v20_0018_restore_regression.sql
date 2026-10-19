\set ON_ERROR_STOP on

DO $block$
DECLARE
  subject_definition text;
  advisor_definition text;
  assignment_policy text;
BEGIN
  IF has_function_privilege(
       'phoenix_canonical_context_binder',
       'auth.bind_context(uuid,uuid,uuid,text,timestamptz,uuid)',
       'EXECUTE') THEN
    RAISE EXCEPTION '0018 restore regression: binder still has legacy bind privilege';
  END IF;

  IF NOT has_function_privilege(
       'phoenix_canonical_context_binder',
       'auth.issue_context_ticket(uuid,uuid,uuid,text,timestamptz,uuid,uuid)',
       'EXECUTE') THEN
    RAISE EXCEPTION '0018 restore regression: binder lost ticket privilege';
  END IF;

  IF NOT has_function_privilege(
       'phoenix_canonical_context_binder',
       'auth.resolve_external_identity(text,text)',
       'EXECUTE') THEN
    RAISE EXCEPTION '0018 restore regression: binder lost identity resolution privilege';
  END IF;

  SELECT pg_get_functiondef('core.can_read_subject_basics(uuid)'::regprocedure)
    INTO subject_definition;
  IF subject_definition NOT LIKE '%c.status%'
     OR subject_definition NOT LIKE '%OPEN%'
     OR subject_definition NOT LIKE '%PAUSED%' THEN
    RAISE EXCEPTION '0018 restore regression: subject basics lacks case-status gate';
  END IF;

  SELECT pg_get_functiondef('casework.is_current_advisor_for_case(uuid)'::regprocedure)
    INTO advisor_definition;
  IF advisor_definition NOT LIKE '%c.status%'
     OR advisor_definition NOT LIKE '%OPEN%'
     OR advisor_definition NOT LIKE '%PAUSED%' THEN
    RAISE EXCEPTION '0018 restore regression: current advisor lacks case-status gate';
  END IF;

  SELECT qual
    INTO assignment_policy
    FROM pg_policies
   WHERE schemaname = 'casework'
     AND tablename = 'advisor_assignments'
     AND policyname = 'assignments_read';
  IF assignment_policy IS NULL
     OR assignment_policy NOT LIKE '%status%'
     OR assignment_policy NOT LIKE '%OPEN%'
     OR assignment_policy NOT LIKE '%PAUSED%' THEN
    RAISE EXCEPTION '0018 restore regression: assignments policy lacks case-status gate';
  END IF;
END
$block$;

SELECT 'PASS 0018 restore catalog: E-R6 gates and D-2 privilege boundary preserved';
