# Tencent Isolated OIDC Configuration Staging V1.0

**Environment:** Tencent isolated non-production (`A4 OPEN / NOT TRUSTED` for production)

**Date:** 2026-10-27 (Asia/Shanghai)

**State:** CONFIGURATION STAGED / BROKER AND VERIFIER DISABLED / NO APPLICATION RESTART

## Verified public origin

- `api.phoenixnova.com.cn` resolves to the isolated host.
- Nginx terminates HTTPS for that hostname and proxies the API to `127.0.0.1:3010`.
- The certificate names `api.phoenixnova.com.cn`, is issued by Let's Encrypt, and was valid during execution.
- `GET https://api.phoenixnova.com.cn/health` returned HTTP 200.
- The staged `PUBLIC_BASE_URL` is `https://api.phoenixnova.com.cn`.

This evidence authorizes only the isolated environment. It is not a production-domain or production-release approval.

## Protected file layout

| Purpose | Runtime reference | Runtime mode/owner | Persistent source |
|---|---|---|---|
| ES256 signing key | `/run/secrets/phoenix_canonical_oidc_signing_key_v1` | `0600 ubuntu:ubuntu` | root-only `0600` under `/etc/phoenix-canonical/secrets` |
| App pgpass | `/run/secrets/phoenix_canonical_app_pgpass_v1` | `0600 ubuntu:ubuntu` | root-only `0600` under `/etc/phoenix-canonical/secrets` |
| Binder pgpass | `/run/secrets/phoenix_canonical_binder_pgpass_v1` | `0600 ubuntu:ubuntu` | root-only `0600` under `/etc/phoenix-canonical/secrets` |

`/etc/tmpfiles.d/phoenix-canonical-secrets.conf` projects the root-owned persistent sources into `/run/secrets` at boot. The runtime directory is `0700 ubuntu:ubuntu`. No secret value, private key, password or private-file digest is recorded in this repository or evidence.

## Executed validation

- Signing key parses as an EC P-256 private key.
- Public-key SHA-256 fingerprint: `e56ae427b050d034011af327d1622a7741f55c24792fec94e098430f14c025fb`.
- App and binder pgpass files have distinct 64-hex password fields and exact role/database/loopback coordinates.
- `phoenix_canonical_app_runtime` and `phoenix_canonical_binder_runtime` each completed a separate read-only login using its own pgpass file.
- Container-temporary pgpass copies were removed after validation.
- Application tracked source remained clean at commit `79e59fc22c712b500f91c994f62a80e9d546f69f`.
- API PID and HTTPS health remained unchanged; no restart, Broker enablement, Migration or database write occurred.
- The live JWKS URL currently returns HTTP 401 because the deployed application revision does not contain the public Broker/JWKS route. This is expected and keeps live integration on HOLD.

## Enablement gate

Do not set either enable flag to `true` until all of the following pass against the exact deployed revision:

1. Separate app and binder connection pools use only their respective pgpass files.
2. Verified application user IDs map to approved `usr_*` broker subjects without automatic principal provisioning.
3. Ticket issue/redeem, context clear and discard-on-clear-failure pass split-login negative tests.
4. Protected gateway audit correlation passes without raw tokens or personal data.
5. Public JWKS, signed-token verification, wrong issuer/audience, expiry, unknown `kid`, rotation and JWKS outage tests pass.
6. Rollback is rehearsed before restart.

## Rollback boundary

- Keep `CANONICAL_OIDC_BROKER_ENABLED=false` and `CANONICAL_OIDC_ENABLED=false` for the current staged state.
- Reverting the public configuration requires restoring the protected pre-change `.env.uat` backup and restarting only through the approved application supervisor procedure.
- Removing or rotating a protected file requires stopping the future Broker-dependent revision first; never delete an in-use key or credential.
- Database roles, Migration state and Canonical data are not changed by this staging action.
