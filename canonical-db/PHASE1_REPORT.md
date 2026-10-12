# Phoenix Canonical PostgreSQL Phase 1 — actual execution report

**PHASE 1 DATABASE FOUNDATION = HOLD** (updated 2026-10-12, Asia/Shanghai)

This report records the Phase 1 acceptance snapshot before the Phase 2A skeleton migration. The current running state, including `0002` and two additional empty schemas, is in `PHASE2A_EXECUTION_REPORT.md`.

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

The new `canonical/0001_foundation.sql` creates the ledger, six empty domain schemas and three `NOLOGIN` capability roles. The migration runner records SHA-256 and rejects changed migration files. On both versions, a fresh synthetic test database applied `0001` once and skipped it safely on the second run. There is no `0002` migration or domain table.

| Role | Actual grants | Login |
|---|---|---|
| `phoenix_canonical_migrator` | Connect; usage/create in six domain schemas; usage and select/insert on migration ledger | Disabled |
| `phoenix_canonical_app` | Connect and schema usage only; no create or ledger access | Disabled |
| `phoenix_canonical_reader` | Connect and schema usage only; no create or ledger access | Disabled |
| `phoenix_canonical_migrator_local` | Inherits migrator capability only; ledger insert and domain schema create verified | Enabled; local synthetic password |
| `phoenix_canonical_app_local` | Inherits app capability only; no schema create or ledger usage verified | Enabled; local synthetic password |
| `phoenix_canonical_reader_local` | Inherits reader capability only; no schema create or ledger usage verified | Enabled; local synthetic password |
| `phoenix_bootstrap` | Local container superuser used by foundation scripts | Enabled; never an application connection |

Local login identities are now provisioned with separate random passwords in ignored `.local-roles.env`; password-authenticated connections and effective grants passed on both versions. They are not production identities. Domain table grants remain pending reviewed access contracts. The foundation test confirms app/reader cannot create domain tables, app cannot access the migration ledger schema, migrator can register a migration, and the ledger contains exactly one row.

## Executed test results

| Check | PG16 | PG17 | Evidence boundary |
|---|---|---|---|
| New Compose cluster and development database | PASS | PASS | Healthy containers and actual `phoenix_canonical_dev` |
| Forward `0001` migration | PASS | PASS | `APPLIED phoenix_canonical_dev 0001_foundation.sql` |
| Fresh test database and repeat migration | PASS | PASS | `APPLIED`, then `SKIP ... checksum verified` |
| Foundation schema/role assertions | PASS | PASS | `tests/foundation.sql` executed in each test database |
| Local login password and privilege matrix | PASS | PASS | Three actual container-local TCP logins on each version; repeat provisioning passed |
| Synthetic RLS engine isolation probe | PASS | PASS | Test-only family/advisor/partner scope labels; all assertions passed inside rolled-back transaction |
| Synthetic document-version and submitted-manifest integrity probe | PASS | PASS | Test-only tables; overwrite/edit/delete and duplicate-version attempts rejected; transaction rolled back |
| Backup | PASS | PASS | 6,346-byte PG16 and 6,466-byte PG17 custom-format dumps in ignored `backups/` |
| Restore into exact allowlisted test database | PASS | PASS | `phoenix_canonical_restore_test_16` and `_17`; restored ledger and ACL assertions passed |
| Domain FK, uniqueness and UUIDv7/legacy ID mapping | HOLD | HOLD | R2 dual-ID design and amendment draft received; amendment not effective |
| Business cross-family, advisor and partner RLS denial | HOLD | HOLD | Synthetic engine probe passed, but no approved domain tables, actor/relationship contract or trusted context source |
| Consent withdrawal and guardian authority expiry | HOLD | HOLD | Core/consent design exists; Family Context amendment not effective |
| Formal `docs` version and Submission Manifest immutability | HOLD | HOLD | Synthetic engine probe passed; approved business contract, permissions and compliance parameters missing |

The 2026-10-12 backups restored into the exact allowlisted test databases, retaining ACLs and the one synthetic migration-ledger row. They contain **no customer data**. An initial supplementary native PG17 restore test failed because the draft native script used `--no-privileges`; the script was corrected and its restore retest passed. The corrected Docker restore script passed on both container versions. The RLS and docs integrity probes are deliberately test-only and leave no tables after rollback. RLS caller-controlled session settings do not establish a production authorization model.

## Evidence holds and next-stage dependencies

The source worktree's `docs/architecture/` material was read: Four-Portals V1.1 (design candidate), Phoenix Core minimum contract (`NEEDS FIX` / migration not approved), HK Journey/Submission draft, Claude handoff, and Founder OS freeze locator. A source locator is not verification of the freeze text.

