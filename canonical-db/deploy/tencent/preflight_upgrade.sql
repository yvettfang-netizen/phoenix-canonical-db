-- Phoenix Canonical PostgreSQL: read-only pre-upgrade check.
-- Run as the reader or bootstrap login BEFORE applying pending migrations.
-- Every row with blocking = true must be resolved (or explicitly approved)
-- before the upgrade; the migrations themselves are atomic and would roll back.
-- Output: check | blocking | detail. It contains no personal data.
\set ON_ERROR_STOP on
WITH ledger AS (
  SELECT coalesce(max(migration_name), '(none)') AS last_applied, count(*) AS applied
  FROM canonical_migrations.applied
)
SELECT 'ledger' AS check, false AS blocking,
       'applied=' || applied || ' last=' || last_applied AS detail
FROM ledger
UNION ALL
-- 0012 adds CHECK (principal_kind = 'SERVICE') = (person_id IS NULL).
SELECT 'service_principal_with_person', count(*) > 0,
       'rows=' || count(*) || ' (0012 requires SERVICE principals without a natural person)'
FROM auth.principals
WHERE principal_kind = 'SERVICE' AND person_id IS NOT NULL
UNION ALL
SELECT 'non_service_principal_without_person', count(*) > 0,
       'rows=' || count(*)
FROM auth.principals
WHERE principal_kind <> 'SERVICE' AND person_id IS NULL
UNION ALL
-- 0012 adds channel/actor CHECKs to ephemeral context tables; contexts must be empty
-- (stop the binder and application first; contexts are disposable).
SELECT 'live_session_contexts', count(*) > 0,
       'rows=' || count(*) || ' (stop binder/app; ephemeral, safe to clear)'
FROM auth.session_contexts
UNION ALL
-- The ticket table exists only from 0007; count it dynamically so this file
-- also runs on an older database (for example one still at 0006).
SELECT 'live_context_tickets', t.n > 0, 'rows=' || t.n
FROM (SELECT CASE WHEN to_regclass('auth.context_exchange_tickets') IS NULL THEN 0
             ELSE (xpath('/row/n/text()', query_to_xml(
                     'SELECT count(*) AS n FROM auth.context_exchange_tickets', false, true, '')))[1]::text::int
        END AS n) t
UNION ALL
-- 0011 adds CHECK (confirmed_by IS NULL) = (confirmed_at IS NULL) on manifests.
-- Before 0011 a manifest may carry confirmed_by without a confirmation time.
SELECT 'manifest_confirmed_without_time', count(*) > 0,
       'rows=' || count(*) || ' (only relevant when 0011 is pending; needs a data decision)'
FROM docs.submission_manifests m
WHERE m.confirmed_by IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM canonical_migrations.applied
                   WHERE migration_name LIKE '0011\_%')
ORDER BY 1;
