# Phoenix Canonical PostgreSQL — greenfield Canonical database

This directory contains the implemented greenfield Canonical database. It does not connect to legacy databases, Feishu, D1 or COS. All acceptance data is synthetic. Migrations `0003`–`0007` implement the new Canonical business baseline while legacy migration remains separately held. Migration `0007` contains the post-audit security boundary fixes; `0008` closes the local reaudit's expiry and cleanup findings. Local-only `0009` adds the Founder-authorized application write API and R-7 guardian evidence protection. Migrations `0001`–`0008` are byte-preserved. `0009` must not be deployed to Tencent before Claude reaudit and Founder approval.

## Layout

| Path | Purpose |
|---|---|
| `compose.yaml` | PostgreSQL 16 and optional PostgreSQL 17 compatibility service on an internal Compose network |
| `migrations/canonical/0001_foundation.sql` | New `canonical_migrations` ledger, seven schemas, restricted capability roles |
| `migrations/canonical/0002_education_identity_skeleton.sql` | Education and Identity namespaces |
| `migrations/canonical/0003_core_consent_access.sql` | Identity, family, Consent, ID mapping, trusted context and base RLS |
| `migrations/canonical/0004_casework_education_identity.sql` | Casework, Education and Identity tables, assignments and RLS |
| `migrations/canonical/0005_documents_submissions.sql` | Document versions, immutable manifests, withdrawal and Legal Hold |
| `migrations/canonical/0006_access_decision_api.sql` | Audited application authorization functions |
| `migrations/canonical/0007_security_boundary_fixes.sql` | Session identity, context tickets, scoped RLS, regrant protection, target validation and guardian scope fixes |
| `migrations/canonical/0008_expiry_and_ephemeral_cleanup.sql` | Natural-expiry normalization, terminal-history protection, function grants and ephemeral cleanup |
| `migrations/canonical/0009_application_write_api.sql` | Local-only SECURITY DEFINER write API, audited decisions, guardian evidence immutability |
| `migrations/canonical/0010_reader_ledger_usage.sql` | Local-only reader schema usage for health ledger query; no DDL grant |
| `migrations/canonical/0011_verified_capacity_official_facts_manifest_confirmation.sql` | Founder-approved capacity evidence, official facts, and distinct confirmation/submission roles; local only pending reaudit |
| `scripts/db.ps1` | Initialization, migration, local login provisioning, exact-name test reset, health, backup and restore test |
| `scripts/native-db.ps1` | Optional local fallback; PG17 was used for a supplemental check before Docker became available |
| `scripts/mock-object-store.ps1` | Synthetic local object put/get, deduplication and backup/restore test |
| `tests/foundation.sql` | Schema, role and repeat-migration checks |
| `tests/rls_probe.sql` | Transactional synthetic RLS engine check; leaves no canonical table |
| `tests/docs_probe.sql` | Transactional synthetic version and submitted-manifest integrity check; leaves no canonical table |
| `tests/contract_neutral_probe.sql` | Transactional synthetic legacy-ID refusal, Consent withdrawal and guardian-expiry decisions with audit reasons |
| `tests/trusted_context_probe.sql` | Phase 2B transactional protected-context RLS simulation; no Canonical business table |
| `tests/phase3_acceptance.sql` | Formal synthetic tests against the implemented Phase 3 business tables and RLS |
| `tests/phase3_defect_regression.ps1` | Separate-login regression coverage for F-01/F-02/F-03/F-04/F-05/F-06/F-07/F-09, reaudit T6c–T6f and cleanup/ACL checks |
| `tests/phase3_fresh_cluster_restore.ps1` | Backup-role export, fresh-cluster restore and post-restore acceptance on PG16/17 |
| `tests/phase3_pg_hba_auth_regression.ps1` | Fresh-container proof that local and host authentication require SCRAM and protected pgpass |
| `tests/f10_local_acceptance.ps1` | Independent PG16/17 network-isolated synthetic write API, role, drift, atomicity and fresh-cluster restore acceptance |
| `tests/9000_atomicity_probe.sql` | Deliberately failing synthetic migration used only by the audit action; never part of the Canonical migration directory |
| `PHASE1_REPORT.md` | Executed evidence and contract holds |
| `PHASE2A_EXECUTION_REPORT.md` | Executed Phase 2A empty-schema and mock-store results |
| `PHASE2B_EXECUTION_REPORT.md` | Executed PG16/17 access-boundary simulation and remaining trust/contract gates |
| `PHASE2B_AUDIT_REPORT.md` | Completion audit, migration/backup fixes, actual retest results and next-stage gate |
| `PHASE2C_EXECUTION_REPORT.md` | PG16/17 negative-acceptance closure, backup tamper refusal and Phase 3 entry audit |
| `PHASE3_EXECUTION_REPORT.md` | Effective greenfield contract, applied business schema, RLS and PG16/17 formal acceptance |
| `phase2-gate/` | Source evidence, the effective greenfield contract and approval register |
| `deploy/tencent/` | No-public-port PostgreSQL 16 deployment, health and backup package |
| `FIX_EXECUTION_REPORT_V1.2_A.md`, `_B.md`, `_C.md` | Separate local rebuild, Tencent isolated update and local 0009 execution results, with raw evidence paths |
| `FIX_EXECUTION_REPORT_V1.3.md` | First local V1.3 batch: reader ledger fix, LF archive policy, PG16/17 cross acceptance and remaining work |
| `FIX_EXECUTION_REPORT_V1.4.md` | Local E1–E3 and D6 execution with PG16/17 raw evidence; pending Claude review |

