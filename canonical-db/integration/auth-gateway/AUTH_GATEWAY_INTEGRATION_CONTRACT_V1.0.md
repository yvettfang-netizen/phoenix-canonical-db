# Phoenix Canonical Auth Gateway Integration Contract V1.0

**Status:** VERIFIED PUBLIC CONFIGURATION / LIVE RUNTIME INTEGRATION HOLD
**Authority:** `FOUNDER_DECISION_ADDENDUM_V1.3_FD6_FD7.md`, FD-6
**Scope:** Application-side authentication and trusted-context handoff to the existing Canonical PostgreSQL database

## 1. Fixed rules

1. The application backend validates OIDC/JWT. PostgreSQL never receives a browser token or user token.
2. Accepted signing algorithms are `RS256` and `ES256`. `none` and every `HS*` algorithm are rejected.
3. The gateway validates `iss`, `aud`, `exp` and `nbf`. Clock skew is at most 60 seconds and access-token lifetime is at most 900 seconds.
4. JWKS failure rejects the request. Cache lifetime is at most 3600 seconds. An unknown `kid` triggers one rate-limited refresh and then rejects if unresolved.
5. External identity is resolved only as `issuer + subject` through `auth.resolve_external_identity`. Missing or disabled mappings do not auto-provision a principal.
6. Binder and app use separate database credentials and separate pools. Binder holds only the binder capability; app holds only the app capability.
7. Binder creates a random request UUID and issues one ticket per request. Ticket lifetime is at most 60 seconds.
8. App redeems the ticket on the same session used for the business query. Transaction pooling is forbidden.
9. Before a connection returns to the pool, app calls `auth.clear_context()`. A connection is discarded when clearing fails.
10. Logs contain the request UUID, issuer, subject identifier, channel, decision and reason code. They never contain raw tokens, names, contact details, passwords or private keys.

The FD-6 baseline permits `RS256` or `ES256` and up to 900 seconds. The Founder-selected first-party profile is deliberately narrower: exact issuer `https://api.phoenixnova.com.cn/canonical-identity`, exact audience `phoenix-canonical-postgresql`, exact JWKS URI, `ES256` only, 300-second token lifetime and 300-second JWKS cache. Integration-mode validation rejects widening or metadata/reference drift.

## 2. Required request sequence

1. Receive the user access token over the approved application transport.
2. Verify algorithm, signature, `iss`, `aud`, `exp`, `nbf` and maximum token lifetime.
3. Resolve `issuer + subject` through the binder connection.
4. Reject an unknown or disabled identity. Do not create a principal automatically.
5. Generate a random request UUID with no personal data.
6. Use the binder connection to call `auth.issue_context_ticket` with the resolved principal, approved family/channel context and a lifetime no greater than 60 seconds.
7. Use an app session to call `auth.redeem_context_ticket` and then the approved read/write API.
8. Call `auth.clear_context()` before returning that app session to its pool.
9. Discard the connection if redemption, business execution or context clearing leaves the connection state uncertain.
10. Correlate gateway decision logs with `audit.access_events` and `PHOENIX_AUDIT` through the request UUID.

## 3. Failure behavior

Every failure returns a denial. The gateway must not fall back to an unsigned token, shared-secret algorithm, stale unbounded key cache, user-supplied principal ID, default family, privileged database login or unbound application query.

## 4. Credential boundary

- The configuration stores credential references only. It never stores credential values.
- Binder and app references must be different.
- Browser and mobile clients never receive either database credential.
- Runtime services do not receive the bootstrap, migrator, reader or backup credential.

## 5. Entry criteria for live integration

Live integration may start only after the application team supplies and reviews:

- identity provider name;
- exact issuer;
- exact audience;
- exact JWKS or discovery URL;
- application owner;
- binder owner;
- principal-resolution owner;
- audit-event owner;
- incident-response owner;
- separate app and binder secret references;
- approved application repository and deployment environment.

The public metadata and three protected references are staged in the isolated environment and the tracked integration candidate now passes the configuration validator. This does not enable runtime integration: the deployed application revision, subject mapping, separated pools, ticket lifecycle, clear/discard behavior, protected audit output and live negative tests remain required.
