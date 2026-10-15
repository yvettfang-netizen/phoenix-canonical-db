# Phoenix Canonical Production Database — Founder Decision Register V1.0

**Status:** SIGNED — Founder typed approval, 2026-10-15 14:37 +0800 (Asia/Shanghai). Prefilled by Claude; all prefilled selections confirmed without changes.  
**Purpose:** Record decisions that cannot be inferred from SQL, tests or an unverified historical document.  
**Security:** Do not paste passwords, private keys, tokens, client secrets or document bytes here.

> **预填说明（Claude）：** 每一项中标为 `[x]` 的选项，是 Claude 根据三轮审计结果给出的**建议**，**不是批准**。
> 标有"待 Founder 填写"的字段，只有 Founder 本人掌握相关事实，Claude 没有替你编造。
> 在下方"Approval record"中填写姓名、角色、日期和签名（或 typed approval）之前，所有项目一律视为 **HOLD**。
> 任何一项想改，直接修改勾选和字段即可；没改的项目，以签名时文件中的内容为准。
>
> **签名记录：** Founder 于 2026-10-15 14:37 +0800 在会话中回复"按预填确认，签名：Founder"，确认全部预填内容，未做修改。签名所依据的预填版 SHA-256 为 `e6d1f2273ff534fb4f39c1ebe927b6e97bef446fad4e0a603aff32c196121247`。签名时仍空缺的字段已逐项标注，不视为已决定。

## How to complete

For every item, select one decision, attach the source or rationale, and fill in the approver and date. A typed approval in the current Codex session may be recorded as the approval event; legal signatures should be handled in the organization's normal contract process.

## Decisions requiring Founder input

### FD-1 — Production scope

- [x] Approve an empty Canonical database as the only production scope for the next release. （Claude 建议）
- [ ] Approve real-data migration in a later gate after all remaining decisions close.
- [ ] Hold production use.

**Founder input:**

- Decision: `[x] 选项 1 — 本期只批准空的 Canonical 库；真实数据迁移另行立项、另行审批`
- Rationale or referenced plan: 三轮审计（V1.0 / V1.1 / V1.2）中，代码与本地测试已达 PASS；但 EV-1 至 EV-8 缺失，宿主机安全事件闸门 G-1 至 G-8 未关闭，应用写入与鉴权尚未接入
- Approver name and role: Founder
- Approval date/time and timezone: 2026-10-15 14:37 +0800 (Asia/Shanghai)
- Signature or typed approval: "按预填确认，签名：Founder"（会话中的 typed approval）

### FD-2 — Family Context and identity authority

- [x] Approve `CANONICAL_BUSINESS_CONTRACT_V1.0_EFFECTIVE.md` as the greenfield production identity baseline. （Claude 建议：只用于新库）
- [ ] Replace it with a supplied final Family Context contract.
- [ ] Hold until the historical Family Context V1 original is recovered.

Required confirmation: `core.people` is the only natural-person master; Student is a Person profile; Guardian is time-bounded; UUIDv7 is the internal ID authority; legacy IDs require source-qualified evidence.

**Founder input:**

- Selected option: 选项 1 — 批准为**新库**的身份与业务基线。历史 Family Context V1 原件如果找回，须逐条比对；有冲突时另行修订，不追溯改动已登记的 Migration
- Final source path or attachment: `canonical-db/phase2-gate/CANONICAL_BUSINESS_CONTRACT_V1.0_EFFECTIVE.md`
- Source SHA-256: `f89a1bbe3cff78ed96e8e6620fce7d41837ae4d30de0b9fd91929f2f6bcf4c93`
- Changed clauses（Claude 建议的补充裁定，随本项一并批准）:
  1. **F-04：** 顾问或渠道方查看**被分配或被授权学生**的基本展示信息（姓名、学生档案），**不需要**额外 Consent；查看申请、身份案件、文件，仍须相应 Consent（维持现有实现）。
  2. **F-09：** 监护范围精确匹配。`GENERAL` **不覆盖** `IDENTITY_SENSITIVE`；身份类文件必须有 `IDENTITY` 范围、证据等级为 `VERIFIED` 的监护授权（维持现有实现）。
  3. **F-18：** 公开 ID 保持 `per_ / fam_ / stu_ / gdn_ + 32 位十六进制`；`usr_` 预留给登录主体（principal），使用前另行实现。旧系统的 `usr_` 等值只作为来源标识，必须经映射表解析。
  4. **R-7：** 监护授权的 `evidence_level` 不可原地修改。证据升级或降级必须新建一条授权记录并留审计，旧记录终止。
  5. **R-5：** 应用每个请求通过一次性票据（≤60 秒）取得上下文；连接归还连接池前必须调用 `auth.clear_context()`。
  6. **F-10 写入依据：** 批准 `F10_APPLICATION_WRITE_API_DESIGN_DRAFT.md`（SHA-256 `1eb356cb7547ca6ad095a9e7cb999dd74d3661f4c02a340e318114fde5d97d79`）中的写入边界、创建者与状态流转，作为 `0009+` 写入接口的实现依据：
     - Family / Person 只能由 INTERNAL 渠道的 SERVICE 主体创建；
     - Education：`DRAFT→READY→SUBMITTED→DECIDED`，`WITHDRAWN` 只能从未决定的状态进入；
     - Identity：`DRAFT→EVIDENCE_PENDING→UNDER_REVIEW→RESOLVED/CLOSED`。

     字段白名单只限合同 §Casework, Education and Identity 已列出的核心字段，扩展字段另批。