## Run locally when Docker is available

The script creates an ignored `.env` containing a random local bootstrap password on first use. Docker Compose data volumes are local to this project. Do not use production credentials or real records.

```powershell
pwsh -File ./scripts/db.ps1 -Action init -Version 16
pwsh -File ./scripts/db.ps1 -Action provision-local-roles -Version 16
pwsh -File ./scripts/db.ps1 -Action health -Version 16
pwsh -File ./scripts/db.ps1 -Action test -Version 16
pwsh -File ./scripts/db.ps1 -Action init -Version 17
pwsh -File ./scripts/db.ps1 -Action provision-local-roles -Version 17
pwsh -File ./scripts/db.ps1 -Action test -Version 17
pwsh -File ./scripts/db.ps1 -Action probe -Version 16
pwsh -File ./scripts/db.ps1 -Action probe -Version 17
pwsh -File ./scripts/db.ps1 -Action audit-migration -Version 16
pwsh -File ./scripts/db.ps1 -Action audit-migration -Version 17
pwsh -File ./scripts/db.ps1 -Action audit-backup -Version 16
pwsh -File ./scripts/db.ps1 -Action audit-backup -Version 17
pwsh -File ./scripts/db.ps1 -Action backup -Version 16
pwsh -File ./scripts/db.ps1 -Action restore-test -Version 16 -BackupPath ./backups/<actual-backup-file>.dump
pwsh -File ./scripts/db.ps1 -Action backup -Version 17
pwsh -File ./scripts/db.ps1 -Action restore-test -Version 17 -BackupPath ./backups/<actual-backup-file>.dump
pwsh -File ./scripts/mock-object-store.ps1 -Action test
```

`test` resets only `phoenix_canonical_test_16` or `phoenix_canonical_test_17`; `restore-test` resets only `phoenix_canonical_restore_test_16` or `_17`. The development database is never reset by those actions. `migrate` applies checksum-locked files in lexical order and checks applied file hashes on repeat runs. Each migration body and its ledger registration now commit in the same transaction under an advisory lock. `audit-migration` verifies that a forced synthetic failure leaves neither schema nor ledger residue and that an altered applied migration is rejected. `audit-backup` creates a new synthetic-only backup, rejects both dump-byte and provenance-manifest tampering before restore, and verifies that the allowlisted restore-test database remains unchanged.

