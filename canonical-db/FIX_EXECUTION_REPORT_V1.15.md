# FIX EXECUTION REPORT V1.15 — Learning Core Migration 0022

**Execution date:** 2026-10-22

**Scope:** Founder-approved local PostgreSQL 16/17 Migration 0022; synthetic data only

**Result:** **PASS for the approved local Learning 0022 scope; application integration, real data and production deployment remain HOLD**

**Implementation and raw evidence commit:** `c8c5a3aff14cde026417b07afd16adb91bd1dd53`

## 1. Authorization and integrity

The Founder approved every prefilled item in `FOUNDER_DECISION_LEARNING_0022_V1.0` and approved the exact source-contract SHA-256. The approval record is preserved under `release/v1.15/evidence/`.

| Artifact | Verified SHA-256 |
|---|---|
| `release/v1.14/LEARNING_CORE_SOURCE_CONTRACT_DRAFT_V1.0.md` | `3a3c95d671dfd66c872ffb61c4855bb04eff6dabdb8a41f1c61a44f5ba43fc16` |
| `migrations/canonical/0022_learning_core.sql` | `4df4b55cc9b2830c357d676906a77a9fa7ac981bbe4673c156285aa40fba2f5f` |

Migrations `0001`–`0021` were compared with `HEAD` before 0022 and remain byte-preserved. The Canonical migration directory contains exactly 22 numbered SQL files.

## 2. Implemented scope

Migration 0022 adds the internal `learning` domain with 14 tables:

- course and course version;
- teacher and class;
- enrollment, status history and class placement;
- teacher assignment and schedule slot;
- attendance and correction history;
- after-class card, publication and stage report.

The implementation also adds the approved `TEACHER`, `SUPERVISOR`, `STAFF`, `LEARNING_RECORD`, `LEARNING` data-class and guardian-scope vocabulary.

| Contract rule | Implemented control |
|---|---|
| Operations remains authoritative for entitlement | Enrollment calls `operations_ref.has_valid_entitlement`; no Learning entitlement/order copy exists |
| Entitlement does not create Consent | Regression asserts enrollment succeeds while Consent row count is unchanged |
| Teacher identity and channel | Teacher and supervisor principals must use `STAFF`; mismatched channel is rejected |
| Teacher access | Requires current assignment to an open/running class and current subject `LEARNING_RECORD` Consent |
| Family isolation | Controlled reads verify the bound family and subject; cross-family reads return zero |
| Publication separation | Teacher submits; supervisor publishes and retracts; teacher publication is denied |
| Scheduling | `btree_gist` exclusion prevents overlapping teacher assignments in time |
| History and terminal states | Append-only history, correction records and state guards block silent rewrite or reactivation |
| Runtime table access | Forced RLS on all 14 tables; app and reader receive no direct Learning table SELECT or DML |
| Controlled API | Signature-specific function grants, fixed `search_path`, PUBLIC execution revoked and audit decisions recorded |

## 3. Executed commands

The following command families were executed locally and their complete output is stored in `evidence/`:

```powershell
bash tests/f10_local_acceptance.sh 16 evidence/v1.15-0022-f10-pg16.txt
bash tests/f10_local_acceptance.sh 17 evidence/v1.15-0022-f10-pg17.txt
pwsh -NoProfile -File tests/f10_local_acceptance.ps1 -Version 16
pwsh -NoProfile -File tests/f10_local_acceptance.ps1 -Version 17
pwsh -NoProfile -File scripts/db.ps1 -Action migrate -Version 16
pwsh -NoProfile -File scripts/db.ps1 -Action migrate -Version 17
pwsh -NoProfile -File scripts/db.ps1 -Action health -Version 16
pwsh -NoProfile -File scripts/db.ps1 -Action health -Version 17
pwsh -NoProfile -File scripts/db.ps1 -Action probe -Version 16
pwsh -NoProfile -File scripts/db.ps1 -Action probe -Version 17
pwsh -NoProfile -File scripts/db.ps1 -Action audit-migration -Version 16
pwsh -NoProfile -File scripts/db.ps1 -Action audit-migration -Version 17
pwsh -NoProfile -File scripts/db.ps1 -Action audit-backup -Version 16
pwsh -NoProfile -File scripts/db.ps1 -Action audit-backup -Version 17
bash tests/deploy_package_rehearsal.sh <local-scratch> evidence/v1.15-0022-deploy-package-rehearsal.txt
```

The deployment-package command operated on a local scratch copy and disposable local containers. It made no Tencent connection and performed no deployment.

## 4. Acceptance results

