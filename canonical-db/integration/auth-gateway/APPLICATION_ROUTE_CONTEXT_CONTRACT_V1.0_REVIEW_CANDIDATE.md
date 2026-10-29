# Phoenix Canonical Application Route Context Contract V1.0

- **Status:** FOUNDER APPROVED FOR LOCAL IMPLEMENTATION / NOT DEPLOYED
- **Date:** 2026-10-28 (Asia/Shanghai)
- **Scope:** Application-side derivation of a Canonical `FAMILY` context from an already authenticated Phoenix Family OS request

Founder approved the five local implementation decisions in this file on 2026-10-28. This approval authorizes Migration `0023` and local synthetic verification only. It does not create real mappings or identity records, enable the HTTP routes, authorize Tencent deployment or authorize production use.

## 1. Verified application facts

1. The trusted server authenticates an opaque application session and returns a server-side user record.
2. New application user IDs use `usr_` plus a random non-personal identifier. They satisfy the selected first-party broker subject contract and may be used as the JWT `sub` without placing WeChat OpenID, UnionID, name or contact data in the token.
3. Application family and student IDs use `fam_` / `stu_` plus UUIDv4-derived text. They are not Canonical UUIDv7 values and must never be converted by identifier shape.
4. Canonical identity equivalence requires explicit reviewed mappings. Names, phone numbers, OpenID values and apparent identifier similarity are forbidden matching evidence.

## 2. Approved initial route allowlist

Only the following authenticated family-owned reads are approved for the local bridge:

| HTTP route | Canonical operation code | Family derivation |
|---|---|---|
| `GET /v1/me/family` | `FAMILY_PROFILE_READ` | Family row whose `user_id` equals the authenticated application user |
| `GET /v1/me/students` | `STUDENT_LIST_READ` | Family row whose `user_id` equals the authenticated application user |
| `GET /v1/me/students/:studentId` | `STUDENT_PROFILE_READ` | Student row → family row → authenticated application user ownership |

Every write, report, assessment, order, payment, refund, advisor, admin, webhook, worker and unknown route remains denied. Adding a route requires a reviewed contract update and negative ownership test. This approval does not authorize returning raw Canonical rows; HTTP wiring and response-field conversion still require isolated review.

## 3. Trusted derivation rules

1. `subjectId` is always the authenticated server user ID. A request body, query parameter or header cannot replace it.
2. The application family ID is always obtained from the trusted application Store after ownership checks. It is never accepted from a request body or query parameter.
3. `channel` is fixed to `FAMILY` for this allowlist. Admin roles cannot enter the family bridge.
4. The first-party broker issues the short-lived token internally. The token is not returned to the browser or mini program.
5. The binder-only atomic database function resolves and tickets the Canonical actor person UUIDv7 and family UUIDv7 for the exact application family ID. The application runtime may not supply either Canonical identifier.
6. Missing, mismatched, non-VERIFIED, disabled or expired mapping/context facts deny before app-pool use.
7. The app pool only redeems the one-use ticket, then clears the context and discards or safely releases the connection.

## 4. Approved mapping authority and identity process

1. The stable application source code is exactly `PHOENIX_FAMILY_OS`.
2. `integration.legacy_id_mappings` is the only Canonical family mapping authority; resolution accepts only exact source + `FAMILY` + legacy ID records in `VERIFIED` status.
3. Only the binder role may execute the SECURITY DEFINER atomic resolver/ticket function.
4. Real `auth.external_identities` records may be created or disabled only through the existing controlled SERVICE functions. Unknown identities are never auto-provisioned.
5. No real mapping or identity row is approved by this document. Each future real record needs its own evidence and operator trace.
6. The application runtime must not use an unsigned mapping file or duplicate identity authority.

Implemented local shape:

```text
issuer + usr_* subject + PHOENIX_FAMILY_OS + application family ID
  -> active external identity
  -> active FAMILY principal and actor person
  -> one VERIFIED family legacy mapping
  -> current family membership
  -> one-use ticket for principal + actor + canonical family + FAMILY channel
```

## 5. Local implementation evidence

Migration `0023` implements `auth.issue_application_family_context_ticket(...)`. The function fixes the source namespace internally, locks the matched identity/principal/mapping/membership rows during ticket issuance, returns no row for unresolved input, and grants execution only to `phoenix_canonical_context_binder`.

`server/src/auth/canonical-application-route-bridge.ts` implements the three-route allowlist, trusted Store ownership derivation, internal subject/token flow and default denial. It sends only the authenticated token and trusted application `fam_*` ID to the context gateway. It does not accept Canonical actor/family UUIDs. The context gateway uses one binder call and the existing app-pool ticket redemption/clear/discard flow.

Synthetic regression covers:

- the three read routes and cross-family ownership denial;
- active identity, FAMILY principal, VERIFIED mapping and current membership;
- wrong source, PENDING/REVOKED mapping, disabled identity and expired membership denial;
- separate binder/app LOGINs, one-use redemption and function ACLs;
- no automatic provisioning and no real records.

## 6. Decision and execution state

| Decision | Approved value | State |
|---|---|---|
| Stable application `source_system` | `PHOENIX_FAMILY_OS` | APPROVED / implemented locally in 0023 |
| Family mapping authority | `integration.legacy_id_mappings`, exact source + kind + legacy ID, `VERIFIED` only | APPROVED / resolver implemented; real record evidence remains HOLD |
| Atomic resolver | Binder-only active identity + FAMILY principal/person + VERIFIED mapping + current membership + ticket | APPROVED / implemented locally in 0023 |
| Initial route scope | The three read-only routes in section 2 | APPROVED locally / HTTP wiring and response mapping remain HOLD |
| External identity registration | Controlled SERVICE workflow, no automatic provisioning | APPROVED process / no real records created |

Until PG16/17 acceptance, application response mapping, real record evidence and an isolated end-to-end review are complete, `CANONICAL_CONTEXT_GATEWAY_ENABLED=false` remains mandatory.
