# Phoenix Canonical PostgreSQL Phase 2A — local execution report

**PHASE 2A EMPTY-SCHEMA FOUNDATION = PASS** · **PHASE 2A BUSINESS SCHEMA = HOLD**

Executed 2026-10-12 (Asia/Shanghai) in the existing `codex/canonical-postgresql-phase1` isolated worktree. No new repository or worktree was created.

## Actual database state

| Check | PostgreSQL 16 | PostgreSQL 17 |
|---|---|---|
| Server | 16.15, healthy | 17.11, healthy |
| Development database | `phoenix_canonical_dev` | `phoenix_canonical_dev` |
| Canonical migrations applied | `0001`, `0002` | `0001`, `0002` |
| Domain schemas | `core`, `consent`, `audit`, `integration`, `docs`, `casework`, `education`, `identity` | Same eight |
| Domain tables / business RLS policies | **0 / 0** | **0 / 0** |
| Non-domain table | `canonical_migrations.applied` only | Same |

Both containers run on the Compose `internal: true` network with no host port binding. The Docker `ps` display of `5432/tcp` is the container-internal port, not a published host port. No Tencent Cloud server, production database, credential, real student/family record, COS bucket, Feishu Base, or Founder OS D1 was accessed.

## Migration and permission result

| File | SHA-256 | Actual result |
|---|---|---|
| `canonical/0001_foundation.sql` | `eea8d1deece72afdc3832d075fcfb42b71b4c1fe4fdccc8900104a0e0ca78a2d` | Existing checksum verified and skipped on both development databases |
| `canonical/0002_education_identity_skeleton.sql` | `bef7d9a902e8ad34491b7455987d7791667dcb8a5ab31945cf609a6aa97e4e7f` | Applied to both development databases; creates only two empty schemas |

Fresh allowlisted synthetic test databases applied both files, then skipped both on a second run with matching checksums. `tests/foundation.sql` passed on PG16 and PG17, including the eight-schema inventory, two ledger rows, **zero domain tables**, and privileges. Password-authenticated container-local connections for migrator, app, and reader login roles passed again on both versions. The migrator can create in the new schemas; app and reader have usage but cannot create there or access the migration ledger.

## Synthetic tests and backups

| Check | PG16 | PG17 | Evidence limit |
|---|---|---|---|
| Family/advisor/partner RLS engine probe | PASS | PASS | Rolled-back synthetic schema; not final trusted identity/RLS |
| Document version and submitted-manifest integrity probe | PASS | PASS | Rolled-back synthetic schema; not a Canonical `docs` table |
| New database backup and restore | PASS | PASS | 7,422-byte PG16 and 7,562-byte PG17 dumps restored into exact allowlisted restore-test databases; `foundation.sql` passed |
| Local mock object storage | PASS | Same local test, database independent | Synthetic content put/get, SHA-256 content key, deduplication, ZIP backup and restored-content digest; 517-byte ZIP |

## Continued synthetic acceptance run (2026-10-12)

Both existing development containers were healthy. The new `probe` action ran on PG16 and PG17 without resetting either development database or applying another migration. It verified the foundation and all three disposable probes, then confirmed that `acceptance_probe` did not persist. Both runs returned `PASS`.

| Disposable synthetic check | PG16 | PG17 | Limit |
|---|---|---|---|
| Source-qualified legacy mapping; unmapped/ambiguous/non-v7 rejection | PASS | PASS | Candidate rules, no canonical mapping table |
| Consent withdrawal takes effect on next decision | PASS | PASS | Test function with supplied actor; no trusted session binding |
| Guardian expiry, family mismatch and self-declared legacy evidence refusal | PASS | PASS | Fixed synthetic evaluation time; legal age/evidence policy remains undecided |
| Stable denial reasons recorded in disposable audit table | PASS | PASS | No canonical audit event table |
| Submitted manifest append, edit, delete and status reversion refusal | PASS | PASS | Test-only trigger and tables |
| Pinned digest match, missing-version refusal and reuse across submissions | PASS | PASS | Test-only snapshot mechanism; no final submission contract |

The modified files are `tests/contract_neutral_probe.sql`, `tests/docs_probe.sql`, and `scripts/db.ps1`. These checks are deliberately transactional and use generated or fixed synthetic identifiers only. They cannot be reported as production authorization or approved Education/Identity business schema.

The mock test writes only generated text beginning `SYNTHETIC PHOENIX DOCUMENT` under ignored `runtime/`; its ZIP is under ignored `backups/`. It accepts no customer file path and uses no external object store. Every run gets new local directories; no existing backup or object is deleted.

## What remains unbuilt

- No Person, Student, Guardian, Consent, Education Application, Identity Case, document, submission, or legacy-mapping business table exists.
- No trusted application session binding or business RLS policy exists. The RLS probe's session settings are caller-controlled and cannot be used for production authorization.
- Mapping-refusal, Consent-withdrawal, guardian-expiry and submission-snapshot mechanism probes pass, but none has run against final business tables or a trusted application session.
- The Family Context original contract and effective amendment, `auth` versus `core` principal ownership, `docs` versus `documents` naming, domain field lists, retention/deletion/storage-region policy, and Founder OS freeze original remain unresolved as detailed in `phase2-gate/PHASE2A_START_GATE.md`.

**Next engineering boundary:** Continue synthetic, contract-neutral probes and mock storage work locally. Dependent business-table migrations require the specific contract gates in the Phase 2A start file. No push, merge, deployment, old-data migration, or production change was performed.
