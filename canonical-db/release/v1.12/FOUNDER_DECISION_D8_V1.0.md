# Founder Decision D-8 — Operations Entitlement Reference V1.0

**Status:** UNSIGNED / HOLD  
**Contract to approve:** `OPERATIONS_ENTITLEMENT_REFERENCE_CONTRACT_DRAFT_V1.0.md`  
**Effect of approval:** Authorizes local Migration 0021 development and synthetic PG16/PG17 testing only. It does not authorize Operations data reuse, real data, Tencent deployment, application integration, push, merge or production cutover.

## 1. Recommended selections

Founder may approve the prefilled selections or edit them before signing.

### D8-1 Authority and owner

- [x] Operations remains the entitlement authority; Canonical stores references only.
- Accountable Operations owner: **[REQUIRED — name or role]**
- Incident owner: **[REQUIRED — name or role]**

### D8-2 Source identity

- Authoritative `source_system`: **[REQUIRED — stable code]**
- [x] Treat external entitlement IDs as opaque stable strings; do not infer business meaning or require a new prefix.
- [ ] Use this approved external ID format instead: **[describe and cite source]**
- [x] Enforce uniqueness by `(source_system, external_entitlement_id)`.

### D8-3 Interface

- [x] Operations SERVICE uses a controlled SECURITY DEFINER API with INTERNAL context; direct table writes are denied.
- Authenticating service principal / owner: **[REQUIRED]**
- [x] Require an idempotent `source_event_id` and at-least-once-safe processing.
- [x] Reject out-of-order events unless a newer source version is proven.

### D8-4 Validity and revocation

- [x] Valid only while `ACTIVE`, within `[valid_from, valid_until)`, not revoked, and scope matches.
- [x] No grace period in Canonical.
- [x] Revoked or naturally expired references cannot be reactivated; a new grant uses a new reference/version.
- Revocation delivery target: **[REQUIRED — recommended: within 60 seconds]**
- [x] Revocation affects the next authorization check after Canonical accepts the event.

### D8-5 Product and privacy boundaries

- [x] `EDUCATION_SERVICE`, `COURSE` and `ASKWISE` entitlements are independent.
- [x] Course purchase does not create Consent or grant learning-sensitive-data access.
- [x] Canonical stores no amount, payment, invoice, discount or commission data.
- [x] Initial family-facing access returns only a boolean decision and reason code; raw external order and entitlement IDs remain hidden.

## 2. Approval record

Approval is valid only when required fields are filled and the exact contract hash is recorded.

- Contract SHA-256: `7754ccf9f682973f0ee282090df9961760a3007493dee71d27d5dd6af6c7a784`
- Decision file SHA-256 before signature: **[fill after final edits]**
- Founder / approver: **[REQUIRED]**
- Role: Founder
- Date, time and timezone: **[REQUIRED]**
- Typed approval or signature: **[REQUIRED]**

Suggested typed approval:

> I approve Founder Decision D-8 V1.0 and the referenced Operations Entitlement Reference Contract with the completed required fields and recorded SHA-256 values. This approval authorizes local Migration 0021 development and synthetic testing only.

## 3. Stop conditions that remain after approval

- If the supplied source system or service principal does not exist in the approved authentication contract, implementation stops at the database interface boundary.
- No real Operations identifier or record is used in tests.
- No connection to Tencent and no deployment occur in this batch.
- Any later change to the signed contract requires a new version and hash; historical migrations remain immutable.

