# Phoenix Canonical PostgreSQL — Finance Data Authority Report V2.0

**Task:** PHOENIX-CANONICAL-DB-V2-IMPLEMENTATION-20261030 / P3

**Date:** 2026-10-30

**Scope:** authority and interface boundary only; no Finance Migration and no transaction migration

**Result:** **P3 FINANCE AUTHORITY DESIGN = CONDITIONAL PASS**

**Database implementation:** **HOLD** pending the missing authorities listed below

## 1. Decision

The existing Canonical PostgreSQL remains the authority for CRM commercial intent and service-delivery references, but it is **not** made the payment, refund, invoice, contract, settlement or General Ledger authority in this phase.

Current source evidence supports the following boundaries:

1. `crm.deals` is the Canonical commercial-intent record. Its amount is an estimate and is not a charged or settled amount.
2. `service.projects` is the Canonical delivery record. It deliberately has no `contract_id`, payment state or invoice state.
3. The Education Compass trusted server owns its current product catalogue, orders, verified provider events, refunds and report entitlements.
4. WeChat Pay is the external settlement fact source for its own transaction and refund results; the Education Compass server validates and records those provider facts.
5. Phoenix Operations remains the authority for cross-domain `EDUCATION_SERVICE`, `COURSE` and `ASKWISE` entitlement facts. Canonical `operations_ref` is a fail-closed reference boundary, not the originating transaction system.
6. There is no approved evidence for a universal Phoenix product catalogue, contract authority, invoice authority, settlement ledger, General Ledger or production deployment of any such system. Those authorities remain `EVIDENCE_MISSING`.

No transaction rows, real records or provider secrets were read or imported. No existing Migration was changed.

## 2. Evidence register

| Evidence | SHA-256 | What it proves | What it does not prove |
|---|---|---|---|
| `Phoenix Compass/education compass/server/migrations/001_initial_schema.sql` | `502ab6bed513978922fad8fd424d1c11281b07771e37ce056cf001a2674b35c9` | The Education Compass server schema defines `products`, `orders`, `entitlements`, `payment_events` and `refunds`. | Production deployment, real transactions, company-wide Finance authority. |
| `Phoenix Compass/education compass/server/migrations/005_education_compass_levels.sql` | `1b398d9ffa3b85947a0814eeddf512c139af03e0560b385285c7f652afd40289` | Product/deliverable evolution remains in the application transaction boundary. | A universal product or accounting catalogue. |
| `Phoenix Compass/education compass/server/src/services/order-service.ts` | `8cff4d29b1b5bfb3ba1f2ba16f0a31699694d50c9c28fe84cb9bdc29f64e4609` | Provider verification, idempotent payment event handling, refund reconciliation and entitlement grant/revocation are implemented in that server boundary. | Live provider configuration or real-money acceptance. |
| `canonical-db/migrations/canonical/0021_operations_entitlement_reference.sql` | `adb8ec15e956c726e5717f9b19aebaae9d37ba4acece6a960729a204aa746d09` | Operations-origin entitlement references are source-qualified, versioned and fail closed; price/payment/invoice content is excluded. | Operations transaction tables or production synchronization. |
| `canonical-db/migrations/canonical/0027_crm_lead_deal_foundation.sql` | `81976bd7835a7ada6ab8d0e335ac751d3fd98432a53b0dc4d343c750456e78cc` | Canonical Deal stores commercial pipeline status and `NUMERIC(18,2)` estimated amount. | Payment, invoice, settlement or recognized revenue. |
| `canonical-db/migrations/canonical/0028_service_project_task_delivery.sql` | `b8ec5d270d34da8f24423771b362d1dd6d3aa6c6f3d78cbd61b12968ebf6e8a2` | Canonical Service Project references Client/Family and optional Deal without inventing Finance contract authority. | Contract, receivable or payment authority. |

Repository text search found payment reconciliation only in the Education Compass server and no approved Canonical invoice, contract, settlement or General Ledger authority. Absence from this repository is recorded as `EVIDENCE_MISSING`, not proof that no external system exists.

## 3. Authority matrix

