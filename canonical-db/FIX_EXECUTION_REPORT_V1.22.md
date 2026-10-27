# Phoenix Canonical PostgreSQL — Isolated OIDC Origin and Protected Files V1.22

**Execution date:** 2026-10-27 (Asia/Shanghai)

**Branch:** `codex/canonical-postgresql-phase1`

**Implementation/evidence commit:** `e5b2bda1a9b4f2ad3831c34e14e9900e260c3494`

**Scope:** verify the isolated HTTPS public origin, stage reference-only OIDC configuration, provision protected signing/app/binder files, harden the integration validator and preserve fail-closed runtime state

**Verdict:** **PASS WITH APPLICATION RUNTIME INTEGRATION HOLD**

## 1. Authorization and boundary

Founder instructed Codex to continue the exact next action from V1.21: establish the formal `PUBLIC_BASE_URL` and configure the signing, app and binder protected files in the isolated environment.

This execution changed only the Tencent isolated non-production application configuration and protected-file staging. It did not restart the application, enable the Broker/verifier, deploy application code, add a Migration, write Canonical data, import real identities/data, expose PostgreSQL, or perform a production switch.

## 2. Verified public origin

| Evidence | Result |
|---|---|
| DNS `api.phoenixnova.com.cn` | `1.12.77.180` |
| TLS subject/DNS name | `api.phoenixnova.com.cn` |
| Certificate issuer | Let's Encrypt |
| Certificate validity during execution | PASS |
| Nginx upstream | `127.0.0.1:3010` |
| HTTPS `/health` | HTTP 200 / `{"ok":true}` |
| Staged `PUBLIC_BASE_URL` | `https://api.phoenixnova.com.cn` |
| Exact issuer | `https://api.phoenixnova.com.cn/canonical-identity` |
| Exact JWKS URI | `https://api.phoenixnova.com.cn/.well-known/phoenix-canonical-jwks.json` |

The live JWKS URL currently returns HTTP 401 because the running application is still commit `79e59fc22c712b500f91c994f62a80e9d546f69f` and does not contain the V1.21 Broker/JWKS route. This is expected and proves that configuration staging was not misreported as live enablement.

## 3. Protected files

| File | Runtime state | Persistence | Validation |
|---|---|---|---|
| OIDC signing key | `/run/secrets/phoenix_canonical_oidc_signing_key_v1`, `0600 ubuntu:ubuntu` | root-owned `0600` source under `/etc/phoenix-canonical/secrets` | EC P-256 valid |
| App pgpass | `/run/secrets/phoenix_canonical_app_pgpass_v1`, `0600 ubuntu:ubuntu` | root-owned `0600` source | separate app read-only login PASS |
| Binder pgpass | `/run/secrets/phoenix_canonical_binder_pgpass_v1`, `0600 ubuntu:ubuntu` | root-owned `0600` source | separate binder read-only login PASS |

`/etc/tmpfiles.d/phoenix-canonical-secrets.conf` projects the root-only sources into the `0700` runtime directory at boot. App and binder password values were consumed only inside the server from the existing protected database environment. They were not placed on the command line, printed, downloaded or committed. Container-temporary pgpass copies were removed.

The signing public-key SHA-256 fingerprint is `e56ae427b050d034011af327d1622a7741f55c24792fec94e098430f14c025fb`. No private-key digest or material is recorded.

## 4. Runtime state after staging

- `.env.uat` and its protected pre-change rollback copy are `0600 ubuntu:ubuntu`.
- `CANONICAL_OIDC_BROKER_ENABLED=false`.
- `CANONICAL_OIDC_ENABLED=false`.
- API PID remained unchanged and HTTPS health remained 200.
- Deployed application tracked source remained clean at commit `79e59fc22c712b500f91c994f62a80e9d546f69f`.
- PostgreSQL container remained healthy; no Migration or Canonical data write ran.

## 5. Machine gate and regression

The tracked candidate now records exact public metadata plus the three reference names and passes integration-mode validation. Integration validation is narrowed to the selected first-party profile and rejects drift in issuer, audience, JWKS, signing reference, algorithm, TTL and database credential references.

| Check | Result |
|---|---|
| Auth-gateway regression | 30/30 PASS |
| Exact integration candidate | PASS |
| Issuer/audience/JWKS drift rejection | PASS |
| Signing/app reference drift rejection | PASS |
| Algorithm widening and TTL drift rejection | PASS |
| JSON parse | 3/3 PASS |
| Credential-material scan | 0 hits |
| `git diff --check` | PASS |
| Canonical Migration changes | NONE |

## 6. Evidence and SHA-256

| Artifact | SHA-256 |
|---|---|
| `auth-contract.owner-confirmed.candidate.json` | `2758d6a372a0b421f2d19a34b8aacbd2c713783f35d015901cce6bff440dccbf` |
| `validate-auth-contract.ps1` | `2c8a439ab527a7f169d4f89c2942712decbe957821108709557d31c8b786705a` |
| `auth_gateway_contract_regression.ps1` | `59874766b6b28ee8e7fa76b04e5bea60e9ecdd0a98aaa0000a53853ab7435499` |
| `TENCENT_ISOLATED_OIDC_STAGING_V1.0.md` | `555feac93e2f9e6bbb7e8ad8ae48f2330c958b02eb767f0f80d7b1add8906dd6` |
| `v1.22-tencent-oidc-origin-and-protected-files.txt` | `a005689b57db005f26601e713f1b41ab70e9e5b131360a867c6a1d3e82510e58` |

Raw redacted commands and outputs are stored in `canonical-db/evidence/v1.22-tencent-oidc-origin-and-protected-files.txt`.

## 7. Security assessment

| Severity | Finding | State |
|---|---|---|
| Critical / High | Secret exposure, shared app/binder credential, public PostgreSQL or unexpected enablement | NONE OBSERVED |
| Medium | Deployed application revision lacks the Broker/JWKS and pool/ticket/clear/audit implementation | HOLD |
| Medium | Live key rotation and JWKS outage behavior are not yet tested against the isolated endpoint | HOLD |
| Low | Protected pre-change `.env.uat` rollback copy remains on the host | ACCEPTED FOR ROLLBACK / 0600 |

No legal or privacy-contract decision was made in this batch.

## 8. Remaining HOLD

- Publish and deploy an immutable application revision containing the selected Broker/verifier.
- Approve and implement WeChat application user to `usr_*` subject mapping without automatic provisioning.
- Implement separate app/binder pools, one-time ticket issue/redeem, clear-on-return, discard-on-failure and protected audit correlation.
- Run isolated public JWKS, token, rotation, outage and split-login end-to-end tests before either enable flag changes.
- Real identities, real customer data, production credentials, production deployment and cutover remain forbidden.

## 9. Unique next action

Implement and publish the immutable application runtime revision for separate app/binder pools, subject mapping, one-time ticket handoff, context clear/discard and protected audit; run it disabled-by-default in local synthetic tests before any Tencent application deployment or enablement.
