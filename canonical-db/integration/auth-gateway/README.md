# Phoenix Canonical authentication gateway integration gate

This directory turns the approved FD-6 rules into a fail-closed configuration gate and an application-team handoff. It does not contain a production identity provider, JWT signing key, database password or real user mapping.

## What is implemented

- A machine-readable contract template for the facts the application team must supply.
- A PowerShell validator that enforces the approved OIDC/JWT, JWKS cache, ticket, connection-pool, audit and ownership boundaries.
- A synthetic fixture and regression suite covering the required rejection paths.
- An implementation contract describing the binder/app request lifecycle without choosing an identity provider.
- A partially completed facts register with Founder-confirmed ownership, verified runtime/repository evidence and explicit identity/key holds.
- An owner-confirmed candidate configuration that passes only when the verified isolated origin and all selected reference names match exactly.
- A Founder-approved Option A direction, selected first-party broker and provider-neutral application verifier with synthetic ES256, claim, JWKS and fail-closed tests. Both components are disabled and not connected to a live database path.

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

The repository does not include secret values. The tracked `auth-contract.owner-confirmed.candidate.json` contains public metadata and reference names only; it is not a runtime secret file and does not enable the application. Runtime secret values stay outside Git.

## Gate result

The synthetic configuration gate is executable. The verified isolated origin is `https://api.phoenixnova.com.cn`, and the three protected files are staged with restrictive permissions while both enable flags remain `false`. The current deployed application still uses WeChat `code2Session` plus an application-issued opaque session and does not contain the broker revision. Live integration remains `HOLD` until the application-side subject mapping, pool/ticket/clear/audit implementation and isolated end-to-end tests are supplied and reviewed. The validator does not configure a live connection pool or write identity mappings.