| Business fact | Current authority | Canonical treatment | Status |
|---|---|---|---|
| Lead, campaign and commercial source | Canonical `crm` | Authoritative | Implemented in 0027 |
| Deal pipeline and estimated value | Canonical `crm.deals` / `deal_items` | Authoritative commercial intent | Implemented in 0027 |
| Client service delivery | Canonical `service` | Authoritative project/task/deliverable record | Implemented in 0028–0029 |
| Education Compass product price and SKU | Education Compass trusted server catalogue | Reference only if a future approved interface requires it | Source implemented; production not proven |
| Education Compass order | Education Compass trusted server | Do not duplicate as a Canonical order | Source implemented; production not proven |
| WeChat payment/refund result | WeChat Pay, validated and recorded by the Education Compass server | Store only approved references/projections in a future integration, never raw secrets or callback bodies | External/live verification HOLD |
| Education Compass report entitlement | Education Compass trusted server | Do not replace with `operations_ref` unless an approved migration/authority transfer exists | Source implemented; production not proven |
| Cross-domain service/course/ASKWISE entitlement | Phoenix Operations | `operations_ref` source-qualified reference/cache | Canonical reference implemented; live sync HOLD |
| Contract | No approved authority found | No `contract_id` or contract table added | `EVIDENCE_MISSING` |
| Invoice / receivable | No approved authority found | No table added | `EVIDENCE_MISSING` |
| General Ledger / revenue recognition | No approved authority found | No table added | `EVIDENCE_MISSING` |
| Settlement and bank reconciliation | No approved authority found | No table added | `EVIDENCE_MISSING` |

## 4. Non-duplication rules

- A Deal becoming `WON` must not be interpreted as payment, settlement, entitlement or recognized revenue.
- A Service Project becoming `ACTIVE` or `COMPLETED` must not create a payment, invoice or contract fact.
- Canonical must not copy raw payment notification bodies, payment credentials, card/bank data or provider secrets.
- Canonical must not create an entitlement from an estimated Deal amount.
- `operations_ref` must remain a source-qualified, revocable reference and must not become an order/payment ledger.
- Application transaction tables must not be copied into Canonical merely to create a single database. Authority must follow the approved business system, not physical co-location.

## 5. Future interface design (not yet approved for implementation)

If Phoenix later approves a cross-system Finance projection, it should be additive and reference-only:

| Proposed concept | Minimum fields | Required controls |
|---|---|---|
| `finance_ref.product_reference` | `source_system`, external product ID, product kind, version, status | source/version uniqueness; no silent price overwrite |
| `finance_ref.transaction_reference` | source transaction ID, optional Deal/Client/Project references, amount/currency, provider state, occurred time, source version | append-only source events; idempotency; no credential/payload storage |
| `finance_ref.refund_reference` | source refund ID, source transaction ID, amount/currency, state, occurred time | monotonic state; source event evidence |
| `finance_ref.reconciliation_event` | source event ID, source system, comparison result, evidence digest, actor/time | immutable audit; fixed search path; no PUBLIC execution |

This design is intentionally not a Migration. Table names, source systems, retention, accounting treatment and access rights require an effective Finance authority decision.

## 6. HOLD and evidence gaps

| Gate | Required evidence/decision | Current state |
|---|---|---|
| FIN-1 Universal product catalogue | Named owner, source system, lifecycle and version contract | HOLD / `EVIDENCE_MISSING` |
| FIN-2 Contract authority | Named system, contract ID, amendment/cancellation rules and document retention | HOLD / `EVIDENCE_MISSING` |
| FIN-3 Invoice/receivable authority | Named system, numbering, tax/currency rules and reversal process | HOLD / `EVIDENCE_MISSING` |
| FIN-4 Settlement/GL authority | Named ledger, posting and reconciliation ownership, period close and correction rules | HOLD / `EVIDENCE_MISSING` |
| FIN-5 Application-to-Canonical references | Approved identifiers, events, service principal and fail/retry rules | HOLD |
| FIN-6 Production evidence | Deployment, backup/restore, provider verification and operational ownership | HOLD |

## 7. Reproduction commands

Run from the repository root:

```powershell
rg -n -A 42 -B 3 'CREATE TABLE IF NOT EXISTS (products|orders|entitlements|payment_events|refunds)' 'Phoenix Compass\education compass\server\migrations\001_initial_schema.sql'
rg -n -i --glob '!evidence/**' --glob '!backups/**' --glob '!runtime/**' '(invoice|general ledger|settlement|contract authority|payment authority|finance authority|reconciliation)' canonical-db 'Phoenix Compass\education compass\server'
Get-FileHash -Algorithm SHA256 'Phoenix Compass\education compass\server\migrations\001_initial_schema.sql','Phoenix Compass\education compass\server\migrations\005_education_compass_levels.sql','Phoenix Compass\education compass\server\src\services\order-service.ts','canonical-db\migrations\canonical\0021_operations_entitlement_reference.sql','canonical-db\migrations\canonical\0027_crm_lead_deal_foundation.sql','canonical-db\migrations\canonical\0028_service_project_task_delivery.sql'
```

## 8. Gate conclusion

- Authority/non-duplication design: **PASS**.
- Finance Migration: **HOLD** and intentionally absent.
- Transaction/data migration: **PROHIBITED IN THIS PHASE** and not executed.
- Production Finance claim: **NOT ESTABLISHED**.
- Unique next action: complete the P4 Health dependency gate without merging Health PR #1.

`HANDOFF_REQUIRED: 白虎` — review financial governance, payment/refund responsibility, retention, external-provider obligations and future accounting authority before any Finance Migration is authorized.
