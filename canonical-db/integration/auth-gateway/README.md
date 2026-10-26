# Phoenix Canonical authentication gateway integration gate

This directory turns the approved FD-6 rules into a fail-closed configuration gate and an application-team handoff. It does not contain a production identity provider, JWT signing key, database password or real user mapping.

## What is implemented

- A machine-readable contract template for the facts the application team must supply.
- A PowerShell validator that enforces the approved OIDC/JWT, JWKS cache, ticket, connection-pool, audit and ownership boundaries.
- A synthetic fixture and regression suite covering the required rejection paths.
- An implementation contract describing the binder/app request lifecycle without choosing an identity provider.
- An input register for the still-missing issuer, audience, JWKS/discovery URL and named owners.

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

The repository does not include `auth-contract.integration.json`. Keep the real file in the approved secret/configuration system. The file may contain public identity-provider metadata and secret references, but never tokens, passwords, private keys or client secrets.

## Gate result

The synthetic configuration gate is executable. Live OIDC/JWT/JWKS integration remains `HOLD` until every field in `APPLICATION_AUTH_FACTS_REGISTER_V1.0.md` is supplied and reviewed. The validator does not fetch JWKS, validate a real token, configure an application connection pool or write identity mappings.
