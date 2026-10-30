# Phoenix Nova™ Canonical PostgreSQL V2.0 — Founder Delivery Pack

**Document status:** FOUNDER REVIEW / WRITABLE

**Prepared date:** 2026-10-30 (Asia/Shanghai)

**Execution owner:** Codex

**Database owner:** Jimson

**Formal decision owner:** Founder / 方琳媛

**Current engineering verdict:** `M0–M5 ENGINEERING = PASS`

**Governance acceptance:** `PENDING`

**Production and Tencent deployment:** `HOLD / NOT EXECUTED`

> This is the single Founder-facing index for the Canonical PostgreSQL governance
> baseline, six-milestone engineering delivery, GitHub evidence and acceptance
> actions. It does not itself authorize a merge, deployment, real-data import or
> production cutover.

## 1. Founder core judgment

The existing unique Phoenix Canonical PostgreSQL has been extended through six
forward-only milestones. No second Canonical database and no duplicate Person,
Family, Student, Principal, Client or document authority was created.

- PostgreSQL 16 and 17 full acceptance: **PASS**.
- Current local migration head: **0035**.
- Verified catalog: **35 migration files / 35 ledger rows / 92 tables / 83 RLS policies**.
- Fresh install, repeat execution, checksum drift refusal and forced atomic rollback: **PASS**.
- Split LOGIN, one-use context tickets, tenant isolation, RLS/ACL negative tests: **PASS**.
- Dedicated backup LOGIN, SHA-256 manifest verification and fresh-cluster restore: **PASS**.
- Test data: **synthetic only**.
- Six milestone pull requests: **DRAFT / OPEN / UNMERGED**.
- Tencent connection, real data, production secrets and production deployment: **NOT EXECUTED**.

## 2. Repository and authority map

