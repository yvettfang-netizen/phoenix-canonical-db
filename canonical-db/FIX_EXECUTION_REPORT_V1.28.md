# Phoenix Canonical PostgreSQL — FIX EXECUTION REPORT V1.28

- **Execution completed:** 2026-10-30 (Asia/Shanghai)
- **Execution owner:** Codex
- **Scope:** Founder-approved FM-1–FM-8 controlled family-mapping lifecycle
- **Result:** `LOCAL 0024/0025 + PG16/PG17 FULL ACCEPTANCE = PASS`
- **Real registration / Tencent / production:** `NOT EXECUTED / HOLD`

## 1. Approval and boundary

Founder approval binds the unchanged decision draft:

- decision file SHA-256:
  `41dc44d03dd9ba6cdd6b5812d0b050e07445ac5db129f2693d304b29f9501475`;
- approval record:
  `phase2-gate/evidence/approved/FOUNDER_DECISION_FAMILY_MAPPING_MANAGEMENT_API_V1.0_APPROVAL.md`;
- approval-record SHA-256:
  `fbc2691c48317f6315cd559258424c76bb96c6f64b0f51a45a1f0aa9efa227a5`.

The approval authorizes local forward Migration and synthetic PG16/17 testing.
This execution did not create a real external identity, family mapping or
customer record. It did not connect to Tencent, deploy, use a production secret,
merge or create a PR.

## 2. Forward Migrations

| Migration | Purpose | SHA-256 |
|---|---|---|
| `0024_family_mapping_management_api.sql` | FM_V1 evidence-bound proposal, distinct verification, immediate revocation, explicit supersession, terminal immutability and exact ACLs | `992a9623e933b84f8e58db937450b0bb440e9aaf234ed204b72b7497e44c605f` |
| `0025_family_mapping_lock_hardening.sql` | Reject unauthorized app calls before acquiring the transaction serialization lock | `fbedd76cb36b6938c9a051ab3606146b9c097f529dee41a7d5cc1f12ee876aea` |

Migrations `0001`–`0023` were not changed. `0024` was preserved after it
entered the local ledger; the lock-order improvement was correctly delivered as
forward Migration `0025`, rather than rewriting an applied checksum.

## 3. Implemented mechanism

The database now provides these controlled SECURITY DEFINER entry points:

- `integration.propose_family_mapping(...)`;
- `integration.verify_family_mapping(uuid,uuid)`;
- `integration.revoke_family_mapping(uuid,uuid)`;
- `integration.supersede_family_mapping(uuid,uuid,uuid)`.

The mechanism enforces:

1. exact source `PHOENIX_FAMILY_OS` and entity kind `FAMILY`;
2. active INTERNAL SERVICE context bound to the target Canonical family;
3. request nonce equality with the trusted database context;
4. current Canonical family membership and UUIDv7 identifiers;
5. three opaque evidence references with SHA-256 digests;
6. proposer and verifier as distinct accountable SERVICE principals;
7. one current VERIFIED application family per Canonical family;
8. idempotent identical retries and audited collision/evidence-drift denial;
9. immediate access-reducing revocation without second approval;
10. explicit old-to-new supersession with immutable terminal history;
11. app function execution only; app, binder, reader and PUBLIC have no direct
    mapping-table DML;
12. authorization before the 0025 serialization lock.

No automatic identity reconciliation, name/phone/OpenID matching or real-record
bootstrap was added.

## 4. PG16 and PG17 acceptance

Commands:

```powershell
pwsh -NoLogo -NoProfile -File tests/f10_local_acceptance.ps1 -Version 16
pwsh -NoLogo -NoProfile -File tests/f10_local_acceptance.ps1 -Version 17
```

Both versions passed:

- clean application of 25 Migration files;
- repeat execution with checksum verification;
- extra/missing Migration refusal;
- all pre-existing Canonical acceptance suites;
- split app/binder LOGIN and one-use SERVICE tickets;
- proposal, exact idempotent retry and evidence-drift denial;
- wrong source/kind, missing family, expired membership and disabled SERVICE
  denial;
- same-principal verification denial and distinct-principal approval;
- 0023 resolver success only while the mapping is VERIFIED;
- immediate revoke and explicit supersession;
- app/binder/reader/PUBLIC privilege negatives and direct DML denial;
- terminal update/delete refusal;
- authorization-before-lock assertion for all four functions;
- migration drift refusal and forced atomic rollback;
- dedicated backup-role export and manifest digest check;
- restore to a new network-isolated PG16/PG17 cluster;
- post-restore ledger 25, tables 50 and RLS policies 41.

