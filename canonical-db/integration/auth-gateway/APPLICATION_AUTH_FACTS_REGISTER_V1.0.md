# Phoenix Canonical Application Authentication Facts Register V1.0

**Status:** INPUT REQUIRED / HOLD
**Purpose:** Supply application-owned facts without changing the approved FD-6 rules
**Do not enter:** passwords, tokens, client secrets, private keys, database credentials or real user data

## Identity provider facts

| Field | Required value | Current status |
|---|---|---|
| Provider name | Public product/service name | REQUIRED |
| Issuer (`iss`) | Exact HTTPS issuer string | REQUIRED |
| Audience (`aud`) | Exact expected audience | REQUIRED |
| JWKS URI or discovery URL | Exact HTTPS URL | REQUIRED |
| Allowed algorithm | `RS256`, `ES256`, or both | FIXED RULE |
| Token maximum lifetime | No more than 900 seconds | FIXED RULE |
| Clock skew | No more than 60 seconds | FIXED RULE |
| JWKS cache | No more than 3600 seconds | FIXED RULE |

## Ownership facts

| Field | Required value | Current status |
|---|---|---|
| Application owner | Named accountable person/role | REQUIRED |
| Binder owner | Named accountable person/role | REQUIRED |
| Principal-resolution owner | Named accountable person/role | REQUIRED |
| Audit-event owner | Named accountable person/role | REQUIRED |
| Incident-response owner | Named accountable person/role | REQUIRED |

## Runtime facts

| Field | Required value | Current status |
|---|---|---|
| Application repository | Exact private repository and branch | REQUIRED |
| Integration environment | Isolated non-production environment | REQUIRED |
| App database credential reference | Secret-manager reference only | REQUIRED |
| Binder database credential reference | Different secret-manager reference only | REQUIRED |
| Pool mode | Direct or session | FIXED RULE |
| Clear-on-return hook | Implementation path and owner | REQUIRED |
| Clear-failure discard | Implementation path and test evidence | REQUIRED |
| Gateway audit destination | Protected destination reference, no secret | REQUIRED |

## Review record

- Supplied by:
- Reviewed by:
- Review date/time and timezone:
- Application contract path/version:
- Configuration validation evidence:
- Live JWKS/token test evidence:
- Decision: `PASS / CONDITIONAL / HOLD`

This register is not approved merely because the template exists. Blank fields keep application integration on `HOLD`.