| Purpose | Repository / path | Current status | Link |
|---|---|---|---|
| Primary engineering provenance | `phoenix-canonical-db/canonical-db/` | M0–M5 engineering complete on private branch | [Open private M5 branch](https://github.com/yvettfang-netizen/phoenix-canonical-db/tree/codex/canonical-v2-m5-service-delivery/canonical-db) |
| Target main-repository authority | `phoenix/database/canonical/` | Copied and reviewable; authority activates only after approved merge | [Open main-repository candidate](https://github.com/yvettfang-netizen/phoenix/tree/codex/canonical-postgresql-mainline-copy/database/canonical) |
| Governance documentation | `phoenix/docs/database/` | V1.0 baseline; predates M0–M5 and is supplemented by this pack | [Open governance directory](https://github.com/yvettfang-netizen/phoenix/tree/codex/canonical-postgresql-mainline-copy/docs/database) |

**Authority rule:** after the main-repository copy is reviewed and merged, all
new Phoenix Nova database work—including Health Compass—must enter
`phoenix/database/canonical/` through the next ordered forward migration. The
private repository remains audit provenance and must not become a competing
migration line.

## 3. Three governance deliveries

### 3.1 Database asset inventory

**Source:** [DATABASE_ASSET_INVENTORY_V1.0.md](https://github.com/yvettfang-netizen/phoenix/blob/6176621a79d6493dcb21da4901f0294b5c7c5929/docs/database/DATABASE_ASSET_INVENTORY_V1.0.md)

The V1.0 inventory records:

- local PostgreSQL 16 development and PostgreSQL 17 compatibility databases as
  active, isolated and synthetic-only;
- the private Canonical repository as provenance and the main-repository copy as
  the candidate future authority;
- Tencent PostgreSQL as isolated non-production and behind the local head;
- disposable F10/restore clusters and the mock object store as ephemeral;
- conflicting legacy `006`, legacy `phoenix_core`, Founder OS D1, Feishu, COS,
  real customer data and historical imports as non-authoritative or `HOLD`;
- no deletion authorization for historical dumps, manifests or unattributed
  Docker volumes.

**Current engineering delta:** the published V1.0 inventory was captured at the
0025 local head and Tencent 0022 evidence. The latest private engineering branch
is now 0035 with 92 tables and 83 RLS policies. Tencent remains untouched and
must not be represented as upgraded by this delivery.

### 3.2 GitHub cleanup inventory

**Source:** [GITHUB_CLEANUP_INVENTORY_V1.0.md](https://github.com/yvettfang-netizen/phoenix/blob/6176621a79d6493dcb21da4901f0294b5c7c5929/docs/database/GITHUB_CLEANUP_INVENTORY_V1.0.md)

The V1.0 cleanup inventory establishes:

- keep `phoenix:main`, the Canonical mainline-copy review branch, private
  Canonical provenance, every unmerged branch and all migration/audit evidence;
- five already-merged branch tips are archive candidates only after their final
  SHA and merge/PR reference are registered;
- no repository, branch, tag, release or evidence deletion is approved;
- private `phoenix-canonical-db` cannot be archived or deleted until the
  main-repository copy is merged, byte verification passes, build/test paths are
  switched, a final snapshot is tagged and Founder explicitly approves.

**Current engineering delta:** Draft PRs #2–#7 and their six branches are now
mandatory keep items until ordered review, acceptance and merge are complete.

### 3.3 Canonical database authority

**Source:** [CANONICAL_DATABASE_AUTHORITY_V1.0.md](https://github.com/yvettfang-netizen/phoenix/blob/6176621a79d6493dcb21da4901f0294b5c7c5929/docs/database/CANONICAL_DATABASE_AUTHORITY_V1.0.md)

The authority document establishes:

- Phoenix Canonical PostgreSQL is the only approved destination for new Phoenix
  Nova business data;
- new domains reuse Canonical Person, Family, membership, Consent, audit,
  document and integration boundaries;
- browser/client code never connects directly to PostgreSQL;
- changes require ordered checksum-locked migrations, separate binder/app
  credentials, one-use context tickets, RLS and audited principal/family scope;
- files remain in private object storage; Canonical stores approved metadata,
  immutable versions, manifests and retention state;
- missing identity, Consent, retention or business-contract facts fail closed.

**Health Compass boundary:** Health Compass must not create standalone Person,
Family, Guardian, Consent or document masters. Real Health persistence remains
`HOLD` until its data classification, minimum fields, Consent basis,
professional-access, retention, deletion and emergency rules are approved.

## 4. Six controlled milestones

| Milestone | Migration | Migration SHA-256 | Implementation commit | Draft PR | Engineering |
|---|---:|---|---|---|---|
| M0 Core Organization & Identity | 0030 | `c0559ba97ad9edeaa8cb6559b9d382030e27ef4c9a109e97ab7ea99c43eb2d2e` | [`666118b`](https://github.com/yvettfang-netizen/phoenix-canonical-db/commit/666118be95ae8e2c946498d6511c29f27b2ec949) | [#2](https://github.com/yvettfang-netizen/phoenix-canonical-db/pull/2) | PASS |
| M1 Client & Partner | 0031 | `a58d07ffd116a5890c46f6ca13c97034632b0905522ebdf1f464301746043936` | [`16bbb5c`](https://github.com/yvettfang-netizen/phoenix-canonical-db/commit/16bbb5ca404562510c7a3f48875f773318b53a53) | [#3](https://github.com/yvettfang-netizen/phoenix-canonical-db/pull/3) | PASS |
| M2 Lead & Acquisition | 0032 | `714ee075bde36d52545e6ae38afc61b3de2509b6f749f0ed31ba29805931047e` | [`b81500c`](https://github.com/yvettfang-netizen/phoenix-canonical-db/commit/b81500c82502e378391c24269192d5a07d150676) | [#4](https://github.com/yvettfang-netizen/phoenix-canonical-db/pull/4) | PASS |
| M3 Consultation & Deal | 0033 | `f4f08da18a5e4a39eaeeb13c3f1130fd83521fc2583d5394647fb886763a0320` | [`c966d2c`](https://github.com/yvettfang-netizen/phoenix-canonical-db/commit/c966d2c0ff5817db213fd5c2b866f56a616a3669) | [#5](https://github.com/yvettfang-netizen/phoenix-canonical-db/pull/5) | PASS |
| M4 Service Project | 0034 | `fa879f5088f12a1797dc9264e9b2e52c2b5ed75d7151bb2d088b0788df9a1895` | [`54f3888`](https://github.com/yvettfang-netizen/phoenix-canonical-db/commit/54f3888da3bd35f5c844821767a34b1e95d2801d) | [#6](https://github.com/yvettfang-netizen/phoenix-canonical-db/pull/6) | PASS |
| M5 Service Delivery | 0035 | `c25d5efb3ddecdd11b1fa45793061b992e8bcaee278e3e1e359f7ca6b510c631` | [`46368a8`](https://github.com/yvettfang-netizen/phoenix-canonical-db/commit/46368a8fd4cbec77c739b53f02aed4b0cff3eb0c) | [#7](https://github.com/yvettfang-netizen/phoenix-canonical-db/pull/7) | PASS |

Required merge order: **M0 → M1 → M2 → M3 → M4 → M5**.

Current private branch HEAD:
[`7e5f3b7f415e55b1f0fb8bd662adb60fc56a06a7`](https://github.com/yvettfang-netizen/phoenix-canonical-db/commit/7e5f3b7f415e55b1f0fb8bd662adb60fc56a06a7).

## 5. Core engineering deliveries

| Delivery | Content | GitHub evidence |
|---|---|---|
| Six-milestone execution report | Final verdict, milestone SHA/commit/PR chain, final catalog, HOLD and next action | [Open report](https://github.com/yvettfang-netizen/phoenix-canonical-db/blob/7e5f3b7f415e55b1f0fb8bd662adb60fc56a06a7/canonical-db/ENTERPRISE_DATABASE_V2_SIX_MILESTONES_EXECUTION_REPORT.md) |
| M5 Migration 0035 | Task transfer history, versioned milestone templates, exact document-version delivery, submit/review/accept lifecycle and immutable events | [Open SQL](https://github.com/yvettfang-netizen/phoenix-canonical-db/blob/7e5f3b7f415e55b1f0fb8bd662adb60fc56a06a7/canonical-db/migrations/canonical/0035_m5_service_delivery_governance.sql) |
| M5 execution report | Branch/base, implemented controls, engineering result and no-deployment boundary | [Open report](https://github.com/yvettfang-netizen/phoenix-canonical-db/blob/7e5f3b7f415e55b1f0fb8bd662adb60fc56a06a7/canonical-db/milestones/m5-service-delivery/MILESTONE_EXECUTION_REPORT.md) |
| M5 test report | PG16/17 fresh, upgrade, repeat, drift, rollback, split-login, lifecycle and restore matrix | [Open report](https://github.com/yvettfang-netizen/phoenix-canonical-db/blob/7e5f3b7f415e55b1f0fb8bd662adb60fc56a06a7/canonical-db/milestones/m5-service-delivery/TEST_REPORT.md) |
| M5 Founder acceptance | Eight acceptance checkboxes and merge authorization field | [Open acceptance](https://github.com/yvettfang-netizen/phoenix-canonical-db/blob/7e5f3b7f415e55b1f0fb8bd662adb60fc56a06a7/canonical-db/milestones/m5-service-delivery/FOUNDER_ACCEPTANCE.md) |
| M5 evidence directory | Raw synthetic PG16/17 F10, audit, database-ID and restore evidence | [Open evidence](https://github.com/yvettfang-netizen/phoenix-canonical-db/tree/7e5f3b7f415e55b1f0fb8bd662adb60fc56a06a7/canonical-db/evidence) |

### M5 implemented content

- Task transfer requires an active Project assignment and records immutable
  old/new assignee history.
- Milestone templates are versioned, domain-scoped and retire-only.
- New deliverables require an exact immutable `docs.document_versions` link.
- Submit, changes request, resubmit, review approval, acceptance and withdrawal
  are controlled and audited.
- Submitter, reviewer and acceptor separation is enforced.
- Legacy unversioned application entry points are revoked.
- The Service domain stores no document body, content, payload or blob.

## 6. Milestone delivery directories

Each directory contains Architecture, Data Dictionary, ERD, Migration Manifest,
Security Review, Test Report, Rollback/Recovery, Open Risks, Execution Report and
Founder Acceptance.

- [M0 delivery](https://github.com/yvettfang-netizen/phoenix-canonical-db/tree/7e5f3b7f415e55b1f0fb8bd662adb60fc56a06a7/canonical-db/milestones/m0-core-organization-identity)
- [M1 delivery](https://github.com/yvettfang-netizen/phoenix-canonical-db/tree/7e5f3b7f415e55b1f0fb8bd662adb60fc56a06a7/canonical-db/milestones/m1-client-partner)
- [M2 delivery](https://github.com/yvettfang-netizen/phoenix-canonical-db/tree/7e5f3b7f415e55b1f0fb8bd662adb60fc56a06a7/canonical-db/milestones/m2-lead-acquisition)
- [M3 delivery](https://github.com/yvettfang-netizen/phoenix-canonical-db/tree/7e5f3b7f415e55b1f0fb8bd662adb60fc56a06a7/canonical-db/milestones/m3-consultation-deal)
- [M4 delivery](https://github.com/yvettfang-netizen/phoenix-canonical-db/tree/7e5f3b7f415e55b1f0fb8bd662adb60fc56a06a7/canonical-db/milestones/m4-service-project)
- [M5 delivery](https://github.com/yvettfang-netizen/phoenix-canonical-db/tree/7e5f3b7f415e55b1f0fb8bd662adb60fc56a06a7/canonical-db/milestones/m5-service-delivery)

## 7. Current HOLD / PENDING

| Item | Status | Release condition |
|---|---|---|
| Founder acceptance of M0–M5 | PENDING | Sign the six `FOUNDER_ACCEPTANCE.md` files |
| Independent named reviewer approvals | PENDING | Obtain explicit 玄武 / 白虎 / 麒麟 conclusions; Codex review lenses are not independent signatures |
| Ordered merge of PRs #2–#7 | PENDING | Acceptance and required reviewer approvals present |
| Real milestone-template and deliverable-kind catalogues | HOLD | Approved production catalogue and owner |
| Real application integration, identities and data | HOLD | Approved application contract, identities, secrets and integration evidence |
| Tencent / production deployment | HOLD / NOT EXECUTED | Separate isolated-deployment and production-cutover approvals |
| Real data migration / legacy import | HOLD / NOT EXECUTED | Approved mapping contract, rehearsal and rollback plan |
| Supplied acceptance attachment tail | EVIDENCE HOLD | Obtain the missing source text; do not infer requirements |

## 8. Founder review and write-in

### 8.1 Required review

- [ ] I reviewed the three governance deliveries and the 0025 → 0035 delta.
- [ ] I reviewed the six Draft PRs and their mandatory merge order.
- [ ] I reviewed the PG16/PG17, RLS/ACL and fresh-restore evidence.
- [ ] I reviewed the HOLD items and confirm they are not production-complete.
- [ ] I reviewed each milestone's `FOUNDER_ACCEPTANCE.md`.

### 8.2 Founder decision

**Decision:** `APPROVE / CONDITIONAL / HOLD`

**Founder:** 方琳媛

**Date:** ____________________

**Conditions / required changes:**

> Founder notes:

### 8.3 Reviewer record

| Review role | Reviewer | Decision | Date | Evidence / conditions |
|---|---|---|---|---|
| Security / 玄武 |  | `PASS / CONDITIONAL / HOLD` |  |  |
| Data governance / 白虎 |  | `PASS / CONDITIONAL / HOLD` |  |  |
| Business / 麒麟 |  | `PASS / CONDITIONAL / HOLD` |  |  |
| Database owner / Jimson | Jimson | `ACCEPT / CONDITIONAL / HOLD` |  |  |

## 9. Unique next action

Review and sign M0–M5 `FOUNDER_ACCEPTANCE.md`, obtain the named reviewer
decisions, then merge Draft PRs #2 through #7 in order. Until that gate is
complete, keep Tencent, production deployment, real identities and real data on
`HOLD`.
