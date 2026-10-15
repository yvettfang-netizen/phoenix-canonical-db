# Tencent Canonical PostgreSQL Deployment Execution Report

Date: 2026-10-14  
Host: `1.12.77.180`  
Deployment path: `/home/ubuntu/phoenix-canonical-db-deploy`

## Result

**PASS — isolated empty Canonical PostgreSQL deployment**

The database name was confirmed as `phoenix_canonical_dev`. No legacy data, customer data, Founder OS data, Feishu data, COS objects, or real identity files were imported.

## Runtime evidence

| Check | Result |
|---|---|
| OS | Ubuntu, Linux 6.8.0-124-generic, x86_64 |
| Docker | 29.1.3 |
| Docker Compose | 2.40.3 |
| PostgreSQL | 16.15 |
| Migration ledger | 6/6 applied; repeat run checksum verified |
| Business tables | 24 |
| RLS policies | 20 |
| Persistent domain rows | 0 rows reported by `pg_stat_user_tables` |
| Container | `tencent-postgres-1`, healthy |
| Host PostgreSQL exposure | Canonical container has no host port mapping; host `5432` remains `127.0.0.1` only |

The image reference is `mirror.ccs.tencentyun.com/library/postgres@sha256:ca0bd484cb98bf4b24eb1010e73fb3fcbd6714d240fbc1a10eea5b7dbecb641d`. The digest matches the locally tested PostgreSQL 16 image.

## Access and backup evidence

- `health.sh` passed using container-local Unix sockets and non-bootstrap runtime roles.
- `backup.sh` passed using `phoenix_canonical_backup_runtime`.
- The backup role is `LOGIN`, `NOSUPERUSER`, `BYPASSRLS`, and inherits `pg_read_all_data`; it has no password and is used only through the container-local socket.
- Backup artifact: `backups/phoenix_canonical_20261014T092721Z.dump`
- Backup SHA-256: `4d80b7504e0fea6849f84d012809dfe1633fd0dbd543fb58d0d8b348d9db9439`
- SHA-256 manifest matched the dump; `pg_restore -l` returned 299 directory entries.
- Dump and manifest permissions: `600`.

## Files and cleanup

The active deployment directory contains only the tracked migration and Tencent deployment files plus the required mode-600 `.env`. The prior interrupted upload had its `runtime/`, `backups/`, root `.env`, and `.local-roles.env` removed. No production database, website files, or existing local PostgreSQL service was modified.

## Remaining boundary

Application integration, real-data migration, legacy ID reconciliation, public deployment, and production cutover remain outside this isolated database deployment.
