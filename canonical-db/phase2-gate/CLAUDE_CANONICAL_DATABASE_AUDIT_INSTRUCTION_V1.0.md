# Claude 审计指令：Phoenix Canonical PostgreSQL

请对当前仓库中的 Phoenix Canonical PostgreSQL 实现执行一次**只读、证据驱动的独立审计**，并在审计结束后生成完整 Markdown 审计报告。

## 审计边界

1. 仅审计当前仓库中的 `canonical-db/`，不要扫描其他项目、用户目录或整个磁盘。
2. 先读取：
   - `canonical-db/README.md`
   - `canonical-db/PHASE1_REPORT.md`
   - `canonical-db/PHASE2A_EXECUTION_REPORT.md`
   - `canonical-db/PHASE2B_EXECUTION_REPORT.md`
   - `canonical-db/PHASE2B_AUDIT_REPORT.md`
   - `canonical-db/PHASE2C_EXECUTION_REPORT.md`
   - `canonical-db/PHASE3_EXECUTION_REPORT.md`
   - `canonical-db/TENCENT_DEPLOYMENT_EXECUTION_REPORT.md`
   - `canonical-db/phase2-gate/` 下的合同、审批登记、生产方案和证据请求文件
3. 核对当前 Git 分支、HEAD、工作树、变更文件和实际文件内容。报告中必须区分：
   - 本地代码
   - 本地 PG16/PG17 测试
   - 腾讯云隔离运行时
   - 生产就绪状态
4. 不连接腾讯云，不使用生产密钥，不读取或迁移真实数据，不执行部署、Push、Merge、DROP、TRUNCATE、重置数据库或任何不可逆操作。
5. 不修改源代码、Migration、Compose、脚本或合同文件。唯一允许生成的文件是审计报告：
   `canonical-db/phase2-gate/CLAUDE_CANONICAL_DATABASE_AUDIT_REPORT_V1.0.md`

## 必查项目

### A. Migration 与 Schema

- Canonical Migration 是否为独立命名空间，未复用旧 `006`。
- 0001–0006 的文件内容、SHA-256、顺序、重复执行和漂移拒绝证据。
- `auth`、`core`、`consent`、`audit`、`integration`、`docs`、`casework`、`education`、`identity` 的实际表、外键、唯一约束、索引和 RLS。
- 是否存在重复自然人或家庭主数据模型。
- 是否有未经批准的历史 ID 映射、真实数据迁移或隐含业务语义。

### B. 权限与数据隔离

- bootstrap、migrator、app、reader、context-binder、backup 角色的实际权限。
- health/backup 是否使用 bootstrap 超级用户。
- RLS 是否覆盖跨家庭、顾问越权、渠道跨主体、Consent 撤回、监护权限到期和 trusted context 清理/重绑定。
- 是否存在公开监听的 PostgreSQL 5432。

### C. 文档、提交和对象存储

- 文档版本是否不可静默覆盖。
- 已提交 Submission Manifest 是否不可未经授权修改。
- Withdrawal、Legal Hold、版本链和旧快照是否有可验证规则。
- 私有对象存储是否仍是 Mock/未批准状态；不得把 Mock 写成真实 COS 生产证据。

### D. 备份、恢复和运行时

- Compose 镜像是否有 SHA-256 锁定，PG16/PG17 版本是否与报告一致。
- 备份是否使用非 bootstrap 角色、容器内本地 socket 或受保护凭据。
- 备份文件、manifest、摘要、恢复演练和篡改拒绝是否有实际证据。
- 腾讯云容器是否健康、是否无公网 5432、是否为隔离空库。

### E. 生产门禁和缺失证据

逐项检查并标明 `PASS`、`CONDITIONAL`、`HOLD` 或 `EVIDENCE_MISSING`：

- Family Context 正式原件和生效修订
- Founder OS Freeze 原件及 ID 决议
- Founder OS / Operations OS / D1 复用决定
- Legacy ID 清单、冲突策略和迁移授权
- Docs & Submission 最终契约
- Education / Identity 业务状态和责任人
- 对象存储、保留、Legal Hold、清除和备份合同
- Web 鉴权、JWKS、trusted context 和连接池生命周期
- RPO、RTO、监控、值班、回滚和切换批准
- 真实数据导入和生产应用切换批准

## 证据规则

- 每个结论必须引用文件路径、Git commit、命令输出摘要或数据库运行时证据。
- 不能从报告标题、提交消息或设计文件推断“已部署”或“生产就绪”。
- 无法取得证据时必须写 `EVIDENCE_MISSING`，并说明需要什么证据。
- 现有报告只能作为待核对线索；若实际状态与报告冲突，以实际状态为准并记录冲突。

## 审计报告要求

生成 `canonical-db/phase2-gate/CLAUDE_CANONICAL_DATABASE_AUDIT_REPORT_V1.0.md`，包含：

1. 审计时间、审计范围、Git 分支和 HEAD。
2. 一页结论：
   - `CODE_AUDIT = PASS / CONDITIONAL / HOLD`
   - `LOCAL_RUNTIME = PASS / CONDITIONAL / HOLD`
   - `TENCENT_ISOLATED_RUNTIME = PASS / CONDITIONAL / HOLD / EVIDENCE_MISSING`
   - `PRODUCTION_READY = YES / NO`
3. 事实、证据、发现、风险和未决事项表。
4. Migration、Schema、RLS、权限、备份恢复、网络暴露和合成数据测试结果。
5. 明确列出所有 `HOLD`、`CONDITIONAL` 和 `EVIDENCE_MISSING`，不得用“以后处理”替代具体证据要求。
6. 明确写出：隔离空库通过不等于真实生产切换通过。
7. 只给出可逆、只读的下一步建议；不得自行部署、迁移、推送、合并或导入数据。

最终报告末尾必须给出：

`FINAL AUDIT VERDICT = PASS / CONDITIONAL / HOLD`

其中，只要生产审批、历史合同、真实 ID 决议、应用鉴权或真实数据切换证据缺失，最终结论不得为生产 `PASS`。