- Approver/date/signature: Founder，2026-10-15 14:37 +0800，typed approval（见 Approval record）

### FD-3 — Founder OS and Operations reuse

- [x] No Founder OS, D1 or Operations data/IDs/assets will enter Canonical in this release. （Claude 建议）
- [ ] Approve a specific reuse plan after the original Founder OS freeze and reconciliation evidence are attached.
- [ ] Hold.

**Founder input:**

- Selected option: 选项 1 — 本期不复用。Founder OS / Operations OS 的资产与规则按 `OPERATIONS_OS_ASSET_PRESERVATION_AND_POSTGRES_REUSE_V1.0.md` 保留，不迁移
- Exact repository/branch/commit or file path: 不适用（本期不复用）。Freeze 原件 `3d5d6758…` 仍为 EVIDENCE_MISSING
- Source SHA-256: 不适用
- Reused entities/assets, if any: 无
- Approver/date/signature: Founder，2026-10-15 14:37 +0800，typed approval（见 Approval record）

### FD-4 — Legacy ID reconciliation

- [x] No legacy IDs or real records are imported in this release. （Claude 建议）
- [ ] Approve a later reconciliation project using explicit `source_system + entity_kind + legacy_id` mappings and evidence states.
- [ ] Hold.

Required source inventory: system name, table/file, owner, ID examples (synthetic if necessary), collision policy, supersession policy, reviewer and audit retention.

**Founder input:**

- Selected option: 选项 1 — 本期不导入任何旧 ID 或真实记录；对账项目以后单独立项
- Source systems in scope: 无（本期）
- Mapping owner: （以后立项时填写）
- Evidence standard: 不适用（本期）
- Approver/date/signature: Founder，2026-10-15 14:37 +0800，typed approval（见 Approval record）

### FD-5 — Documents, Submission and object storage

- [x] Approve metadata-only Canonical deployment until private object storage is approved. （Claude 建议）
- [ ] Approve a real private object store and adapter after the fields below are complete.
- [ ] Hold.

Required fields: provider, account/project, bucket/container name (no secret), region, encryption owner, retention schedule, legal-hold authority, purge authority, cross-border rule, backup destination and incident owner.

**Founder input:**

- Selected option: 选项 1 — 只部署文件元数据，不存放任何真实文件字节；本地只用 Mock 存储
- Provider/region: 不适用（本期）。注意：现有 COS 密钥（安全事件 SR-7）未轮换前，不得作为对象存储或备份目的地
- Retention and purge rule: 不适用（无真实文件）。F-08 清除方案维持草案状态，不授予清除权限
- Legal-hold authority: （以后接入真实存储时填写）
- DS-1–DS-5 final source path and SHA-256: 不适用（本期）
- Approver/date/signature: Founder，2026-10-15 14:37 +0800，typed approval（见 Approval record）

### FD-6 — Application authentication and trusted context

Required fields: token issuer, audience, JWKS/discovery URL, principal-to-Person resolution owner, binder service owner, app/binder connection-pool separation, pool clear-on-return mechanism, expiry policy, audit event owner and incident response owner.

