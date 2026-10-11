# Phoenix Canonical PostgreSQL — isolated Phase 1 foundation

This directory is a new development database namespace. It does not connect to legacy databases, Feishu, D1, COS, or production. All data used by the supplied tests is synthetic; the first migration creates no customer rows or identity master tables.

## Layout

| Path | Purpose |
|---|---|
| `compose.yaml` | PostgreSQL 16 and optional PostgreSQL 17 compatibility service, loopback ports only |
| `migrations/canonical/0001_foundation.sql` | New `canonical_migrations` ledger, seven schemas, restricted capability roles |
| `scripts/db.ps1` | Initialization, migration, exact-name test reset, health, backup and restore test |
| `tests/foundation.sql` | Schema, role and repeat-migration checks |
| `PHASE1_REPORT.md` | Executed evidence and contract holds |

## Run locally when Docker is available

The script creates an ignored `.env` containing a random local bootstrap password on first use. Docker Compose data volumes are local to this project. Do not use production credentials or real records.

```powershell
pwsh -File ./scripts/db.ps1 -Action init -Version 16
pwsh -File ./scripts/db.ps1 -Action health -Version 16
pwsh -File ./scripts/db.ps1 -Action test -Version 16
pwsh -File ./scripts/db.ps1 -Action test -Version 17
pwsh -File ./scripts/db.ps1 -Action backup -Version 16
pwsh -File ./scripts/db.ps1 -Action restore-test -Version 16 -BackupPath ./backups/<actual-backup-file>.dump
```

`test` resets only `phoenix_canonical_test_16` or `phoenix_canonical_test_17`; `restore-test` resets only `phoenix_canonical_restore_test_16` or `_17`. The development database is never reset by those actions. `migrate` applies checksum-locked files in lexical order and checks applied file hashes on repeat runs. The SQL itself is transaction wrapped and repeat safe if interrupted before ledger registration.

The PostgreSQL 16 and 17 services listen on `127.0.0.1:55416` and `127.0.0.1:55417` respectively. Containers share only the Compose `internal` network. Do not publish these ports on a nonlocal interface.

## Role boundary

The migration creates three `NOLOGIN` capability roles. No application credentials are provisioned while identity and access contracts remain unresolved.

| Role | Database/schema rights | Table rights |
|---|---|---|
| `phoenix_canonical_migrator` | Connect to development database; usage and create in six domain schemas; usage of ledger schema | Select and insert in migration ledger; no domain table rights until explicitly granted |
| `phoenix_canonical_app` | Connect; usage in six domain schemas | None until explicitly granted in a reviewed migration |
| `phoenix_canonical_reader` | Connect; usage in six domain schemas | None until explicitly granted in a reviewed migration |
| `phoenix_bootstrap` | Local container superuser for setup, migration and synthetic tests | All; never an application connection |

The migration ledger is inaccessible to app and reader roles. Future login roles must be provisioned separately with reviewed credentials and grants. Future tables must grant exact operations and enable RLS in their own reviewed migrations.

## Contract holds

Only empty domain schemas are created. `core.people`, `core.students`, family membership/guardianship, consent grants, document metadata/version, submission manifests, casework, and legacy ID mappings remain pending the reviewed contracts. Their access and integrity acceptance tests are therefore pending too. No old `006` migration is copied into this namespace.
