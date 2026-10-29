# Founder Decision — Family Mapping Management API V1.0

- **Status:** DRAFT / NOT APPROVED
- **Prepared:** 2026-10-29 (Asia/Shanghai)
- **Purpose:** close the fail-closed write/rollback gap before the first real `PHOENIX_FAMILY_OS` family mapping
- **Current database:** no real external identity or family mapping rows

No Migration or real record may be created from this draft until the Founder
approves the decisions below. Approval of this file authorizes a local forward
Migration and synthetic PG16/17 testing only unless deployment is separately
stated.

## Decisions requested

| ID | Recommended decision | Why it is recommended | Founder decision |
|---|---|---|---|
| FM-1 | Use a controlled lifecycle: `PENDING` proposal → `VERIFIED` approval → `REVOKED` or `SUPERSEDED`; never edit a terminal row back to active | Preserves history and makes rollback auditable | PENDING |
| FM-2 | Restrict create/verify/revoke functions to an INTERNAL SERVICE context through the existing app capability role; no PUBLIC, reader, binder or direct table DML | Reuses the established least-privilege runtime and keeps binder read/issue-only | PENDING |
| FM-3 | Require proposer and verifier to be distinct accountable principals for a real `VERIFIED` family mapping; synthetic tests may use test principals | Family equivalence grants cross-system access and deserves independent review even though V1.4 did not explicitly require it | PENDING |
| FM-4 | For `PHOENIX_FAMILY_OS` + `FAMILY`, allow only one current VERIFIED application family ID per Canonical family; changes require explicit supersession | Prevents silent many-to-one household merges | PENDING |
| FM-5 | Bind application-ownership, Canonical-membership and Founder-approval evidence references plus SHA-256 digests to the proposal; never store customer content in the mapping row or audit log | Makes the decision reproducible without copying PII | PENDING |
| FM-6 | Revocation is immediately executable by an authorized SERVICE operator and does not require a second approval; it only narrows access | Matches the existing access-reducing revocation rule | PENDING |
| FM-7 | Duplicate/retry with identical immutable inputs is idempotent; conflicting duplicate, wrong source/kind, inactive principal/family/membership or evidence drift is denied and audited | Supports safe operations and fail-closed retries | PENDING |
| FM-8 | Implement as forward Migration `0024` or later; do not modify `0001`–`0023` | Preserves the canonical ledger and reviewed history | PENDING |

## Required implementation after approval

The Migration must add the minimum proposal/verification attribution required by
the approved decisions, controlled SECURITY DEFINER functions, append-only
allow/deny audit with request nonce, revocation/supersession, exact grants and
transaction locking. It must not create any real mapping.

PG16 and PG17 acceptance must include:

- PENDING proposal, distinct-verifier promotion and exact 0023 resolver success;
- same-person approval denial if FM-3 is approved;
- duplicate, collision, evidence drift, wrong source/kind and inactive/expired
  principal/family/membership denial;
- app/binder/reader/PUBLIC privilege negatives and direct DML denial;
- immediate revoke, resolver denial after revoke and safe supersession;
- repeat migration, checksum drift, atomic rollback and fresh-cluster restore;
- zero real records and complete synthetic cleanup.

## Approval record

- Founder: 方琳媛
- Decision date/time: PENDING
- Approved IDs/values: PENDING
- File SHA-256 at approval: PENDING
- Scope: PENDING

**Until approved:** `REAL FAMILY MAPPING REGISTRATION = HOLD`.
