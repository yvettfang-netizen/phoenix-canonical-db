# Founder OIDC Broker 技术选型授权记录 V1.0

| 项 | 值 |
|---|---|
| 上一门禁 | `canonical-db/FIX_EXECUTION_REPORT_V1.20.md` |
| 批准人 / 角色 | Founder 方琳媛 / Founder |
| 时间 | 2026-10-27（Asia/Shanghai） |
| 方式 | 会话 typed instruction，原话：`确定，继续下一步` |
| 记录人 | Codex（记录并执行技术选型，不代造外部事实） |

## 授权解释

- Founder 授权 Codex 在已批准 Option A 与现有 FD-6 边界内确定具体技术组件并继续本地实施。
- Codex 选择 `Phoenix First-Party Canonical Identity Broker V1.0`，作为现有可信服务端内的独立身份信任组件，不新增客户品牌或产品线。
- 固定 `ES256`、300 秒令牌、audience `phoenix-canonical-postgresql`、issuer/JWKS 路径及三项受保护文件引用名称。
- 允许使用纯合成 P-256 密钥完成本地正负向验收、报告、私有分支提交与同步。

## 未授权或尚无证据

- 本记录不把示例域名视为正式 `PUBLIC_BASE_URL`，也不虚构可用 DNS、证书或公网服务。
- 本记录不生成、读取、提交或部署真实私钥、数据库口令或真实用户身份。
- 三项 `file:/run/secrets/...` 仅为批准的引用名称；本记录不证明对应 secret 已创建。
- 未授权腾讯更新、生产部署、真实数据导入、生产切换或自动开户。

因此，本地技术选型可继续；live integration 仍须由正式 public origin、实际 secret provisioning 和后续应用连接池验收关闭。
