-- Optional schema-only evidence probe. NOT a migration and NOT automatically run.
-- Execute only through an already-authorized read-only catalog connection.
-- Returns object metadata only: never SELECT from patient/business data tables.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '5s';
SET LOCAL lock_timeout = '1s';

SELECT current_setting('server_version') AS server_version;

-- Locate physical keys without guessing that a Person is the approved Member.
SELECT n.nspname AS schema_name, c.relname AS relation_name,
       a.attname AS column_name,
       pg_catalog.format_type(a.atttypid, a.atttypmod) AS column_type,
       a.attnotnull AS not_null,
       EXISTS (
         SELECT 1 FROM pg_catalog.pg_index i
         WHERE i.indrelid = c.oid AND i.indisprimary
           AND a.attnum = ANY(i.indkey)
       ) AS part_of_primary_key
FROM pg_catalog.pg_attribute a
JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p') AND a.attnum > 0 AND NOT a.attisdropped
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND n.nspname NOT LIKE 'pg_toast%'
  AND a.attname IN (
    'person_id', 'member_id', 'family_id', 'student_id', 'partner_id',
    'client_id', 'lead_id', 'deal_id', 'contract_code', 'payment_id',
    'service_project_id', 'task_id', 'canonical_task_id', 'principal_id'
  )
ORDER BY n.nspname, c.relname, a.attnum;

SELECT n.nspname AS schema_name, c.relname AS relation_name,
       con.conname AS constraint_name, con.contype AS constraint_type,
       pg_catalog.pg_get_constraintdef(con.oid) AS definition
FROM pg_catalog.pg_constraint con
JOIN pg_catalog.pg_class c ON c.oid = con.conrelid
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('core', 'auth', 'consent', 'casework', 'operations_ref', 'health')
  AND con.contype IN ('p', 'u', 'f', 'c')
ORDER BY n.nspname, c.relname, con.conname;

-- Signatures only; do not execute a context binder or access-audit function.
SELECT n.nspname AS schema_name, p.proname AS function_name,
       pg_catalog.pg_get_function_identity_arguments(p.oid) AS arguments,
       p.prosecdef AS security_definer
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE (n.nspname = 'auth' AND p.proname IN (
  'current_principal_id', 'current_actor_person_id', 'current_family_id',
  'write_context_is_live', 'issue_application_family_context_ticket',
  'redeem_context_ticket'
)) OR (n.nspname = 'audit' AND p.proname IN (
  'record_access_event', 'record_write_decision'
))
ORDER BY n.nspname, p.proname, arguments;

ROLLBACK;
