# Phoenix Canonical PostgreSQL — Health Dependency Gate V2.0

**Task:** PHOENIX-CANONICAL-DB-V2-IMPLEMENTATION-20261030 / P4

**Date:** 2026-10-30

**Result:** **P4 HEALTH = HOLD**

**Remote review target:** private draft PR `yvettfang-netizen/phoenix-canonical-db#1`

## 1. Executive conclusion

Draft PR #1 remains correctly unmerged and must stay a design/dependency package. Enterprise V2 P1/P2 has now supplied three structural dependencies that were missing from its pinned base: Canonical Lead, Service Project and generic Service Task. This does **not** clear Health implementation.

The following business and security contracts remain absent or unapproved:

- the exact Patient-to-`core.people` semantic contract, including non-Student patients and capacity/proxy handling;
- Health-specific consent purposes, scopes, recipients, project/case binding and revocation behavior;
- Health document classification, private-object access, retention, legal hold and purge authority;
- the exact approved 14-question Health Compass source/version/digest and immutable response/result contract;
- controlled Lead conversion and Health Project/Task application commands;
- provider/institution verification ownership and Health operations roles;
- an approved Health Migration/acceptance instruction after these contracts are effective.

No Health Migration, table, RLS policy, runtime grant, seed, API route or data was created. No remote branch or PR state was changed.

## 2. Remote PR verification

GitHub private-repository metadata was checked on 2026-10-30:

| Property | Verified value |
|---|---|
| Repository | `yvettfang-netizen/phoenix-canonical-db` |
| PR | `#1` — `docs(health): HOLD canonical dependency gate and extension design` |
| State | `open` |
| Draft | `true` |
| Merged | `false` |
| Base | `codex/canonical-postgresql-phase1` at `48bb6c3ae18906f870ea9e8a717c03ebb2da34bd` |
| Head | `codex/health-services-v1` at `dc825d7799242f63bfcfbfbbc94bb475f76046b0` |
| Changed files | 6 documentation/catalog-probe files; no Health Migration |

Independent `git ls-remote` returned the same base, head and `refs/pull/1/head` SHAs. The PR package explicitly says static preparation only and Health implementation HOLD. Its catalog probe is outside the automatic Migration directory.

## 3. Dependency delta since the PR base

| PR #1 dependency | Current Enterprise V2 evidence | Gate result |
|---|---|---|
| Family authority | `core.families` and temporal `core.family_memberships`; 0026 preserves Person/Family/Student | Structurally available |
| Person/member/patient | `core.people(person_id)` exists; no approved rule says every Person is a Patient or that `member_id` may be silently renamed to `person_id` | **HOLD** |
| Lead | `crm.leads(lead_id)` in 0027, with optional verified Person/Family links and no name/phone/OpenID dedupe | Structurally available; Health conversion command HOLD |
| Service Project | `service.projects(service_project_id)` in 0028, scoped to Canonical Client/Family with `HEALTH` allowed as a domain | Structurally available; Health lifecycle command HOLD |
| Generic Task | `service.tasks(task_id)` in 0028, scoped to Service Project with the approved five task states | Structurally available; Health extension semantics HOLD |
| Party/Subject linkage | `service.project_parties` / `project_subjects` in 0028 and controlled APIs in 0029 | Candidate reusable boundary; Patient semantics HOLD |
| Consent | Existing `consent.grants` does not contain Health purposes or a named institution/project/case sharing contract | **HOLD** |
| Documents | Existing `docs.documents` classes are `GENERAL`, `EDUCATION`, `IDENTITY_SENSITIVE`; there is no approved Health class/retention/access contract | **HOLD** |
| Health Compass | PR evidence refers to a locally observed `health-navigation-v0.1-draft`; the exact approved 14-question source is not present in this Canonical repository | **HOLD / EVIDENCE_MISSING** |

Migration evidence:

| File | SHA-256 |
|---|---|
| `migrations/canonical/0003_core_consent_access.sql` | `7dc0c5060237fae9069915ba8a1ecc39323cf74ab8ea0d49dd832ef9d8330618` |
| `migrations/canonical/0027_crm_lead_deal_foundation.sql` | `81976bd7835a7ada6ab8d0e335ac751d3fd98432a53b0dc4d343c750456e78cc` |
| `migrations/canonical/0028_service_project_task_delivery.sql` | `b8ec5d270d34da8f24423771b362d1dd6d3aa6c6f3d78cbd61b12968ebf6e8a2` |
| `migrations/canonical/0029_service_party_milestone_delivery_api.sql` | `898079125502bd5406e64fe50744ea04fe846f519e26d00bd30fe4bbe695fb33` |

