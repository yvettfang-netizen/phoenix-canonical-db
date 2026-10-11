# Phoenix Canonical PostgreSQL Phase 1 — actual execution report

**PHASE 1 DATABASE FOUNDATION = HOLD** (2026-10-11, Asia/Shanghai)

Phase 1A's isolated database foundation is running and its migration, repeat execution, backup, and restore checks pass on PostgreSQL 16 and 17. Phase 1B's contract-dependent business tables and Phase 1C's required business access and immutability tests remain on CONTRACT HOLD. No design document is counted as a built table or tested RLS policy.

## Scope and safety

- Existing worktree reused: `D:\CODEX\01_PHOENIX\01_NOVA\_worktrees\canonical-postgresql-phase1`, branch `codex/canonical-postgresql-phase1`, initially based on local `origin/main` at `846f77c120cd00a49d89635dd4297b020af7d03a`.
- No new clone, push, merge, PR change, deployment, legacy migration, D1 migration, Tencent Cloud connection, production key, COS connection, or real customer record was used.
- Tencent Cloud production server remains **A4 OPEN / NOT TRUSTED** and is excluded from this work.
- Docker Engine 29.8.2 on local Linux/AMD64 Docker Desktop. Two Compose volumes hold the new synthetic development clusters. The Compose network is `internal: true`; **no host port is published**. Database access for these checks uses `docker compose exec`.

## Actual running state

| Service | Actual server version | Database | Container state | Storage |
|---|---|---|---|---|
| `pg16` | PostgreSQL 16.15 (Debian 16.15-1.pgdg13+2) | `phoenix_canonical_dev` | Running, healthy | `phoenix-canonical-foundation_pg16_data` |
| `pg17` | PostgreSQL 17.11 (Debian 17.11-1.pgdg13+2) | `phoenix_canonical_dev` | Running, healthy | `phoenix-canonical-foundation_pg17_data` |

`docker compose config --quiet` passed. After clarifying the network-only configuration, both containers were recreated **without removing volumes**; both remained healthy and re-running migration reported `SKIP ... checksum verified`. Database initialization was not repeated.

## Schema and migration inventory

| Namespace/object | Actual state on PG16 and PG17 |
|---|---|
| `canonical_migrations.applied` | Only table; one row for `0001_foundation.sql` |
| `core`, `consent`, `audit`, `integration`, `docs`, `casework` | Schemas exist; **zero domain tables** |
| Domain RLS policies | **Zero**, because no contract-dependent domain tables are approved |
| Legacy `006` | Not reused |

The new `canonical/0001_foundation.sql` creates the ledger, six empty domain schemas and three `NOLOGIN` capability roles. The migration runner records SHA-256 and rejects changed migration files. On both versions, a fresh synthetic test database applied `0001` once and skipped it safely on the second run.

| Role | Actual grants | Login |
|---|---|---|
| `phoenix_canonical_migrator` | Connect; usage/create in six domain schemas; usage and select/insert on migration ledger | Disabled |
| `phoenix_canonical_app` | Connect and schema usage only; no create or ledger access | Disabled |
| `phoenix_canonical_reader` | Connect and schema usage only; no create or ledger access | Disabled |
| `phoenix_bootstrap` | Local container superuser used by foundation scripts | Enabled; never an application connection |

Application, migration and reader login identities and table grants are still pending reviewed access contracts. The foundation test confirms app/reader cannot create domain tables, app cannot access the migration ledger schema, migrator can register a migration, and the ledger contains exactly one row.

## Executed test results

| Check | PG16 | PG17 | Evidence boundary |
|---|---|---|---|
| New Compose cluster and development database | PASS | PASS | Healthy containers and actual `phoenix_canonical_dev` |
| Forward `0001` migration | PASS | PASS | `APPLIED phoenix_canonical_dev 0001_foundation.sql` |
| Fresh test database and repeat migration | PASS | PASS | `APPLIED`, then `SKIP ... checksum verified` |
| Foundation schema/role assertions | PASS | PASS | `tests/foundation.sql` executed in each test database |
| Backup | PASS | PASS | 6,346-byte PG16 and 6,466-byte PG17 custom-format dumps in ignored `backups/` |
| Restore into exact allowlisted test database | PASS | PASS | `phoenix_canonical_restore_test_16` and `_17`; restored ledger and ACL assertions passed |
| Domain FK, uniqueness and UUIDv7/legacy ID mapping | HOLD | HOLD | Reviewed amendment and mapping semantics missing |
| Cross-family, advisor and partner RLS denial | HOLD | HOLD | No approved tables, actor/relationship contract or RLS policy |
| Consent withdrawal and guardian authority expiry | HOLD | HOLD | No approved core/consent identity semantics |
| Document version and Submission Manifest immutability | HOLD | HOLD | Final Document & Submission Contract missing |

The backup contains the foundation schema, permissions and one synthetic migration-ledger row; it contains **no customer data**. Restores retained ACLs. An initial supplementary native PG17 restore test failed because the draft native script used `--no-privileges`; the script was corrected and its restore retest passed. The corrected Docker restore script passed on both container versions.

## Evidence holds and next-stage dependencies

The source worktree's `docs/architecture/` material was read: Four-Portals V1.1 (design candidate), Phoenix Core minimum contract (`NEEDS FIX` / migration not approved), HK Journey/Submission draft, Claude handoff, and Founder OS freeze locator. The exact **Claude Code R4 Architecture Gap Review**, **Canonical PostgreSQL V1.2 Reviewed**, approved **Family Context Contract Amendment**, final **Document & Submission Contract**, verified **Founder OS ID Decision Freeze original**, and **Migration conflict report** were not present in the current repository evidence set. A source locator is not verification of the freeze text.

Before Education or Identity implementation, obtain those exact reviewed artifacts; freeze Person/Student/Guardian/Family and UUIDv7-to-legacy mappings; approve resource permissions, assignment/consent rules and RLS; then add Education Application and Identity Case in their owning domains. `casework` remains generic collaboration only. Document metadata/versioning must be reviewed before tables are added; private object storage stays local mock until separately approved.

**Status boundary:** Phase 1A infrastructure = PASS. Overall Phase 1 = HOLD because the required business Schema/RLS/negative-access/immutability acceptance set has not been implemented or run.
