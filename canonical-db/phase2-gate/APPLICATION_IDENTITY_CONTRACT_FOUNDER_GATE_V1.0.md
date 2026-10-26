# Phoenix Canonical Application Identity Contract — Founder Gate V1.0

**Status:** FOUNDER DECISION REQUIRED / HOLD
**Prepared:** 2026-10-26 (Asia/Shanghai)
**Scope:** Identity contract used between the deployed Phoenix Family OS application and Canonical PostgreSQL
**Not an approval:** This document is decision material only and must not be marked effective without a separate Founder decision record.

## Can Pass Now

- Founder 方琳媛 is recorded as the current application, binder, principal-resolution, audit-event and incident-response owner.
- The Tencent isolated non-production runtime, application repository, branch, commit and package have been identified read-only.
- The database-side binder/app roles, one-time ticket flow and fail-closed configuration validator exist.
- The application context is verified as WeChat Mini Program `code2Session` / OpenID plus a server-issued opaque bearer session.
- The incomplete owner-confirmed candidate configuration is rejected by the integration validator.

## Must Add Evidence

- The approved identity-provider or broker product name.
- Exact HTTPS issuer, audience and JWKS/discovery URL if FD-6 remains OIDC/JWT.
- Separate app and binder credential references in an approved secret/configuration manager.
- Application-side session/direct pools, ticket handoff, context clear/discard and protected audit implementation.
- Immutable remote branch/commit for the application integration revision.
- Live negative authentication tests using non-production credentials.

## Founder Must Decide

Choose exactly one contract direction:

### Option A — Preserve FD-6 and add an OIDC/JWT broker (recommended)

- WeChat remains the customer login source.
- A trusted backend/broker converts the approved external identity into short-lived asymmetric OIDC/JWT assertions that meet FD-6.
- Canonical mapping remains `issuer + subject`; browser tokens never reach PostgreSQL.
- Requires selecting the broker and supplying exact public metadata plus protected client/key references.

**Reason for recommendation:** This preserves the already-approved database and gateway trust boundary, keeps token validation standard and avoids weakening the Canonical contract around a seven-day opaque application session.

### Option B — Amend FD-6 for a first-party opaque-session contract

- The existing WeChat `code2Session` and application-issued opaque session become the approved upstream identity mechanism.
- Requires a new security contract covering session TTL, revocation, rotation, replay, application-to-database principal proof, audit correlation and incident response.
- The current seven-day session cannot be accepted automatically; its duration and controls require explicit review.

**Trade-off:** Fewer moving parts, but more Phoenix-specific security logic and a larger contract/review burden.

## Must Not Do Yet

- Do not invent `iss`, `aud` or JWKS values from WeChat endpoints.
- Do not treat `openid` as an OIDC subject without the approved broker/mapping design.
- Do not place app secrets, database passwords or private keys in Git, this decision file or the facts register.
- Do not connect the live application to Canonical PostgreSQL, provision real users or import real data.
- Do not deploy this gate as production configuration.

## Minimal Next Action

Founder records **Option A** or **Option B** in a separate signed decision record. If Option A is chosen, also name the approved OIDC broker/product owner. Key values remain outside the decision record; only future secret-manager reference names enter the integration configuration.

## Decision Record (not completed)

- Selected option: `A / B / NOT DECIDED`
- Approved identity provider or broker (required for A):
- Contract amendment owner (required for B):
- Decision date/time and timezone:
- Founder signature evidence path:
- Signed file SHA-256:
