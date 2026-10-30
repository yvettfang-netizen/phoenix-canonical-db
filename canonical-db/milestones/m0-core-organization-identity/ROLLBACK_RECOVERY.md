# M0 Rollback & Recovery

## Rollback rule

M0 is forward-only. There is no destructive down migration. Before an approved deployment, take a manifest-verified backup. If application release fails, stop the new writer and keep the additive schema; correct it with a later forward migration.

## Recovery proof

The milestone acceptance creates a dedicated backup through the non-superuser backup role, verifies its SHA-256 manifest, restores into a fresh PostgreSQL cluster with roles/global objects bootstrapped, then checks:

- 30 ledger rows and exact checksums;
- 77 tables and 68 RLS policies;
- Organization governance tables, synthetic lifecycle rows and public IDs;
- restored app/reader/binder/PUBLIC ACL boundaries;
- existing Canonical restore regressions.

The evidence files are listed in `TEST_REPORT.md`. Backup manifests are integrity checks, not signatures; off-site retention and production RPO/RTO remain separately governed.
