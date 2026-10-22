# Founder Decision Learning Core Migration 0022 V1.1

**Status:** EFFECTIVE FOR LOCAL MIGRATION 0022 DEVELOPMENT

**Effective date:** 2026-10-22

**Decision owner:** Founder

**Approved contract:** `../v1.14/LEARNING_CORE_SOURCE_CONTRACT_DRAFT_V1.0.md`

**Exact approved SHA-256:** `3a3c95d671dfd66c872ffb61c4855bb04eff6dabdb8a41f1c61a44f5ba43fc16`

## Effective decisions

1. Learning is an internal Phoenix Family OS and Education service-delivery data domain and creates no new public product or brand.
2. Add `TEACHER`, `SUPERVISOR`, `STAFF`, `LEARNING_RECORD`, the `LEARNING` data class and the `LEARNING` guardian scope.
3. Course entitlement permits enrollment validation only and never creates Consent.
4. Teacher access requires current Consent and an effective assignment to an OPEN or RUNNING class.
5. The Consent grantee is the individual teacher person; no synthetic institution person is created.
6. Teachers submit; supervisors publish and retract.
7. Sensitive reads use controlled audited functions; runtime roles receive no direct sensitive-table `SELECT`.
8. No old teacher assignments are migrated or reused.
9. Learning reuses `operations_ref`; no entitlement or order table is duplicated.
10. Migration 0022 may install `btree_gist` for scheduling exclusion constraints.
11. The approved scope is packaged as one forward Migration 0022; Migrations 0001–0021 remain byte-preserved.
12. ASKWISE, Founder OS summaries, real data, Tencent, Push, Merge and deployment remain out of scope.

Approval evidence is preserved in `evidence/FOUNDER_DECISION_LEARNING_0022_APPROVAL_2026-10-22.md`.
