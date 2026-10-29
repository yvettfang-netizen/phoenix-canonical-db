# Phoenix Canonical PostgreSQL — FIX EXECUTION REPORT V1.27

- **Execution date:** 2026-10-29 (Asia/Shanghai)
- **Execution owner:** Codex
- **Scope:** prepare the first real application identity + family mapping registration package without creating a real record
- **Result:** `RUNBOOK + INTAKE VALIDATOR PASS / REAL REGISTRATION HOLD`

## 1. Boundary confirmation

- Work remained on `codex/canonical-postgresql-phase1`.
- No Migration was created or modified; `0001`–`0023` remain unchanged.
- No real identity, family, student, mapping, customer field or credential was read, written or printed.
- No Tencent connection, deployment, restart, runtime enablement, production switch, merge or PR occurred.
- The only database checks were read-only catalog/count queries against the existing isolated local PG16/17 development databases.

## 2. Delivered controlled registration package

| Artifact | Purpose | Result |
|---|---|---|
| `REAL_APPLICATION_IDENTITY_FAMILY_MAPPING_RUNBOOK_V1.0.md` | Per-record evidence, preflight, abort, intended registration, verification and rollback sequence | READY / execution HOLD |
| `REAL_APPLICATION_MAPPING_REQUEST_TEMPLATE_V1.0.json` | Fillable private evidence packet; contains no secret/customer-content field | READY |
| `validate_application_mapping_request.ps1` | Offline exact-schema, ID, issuer/source, evidence-digest, change-window and no-execution gate | PASS |
| `application-mapping-request.synthetic.json` | Synthetic positive fixture only | PASS |
| `FOUNDER_DECISION_FAMILY_MAPPING_MANAGEMENT_API_V1.0.md` | Prefilled FM-1–FM-8 forward-API decisions | DRAFT / Founder decision required |

The filled real request must stay outside Git in the approved private evidence system. Validator PASS proves structure only; it never sets `execution_authorized=true` and never contacts a database.

## 3. Validator regression

The synthetic packet passed. Seven negative cases were rejected:

1. execution authorization set to true;
2. wrong issuer;
3. non-UUIDv7 Canonical family ID;
4. missing Founder-approval digest;
5. unexpected OpenID field;
6. direct-table-write acknowledgement disabled;
7. change window longer than 60 minutes.

Raw evidence: `evidence/v1.27-mapping-request-validator.txt`
SHA-256: `f6af2d57cdfc10c3cae2a3d671eb9a5acfffe80614355bacabf839ff24daa772`.

## 4. PG16 / PG17 mapping-control catalog audit

Both existing isolated development databases reported:

| Check | PG16 | PG17 |
|---|---:|---:|
| Migration ledger | 23 | 23 |
| `integration.legacy_id_mappings` rows | 0 | 0 |
| `auth.external_identities` rows | 0 | 0 |
| app/binder/PUBLIC mapping table DML | false / false / false | false / false / false |
| controlled external identity register/disable | available | available |
| controlled family mapping functions | 0 | 0 |

Raw evidence:

- `evidence/v1.27-pg16-mapping-control-catalog.txt` — SHA-256 `7d338bceab719d932f54ed676b4d37a36bc5076e76ee4e1a1a9e7c0151227b21`
- `evidence/v1.27-pg17-mapping-control-catalog.txt` — SHA-256 `a844a054f327fc01ecaf1fc037114cf43b831a44bf47406427e216b8f87d11e9`

This proves the current design fails closed: runtime roles cannot directly write mappings. It also proves the full registration/rollback workflow is not yet executable because controlled family mapping create/revoke functions do not exist.

## 5. Security review

| Severity | Finding | Treatment |
|---|---|---|
| Critical / High | None established in the current fail-closed state | No change |
| Medium | Real family mapping creation and revocation would require prohibited privileged DML | Registration stays HOLD; forward management API decision prepared |
| Low / operational | A filled real request contains pseudonymous cross-system linkage | Must remain outside Git/logs; private evidence retention review required |

Identity, authorization, least privilege, tenant isolation, secret handling, PII, audit, rollback and negative-test boundaries were reviewed. `HANDOFF_REQUIRED: 白虎` applies to privacy, retention and accountable operator/reviewer governance for future filled real packets.

## 6. Artifact hashes

- Runbook: `48f2e224aff08b96f73c3dfaa4376efdcbc91ce5a3c861fa3f171a01094ec68b`
- Request template: `77c013b958e57862ccb785dd2912da8f064d550612f515c19726e28b0392d9b4`
- Offline validator: `a74dd8905766d0430e5c199c89638e8dca4772a6b39c9f720d5d9ee9dc9d7d73`
- Catalog audit script: `4c6ca3e7d5f87c1d67aa8fb652f3596dd7044519eb8625d2fd2577f3f6818894`
- Founder decision draft: `41dc44d03dd9ba6cdd6b5812d0b050e07445ac5db129f2693d304b29f9501475`

## 7. Current gate and unique next action

Current state:

- external identity controlled registration/disablement: technically available;
- family mapping controlled proposal/verification/revocation: absent;
- complete real registration and safe rollback: HOLD;
- filled real request: not created;
- Tencent and production: HOLD.

**Unique next action:** Founder reviews and approves or edits FM-1–FM-8 in `phase2-gate/FOUNDER_DECISION_FAMILY_MAPPING_MANAGEMENT_API_V1.0.md`, binding the final SHA-256. Only then may Codex implement a local forward Migration `0024` (or later) and PG16/17 synthetic tests. Approval does not authorize a real record or Tencent deployment.

## 8. Commit state

Implementation/evidence commit: `8630b2ad0bcdaf1bbcc7c1d0dbebf1ae75945b46`.

The report commit and private-branch synchronization are recorded in the final handoff. Public `origin` is not used.
