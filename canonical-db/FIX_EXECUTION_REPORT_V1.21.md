# Phoenix Canonical PostgreSQL — First-Party OIDC Broker Gate V1.21

**Execution date:** 2026-10-27 (Asia/Shanghai)

**Branch:** `codex/canonical-postgresql-phase1`

**Implementation commit:** `17da9de10a7af9b8ec2fa6115944c574c8e6f24f`

**Scope:** Founder-authorized technical broker selection, disabled-by-default first-party broker, public JWKS boundary, protected reference names and synthetic regression

**Verdict:** **PASS WITH PUBLIC ORIGIN, SECRET PROVISIONING AND DATABASE-RUNTIME INTEGRATION HOLD**

## 1. Decision and execution boundary

Founder instructed Codex to determine the concrete broker/issuer and continue the next local gate. Within the previously approved FD-6 Option A, Codex selected `Phoenix First-Party Canonical Identity Broker V1.0` as a technical server-side trust component. It is not a new customer-facing product or brand.

No Canonical Migration, database state, Tencent host, deployment, real user identity, real data or secret value was used or changed. The existing WeChat login and opaque application session remain unchanged.

## 2. Fixed technical facts

| Fact | Fixed value | Actual state |
|---|---|---|
| Broker | `Phoenix First-Party Canonical Identity Broker V1.0` | LOCAL IMPLEMENTATION |
| Algorithm | `ES256` / P-256 | ENFORCED |
| Token lifetime | 300 seconds | ENFORCED |
| Audience | `phoenix-canonical-postgresql` | ENFORCED |
| Issuer | `<approved PUBLIC_BASE_URL>/canonical-identity` | PATH FIXED / ORIGIN HOLD |
| JWKS | `<approved PUBLIC_BASE_URL>/.well-known/phoenix-canonical-jwks.json` | PATH FIXED / ORIGIN HOLD |
| Signing key reference | `file:/run/secrets/phoenix_canonical_oidc_signing_key_v1` | RESERVED / NOT PROVISIONED |
| App credential reference | `file:/run/secrets/phoenix_canonical_app_pgpass_v1` | RESERVED / NOT PROVISIONED |
| Binder credential reference | `file:/run/secrets/phoenix_canonical_binder_pgpass_v1` | RESERVED / NOT PROVISIONED |

The repository contains reference names only. It contains no private key, password or database credential.

## 3. Implemented locally

- Broker configuration is disabled by default and fails closed when the HTTPS origin, fixed references, key ID or TTL is absent or drifts.
- The broker accepts only a P-256 private key and emits a 300-second ES256 assertion with only `iss`, `aud`, `sub`, `iat`, `nbf`, `exp` and `jti`.
- Broker subjects must be non-personal application identifiers in the `usr_*` namespace. OpenID, name, phone, email and family identifiers are not emitted.
- Only a public JWKS GET route is exposed; there is no browser, Mini Program or public token-issuance route.
- The JWKS publishes only the public P-256 verification key and returns a defensive copy.
- On POSIX systems, enabled startup rejects a signing-key file readable or writable by group/other.
- The broker and verifier flags remain `false`; no live request or database connection path was enabled.

## 4. Synthetic acceptance

| Check | Result |
|---|---|
| TypeScript typecheck | PASS |
| Server build | PASS |
| Dedicated broker tests | 5/5 PASS |
| Full server regression | 98/98 PASS |
| Broker-issued token verified by existing FD-6 verifier | PASS |
| Non-P-256 key, unsafe origin, reference drift and invalid subject rejection | PASS |
| JWKS contains no private member and cannot be mutated through returned data | PASS |
| Public token-issuance route absent | PASS |
| Auth-gateway contract regression | 23/23 PASS |
| Incomplete owner-confirmed candidate | EXPECTED REJECT |
| Credential-material scan | 0 hits |
| `git diff --check` | PASS |
| Canonical Migration changes | NONE |

## 5. Evidence and SHA-256

| Artifact | SHA-256 |
|---|---|
| `server/src/auth/canonical-oidc-broker.ts` | `6e8aa84d170dc3b4b3bc397da1bb5987f67c7ef63de58b703a5fdf17f35e18d7` |
| `server/tests/canonical-oidc-broker.test.ts` | `e055b91031de22e2d9b0e430ca62264b90f5b8e6d040760536d07e1597132539` |
| `v1.21-first-party-oidc-broker.txt` | `21823904d2a83b886c3e990dce9151b66a1888f4739a9c3316e3933a3321e20f` |
| `FOUNDER_OIDC_BROKER_TECHNICAL_SELECTION_V1.0.md` | `dd965c58b56c1f07b26d5b669370e757943e246298dfba3140d85f1e76381206` |
| `OIDC_BROKER_SELECTION_REGISTER_V1.0.md` | `4e6f643d69365f8bf6e132e2975f34d4bf250e0d5ff23c651f0202cba9d796e9` |

Raw commands and outputs are stored in `canonical-db/evidence/v1.21-first-party-oidc-broker.txt`.

## 6. Remaining HOLD

| Item | Status | Closure evidence |
|---|---|---|
| Exact HTTPS `PUBLIC_BASE_URL` | HOLD | Approved deployable origin with DNS and certificate evidence |
| Signing, app and binder protected files | HOLD | Three separately provisioned files with restrictive permissions; values never committed |
| WeChat identity to `usr_*` broker-subject mapping | HOLD | Approved mapping and isolated negative tests; no automatic provisioning |
| Separate app/binder pools and one-time ticket handoff | HOLD | Runtime implementation using the reserved credential references |
| Context clear, discard-on-failure and protected audit | HOLD | Application integration and synthetic end-to-end evidence |
| Live broker/JWKS/key-rotation validation | HOLD | Isolated non-production evidence after origin and secrets exist |
| Tencent or production deployment | NOT EXECUTED / HOLD | Separate reviewed deployment gate |

## 7. Unique next action

Founder/Operations supplies and approves the exact HTTPS `PUBLIC_BASE_URL` and provisions the three reserved protected files in the isolated environment. Until that evidence exists, both broker and verifier remain disabled and the database-runtime integration does not start.
