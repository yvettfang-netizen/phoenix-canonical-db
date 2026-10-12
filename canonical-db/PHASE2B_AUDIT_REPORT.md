# Phoenix Canonical PostgreSQL — Phase 2B completion audit and next gate

**ISOLATED FOUNDATION / SYNTHETIC ACCEPTANCE = PASS** · **BUSINESS SCHEMA / NEXT CANONICAL PHASE = HOLD**

Audited and retested on 2026-10-12 (Asia/Shanghai) in the existing isolated worktree. This report distinguishes running database evidence from draft contracts. No production system, Tencent server, real data, external object store, push, merge, or deployment was used.

## Completed in the authorized local scope

| Item | PG16.15 | PG17.11 | Direct evidence |
|---|---|---|---|
| Internal-only Compose service, no published host port | PASS | PASS | Compose config `internal: true`; Docker publishers have `PublishedPort: 0` |
| Fresh Canonical `0001`/`0002` apply and repeat checksum skip | PASS | PASS | Exact allowlisted synthetic test databases reset after confirming zero domain tables; both migrations applied and then skipped |
| Foundation and all disposable RLS, mapping, Consent, guardian, docs and protected-context probes | PASS | PASS | `db.ps1 -Action test`; probe schemas rolled back |
| Local migrator/app/reader password login and least-privilege checks | PASS | PASS | `provision-local-roles` rechecked real container-local TCP logins |
| Atomic migration failure rollback | PASS | PASS | `audit-migration` observed intentional `SYNTHETIC FORCED MIGRATION FAILURE`; no test schema or ledger row persisted |
| Synthetic-only database backup and restore | PASS | PASS | New uniquely named, SHA-256 manifested dumps restored into exact allowlisted restore-test databases; foundation checks passed |
| Local mock object store put/get, digest, deduplication and ZIP restore | PASS | Database independent | New synthetic-only test run passed |

Current development catalog readback on both versions: Canonical ledger has exactly `0001_foundation.sql` and `0002_education_identity_skeleton.sql`; the eight domain schemas contain **0 tables and 0 RLS policies**. Neither `acceptance_probe` nor `acceptance_atomicity_probe` remains. The newly backed-up PG16 and PG17 dumps are 7,422 and 7,562 bytes respectively, each with a local SHA-256 manifest under ignored `backups/`.

## Audit fixes made

1. The previous migration runner committed migration SQL and ledger registration in separate transactions. It now executes both under one transaction and advisory lock, using the exact bytes that were hashed. A forced failure confirms full rollback on PG16/17. Existing `0001` and `0002` file bytes and registered hashes were not changed.
2. Backup previously used one container temporary filename and a timestamp-only local filename; closely spaced runs could overwrite. Each run now has unique names, checks the ledger and requires zero non-ledger tables before dumping. Backup no longer applies pending migrations as a side effect.
3. Restore now requires a version-matched local dump and its synthetic provenance/digest manifest, validates the archive before resetting the allowlisted restore-test database, and rejects older unmanifested snapshots. The rejection was checked against a historical PG16 dump; the restore-test database remained intact.

## Remaining HOLD items

| Gate | Why it remains open |
|---|---|
| Family identity / Consent / guardianship business DDL | Original Family Context V1 and effective approved amendment absent; `auth` versus `core`, UUIDv7/public/legacy mapping, evidence and expiry policies unresolved |
| Document / Submission business DDL | `docs` versus `documents`, manifest ownership/freeze point, retention/deletion/legal-hold authority, storage region and domain material lists unresolved |
| Formal business RLS / audit acceptance | No final tables, trusted web identity binding, request-scoped context lifecycle or canonical access-audit path; current probes simulate mechanisms only |
| Founder OS / Operations reuse | Exact Founder OS freeze original and approved D1 reconciliation remain unavailable; existing assets preserved and not imported |

No approved Canonical PostgreSQL Phase 2C or Phase 3 specification was found in `canonical-db` or the relevant Education/Identity project documentation. Accordingly, the audit does not authorize a fabricated next-phase migration. The next executable business phase starts only after its scope and the applicable contract gates in `phase2-gate/PHASE2A_START_GATE.md` are closed with approver, date, exact source hash and changed clauses. Until then the running database remains the tested eight-schema foundation.
