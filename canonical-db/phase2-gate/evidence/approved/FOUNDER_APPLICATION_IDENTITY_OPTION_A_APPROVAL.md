# Founder 应用身份合同 Option A：批准记录

| 项 | 值 |
|---|---|
| 决策文件 | `canonical-db/phase2-gate/APPLICATION_IDENTITY_CONTRACT_FOUNDER_GATE_V1.0.md` |
| 决策文件 SHA-256 | `eec9add0f107bd09ba29e7211b12febc41977821857c30824ffcaecae2e3828a` |
| 批准人 / 角色 | Founder 方琳媛 / Founder |
| 时间 | 2026-10-26（Asia/Shanghai，记录日期） |
| 方式 | 会话中的 typed approval，原话："A：保留 FD-6 并指定 OIDC broker（推荐）" |
| 记录人 | Codex（只记录，不代为决定） |

## 生效范围

- 批准 Option A：保留现有 FD-6 OIDC/JWT、JWKS、短时令牌、binder/app 分离和 fail-closed 规则。
- 授权在现有私有工作分支中实现不依赖真实身份或密钥的 provider-neutral 应用验证骨架及合成测试。
- 现有微信 `code2Session` / OpenID 可作为未来 broker 的已验证上游身份来源，但不得直接改写为 OIDC `iss/sub`。

## 未批准事项

- 本记录没有指定具体外部 broker 产品，也没有批准任何未经核验的 issuer、audience 或 JWKS URL。
- 没有批准生成、读取、提交或部署真实签名密钥、client secret 或数据库凭据。
- 没有批准连接真实身份、自动开户、应用联调、腾讯部署、生产部署、真实数据或生产切换。
- app 与 binder 的两个分离 secret-manager reference 仍为 HOLD。

## 效力边界

本批准只冻结身份合同方向。具体 broker、精确公共元数据、密钥引用、应用连接池和上线批次仍需后续证据与单独门禁。决策文件如有任何字节改动，须重新批准。
