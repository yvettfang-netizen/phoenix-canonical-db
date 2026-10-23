# Tencent Isolated Canonical PostgreSQL Update — Execution Report V1.16

**Execution date:** 2026-10-23  
**Host:** `1.12.77.180` / `VM-0-15-ubuntu`  
**Deployment path:** `/home/ubuntu/phoenix-canonical-db-deploy`  
**Container:** `tencent-postgres-1`  
**Data volume:** `phoenix_canonical_pg16_data`  
**Database:** `phoenix_canonical_dev`  
**Boundary:** isolated non-production update; synthetic/empty data only

## Result

**TENCENT ISOLATED NON-PRODUCTION UPDATE = PASS**

**PRODUCTION DEPLOYMENT / CUTOVER = HOLD**

The existing empty Canonical PostgreSQL 16 database was upgraded in place from Migration `0006` to `0022`. No volume was deleted or reset.

## 1. Pre-update gates

| Gate | Result |
|---|---|
| Expected host, container and volume | PASS |
| Canonical container host port | none |
| Database before update | PG16.15 / ledger 6 |
| Domain rows before update | 0 |
| Session contexts / tickets | 0 / 0 |
| Upgrade preflight blockers | 0 |
| `.env` mode | 600 |
| Pinned image digest | `ca0bd484cb98…` |

The previous paused upload had left the dedicated backup password in `.env` out of sync with the role because its installation never ran. The role password was repaired through a protected bootstrap pgpass with password-statement logging disabled. The update backup was then created using the non-superuser backup role.

Verified pre-update backup:

- File: `phoenix_canonical_preupgrade_v116_20261023T030728Z.dump`
- SHA-256: `d3a162a043c052625117a8f310c7443cba1a07f724d126e4df1759cac0c84ee7`
- `pg_restore` entries: 299
- Dump, manifest and verification marker mode: 600

Two failed-attempt artifacts were preserved under `backups/failed-v116/`; neither has a manifest or verification marker and neither is eligible for restore selection.

## 2. Controlled payload update

- Full pre-update directory snapshot: `/home/ubuntu/phoenix-canonical-db-deploy.bak-v116-20261023T030820Z`.
- Initial migration/deployment payload source: local commit `7b620344af7f87b1a0d882c5f6ae251432440382`.
- Final operational payload source after backup-selector fixes: `273418911a9160a40e18959d3c6da038ad90277f`.
- Payload files: 36 tracked files.
- Final manifest SHA-256: `59ecec9c3ae16007c058a1e35b44e9af084374333129c4a05b6b60a1008425d6`.
- Every deployed payload file matched the final `git archive` manifest.
- `.env` was preserved and remained mode 600.
- No runtime credentials were read into evidence or passed through command-line `PGPASSWORD`.

## 3. Migration result

`install.sh` applied `0007`–`0022` atomically. A repeat run skipped every migration with checksum verification.

| Catalog | Result |
|---|---:|
| Migration ledger | 22 |
| Tables | 50 |
| RLS policies | 41 |
| Persistent domain rows | 0 |

No environment SERVICE principal was installed because no approved environment principal ID was configured. Management writes therefore remain fail-closed.

## 4. Authentication hardening

The initialized volume had two local `trust` rules. The HBA file was backed up inside the data volume, changed to SCRAM and reloaded.

- HBA before SHA-256: `45b68cd420caab6d19725857c309871880a66a4c195bcd7e1604e7c334b6be82`
- HBA after SHA-256: `7580c87d60bb8dcd34ff202ae2c11c2814f4488ed16b95406f985f36ee471991`
- Local trust rules after update: 0
- Socket connection without password: refused
- Reader, backup and binder socket login through protected pgpass: PASS

The first verification attempt exercised the rollback hook during an expected refusal and restored the original file. The test harness was corrected and the second execution completed with all actual HBA rules set to `scram-sha-256`.

## 5. Backup, restore and operations

Deployment backup:

- File: `phoenix_canonical_20261023T030949Z.dump`
- `pg_restore` entries: 867
- Manifest and verification marker created.

The first default restore drill selected the descriptive pre-update backup and correctly refused it because its ledger contained only six migrations. Backup selection was corrected in committed forward operational changes:

- `6a7634e` — select the newest regular runtime backup for restore drill.
- `2734189` — apply the same runtime/pre-upgrade separation to alert and retention selection.

The repeated restore drill selected the post-update backup and passed:

- ledger matched 22 migration files;
- 50 tables and 41 policies;
- families 0, audit rows 0;
- disposable restore network `none`, ports `{}`;
- elapsed time 4 seconds.

Operational checks:

- audit extraction hash chain: `CHAIN_OK`;
- alert check: 0 alerts;
- backup pruning: dry-run only, 0 candidates;
- disposable restore containers after drill: none.

## 6. Final runtime state

| Check | Result |
|---|---|
| PostgreSQL | 16.15 |
| Container health | healthy |
| Migration / table / policy | 22 / 50 / 41 |
| Domain rows | 0 |
| Host PostgreSQL port mapping | none |
| Canonical Docker network | internal |
| `.env` | mode 600 |
| HBA authentication | SCRAM for local and host rules |
| Audit chain | PASS |
| Alert check | PASS, 0 alerts |

## 7. Preserved boundaries and remaining work

- No production deployment or production cutover occurred.
- No real data or production credential was used.
- Host PostgreSQL, MySQL, Nginx, PM2, SSH, firewall, security groups and unrelated volumes were not changed.
- No Push, Merge or PR action occurred.
- The private remote branch remains behind the local reviewed payload.
- Application authentication, environment SERVICE/staff provisioning, real Operations synchronization and real application integration remain HOLD.

## 8. Evidence commit

Raw local and remote output is committed in `36cf9bc` under `canonical-db/evidence/v1.16-*`.

