# Phoenix Canonical authentication gateway integration gate

This directory turns the approved FD-6 rules into a fail-closed configuration gate and an application-team handoff. It does not contain a production identity provider, JWT signing key, database password or real user mapping.

## What is implemented

- A machine-readable contract template for the facts the application team must supply.
- A PowerShell validator that enforces the approved OIDC/JWT, JWKS cache, ticket, connection-pool, audit and ownership boundaries.
- A synthetic fixture and regression suite covering the required rejection paths.
- An implementation contract describing the binder/app request lifecycle without choosing an identity provider.
- A partially completed facts register with Founder-confirmed ownership, verified runtime/repository evidence and explicit identity/key holds.
- An owner-confirmed candidate configuration that is intentionally rejected until OIDC metadata and separate credential references exist.

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

The synthetic configuration gate is executable. Ownership and runtime location are verified, but the current application uses WeChat `code2Session` plus an application-issued opaque session rather than OIDC/JWT. Live integration remains `HOLD` until the compatible OIDC path (or a formally amended contract), exact metadata, distinct secret references and application-side pool/clear/audit implementation are supplied and reviewed. The validator does not fetch JWKS, validate a real token, configure an application connection pool or write identity mappings.
