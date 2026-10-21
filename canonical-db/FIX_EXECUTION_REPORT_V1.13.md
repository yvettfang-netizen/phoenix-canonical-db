# FIX EXECUTION REPORT V1.13 — D-8 / Operations Entitlement Migration 0021

**Execution dates:** 2026-10-20 to 2026-10-21

**Scope:** local isolated PostgreSQL 16/17 only

**Result:** **PASS for the Founder-approved local D-8 / 0021 scope; source integration and production deployment remain HOLD**

**Implementation and evidence commit:** `656948152871bca329c7c8f0edb4e1cf4d469cb8`

## 1. Authorization and integrity

The Founder approval `批准，继续下一步` is preserved in `release/v1.12/evidence/FOUNDER_DECISION_D8_APPROVAL_2026-10-20.md`.

| Artifact | Verified SHA-256 |
|---|---|
| Approved D-8 contract draft | `7754ccf9f682973f0ee282090df9961760a3007493dee71d27d5dd6af6c7a784` |
| Effective D-8 decision | `3289c5ce78b2c3ffe1a51004a14c8952a3d0aa307fe83f765e928b2b56b52358` |
| `0021_operations_entitlement_reference.sql` | `adb8ec15e956c726e5717f9b19aebaae9d37ba4acece6a960729a204aa746d09` |

Migration files `0001`–`0020` were not modified. The Canonical migration directory contains exactly 21 SQL files.

## 2. Contract rule to implementation and evidence

| D-8 rule | Implemented control | Evidence |
|---|---|---|
| Operations remains authoritative | `operations_ref` stores source-qualified entitlement references and events; no price, payment, invoice, discount, commission, or contract content | Migration 0021 schema; full F10 catalog audit |
| Fixed source identity | `source_system='phoenix_operations'`; opaque trimmed external IDs; unique source/reference pair | 0021 checks and unique constraint; wrong-source and duplicate tests |
| Subject and family integrity | Person existence and live family membership are checked before registration | Cross-family denial in `f10_v22_0021_operations_entitlement.sh` |
| Product separation | Exact enum for `EDUCATION_SERVICE`, `COURSE`, `ASKWISE`; course ID required only for `COURSE` | Product mismatch, course, and ASKWISE regressions |
| Validity and fail closed | `[valid_from, valid_until)`; missing, future, expired, mismatched, and revoked checks deny; no grace | Valid, missing, future, expired, and revoked regressions |
| Terminal history | Trigger blocks identity/validity changes, deletes, reactivation, and event mutation | Reactivation and direct mutation denial regressions |
| Source delivery safety | Source event idempotency, conflict detection, strictly increasing source version, out-of-order denial | Duplicate, conflicting duplicate, and out-of-order regressions |
| Restricted source caller | Register, revoke, and expiry require SERVICE/INTERNAL plus exact label `operations_entitlement_service` | Separate LOGIN and wrong-label denial regressions |
| Runtime data minimization | Runtime APIs expose boolean and reason only; table reads and raw source IDs are not granted | ACL regression and access matrix V1.2 |
| Consent separation | Operations functions contain no Consent write; row count is unchanged in regression | Consent unchanged regression |
| RLS and minimal grants | Both new tables enable and force RLS; no runtime table DML; PUBLIC function execution revoked | Catalog audit, direct DML and PUBLIC ACL regressions |
| Audit | Controlled register, revoke, and check functions call the established audit decision APIs | F10 audit IDs, server audit log, and reconciliation evidence |

## 3. Executed commands

```powershell
pwsh -NoLogo -NoProfile -File ./tests/f10_local_acceptance.ps1 -Version 16
pwsh -NoLogo -NoProfile -File ./tests/f10_local_acceptance.ps1 -Version 17
pwsh -NoLogo -NoProfile -File ./scripts/db.ps1 -Action migrate -Version 16
pwsh -NoLogo -NoProfile -File ./scripts/db.ps1 -Action migrate -Version 17
pwsh -NoLogo -NoProfile -File ./scripts/db.ps1 -Action probe -Version 16
pwsh -NoLogo -NoProfile -File ./scripts/db.ps1 -Action probe -Version 17
```

The two local development services were resumed after Docker Desktop restarted. Their existing data volumes were retained. No database was reset or reinitialized.

## 4. Executed results

| Check | PG16 | PG17 |
|---|---|---|
| Fresh 0001–0021 migration; output includes `APPLIED 0021` | PASS | PASS |
| Processed files = directory files = ledger rows = 21 | PASS | PASS |
| Repeat migration and SHA verification | PASS | PASS |
| Extra/missing migration refusal | PASS | PASS |
| Checksum drift refusal | PASS | PASS |
| Forced atomic rollback | PASS | PASS |
| All historical F10 regressions | PASS | PASS |
| Separate LOGIN plus one-use ticket 0021 regression | PASS | PASS |
| Source, idempotency, ordering, tenant, product, validity, revocation, Consent, and ACL checks | PASS | PASS |
| Dedicated backup LOGIN and protected pgpass | PASS | PASS |
| Manifest digest verified before restore | PASS | PASS |
| Fresh-cluster restore and restored 0021 regression | PASS | PASS |
| Restored catalog | `ledger=21`, `tables=36`, `policies=27` | `ledger=21`, `tables=36`, `policies=27` |
| Disposable isolation | `network=none`, no ports | `network=none`, no ports |
| Disposable containers, volumes, and synthetic env files removed | PASS | PASS |
| Existing local development catalog | 21 / 36 / 27; Operations rows 0 | 21 / 36 / 27; Operations rows 0 |

PG16 backup SHA-256: `1ad319568e09251b16d7fadc826c28c0456fc4d68049ef505222b9cdca917afb`.

PG17 backup SHA-256: `815ac8c2ed2151b9de6f58251bb3c0aa4430afd2f6b193de2d53ef258c8860a3`.

## 5. Raw evidence

- `evidence/v1.13-0021-pwsh-f10-pg16.txt`
- `evidence/v1.13-0021-pwsh-f10-pg17.txt`
- `evidence/v1.13-0021-pwsh-audit-log-pg16.txt` and `pg17`
- `evidence/v1.13-0021-pwsh-audit-db-ids-pg16.txt` and `pg17`
- `evidence/v1.13-0021-pwsh-audit-reconcile-pg16.txt` and `pg17`
- `evidence/v1.13-0021-local-migrate-pg16.txt` and `pg17`
- `evidence/v1.13-0021-local-repeat-pg16.txt` and `pg17`
- `evidence/v1.13-0021-local-probe-pg16.txt` and `pg17`
- `evidence/v1.13-0021-local-catalog-pg16.txt` and `pg17`
- `evidence/v1.13-0021-static-validation.txt`

## 6. Remaining HOLD items

- Operations application authentication, environment-specific service principal provisioning, source endpoint, source retry worker, monitoring, and end-to-end 60-second SLO measurement remain HOLD.
- No Operations data, IDs, credentials, assets, or real records were read or imported.
- Migration 0022 Learning Core remains HOLD on D-3, D-5, and an approved source contract.
- Tencent task B remains PAUSED. The deployment scripts were only kept count-aware of `operations_ref`; none was executed and no Tencent connection occurred.
- No Push, Merge, PR state change, production deployment, or historical volume deletion occurred.

## 7. Phase decision

**D-8 / MIGRATION 0021 LOCAL FOUNDATION = PASS**

**PRODUCTION OPERATIONS INTEGRATION = HOLD**