| Check | PG16 | PG17 |
|---|---|---|
| Fresh 0001–0022 apply with `APPLIED 0022` | PASS | PASS |
| Processed files = directory files = ledger rows = 22 | PASS | PASS |
| Repeat migration and checksum verification | PASS | PASS |
| Missing, extra and unnumbered migration refusal | PASS | PASS |
| Applied migration drift refusal | PASS | PASS |
| Forced atomic rollback | PASS | PASS |
| All historical regressions | PASS | PASS |
| Separate SERVICE, TEACHER, SUPERVISOR and FAMILY LOGIN accounts | PASS | PASS |
| Separate binder plus one-use context tickets | PASS | PASS |
| Entitlement without implicit Consent | PASS | PASS |
| Assignment, schedule, attendance and publication rules | PASS | PASS |
| Cross-family, wrong-channel and direct-table denial | PASS | PASS |
| Audit catalog: app direct writes 0, PUBLIC executable controlled functions 0 | PASS | PASS |
| Dedicated backup LOGIN with protected pgpass | PASS | PASS |
| Manifest digest verified before restore | PASS | PASS |
| Fresh-cluster restore and restored 0022 regression | PASS | PASS |
| Restored catalog | 22 migrations / 50 tables / 41 policies | 22 migrations / 50 tables / 41 policies |
| Bash acceptance entry | PASS | PASS |
| PowerShell acceptance entry | PASS | PASS |

Disposable F10 backup SHA-256 values:

- PG16: `5dbda7d7ed8673a631fd1b1028a9deb7ad2034ce43083f54738dc7005246e333`
- PG17: `1bbb967c7de1702000e7867c1ce2f612a2b305ef66318121c817c84f582a6b8a`

## 5. Existing local development databases

Disposable PG16 and PG17 acceptance passed before the existing development volumes were touched. Migration 0022 was then applied forward to both existing `phoenix_canonical_dev` databases.

| Check | PG16 | PG17 |
|---|---|---|
| First forward run | `APPLIED 0022_learning_core.sql` | `APPLIED 0022_learning_core.sql` |
| Second run | `SKIP ... checksum verified` | `SKIP ... checksum verified` |
| Health | PASS | PASS |
| Transactional nondestructive probes | PASS | PASS |
| Migration atomicity and drift audit | PASS | PASS |
| Ledger / tables / policies | 22 / 50 / 41 | 22 / 50 / 41 |
| Learning tables / Learning rows | 14 / 0 | 14 / 0 |
| Actual backup and allowlisted restore test | PASS | PASS |
| Dump and manifest tamper refusal | PASS | PASS |

The local backup guard was corrected to count `learning` tables and to query the requested source database. It will not certify a synthetic-only backup when Learning contains rows.

## 6. Deployment-package local rehearsal

The count-aware Tencent package was exercised only as a local copy with the already pinned PostgreSQL 16 digest and disposable names. Results:

- install and repeat install: PASS;
- health: 22 migrations, 50 tables, 41 policies;
- runtime binder-ticket-to-app write: PASS;
- direct app table write denial: PASS;
- backup, manifest verification and fresh restore: PASS;
- retention dry run and apply: PASS on synthetic scratch backups;
- network-isolated restore drill: PASS;
- audit extraction, hash chain, alerts and tamper detection: PASS;
- failed role-statement password-log hardening: PASS.

No production `.env`, credential, server or data volume was used.

## 7. Raw evidence

- `evidence/v1.15-0022-f10-pg16.txt`, `evidence/v1.15-0022-f10-pg17.txt`
- `evidence/v1.15-0022-pwsh-f10-pg16.txt`, `evidence/v1.15-0022-pwsh-f10-pg17.txt`
- `evidence/v1.15-0022-pwsh-audit-log-pg16.txt`, `evidence/v1.15-0022-pwsh-audit-log-pg17.txt`
- `evidence/v1.15-0022-pwsh-audit-db-ids-pg16.txt`, `evidence/v1.15-0022-pwsh-audit-db-ids-pg17.txt`
- `evidence/v1.15-0022-pwsh-audit-reconcile-pg16.txt`, `evidence/v1.15-0022-pwsh-audit-reconcile-pg17.txt`
- `evidence/v1.15-0022-local-pg16.txt`, `evidence/v1.15-0022-local-pg17.txt`
- `evidence/v1.15-0022-local-zero-catalog-pg16.txt`, `evidence/v1.15-0022-local-zero-catalog-pg17.txt`
- `evidence/v1.15-0022-local-backup-audit-pg16.txt`, `evidence/v1.15-0022-local-backup-audit-pg17.txt`
- `evidence/v1.15-0022-local-backup-restore-pg16.txt`, `evidence/v1.15-0022-local-backup-restore-pg17.txt`
- `evidence/v1.15-0022-deploy-package-rehearsal.txt`
- `evidence/v1.15-0022-static-gates.txt`

## 8. Remaining HOLD items

- Learning application authentication, environment-specific staff/service principal provisioning and real credential handling remain HOLD.
- Real Operations entitlement synchronization and end-to-end operational acceptance remain HOLD.
- ASKWISE, Founder OS summaries and any Learning V2 expansion require separate approved source contracts and future forward migrations.
- No Learning, Operations, Founder OS, Feishu, customer or historical record was read or imported.
- Tencent task B remains PAUSED. No Tencent connection, update or deployment occurred.
- No Push, Merge, PR state change or historical Docker volume deletion occurred.

## 9. Phase decision

**LEARNING CORE MIGRATION 0022 LOCAL FOUNDATION = PASS**

**PRODUCTION LEARNING INTEGRATION AND DEPLOYMENT = HOLD**