`probe` runs the foundation and synthetic checks against the existing development database without resetting it. Every acceptance probe rolls back and the script verifies that its disposable schema is gone. It does not run a migration.

`backup` is read-only with respect to the database: it requires all current local migrations to be registered with matching hashes and zero persistent domain rows. It writes a unique dump plus a synthetic-only SHA-256 manifest under ignored `backups/`; it never overwrites an existing dump. `restore-test` accepts only a matching, manifest-verified current-migration dump from that directory, validates the archive before resetting an exact allowlisted restore-test database, and checks the current business schema. Earlier Phase 1/2 dumps remain historical snapshots and are deliberately rejected because they lack the current manifest. The manifest is an integrity check, not a signature. The signed Founder register supplies only empty-database backup values; the on-call owner and offsite destination remain unassigned.

The containers expose PostgreSQL only within the Compose `internal` network; no host port is published. The scripts access PostgreSQL with `docker compose exec`. Do not publish these ports on a nonlocal interface.

## Role boundary

The migrations create migrator, application, reader and trusted context-binder `NOLOGIN` capability roles. The separate `provision-local-roles` action creates four local development logins with random passwords in ignored `.local-roles.env`. It repeats safely and verifies actual password connections and effective grants over container-local TCP.

| Role | Database/schema rights | Table rights |
|---|---|---|
| `phoenix_canonical_migrator` | Connect; schema DDL and migration ledger | Migration execution only |
| `phoenix_canonical_app` | Connect and exact schema usage | RLS-filtered reads and audited SECURITY DEFINER write functions; no direct table DML |
| `phoenix_canonical_reader` | Connect and exact schema usage | RLS-filtered metadata reads |
| `phoenix_canonical_context_binder` | Auth schema usage | Bind/clear trusted backend context only |
| `phoenix_canonical_migrator_local` | Inherits only migrator capability | Ledger select/insert; domain schema create |
| `phoenix_canonical_app_local` | Inherits only app capability | No domain table rights or ledger access |
| `phoenix_canonical_reader_local` | Inherits only reader capability | RLS-filtered metadata reads; no ledger access |
| `phoenix_canonical_context_binder_local` | Inherits only binder capability | No business-table access |
| `phoenix_canonical_backup_local` | Inherits backup capability for synthetic local backups | `pg_read_all_data`, `BYPASSRLS`, `NOSUPERUSER` |
| `phoenix_canonical_backup_runtime` | Deployment-only backup role | `pg_read_all_data`, `BYPASSRLS`, `NOSUPERUSER` |
| `phoenix_bootstrap` | Local container superuser for setup, migration and synthetic tests | All; never an application connection |

The migration ledger is inaccessible to the app role. Phase 3 RLS uses a private backend-bound context that the application role cannot forge. Family, advisor and partner access requires the applicable membership, assignment, subject grant, Consent and authority. The 0009 write functions record allow/deny reason codes; Guardian evidence level cannot be edited in place. Acceptance data exists only inside removed disposable containers. FD-6 application authentication and real Web integration remain HOLD.

The Founder authorized rebuilding the two local development volumes. That run stopped under the instruction's HOLD rule when bootstrap authentication failed on the newly created PG16 volume; PG17 remains stopped without its old volume. Neither development database is current acceptance evidence. The F-10 / 0009 checks instead ran in disposable `--network none` PG16 and PG17 clusters, which were removed after each run. See the separate V1.2 A and C execution reports.

## Contract holds

The new Canonical business schema is implemented. The post-audit catalog is 25 tables and 20 RLS policies on PG16/17. Historical Family Context and Founder OS originals remain unavailable, so legacy compatibility, Founder OS/D1/Operations reuse, Feishu import, real-data migration and automatic identity reconciliation remain HOLD. No old `006` migration is copied into this namespace.