Raw evidence:

| Evidence | SHA-256 |
|---|---|
| `evidence/v1.28-0024-pwsh-f10-pg16.txt` | `294c226911a48588b560598f24d05797be322e48b51d74462f5bbdfef9d9e70e` |
| `evidence/v1.28-0024-pwsh-f10-pg17.txt` | `1c95006db552cce4f32b39e67da0eeaa7ee9e5c273afbd5dd14ee9b8d995afbc` |
| `evidence/v1.28-0024-pwsh-audit-log-pg16.txt` | `5bfaba93aa414afd16e5bb3d692dd15c549ba82277e121109d3b1a6c8d68c109` |
| `evidence/v1.28-0024-pwsh-audit-log-pg17.txt` | `af3460dfcbd4208b75e74d40f6f1c8ffa9d67c1e34744e5568c08193caf41095` |
| `evidence/v1.28-0024-pwsh-audit-db-ids-pg16.txt` | `5b3979bff16070195a1a3e69bbe4a1f2371591f53b3fa0fd411cb3cb3430e17f` |
| `evidence/v1.28-0024-pwsh-audit-db-ids-pg17.txt` | `7f26b4c73561d5f5657cf346095c4d966b41623edcc45406fb6b5ab0d0b3ecd9` |
| `evidence/v1.28-0024-pwsh-audit-reconcile-pg16.txt` | `259f0ce4f247b24088261da8279bb1c4dcf26516c6470555914d660f6d57256a` |
| `evidence/v1.28-0024-pwsh-audit-reconcile-pg17.txt` | `26f9bc2a435682898f09c2ef3a1cbe717adeefe1a4744be6fd926d53511b8b84` |

Permanent test hashes:

- `f10_v28_0024_family_mapping_management.sh`:
  `5a3776df9ed6f5ea81b93e660ba665a89db49fc764225ec099af8635dd6ef342`;
- `f10_v28_0024_restore_regression.sql`:
  `8e06eab5b54b5b8ca66327b5f59ccb198a3c67f3efa297fe9222d07e31dd2968`.

## 5. Local development database state

After applying `0024` and forward hardening `0025`, both isolated local
development databases returned the same read-only catalog result:

```text
ledger=25
mapping_rows=0
external_identity_rows=0
managed_rows=0
management_functions=4
authorization_before_lock=4
tables=50
policies=41
```

This distinguishes implemented capability from data state: the API exists and
has been tested, but no real or synthetic business record remains in either
local development database.

## 6. Security assessment

| Severity | Finding | Result |
|---|---|---|
| Critical | None established | PASS |
| High | None established | PASS |
| Medium | An early 0024 draft acquired a global mapping lock before validating the caller | CLOSED by forward 0025 and permanent PG16/17 assertion |
| Low / operational | Filled mapping packets are pseudonymous linkage evidence and require controlled retention outside Git | HOLD for governance |

Identity, authn context, authz, least privilege, tenant/family isolation, secret
handling, PII minimization, auditability, abuse paths, rollback, terminal history
and negative tests were reviewed. The database layer is fail-closed. Gateway
rate limits, human operator/reviewer provisioning and evidence retention remain
application/governance responsibilities.

`HANDOFF_REQUIRED: 白虎` remains for privacy, retention, operator accountability
and approval-record governance before the first filled real packet.

## 7. Commit and synchronization state

Implementation and raw-evidence commit:
`c9da0555cbe44331b9614b342ca54b2030a609b8`.

The final report commit and private-branch synchronization are recorded in the
handoff after this file is committed. Public `origin` is not used.

## 8. Current gate and unique next action

Current result:

- controlled family-mapping database capability: **PASS**;
- PG16/PG17 compatibility and fresh-cluster recovery: **PASS**;
- local development databases at ledger 25 with zero mappings: **PASS**;
- first real identity/family mapping: **HOLD**;
- Tencent update and production switch: **HOLD / not authorized by this gate**.

**Unique next action:** prepare the first filled request outside Git with exact
application-ownership, Canonical-membership and Founder-approval evidence
digests; assign distinct accountable proposer and verifier; complete the 白虎
privacy/retention gate. A later explicit change-window authorization is still
required before executing any real registration.

