# Phoenix Canonical PostgreSQL — isolated Phase 1 foundation

This directory is a new development database namespace. It does not connect to legacy databases, Feishu, D1, COS, or production. All data used by the supplied tests is synthetic; the first migration creates no customer rows or identity master tables.

## Layout

| Path | Purpose |
|---|---|
| `compose.yaml` | PostgreSQL 16 and optional PostgreSQL 17 compatibility service on an internal Compose network |
| `migrations/canonical/0001_foundation.sql` | New `canonical_migrations` ledger, seven schemas, restricted capability roles |
| `migrations/canonical/0002_education_identity_skeleton.sql` | Phase 2A empty Education and Identity schemas with restricted grants |
| `scripts/db.ps1` | Initialization, migration, local login provisioning, exact-name test reset, health, backup and restore test |
| `scripts/native-db.ps1` | Optional local fallback; PG17 was used for a supplemental check before Docker became available |
| `scripts/mock-object-store.ps1` | Synthetic local object put/get, deduplication and backup/restore test |
| `tests/foundation.sql` | Schema, role and repeat-migration checks |
| `tests/rls_probe.sql` | Transactional synthetic RLS engine check; leaves no canonical table |
| `tests/docs_probe.sql` | Transactional synthetic version and submitted-manifest integrity check; leaves no canonical table |
| `tests/contract_neutral_probe.sql` | Transactional synthetic legacy-ID refusal, Consent withdrawal and guardian-expiry decisions with audit reasons |
| `tests/trusted_context_probe.sql` | Phase 2B transactional protected-context RLS simulation; no Canonical business table |
| `tests/9000_atomicity_probe.sql` | Deliberately failing synthetic migration used only by the audit action; never part of the Canonical migration directory |
| `PHASE1_REPORT.md` | Executed evidence and contract holds |
| `PHASE2A_EXECUTION_REPORT.md` | Executed Phase 2A empty-schema and mock-store results |
| `PHASE2B_EXECUTION_REPORT.md` | Executed PG16/17 access-boundary simulation and remaining trust/contract gates |
| `PHASE2B_AUDIT_REPORT.md` | Completion audit, migration/backup fixes, actual retest results and next-stage gate |
| `PHASE2C_EXECUTION_REPORT.md` | PG16/17 negative-acceptance closure, backup tamper refusal and Phase 3 entry audit |
| `phase2-gate/` | Four source-checked iteration files and the bounded Phase 2A start gate |

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

`backup` is read-only with respect to the database: it requires all local migrations to be registered with matching hashes and zero non-ledger tables. It writes a unique dump plus a synthetic-only SHA-256 manifest under ignored `backups/`; it never overwrites an existing dump. `restore-test` accepts only a matching, manifest-verified dump from that directory, validates the archive before resetting an exact allowlisted restore-test database, and checks the current two-migration schema. Earlier Phase 1 dumps remain historical snapshots and are deliberately rejected by the automated restore action because they lack this provenance manifest.

The containers expose PostgreSQL only within the Compose `internal` network; no host port is published. The scripts access PostgreSQL with `docker compose exec`. Do not publish these ports on a nonlocal interface.

## Role boundary

The migrations create three `NOLOGIN` capability roles and add empty Education/Identity schemas. The separate `provision-local-roles` action creates three local development logins with random passwords in ignored `.local-roles.env`. It repeats safely and verifies actual password connections and effective grants over container-local TCP. These credentials are for these isolated clusters only.

| Role | Database/schema rights | Table rights |
|---|---|---|
| `phoenix_canonical_migrator` | Connect; usage and create in eight empty domain schemas; usage of ledger schema | Select and insert in migration ledger; no domain table rights until explicitly granted |
| `phoenix_canonical_app` | Connect; usage in eight empty domain schemas | None until explicitly granted in a reviewed migration |
| `phoenix_canonical_reader` | Connect; usage in eight empty domain schemas | None until explicitly granted in a reviewed migration |
| `phoenix_canonical_migrator_local` | Inherits only migrator capability | Ledger select/insert; domain schema create |
| `phoenix_canonical_app_local` | Inherits only app capability | No domain table rights or ledger access |
| `phoenix_canonical_reader_local` | Inherits only reader capability | No domain table rights or ledger access |
| `phoenix_bootstrap` | Local container superuser for setup, migration and synthetic tests | All; never an application connection |

The migration ledger is inaccessible to app and reader roles. Future tables must grant exact operations and enable RLS in their own reviewed migrations. The synthetic RLS probe checks family, advisor, and partner scope filtering with test-only labels inside a rolled-back transaction. Its session settings are caller-controlled and cannot serve as a production identity source. The Phase 2B protected-context probe instead ignores those caller settings and checks private context binding, scope, revocation and expiry; its binder is simulated by the test bootstrap role, so it also is not production authentication. The synthetic docs probe checks version overwrite, submitted-manifest edits and append, status reversion, version numbering, digest matching and pinned reuse. The contract-neutral probe checks source-qualified mapping refusal, UUIDv7 version rejection, Consent withdrawal on the next decision, expiry, evidence level and denial audit events. All probes roll back; they are not built business schemas or trusted session binding.

## Contract holds

Only empty domain schemas are created. `core.people`, `core.students`, family membership/guardianship, consent grants, document metadata/version, submission manifests, casework, and legacy ID mappings remain pending the reviewed contracts. Their access and integrity acceptance tests are therefore pending too. No old `006` migration is copied into this namespace.
