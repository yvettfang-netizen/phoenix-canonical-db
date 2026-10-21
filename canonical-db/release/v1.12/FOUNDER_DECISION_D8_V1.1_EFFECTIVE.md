# Founder Decision D-8 — Operations Entitlement Reference V1.1

**Status:** EFFECTIVE FOR LOCAL MIGRATION 0021 DEVELOPMENT  
**Approved at:** 2026-10-20 15:25 +0800 (Asia/Shanghai)  
**Approval method:** Founder typed approval in the current session: `批准，继续下一步`  
**Approved contract:** `OPERATIONS_ENTITLEMENT_REFERENCE_CONTRACT_DRAFT_V1.0.md`  
**Contract SHA-256:** `7754ccf9f682973f0ee282090df9961760a3007493dee71d27d5dd6af6c7a784`

## 1. Effective decisions

| Decision | Effective value |
|---|---|
| Business authority | Operations remains authoritative; Canonical stores references only |
| Accountable owner | `Phoenix Nova Operations Owner` organizational role |
| Incident owner | `Phoenix Nova Operations Owner` organizational role for the local/synthetic stage |
| Source system | `phoenix_operations` |
| External ID | Opaque stable string; uniqueness is `(source_system, external_entitlement_id)` |
| Database caller | A SERVICE principal in an INTERNAL context with service label `operations_entitlement_service` |
| Interface | Controlled SECURITY DEFINER functions; direct table DML denied |
| Delivery | At-least-once safe; `source_event_id` idempotent; out-of-order source versions denied |
| Revocation target | Within 60 seconds from source decision to Canonical acceptance |
| Validity | `[valid_from, valid_until)`, no grace period; missing, future, expired and revoked fail closed |
| Terminal state | Revoked or naturally expired references cannot reactivate |
| Product separation | `EDUCATION_SERVICE`, `COURSE` and `ASKWISE` are independent |
| Consent | Entitlement never creates Consent or learning-sensitive-data access |
| Financial data | Amount, payment, invoice, discount and commission are excluded |
| Runtime visibility | Boolean decision and reason code only; raw external identifiers are hidden |

## 2. Approval boundary

This decision authorizes local Migration 0021 implementation, PG16/PG17 synthetic testing and fresh-cluster recovery testing.

It does not authorize:

- reuse or import of Operations data, IDs, credentials or assets;
- real customer or historical data;
- application production integration;
- Tencent connection or deployment;
- Push, Merge or PR state changes;
- production cutover.

## 3. Implementation note

The role names above are governance and service labels, not natural-person records or login secrets. Environment-specific principal UUIDs and credentials remain deployment inputs and are not stored in this decision.

