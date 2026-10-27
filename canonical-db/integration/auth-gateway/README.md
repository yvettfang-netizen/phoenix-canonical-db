# Phoenix Canonical authentication gateway integration gate

This directory turns the approved FD-6 rules into a fail-closed configuration gate and an application-team handoff. It does not contain a production identity provider, JWT signing key, database password or real user mapping.

## What is implemented

- A machine-readable contract template for the facts the application team must supply.
- A PowerShell validator that enforces the approved OIDC/JWT, JWKS cache, ticket, connection-pool, audit and ownership boundaries.
- A synthetic fixture and regression suite covering the required rejection paths.
- An implementation contract describing the binder/app request lifecycle without choosing an identity provider.
- A partially completed facts register with Founder-confirmed ownership, verified runtime/repository evidence and explicit identity/key holds.
- An owner-confirmed candidate configuration that is intentionally rejected until OIDC metadata and separate credential references exist.
- A Founder-approved Option A direction and a provider-neutral application verifier with synthetic RS256/ES256, claim, rotation and fail-closed tests. The verifier is disabled and not connected to a live request path.

## Run the synthetic gate

```powershell
pwsh -NoProfile -File ./tests/auth_gateway_contract_regression.ps1
```

Validate a proposed integration configuration:

```powershell
pwsh -NoProfile -File ./integration/auth-gateway/validate-auth-contract.ps1 `
  -Path ./integration/auth-gateway/auth-contract.integration.json `
  -Mode integration
```

The repository does not include `auth-contract.integration.json`. Keep the real file in the approved secret/configuration system. The tracked `auth-contract.owner-confirmed.candidate.json` is an incomplete fail-closed record, not a runtime configuration. A real integration file may contain public identity-provider metadata and secret references, but never tokens, passwords, private keys or client secrets.

## Gate result

The synthetic configuration gate is executable. Founder approved preserving FD-6 with an OIDC/JWT broker, and the local provider-neutral verifier passes synthetic tests. The current application still uses WeChat `code2Session` plus an application-issued opaque session, and no concrete broker or live metadata exists. Live integration remains `HOLD` until the broker/issuer implementation, exact metadata, distinct secret references and application-side pool/clear/audit implementation are supplied and reviewed. The tracked integration validator still does not configure a live application connection pool or write identity mappings.
