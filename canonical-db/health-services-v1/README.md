# Health Services V1.0 — dependency gate

- Task: `PHOENIX-HEALTH-DB-EXTENSION-20261030`
- Date: 2026-10-30 (Asia/Shanghai)
- Status: **HOLD — prerequisite business DDL/mapping missing**
- Repository: `yvettfang-netizen/phoenix-canonical-db`
- Base branch: `codex/canonical-postgresql-phase1`
- Base commit: `48bb6c3ae18906f870ea9e8a717c03ebb2da34bd`

## Authorization and scope

The Founder task authorizes Health-specific extension design, development,
synthetic testing, an independent branch and a Draft PR. It supersedes the
earlier Health RESERVED restriction for that development scope. It does not
authorize a main/default-branch merge, production migration or production
deployment. The approved Health Compass questions and result logic stay intact.

This check is limited to the dependencies needed by that extension. It is not a
new global database audit. No production database was contacted and no catalog
result in this package is represented as production evidence.

## Verified repository evidence

The private repository was accessible with the local GitHub CLI account
`yvettfang-netizen`. At inspection, the requested baseline was also the default
branch, with exactly 25 migration files, `0001` through `0025`. Development is
isolated on `codex/health-services-v1`; the original application worktrees were
not changed.

| Required dependency | Evidence in baseline | Compatibility result |
|---|---|---|
| Family | `0003`, `core.families.family_id uuid` | Physical FK target exists; UUIDv7 rule must remain |
| Member / patient | `0003`, `core.people.person_id uuid`; no `member_id` | Person master exists; Member-to-Person equivalence is not approved by this package |
| Student | `0003`, `core.student_profiles.person_id` references Person | Exists; only use where the actual patient is a Student |
| Principal | `0003`, `auth.principals.principal_id`; extended by `0012`/`0022` | Reusable trusted identity; principal is not necessarily a Person |
| Lead | No `lead_id` or lead master DDL in `0001`–`0025` | Required nullable FK target missing |
| Service project | No `service_project_id` or service-project master DDL | Required FK target missing |
| Client, partner, deal, contract, payment | Requested masters/keys absent from the migration series | No verified FK mapping; Health must not create replacement masters |
| Canonical Task / Service Task | No generic task master in the migration series | Cannot yet determine whether a Health task extension is necessary |
| Guardian / capacity | `core.guardian_authorities`, `core.civil_capacity_history` | Mechanisms exist; Health authority vocabulary and applicability require explicit extension |
| Patient consent | Existing `consent.grants` covers approved non-Health purposes/classes | No existing patient/project/scope-specific Health grant |

`casework.cases` has a `case_id`, not a `service_project_id`. Its resource kinds
are Education Application and Identity Case. It is generic advisor collaboration,
not a verified substitute for the requested business service-project authority.
See [0004](../migrations/canonical/0004_casework_education_identity.sql) and the
[effective contract](../phase2-gate/CANONICAL_BUSINESS_CONTRACT_V1.0_EFFECTIVE.md).

The [effective D-8 decision](../release/v1.12/FOUNDER_DECISION_D8_V1.1_EFFECTIVE.md)
keeps Operations authoritative and stores entitlement references in Canonical.
Its financial-data boundary excludes amounts, payments and invoices from that
reference domain. The newer Founder task requires Canonical to remain the unique
operating master source; this requirement is not evidence that those physical
tables already exist. The missing physical business schema/approved bridge must be
identified; its existence cannot be inferred from the newer task wording.
Insurance-claim amounts are Health assistance metadata, never a replacement
payment ledger.

## Consequence

A Health migration satisfying the requested FKs cannot be implemented against
this baseline yet. Creating a second member/project/client/payment master, using
an unconstrained UUID, or treating Casework as the project master would defeat
the explicit reuse requirement. None is included.

No `0026` migration was created or reserved. The next available number must be
rechecked after the dependency is resolved. Existing migrations are byte-preserved.

## Reviewable preparation

- [Logical ERD and field dictionary](MODEL_AND_FIELD_DICTIONARY.md)
- [Security matrix and API mapping](SECURITY_AND_API_CONTRACT.md)
- [Synthetic acceptance and recovery plan](ACCEPTANCE_AND_RECOVERY.md)
- [Catalog-only probe](catalog_dependencies.sql), outside the migration directory

These are design candidates. They do not add tables, enable routes, create
consents, register identities or connect the website to storage. No Health
forward/rollback, RLS, API, integration or end-to-end test has passed yet.

## Evidence needed to resume

Supply the approved DDL location and commit for the member, service-project,
lead and task authorities, including PK types and family/patient ownership.
If those objects have different names, supply the approved mapping. A
schema-only catalog extract is sufficient; no database credentials, customer
records, medical content or backups are needed.

If that DDL exists only in another database, the technical direction must state
how the PostgreSQL FK requirement is met: ordinary PostgreSQL FKs cannot point
at a separate database. A reference-only integration is a different contract
and must be approved explicitly.

Until then: implementation HOLD; synthetic DB tests NOT RUN; production NOT
CONTACTED; default branch unchanged; no merge or deployment.
