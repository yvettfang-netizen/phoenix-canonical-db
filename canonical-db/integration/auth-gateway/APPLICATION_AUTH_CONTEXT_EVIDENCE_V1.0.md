# Phoenix Canonical Application Authentication Context Evidence V1.0

**Verified:** 2026-10-26 (Asia/Shanghai)
**Scope:** Read-only application repository, Tencent runtime and GitHub metadata verification
**Conclusion:** Application and ownership facts are partially closed; live FD-6 OIDC integration remains HOLD

## 1. Repository and runtime identity

| Evidence | Verified fact |
|---|---|
| GitHub repository metadata | `yvettfang-netizen/phoenix` is `PUBLIC`; default branch is `main` |
| Tencent application worktree | `/home/ubuntu/education-compass` |
| Worktree branch | `claude/education-compass-virtual-payment-20261012` |
| Worktree commit | `79e59fc22c712b500f91c994f62a80e9d546f69f` |
| Tracked changes | 0 |
| Remote branch ref | No matching branch ref returned by `git ls-remote` |
| GitHub commit lookup | The exact commit is readable from `yvettfang-netizen/phoenix` |
| Runtime package | `phoenix-family-os-server` V0.5.0 |
| Runtime processes | `phoenix_uat_api` and `phoenix_uat_agent_worker` use the verified worktree path |

The application commit exists on GitHub, but the named deployed branch is not currently published as a remote branch. The application repository is not private. The private Canonical database repository remains a separate repository and cannot be used as evidence that the application repository is private.

## 2. Authentication behavior verified from tracked source

Tracked source and contracts establish this flow:

1. The mini program calls `wx.login` and posts the one-time code to `POST /v1/auth/wechat/session`.
2. The trusted application server calls `https://api.weixin.qq.com/sns/jscode2session` with its app identity.
3. The server receives `openid`, optional `unionid`, and a transient `session_key`.
4. Login persists the WeChat identity and issues a random application bearer token; only its digest is stored.
5. The application bearer token is opaque, and the current application session default is seven days.

Primary tracked evidence:

- `Phoenix Compass/education compass/server/src/auth/wechat-auth-provider.ts`
- `Phoenix Compass/education compass/server/src/services/auth-service.ts`
- `Phoenix Compass/education compass/docs/API.md`
- `Phoenix Compass/education compass/docs/DATA_INVENTORY.md`

## 3. FD-6 compatibility finding

The approved FD-6 contract requires OIDC/JWT verification with exact `iss`, `aud`, `JWKS`, asymmetric algorithms and a 900-second maximum access-token lifetime. The verified application flow instead uses WeChat `code2Session` plus an application-issued opaque session.

Therefore:

- WeChat `openid` must not be re-labelled as OIDC `sub` without an approved mapping/broker design.
- `api.weixin.qq.com` must not be invented as an OIDC issuer or JWKS endpoint.
- The seven-day opaque bearer session must not be represented as the FD-6 JWT.
- The owner-confirmed candidate configuration must remain rejected until a compliant broker/configuration or a formally approved contract amendment exists.

## 4. Environment boundary

- Tencent is an isolated non-production environment and remains `A4 OPEN / NOT TRUSTED` for production.
- Canonical PostgreSQL listens on server loopback at `127.0.0.1:5432`; no public PostgreSQL port was observed.
- This verification did not read `.env`, key files, tokens or credential values.
- No deployment, restart, application write, database migration, real-data import or production cutover was performed.

## 5. Remaining evidence gaps

- Compliant OIDC provider/broker selection and exact metadata.
- Separate app/binder secret-manager references.
- Application-side separate pools, ticket redemption and context-clear/discard implementation.
- Protected gateway audit destination.
- Immutable remote application branch for the intended isolated integration revision.
- Live negative token/JWKS tests.
