# Founder Decision Learning Core Migration 0022 V1.0

**Status:** UNSIGNED / NOT EFFECTIVE

**Decision owner:** Founder

**Contract to approve:** `LEARNING_CORE_SOURCE_CONTRACT_DRAFT_V1.0.md`

**Exact SHA-256:** `3a3c95d671dfd66c872ffb61c4855bb04eff6dabdb8a41f1c61a44f5ba43fc16`

## Recommended decisions

| ID | Decision | Prefilled recommended value | Founder approval |
|---|---|---|---|
| L-1 | Product boundary | Internal Family OS and Education service-delivery domain; no new public product or brand | [ ] |
| L-2 | Identity vocabulary | Add TEACHER, SUPERVISOR, and STAFF | [ ] |
| L-3 | Consent vocabulary | Add LEARNING_RECORD, LEARNING data class, and LEARNING guardian scope | [ ] |
| L-4 | Purchase rule | Entitlement allows enrollment validation only; never creates Consent | [ ] |
| L-5 | Teacher scope | Current Consent plus effective assignment to an OPEN/RUNNING class | [ ] |
| L-6 | Consent grantee | Individual teacher person for 0022; no synthetic institution person | [ ] |
| L-7 | Publication | Teacher submits; supervisor publishes and retracts | [ ] |
| L-8 | Sensitive read audit | Controlled audited read functions; no direct sensitive-table SELECT | [ ] |
| L-9 | Legacy data | Do not migrate or reuse old teacher assignments | [ ] |
| L-10 | Operations dependency | Reuse `operations_ref`; do not duplicate entitlement or order tables | [ ] |
| L-11 | Technical dependency | Permit `btree_gist` installation in Migration 0022 | [ ] |
| L-12 | Packaging | One forward Migration 0022; 0001–0021 byte-preserved | [ ] |
| L-13 | Exclusions | ASKWISE, Founder OS summaries, real data, Tencent, Push, Merge, and deployment remain out of scope | [ ] |

## Signature

- Approver: ____________________
- Decision: approve all prefilled values / approve with listed changes / reject
- Changes: ____________________
- Date, time, timezone: ____________________
- Typed signature: ____________________

Approval must identify the exact contract SHA-256. A generic continuation message does not change this file to EFFECTIVE.
