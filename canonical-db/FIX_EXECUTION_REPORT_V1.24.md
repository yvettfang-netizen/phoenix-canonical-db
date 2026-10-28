# Phoenix Canonical PostgreSQL — FIX EXECUTION REPORT V1.24

- **Execution date:** 2026-10-28 (Asia/Shanghai)
- **Execution owner:** Codex
- **Scope:** local application route-context derivation candidate and synthetic tests
- **Result:** `PASS (LOCAL FAIL-CLOSED SKELETON) / HOLD (MAPPING AUTHORITY AND LIVE ROUTES)`

## 1. Boundary confirmation

- Work was performed only on `codex/canonical-postgresql-phase1`.
- No Tencent connection, deployment, process restart, production key, real identity, real mapping or real customer data was used.
- No Canonical Migration was added or modified.
- The new application route bridge is not wired to the HTTP handler or enabled runtime.
- The contract file is a review candidate and was not marked effective or approved.

## 2. Verified findings

1. Authenticated application users already have non-personal `usr_*` IDs that satisfy the selected broker subject shape.
2. Existing application `fam_*` and `stu_*` values are based on UUIDv4 text. They cannot be treated as Canonical UUIDv7 identifiers.
3. The existing Canonical schema requires explicit identity/mapping evidence; names, phone numbers, OpenID/UnionID and identifier shape cannot establish equivalence.
4. No approved runtime resolver currently converts an application family ID to the Canonical actor person and family UUIDv7 pair.

## 3. Implemented local controls

| Control | Result |
|---|---|
| Route allowlist | Only `GET /v1/me/family`, `GET /v1/me/students` and `GET /v1/me/students/:studentId` are represented |
| Subject derivation | Exact authenticated server `user.id`; client cannot supply or replace it |
| Family derivation | Trusted Store ownership; family ID is never accepted from body/query/header |
| Student ownership | Student → family → authenticated user; cross-family access denies before resolver/broker/gateway |
| Channel | Fixed to `FAMILY`; admin actors rejected |
| Token boundary | First-party token issued internally after mapping validation; never returned to the client |
| Mapping output | Exact application family match plus UUIDv7 actor/family required |
| Default behavior | Writes, unknown routes, missing mapping and malformed mapping deny before token issuance |

## 4. Synthetic verification

Complete command output is preserved in `evidence/v1.24-application-route-context.txt`.

| Command | Result |
|---|---|
| `npm.cmd run typecheck` | PASS |
| `node --test dist/tests/canonical-application-route-bridge.test.js` | PASS — 6/6 |
| `npm.cmd test` | PASS — 114/114 |
| `git diff --check` | PASS; only Windows checkout LF→CRLF notices |
| Migration diff check | PASS — no output |

## 5. Artifact integrity

| Artifact | SHA-256 |
|---|---|
| `server/src/auth/canonical-application-route-bridge.ts` | `29c017cb4b61f69f151cf90b29d6599f56ce3d1b376735c522e70e3a5a95a902` |
| `server/tests/canonical-application-route-bridge.test.ts` | `a1d687599235eb89a9bfa3c1ac2381933f0902d7a9fc6dc42fc242a996c4f2b0` |
| `integration/auth-gateway/APPLICATION_ROUTE_CONTEXT_CONTRACT_V1.0_REVIEW_CANDIDATE.md` | `f2385ac4727bf55249a58cabe35850841f864dd2cef599512b8f6774707460fc` |
| `evidence/v1.24-application-route-context.txt` | `5b9fa67a10ba7a22eefa0ab3741d2e5875f9eb045b42cb568ee8addea1422420` |

Implementation commit: `bb60f2228733791daf917c3561bbb9e399e5ffe2`.

## 6. Remaining decisions and HOLD

The following are not inferred from “continue” and remain Founder decisions:

1. approve the stable application `source_system` code (candidate: `PHOENIX_FAMILY_OS`);
2. approve `integration.legacy_id_mappings` as the family mapping authority and define who may set `VERIFIED`;
3. approve a binder-only atomic resolver for active identity + principal/person + verified family mapping + current membership;
4. approve the first live read-route scope and response-field mapping;
5. approve controlled creation/disablement of real `auth.external_identities` records.

Until those decisions are signed and isolated end-to-end tests pass, the bridge remains unwired and `CANONICAL_CONTEXT_GATEWAY_ENABLED=false` remains mandatory.

## 7. Gate conclusion

The application-side subject, ownership and route derivation boundary is now implemented and tested without fabricating Canonical IDs. Live identity/family mapping and route enablement remain correctly blocked.

**Unique next action:** Founder approval of the four decision rows in `APPLICATION_ROUTE_CONTEXT_CONTRACT_V1.0_REVIEW_CANDIDATE.md`, followed by a new forward Migration for the binder-only resolver; no deployment before its PG16/PG17 and isolated application review.
