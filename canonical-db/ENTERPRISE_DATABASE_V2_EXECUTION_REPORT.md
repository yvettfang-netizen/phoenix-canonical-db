# Phoenix Canonical PostgreSQL — Enterprise Database V2.0 Execution Report

**Task:** PHOENIX-CANONICAL-DB-V2-IMPLEMENTATION-20261030

**Date:** 2026-10-30

**Feature branch:** `codex/canonical-enterprise-v2-core`

**Pinned baseline:** `48bb6c3ae18906f870ea9e8a717c03ebb2da34bd`

**Overall result:** **CONDITIONAL PASS**

## 1. Delivered scope

| Phase | Actual delivery | Commit | Result |
|---|---|---|---|
| P0 Core | Temporal Family membership history, canonical Organization and family-mapped Client | `e5d2b6efd974a3ddfac4b4c426ce5a5e9248b7b5` | PASS |
| P1 CRM | Campaign/source, Lead and identity-resolution lifecycle, Consultation/relationship/Deal/item/referral/follow-up foundation | `13a705fcf808945e91cdf294d69dc707ad7539b7` | PASS; some runtime commands remain fail-closed |
| P2 Service | Service Project, Party, Subject, Domain, Assignment, Task, Event, Milestone and Deliverable authority | `0b8284d0378952304ff6d10dcc42f6aca5c3f285` | PASS |
| P3 Finance | Authority/non-duplication audit; no Finance Migration or transaction migration | `c41a23bdb50126f41436816cecb18e9896153bdd` | CONDITIONAL PASS / implementation HOLD |
| P4 Health | Remote draft PR and dependency-delta audit; no Health Migration | `cf9516db93af2e3108c2aee3414b0e1535e66b1e` | HOLD |

Existing migrations `0001`–`0025` were byte-preserved. All executable database changes are forward-only in `0026`–`0029`. No Person, Family, Student, Principal, Casework or Learning master was duplicated.

## 2. New Canonical Migrations

| Migration | SHA-256 | Purpose |
|---|---|---|
| `0026_enterprise_core_organization_client.sql` | `aad3a52829404e1259d89a9751471af7d0f1322af710d498bb2498c5be7119d5` | Organization, Client and non-overlapping temporal family membership |
| `0027_crm_lead_deal_foundation.sql` | `81976bd7835a7ada6ab8d0e335ac751d3fd98432a53b0dc4d343c750456e78cc` | CRM Lead/identity/Deal foundation and controlled APIs |
| `0028_service_project_task_delivery.sql` | `b8ec5d270d34da8f24423771b362d1dd6d3aa6c6f3d78cbd61b12968ebf6e8a2` | Service Project/Task/Delivery schema, policies and core APIs |
| `0029_service_party_milestone_delivery_api.sql` | `898079125502bd5406e64fe50744ea04fe846f519e26d00bd30fe4bbe695fb33` | Forward-only completion of Party/Milestone/Deliverable controlled APIs |

`0028` was not edited after it had been applied to the local development databases. The additional controlled API completion was delivered as forward Migration `0029`.

## 3. Executed database verification

PG16 and PG17 each passed the full synthetic F10 suite after `0029`, including:

- clean initialization through 29 checksum-locked migrations;
- repeat execution safety;
- extra/missing migration and checksum-drift rejection;
- atomic rollback;
- split LOGIN and one-time context-ticket tests;
- cross-family, wrong-service and direct-ACL denial;
- immutable history/event tests;
- backup manifest validation and fresh-cluster restore;
- Enterprise Core, CRM and Service positive/negative regression.

Final catalog after `0029`: **29 migrations, 73 tables, 64 RLS policies**.

| Evidence | SHA-256 |
|---|---|
| `evidence/v2.0-0029-pwsh-f10-pg16.txt` | `310dc74a8fba542b8cc2672150ea91ebd9b6833c608271d720d2935340585794` |
| `evidence/v2.0-0029-pwsh-f10-pg17.txt` | `7563489bd736f830bcaff0846c18f2741465dd4da8c2ea89ddb529613822144c` |

The existing local PG16 and PG17 development databases were migrated forward without reset. A final health check on 2026-10-30 showed both containers healthy and their local sockets accepting connections.

Detailed phase evidence:

- `ENTERPRISE_DATABASE_V2_P0_EXECUTION_REPORT.md`
- `ENTERPRISE_DATABASE_V2_P1_EXECUTION_REPORT.md`
- `ENTERPRISE_DATABASE_V2_P2_EXECUTION_REPORT.md`
- `FINANCE_DATA_AUTHORITY_REPORT_V2.0.md`
- `HEALTH_DEPENDENCY_GATE_V2.0.md`

## 4. Security and authority outcomes

- All new runtime access is fail-closed, RLS-backed and exposed through exact controlled functions.
- New SECURITY DEFINER functions use fixed search paths; PUBLIC execution is revoked.
- Direct app/reader/binder table mutation is not granted.
- Lead identity linking requires distinct verification and never deduplicates automatically by name, phone or OpenID.
- Project participation does not grant Person, document or family access.
- Service Subject remains a reference to canonical Person; it does not create a duplicate member/patient master.
- Finance application transactions remain with their existing source authority; `crm.deals` is not payment or revenue.
- Health remains unimplemented until Patient, consent, document/retention and questionnaire contracts are effective.

## 5. Explicitly not executed

- No real customer, family, student, identity, payment, medical or historical data.
- No legacy/Feishu/D1 migration.
- No production database or production secret connection.
- No Tencent server update or deployment.
- No volume reset or historical migration edit.
- No Finance or Health transaction schema.
- No merge, default-branch change or PR creation/merge.

## 6. Remaining HOLD

| Area | Missing effective input |
|---|---|
| CRM runtime completion | Exact commands and authorization for Consultation, Client Relationship, Referral and Follow-up mutations |
| Finance | Universal catalogue, contract, invoice/receivable, settlement/GL ownership and integration event contract |
| Health Patient | Exact `core.people` Patient semantics, capacity/proxy and family/project/case evaluation |
| Health Consent/Documents | Health scopes, recipients, retention, legal hold, purge and private-object serving contract |
| Health Compass | Approved 14-question repository path, commit, version and SHA-256 |
| Production | Real identity mappings, protected secrets, deployment/change plan and separate Founder release gate |

## 7. Release boundary

This branch is suitable for private engineering review and continued synthetic development. It is **not** a production-release approval. Finance and Health HOLDs do not invalidate P0–P2, but they prevent claiming the complete enterprise database as production-ready.

`HANDOFF_REQUIRED: 白虎` — independently review financial governance, Patient/medical-data consent, minors/capacity, provider disclosure, retention/deletion and production release boundaries.
