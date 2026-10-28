# Phoenix Canonical PostgreSQL — FIX EXECUTION REPORT V1.23

- **Execution date:** 2026-10-28 (Asia/Shanghai)
- **Execution owner:** Codex
- **Scope:** local application runtime and synthetic tests only
**Result:** `PASS (LOCAL IMPLEMENTATION) / HOLD (LIVE ENABLEMENT AND DEPLOYMENT)`

## 1. Boundary confirmation

- Work was performed only on `codex/canonical-postgresql-phase1`.
- No Tencent connection, remote command, deployment, process restart, production switch, real identity, real data or production key was used.
- No Migration was added or modified. `git diff --name-only -- canonical-db/migrations` returned no output.
- The runtime remains disabled by default and exposes no public token-issuance or Canonical database-operation route.

## 2. Implemented capability

| Item | Result | Implemented control |
|---|---|---|
| Split credentials and pools | PASS | Distinct `phoenix_canonical_app_runtime` and `phoenix_canonical_binder_runtime` pools; exact protected pgpass references; shared passwords rejected |
| Subject mapping | PASS | Only verified `usr_*` subjects are resolved by `auth.resolve_external_identity`; missing/disabled mappings deny; no auto-provisioning |
| One-use ticket bridge | PASS | Binder issues a 45-second ticket; app redeems it on the same connection used by the business transaction |
| Callback confinement | PASS | Business callbacks cannot issue transaction, role or `DISCARD` controls |
| Context cleanup | PASS | `auth.clear_context()` plus NULL-principal assertion before commit; `DISCARD ALL` before reuse; uncertainty destroys the connection |
| Protected audit | PASS | Append-only 0600 JSONL, durable sync, exact seven-field allowlist; no token, actor ID, family ID, database password or free-text PII |
| Fail-closed startup | PASS | Gateway requires broker and verifier flags, fixed 45-second ticket TTL, protected references and exact broker/verifier metadata |
| Application route | HOLD | The internal bridge is constructed but is not exposed by an HTTP route; actor/family/channel derivation still needs an approved application contract |

## 3. Synthetic verification

Commands and complete outputs are preserved in `evidence/v1.23-canonical-context-runtime.txt`.

| Command | Result |
|---|---|
| `npm.cmd run typecheck` | PASS |
| `node --test dist/tests/canonical-context-gateway.test.js` | PASS — 10/10 |
| `npm.cmd test` | PASS — 108/108 |
| `git diff --check` | PASS; only Windows checkout LF→CRLF notices were emitted |
| Migration diff check | PASS — no output |

The dedicated tests cover successful split-pool exchange, unmapped identity denial, non-`usr_*` redaction, forbidden transaction/role control, clear failure, audit failure, discard failure, exact minimal audit serialization, distinct runtime pool construction and shared-password refusal.

## 4. Artifact integrity

| Artifact | SHA-256 |
|---|---|
| `server/src/auth/canonical-context-gateway.ts` | `0d13a3d317ed8d6b3de19f3807bc3b0155b3752ce32c6192942122bd7b6b59b3` |
| `server/src/auth/canonical-context-runtime.ts` | `93f055ea0cc061a62d1fb3e07c3ec6c725030ebd011368e02d8b04f9bf320a40` |
| `server/tests/canonical-context-gateway.test.ts` | `3665f10486a4eb79be1755eca7cd99fd55b8e05b2783f2a6585747fcdace28dc` |
| `evidence/v1.23-canonical-context-runtime.txt` | `624deed3d04abb54515558544f1e6c081be2ed3e172ab98c7e729fe662b65771` |

Implementation commit: `7a80849b5404a784e6b9e075d0911299fa3f6407`.

## 5. Remaining HOLD

1. Real `usr_*` to Canonical principal records in `auth.external_identities`.
2. Approved application mapping for Canonical actor person, family and channel on each business operation.
3. Live broker/JWKS/token verification, explicit gateway enablement and protected audit-path operations.
4. Tencent update and any production deployment or production switch.

These are intentionally not inferred from the existing WeChat session or synthetic fixtures. Unknown identity and missing mapping continue to deny access.

## 6. Gate conclusion

The requested local runtime mechanisms are implemented and regression-tested. The database context bridge is ready for an application-contract review, but it is not a claim of live authentication, deployed application integration or production readiness.

**Unique next action:** approve the application-side actor/family/channel derivation contract and its exact route-to-Canonical operation mapping before any live enablement or Tencent update.
