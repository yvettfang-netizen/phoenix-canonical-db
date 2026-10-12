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
| `PHASE1_REPORT.md` | Executed evidence and contract holds |
| `PHASE2A_EXECUTION_REPORT.md` | Executed Phase 2A empty-schema and mock-store results |
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
pwsh -File ./scripts/db.ps1 -Action backup -Version 16
pwsh -File ./scripts/db.ps1 -Action restore-test -Version 16 -BackupPath ./backups/<actual-backup-file>.dump
pwsh -File ./scripts/mock-object-store.ps1 -Action test
```

`test` resets only `phoenix_canonical_test_16` or `phoenix_canonical_test_17`; `restore-test` resets only `phoenix_canonical_restore_test_16` or `_17`. The development database is never reset by those actions. `migrate` applies checksum-locked files in lexical order and checks applied file hashes on repeat runs. The SQL itself is transaction wrapped and repeat safe if interrupted before ledger registration.

`restore-test` checks the current two-migration schema, so use a backup made after `0002` for that action. Earlier Phase 1 dumps remain historical snapshots.

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

The migration ledger is inaccessible to app and reader roles. Future tables must grant exact operations and enable RLS in their own reviewed migrations. The synthetic RLS probe checks family, advisor, and partner scope filtering with test-only labels inside a rolled-back transaction. It proves PostgreSQL RLS behavior in both engines, not approved business authorization: its session settings are caller-controlled and cannot serve as a production identity source. The synthetic docs probe checks version overwrite, submitted-manifest edits, version numbering and pinned references. It also rolls back, so it is not a built `docs` business schema.

## Contract holds

Only empty domain schemas are created. `core.people`, `core.students`, family membership/guardianship, consent grants, document metadata/version, submission manifests, casework, and legacy ID mappings remain pending the reviewed contracts. Their access and integrity acceptance tests are therefore pending too. No old `006` migration is copied into this namespace.
