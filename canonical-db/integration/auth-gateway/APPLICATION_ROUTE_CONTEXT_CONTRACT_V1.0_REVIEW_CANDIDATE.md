# Phoenix Canonical Application Route Context Contract V1.0

- **Status:** REVIEW CANDIDATE / NOT EFFECTIVE / NOT DEPLOYED
- **Date:** 2026-10-28 (Asia/Shanghai)
- **Scope:** Application-side derivation of a Canonical `FAMILY` context from an already authenticated Phoenix Family OS request

This file records a fail-closed implementation candidate. It does not approve live mappings, create identity records, change the Canonical schema or authorize Tencent deployment.

## 1. Verified application facts

1. The trusted server authenticates an opaque application session and returns a server-side user record.
2. New application user IDs use `usr_` plus a random non-personal identifier. They satisfy the selected first-party broker subject contract and may be used as the JWT `sub` without placing WeChat OpenID, UnionID, name or contact data in the token.
3. Application family and student IDs use `fam_` / `stu_` plus UUIDv4-derived text. They are not Canonical UUIDv7 values and must never be converted by identifier shape.
4. Canonical identity equivalence requires explicit reviewed mappings. Names, phone numbers, OpenID values and apparent identifier similarity are forbidden matching evidence.

## 2. Initial route allowlist

Only the following authenticated family-owned reads are represented by the local bridge candidate:

| HTTP route | Canonical operation code | Family derivation |
|---|---|---|
| `GET /v1/me/family` | `FAMILY_PROFILE_READ` | Family row whose `user_id` equals the authenticated application user |
| `GET /v1/me/students` | `STUDENT_LIST_READ` | Family row whose `user_id` equals the authenticated application user |
| `GET /v1/me/students/:studentId` | `STUDENT_PROFILE_READ` | Student row → family row → authenticated application user ownership |

Every write, report, assessment, order, payment, refund, advisor, admin, webhook, worker and unknown route is denied by this candidate. Adding a route requires a reviewed contract update and a negative ownership test.

## 3. Trusted derivation rules

1. `subjectId` is always the authenticated server user ID. A request body, query parameter or header cannot replace it.
2. The application family ID is always obtained from the trusted application Store after ownership checks. It is never accepted from a request body or query parameter.
3. `channel` is fixed to `FAMILY` for this allowlist. Admin roles cannot enter the family bridge.
4. The first-party broker issues the short-lived token internally. The token is not returned to the browser or mini program.
5. A trusted mapping resolver must return both the Canonical actor person UUIDv7 and family UUIDv7 for the exact application family ID.
6. Missing, mismatched or malformed mappings deny before token issuance and before the app database pool is used.
7. The existing context gateway still resolves `issuer + subject` through `auth.external_identities`, issues/redeems the one-use ticket, verifies Canonical membership and clears/discards the connection.

## 4. Mapping authority gap

No approved runtime resolver currently maps an application `fam_*` identifier to a Canonical family UUIDv7. The current Canonical model contains `integration.legacy_id_mappings`, but a live resolver needs all of the following before a Migration or deployment may be created:

1. an approved stable `source_system` code for Phoenix Family OS application identifiers;
2. an approved process and evidence owner for moving mappings to `VERIFIED`;
3. a binder-only SECURITY DEFINER resolver that atomically checks active external identity, active principal/person, verified family mapping and current family membership;
4. exact read APIs and response-field mapping, because the application DTO and Canonical schema are not interchangeable;
5. reconciliation, disablement and incident procedures for stale or conflicting mappings.

Recommended technical shape for later review only:

```text
issuer + usr_* subject + source_system + application family ID
  -> active external identity
  -> active FAMILY principal and actor person
  -> one VERIFIED family legacy mapping
  -> current family membership
  -> principal_id + actor_person_id + canonical_family_id
```

The application runtime must not use an unsigned mapping file or duplicate identity authority merely to bypass this gate.

## 5. Local implementation evidence

`server/src/auth/canonical-application-route-bridge.ts` implements the three-route allowlist, trusted Store ownership derivation, internal subject/token flow, strict UUIDv7 output validation and default denial. It depends on an injected mapping resolver and is not wired into HTTP runtime because no approved resolver exists.

Synthetic regression proves:

- the three read routes are the only allowed routes;
- cross-family student access is rejected before resolver, broker or gateway use;
- admin and malformed users are rejected;
- missing, mismatched and UUIDv4 mappings are rejected before token issuance;
- successful synthetic context uses the server user as subject and fixes channel to `FAMILY`.

## 6. Founder decisions required before live work

| Decision | Recommended candidate | Current status |
|---|---|---|
| Stable application `source_system` | `PHOENIX_FAMILY_OS` | HOLD — not approved here |
| Family mapping authority | `integration.legacy_id_mappings`, exact source + kind + legacy ID, `VERIFIED` only | HOLD — process/owner required |
| Initial live route scope | The three read-only routes in section 2 | HOLD — response/API mapping review required |
| External identity registration | Controlled SERVICE workflow, no automatic provisioning | HOLD — real records and dual review required |

Until these decisions and an isolated end-to-end review are complete, `CANONICAL_CONTEXT_GATEWAY_ENABLED=false` remains mandatory.