> Claude 建议：本项目前**保持 HOLD**。数据库侧机制已实现并通过审计，但 issuer、audience、JWKS 和负责人只有应用方掌握，不能预填。下面只填技术约束。

**Founder input:**

- Authentication contract path/version: （待应用方提供）
- Issuer/audience: （待应用方提供）
- Binder owner: 签名时未指定（本项 HOLD）
- Application owner: 签名时未指定（本项 HOLD）
- Pool reset mechanism: 每个请求兑换一次性票据（≤60 秒，`auth.redeem_context_ticket`）；连接归还前调用 `auth.clear_context()`；binder 与 app 使用不同账号和不同连接池（已在 0007/0008 实现）
- Approver/date/signature: Founder 确认本项**维持 HOLD**，2026-10-15 14:37 +0800，typed approval（见 Approval record）

### FD-7 — Operations, backup and recovery

Required fields: target RPO, target RTO, backup frequency, retention duration, private backup destination, restore rehearsal cadence, alert channel, on-call owner, incident severity rules and rollback window.

> Claude 建议：以下数值**只适用于当前空库和合成数据阶段**。导入真实数据前必须重新确定。

**Founder input:**

- RPO: 24 小时（每日一次备份）（Claude 建议）
- RTO: 8 小时（Claude 建议）
- Backup retention: 服务器本地保留 14 天（与现有服务器备份策略一致）。异地副本暂缓，等 COS 密钥轮换（SR-7）后再定目的地（Claude 建议）
- Restore cadence: 每月一次，并在每次 Migration 发布前做一次一次性容器恢复演练（Claude 建议）
- On-call owner: **签名时未指定，需补填**（导入任何真实数据前必须指定）
- Rollback window: 每次变更后 24 小时内（Claude 建议）
- Approver/date/signature: Founder，2026-10-15 14:37 +0800，typed approval（见 Approval record）

### FD-8 — Production cutover gate

- [x] Approve only the isolated empty Canonical runtime. （Claude 建议）
- [ ] Approve application staging integration after FD-1 through FD-7 are closed.
- [ ] Approve real-data migration and production cutover after a separate runbook review.
- [ ] Hold.

Required fields: exact target environment, change window, operator, preflight checklist, backup ID, rollback command/runbook, monitoring owner, abort conditions and post-cutover verification owner.

**Founder input:**

- Selected option: 选项 1 — 只批准腾讯云上的隔离空库，并允许把它更新到 0001–0008（按 `CODEX_INSTRUCTION_R6_TENCENT_F10_V1.0.md` 任务 B 执行）；应用联调与真实数据切换另批
- Target environment: 腾讯云 CVM 上的 `tencent-postgres-1` 容器，数据库 `phoenix_canonical_dev`，数据卷 `phoenix_canonical_pg16_data`；不开放公网端口
- Change window: 签名时未指定固定窗口；Founder 已于 2026-10-15 在会话中批准立即执行任务 B
- Operator and approver: 执行 Codex；复审 Claude；批准 Founder
- Rollback reference: Migration 原子回滚；`pg_hba.conf` 变更前备份；更新前备份（按任务 B 步骤 B1 记录备份 ID）
- Approver/date/signature: Founder，2026-10-15 14:37 +0800，typed approval（见 Approval record）

## Approval record

By signing or giving a typed approval tied to this file and its SHA-256, the approver confirms only the selected decisions. Unselected items remain `HOLD`.

- Register version: V1.0（Claude 预填版，2026-10-15；签名时未修改任何选择）
- Register SHA-256: 签名所依据的预填版为 `e6d1f2273ff534fb4f39c1ebe927b6e97bef446fad4e0a603aff32c196121247`；本签名版的 SHA-256 记录在 `evidence/approved/FOUNDER_DECISION_REGISTER_V1.0_APPROVAL.md`
- Founder/approver: Founder
- Role: Founder
- Date/time/timezone: 2026-10-15 14:37 +0800 (Asia/Shanghai)
- Signature or typed approval: "按预填确认，签名：Founder"（会话中的 typed approval）
- Scope of this approval: FD-1、FD-2（含 6 条补充裁定）、FD-3、FD-4、FD-5、FD-7、FD-8 按勾选生效；FD-6 维持 HOLD。签名时空缺的字段（FD-7 值班负责人、FD-8 固定变更窗口、FD-6 负责人）不视为已决定