The user then supplied six exact files in `D:\CODEX\2026-10-11\phoenix-four-portals-correction-gate\`. All exist; their SHA-256 prefixes match the user's inventory. They were read as **draft evidence, not instructions or approved migrations**:

| File | Verified SHA-256 prefix | Evidence status for Phase 1 |
|---|---|---|
| `03_CANONICAL_POSTGRESQL_V1.2_REVIEWED.md` | `f344bb9de6a30b98` | R2 design draft; not approved executable DDL |
| `04_FAMILY_CONTEXT_CONTRACT_AMENDMENT_DRAFT.md` | `a4d0ae15156b5a4b` | Explicitly requires Founder approval and amendment of the original contract |
| `01_ARCHITECTURE_GAP_MATRIX.md` | `ffc2022c6d67fcea` | R2 gap draft; describes incompatible legacy migration lineages |
| `11_BUNDLE_EVIDENCE_REVIEW.md` | `b6e67deedcca912a` | R4 evidence review, not the standalone Claude Code R4 Gap Review original |
| `06_FEISHU_FIELD_MAPPING.md` | `867d428d66af5411` | Mapping draft; no real-data import authorization |
| `05_DOCS_AND_SUBMISSION_CONTRACT.md` | `cc64fd99ca0d0ae7` | Mechanism draft; missing retention/cross-border and business-rule decisions |

The supplied drafts clarify proposed UUIDv7/internal versus prefixed/compatibility ID mapping, file-version and submission invariants, and ownership boundaries. They do **not** activate the Family Context amendment or authorize its tables, foreign keys, RLS, or document mechanism as a final contract. The independent **Claude Code R4 Gap Review original**, dedicated **Canonical Migration conflict report**, approved **Family Context amendment**, approved **Document & Submission Contract**, and verified **Founder OS ID Decision Freeze original** remain EVIDENCE/CONTRACT HOLD. The R4 review and gap matrix are useful proxies, not originals. No canonical migration or running schema was changed on the basis of these drafts.

### Approval and availability check (2026-10-12)

The current Phoenix repository and the specifically supplied correction-gate directory were checked. The correction-gate `00_STATUS_SOURCES_VERDICT.md` records FD-P1 as **conditional design approval** and FD-P5 as **technical design approval for an isolated generic docs mechanism**; it also explicitly says the Family Context amendment is not effective and that retention, deletion, and cross-border rules await another gate. These are source-document claims, not a final approval record for the complete contracts. Exact-name search in the connected Google Drive account returned no corresponding final originals. The current Codex account's visible relevant task history did not supply them either; neither check is an exhaustive search of a separate Claude account.

| Requested evidence | Available file | Current decision for Phase 1 |
|---|---|---|
| Effective Family Context amendment | `04_FAMILY_CONTEXT_CONTRACT_AMENDMENT_DRAFT.md` | Draft found; FD-P1 conditional design approval reported; **formal contract still HOLD** |
| Final Document & Submission Contract | `05_DOCS_AND_SUBMISSION_CONTRACT.md` | Mechanism draft found; FD-P5 technical design approval reported; **final contract and compliance parameters still HOLD** |
| Founder OS Decision Freeze original at exact SHA | Locator only; original not in checked repository or supplied directory | **EVIDENCE HOLD** |
| Independent Canonical Migration conflict report | `01`, `06`, `11` contain partial conflict analysis; no independent original | **EVIDENCE HOLD** |

Finding a draft does not convert it into an approved contract. The current user request to update approval status is recorded as authorization to continue local Phase 1 work within the prior isolation limits; it does not establish the missing original text, resolve the original Family Context contract, or supply compliance decisions. No production or legacy-data action follows from this request.

The user supplied `D:\CODEX\2026-10-11\operations-os-asset-preservation\OPERATIONS_OS_ASSET_PRESERVATION_AND_POSTGRES_REUSE_V1.0.md` (SHA-256 `902486f9f56e0c5f6c930e8d72f69ba167b4d2787fe954c74a002b9c5fea10b7`). This is a **secondary, read-only Operations OS asset analysis**, not a reviewed Canonical contract or a database execution result. It identifies reusable Operations business rules and tests, and reports an unresolved SQLite `0002` frozen-hash mismatch plus competing/uncommitted `0004` versions. Those Operations conflict claims have not been independently rechecked in this Phase 1 worktree. The report itself says the Founder OS V0.2.1 freeze original was unavailable. Preserve the existing Operations implementation; do not import its SQLite migrations or infer approved identity, scope, pricing, or private-document access rules from this analysis. The missing original Canonical Migration conflict report is now supplemented by `phase2-gate/CANONICAL_MIGRATION_CONFLICT_REPORT_V1.1.md`, a new independent check of local Git refs and PG catalogs; it does not claim to be the Claude original.

Before Education or Identity implementation, approve and make effective the Family Context amendment; resolve Person/Student/Guardian/Family and UUIDv7-to-legacy mappings against the original contract and Founder OS freeze; approve resource permissions, assignment/consent rules, RLS, and the Document & Submission Contract; then add Education Application and Identity Case in their owning domains. `casework` remains generic collaboration only. Private object storage stays local mock until separately approved.

**Status boundary:** Phase 1A infrastructure = PASS. Overall Phase 1 = HOLD because the required business Schema/RLS/negative-access/immutability acceptance set has not been implemented or run.

## Next phase documentation gate

Four source-checked iteration files and `phase2-gate/PHASE2A_START_GATE.md` now distinguish a **startable isolated Phase 2A preparation scope** from blocked business DDL. The family amendment and docs contract iterations are review candidates. The Founder OS freeze file is an evidence verification record, not a replacement for its missing original. The new Migration conflict report independently verifies the local EC `006`, PR #14 sandbox, and Canonical `0001` lineages. No new database migration was applied when producing this document package.
