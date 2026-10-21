# Canonical Schema Actual Inventory V1.13

**Verified:** 2026-10-21, local PG16 and PG17 `phoenix_canonical_dev`  
**Evidence:** `evidence/v1.13-0021-local-migrate-pg16.txt`, `evidence/v1.13-0021-local-migrate-pg17.txt`, and the two full F10 outputs  
**Deployment status:** local isolated development only; Tencent task B remains paused.

## Catalog

| Item | Actual |
|---|---:|
| Canonical migrations | 21 (`0001`–`0021`) |
| Business tables | 36 |
| RLS policies | 27 |
| Operations entitlement rows in both development databases | 0 |

Migration 0021 adds:

- `operations_ref.entitlement_ref`
- `operations_ref.entitlement_event`

## Enforced boundaries

- Operations remains authoritative. Canonical stores source-qualified references and source-event metadata only.
- `source_system` is fixed to `phoenix_operations`; external reference identifiers are opaque and hidden from runtime readers.
- Product scopes `EDUCATION_SERVICE`, `COURSE`, and `ASKWISE` are independent. Course scope requires an exact course identifier.
- Only a SERVICE principal in an INTERNAL context with label `operations_entitlement_service` can register, revoke, or expire references through controlled functions.
- Missing, future, expired, mismatched, and revoked references deny access. There is no grace period.
- Revoked or naturally expired references cannot reactivate.
- Direct table DML is denied to application, binder, family, advisor, and partner connections.
- Entitlement operations cannot create or modify Consent.

## Migration hash

| Migration | SHA-256 |
|---|---|
| `0021_operations_entitlement_reference.sql` | `adb8ec15e956c726e5717f9b19aebaae9d37ba4acece6a960729a204aa746d09` |

