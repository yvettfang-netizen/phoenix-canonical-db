# Migration 0022 Learning Core Readiness Audit V1.0

**Audit date:** 2026-10-21

**Scope:** local isolated design gate only

**Verdict:** **HOLD — engineering prerequisites are mostly ready, but the Learning source contract and permission decisions are not approved**

## 1. Current baseline

| Item | Actual state |
|---|---|
| Latest migration | `0021_operations_entitlement_reference.sql` |
| Local PG16/PG17 | Healthy; 21 ledger rows, 36 tables, 27 RLS policies |
| 0018 security dependency | CLOSED / PASS |
| 0019/0020 Education dependency | CLOSED / PASS for approved local scope |
| 0021 Operations entitlement dependency | CLOSED / PASS for approved local scope |
| Historical data | No import authorized or performed |
| Tencent task B | PAUSED |

## 2. Source audit

The four files under `release/learning-v2.0` are internally consistent candidate designs, but each states that it is design, proposed, not implemented, or blocked by unavailable source material. Their hashes are preserved in `evidence/v1.14_learning_repository_audit.txt`.

The current ChatGPT Project official Product Architecture and Enterprise Baseline include Phoenix Family OS student growth records at a high level. They do not define a product named 启明堂, a teacher or academic-operations role model, `LEARNING_RECORD`, ASKWISE, after-class cards, or the proposed Learning state machines. Raw keyword counts and source hashes are preserved in `evidence/v1.14_project_source_audit.txt`.

Therefore:

1. The high-level Family OS direction supports an internal student-growth data capability.
2. It does not approve the detailed Learning Core contract.
3. Migration 0022 must be described as an internal `learning` data domain. It must not introduce a new public brand or product line.
4. The candidate Learning V2.0 documents cannot be relabeled EFFECTIVE without Founder approval.

## 3. Reconciled obsolete blockers

| Earlier blocker | Current result |
|---|---|
| E-R6 / binder hardening | Closed by 0018 |
| Education foundation | Closed by 0019/0020 |
| Operations entitlement reference | Closed by 0021; Learning must reuse `operations_ref`, not create `learning.external_entitlement_ref` |
| ASKWISE dependency | Removed from 0022; ASKWISE remains a later independent migration |
| Legacy teacher assignments | Not needed for greenfield local work, but explicit no-migration approval is still required |
| `btree_gist` availability | Available as version 1.7 on both PG16 and PG17; not installed in development databases |

## 4. Current database gaps confirmed on PG16 and PG17

- Principal kinds are limited to `FAMILY`, `ADVISOR`, `CHANNEL`, and `SERVICE`.
- Context channels do not include `STAFF`.
- Consent purposes do not include `LEARNING_RECORD`.
- Consent data classes do not include `LEARNING`.
- Guardian scopes do not include `LEARNING`.
- No `learning` schema or Learning business table exists.

Raw outputs: `../../evidence/v1.14-0022-readiness-pg16.txt` and `../../evidence/v1.14-0022-readiness-pg17.txt`.

## 5. Decisions required before SQL

| Gate | Required decision | Recommended value in the decision form |
|---|---|---|
| L-1 | Product boundary | Internal Family OS support domain only; no new public product or brand |
| L-2 | Permission vocabulary | Add `TEACHER`, `SUPERVISOR`, `STAFF`, `LEARNING_RECORD`, `LEARNING` |
| L-3 | Purchase boundary | Course entitlement permits enrollment checks only and never creates Consent |
| L-4 | Teacher scope | Effective assignment to an OPEN/RUNNING class only |
| L-5 | Consent grantee | Individual teacher person for 0022; no synthetic institution person |
| L-6 | Publication | Teacher submits; supervisor publishes or retracts |
| L-7 | Sensitive reads | Controlled audited read functions; no direct table SELECT by runtime roles |
| L-8 | Legacy data | No migration or reuse of old teacher assignments |
| L-9 | ASKWISE / Founder OS | Excluded from 0022 |
| L-10 | Scheduling extension | Permit `btree_gist` for exclusion constraints |
| L-11 | Migration packaging | One forward migration `0022`; do not renumber later candidates in this batch |
| L-12 | Source authority | Approve the exact SHA-256 of the new Learning Core source contract |

## 6. Gate outcome

No Migration 0022 SQL was created or applied. This is required because the unresolved items change identity types, Consent meaning, teacher access, family visibility, and publication workflow.

Once the Founder signs `FOUNDER_DECISION_LEARNING_0022_V1.0.md` and approves the exact contract SHA-256, the execution instructions in `CODEX_INSTRUCTION_0022_AFTER_APPROVAL_V1.0.md` become actionable.