These files pass the current PG16/PG17 synthetic F10 and fresh-cluster restore suites on the Enterprise V2 branch. That evidence proves the shared primitives, not Health behavior.

## 4. Mandatory Health contract before executable DDL

The next Health decision package must bind the following without inventing new masters:

1. `patient_person_id` must reference `core.people(person_id)`. The contract must define who becomes a Patient and how family membership, civil capacity, guardian/proxy authority and patient self-access are evaluated at request time.
2. Health Projects must reference `service.projects` and use an exact Health-specific controlled creation/transition API. A Project reference never grants patient or document access.
3. Lead conversion must reference `crm.leads`; it must require explicit consultation authorization and must not derive a Patient or Client by name, phone, OpenID or questionnaire answer.
4. Health Tasks must extend/reference `service.tasks`; do not create a competing task master. Any Health-only category table must retain the canonical task owner, due time, state and immutable events.
5. Health consent must use exact, separate scopes for case read, document read, appointment coordination, translation, claims assistance and named-provider sharing. Family membership or advisor assignment alone is not consent.
6. Health documents require an approved `HEALTH_SENSITIVE` (or other final name) classification, purpose-bound authorization, private object keys, no public URLs, explicit retention periods, legal-hold interaction, purge role and fresh access decisions.
7. The 14-question Health Compass must be pinned by repository path, commit SHA, contract/version ID and SHA-256. The database must reject unknown question keys/values and must not turn navigation results into diagnosis, clinical risk, Lead or Project automatically.
8. Audit records must contain decision metadata only, never answers, document keys, medical text or payment/claim content.

## 5. Proposed release sequence after the HOLD is cleared

This sequence is a plan, not authorization to implement:

1. White Tiger governance review approves the Patient, consent, document, retention and external-recipient contract.
2. Founder binds the approved 14-question source digest and Health role/ownership register.
3. Rebase or retarget draft PR #1 onto the accepted Enterprise V2 P2 commit; keep it draft during conflict and dependency review.
4. Replace placeholder `MEMBER_AUTHORITY`, `LEAD_AUTHORITY`, `SERVICE_PROJECT_AUTHORITY` and `CANONICAL_TASK_AUTHORITY` with exact existing targets. Do not merge the design package as executable schema.
5. Allocate the then-current next Migration number only after refetching the private branch.
6. Implement forward-only Health DDL, fixed-search-path controlled functions, RLS, exact grants and synthetic fixtures.
7. Run PG16 and PG17 fresh/upgrade/repeat/drift/atomicity, split-LOGIN, cross-family/patient/project, consent-revocation, document-retention, audit-minimization and fresh-restore acceptance.
8. Keep production deployment and real data as a separate Founder gate.

## 6. Reproduction commands

```powershell
git ls-remote canonical-private refs/heads/codex/health-services-v1 refs/heads/codex/canonical-postgresql-phase1 refs/pull/1/head
rg -n -A 18 -B 4 'CREATE TABLE (core\.people|crm\.leads|service\.projects|service\.tasks)' canonical-db\migrations\canonical\0003_core_consent_access.sql canonical-db\migrations\canonical\0027_crm_lead_deal_foundation.sql canonical-db\migrations\canonical\0028_service_project_task_delivery.sql
Get-FileHash -Algorithm SHA256 canonical-db\migrations\canonical\0003_core_consent_access.sql,canonical-db\migrations\canonical\0027_crm_lead_deal_foundation.sql,canonical-db\migrations\canonical\0028_service_project_task_delivery.sql,canonical-db\migrations\canonical\0029_service_party_milestone_delivery_api.sql
```

## 7. Gate conclusion

- Lead / Service Project / generic Task structural dependency: **CLOSED on the Enterprise V2 branch**.
- Patient/Person semantic contract: **HOLD**.
- Health consent and document/retention contract: **HOLD**.
- Approved 14-question source digest: **HOLD / EVIDENCE_MISSING**.
- Draft PR #1: **OPEN, DRAFT, UNMERGED; keep as design evidence**.
- Health executable Migration and runtime: **NOT STARTED BY DESIGN**.
- Production connection, real data, deployment and merge: **NOT EXECUTED**.

Unique next action: approve the Health Patient/consent/document decision package together with the exact 14-question source digest; only then update PR #1 and allocate a Health Migration number.

`HANDOFF_REQUIRED: 白虎` — patient authority, minors/capacity, medical-data consent, recipient disclosure, retention/deletion and provider/claim governance require independent governance review before any Health implementation.
