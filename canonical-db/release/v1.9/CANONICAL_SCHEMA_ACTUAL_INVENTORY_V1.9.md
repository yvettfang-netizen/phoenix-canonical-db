# Canonical Schema 实际库存 V1.9（P0 只读核验）

**核验日期：** 2026-10-17
**核验方式：** 只读查询 PG16 本地开发库 `phoenix_canonical_dev`（已升级到 0017，业务数据为 0 行）。原始输出：`evidence/v1.9-inventory-pg16.txt`。Migration 哈希见 `release/02_MIGRATION_MANIFEST.md`。
**不代表生产：** 本地开发库与腾讯暂停库不同，腾讯库仍为 0001–0006。

## 1. Git 与交付基线

| 项 | 实际值 |
|---|---|
| 仓库 | `D:\CODEX\01_PHOENIX\01_NOVA\_worktrees\canonical-postgresql-phase1` |
| 分支 | `codex/canonical-postgresql-phase1` |
| 本地 HEAD | `32f6b1b`（核验时）|
| 未推送提交 | **8 个**（`4a9a29e`、`05fca5b`、`a1ec169`、`12e7a63`、`c5e81e6`、`74533a3`、`58096af`、`32f6b1b`）|
| 私有仓库 `phoenix-canonical-db` | 停在 `d3caaac`（领先 8 个提交未推送）|
| 公开仓库 `origin` | 无此分支（误推已删除，按 SHA 仍可访问，见 `09` H-8）|
| 工作树 | 核验开始时干净；本轮新增的未提交文件：`tests/owner_transfer.sql`、`tests/owner_transfer_check.sql`、`tests/f10_local_acceptance.sh`（加入可选 PoC 步骤）、`evidence/v1.9-*` |

## 2. Migration（实际 0001–0017）

17 个文件，全部在 `migrations/canonical/`，按编号顺序，账本 17 行，最后一条 `0017_external_identity_request_trace.sql`，与文件 SHA-256 一致。

| 编号 | 主要内容 |
|---|---|
| 0001 | 账本、角色、空的领域 schema |
| 0002 | education / identity 命名空间 |
| 0003 | 自然人、家庭、成员、学生档案、监护、主体、上下文、Consent、公开与旧 ID 映射、渠道授权、审计、RLS |
| 0004 | 通用个案、顾问分配、教育申请、身份案件、状态事件、外部事实 |
| 0005 | 文档、版本、提交清单与条目 |
| 0006 | 访问判定 API |
| 0007 | 上下文绑定后端（PID + 启动时间）、一次性票据、生命周期 |
| 0008 | 到期归一、临时状态清理 |
| 0009 | 应用写入 API |
| 0010 | reader 读迁移账本（R-8）|
| 0011 | D-12 民事能力、D-13 官方事实、D-14 确认与提交分离 |
| 0012 | D-11 服务主体不占自然人；R-20 主体类型与渠道对应 |
| 0013 | D-10 引导与 SERVICE 管理接口 |
| 0014 | D-9 审计双写（`PHOENIX_AUDIT` + attempt_id）|
| 0015 | EV 缺口 T1–T4（成员关系、改名、顾问读文件须有分配、文档撤回、身份案件提前结案）|
| 0016 | V16-F1/F2/F3：个案状态与资源主体一致、重复授权审计拒绝 |
| 0017 | FD-6：外部身份映射（`auth.external_identities`）、请求编号进入审计 |

## 3. 表（27 张业务表，9 个 schema）

**核对结果：27 张，与 `release/01` 一致。** 另有迁移账本 `canonical_migrations.applied`，共 28 个关系。

| Schema | 表 | 行数（开发库） |
|---|---|---|
| auth | principals、session_contexts、context_exchange_tickets、external_identities | 0 |
| core | people、families、family_memberships、student_profiles、guardian_authorities、civil_capacity_history | 0 |
| consent | grants | 0 |
| audit | access_events | 0 |
| integration | public_ids、legacy_id_mappings、channel_grants | 0 |
| docs | documents、document_versions、submission_manifests、submission_items | 0 |
| casework | cases、advisor_assignments | 0 |
| education | applications、application_status_events、external_facts | 0 |
| identity | cases、case_status_events、external_facts | 0 |

- **外键：** 64 条。
- **RLS：** 27 张中 22 张启用。未启用的 5 张是 `auth.principals`、`auth.session_contexts`、`auth.context_exchange_tickets`、`integration.public_ids`、`integration.legacy_id_mappings`，它们没有授予 app / reader 任何直接权限，只经 SECURITY DEFINER 函数访问。
- **启用 RLS 但没有策略的 2 张：** `core.civil_capacity_history`、`auth.external_identities`。对非属主角色是默认拒绝，只能经函数访问。这是设计如此，但需要在文档中明示。
- **策略：** 20 条，分布在 20 张表上。
- **RLS 不强制属主：** 所有表 `relforcerowsecurity = false`，属主（当前为超级用户）绕过 RLS。见 `DATABASE_OWNER_SECURITY_DECISION_V1.0.md`。

## 4. 函数与服务接口

| 类别 | 数量 | 说明 |
|---|---|---|
| 业务 schema 内函数 | 100 | auth 23、core 23、docs 17、casework 8、education 9、identity 9、consent 6、audit 2、integration 3 |
| SECURITY DEFINER | 94 | 全部固定 `search_path`；没有动态 SQL；PUBLIC 可执行为 0 |
| 属主 | 100 | 全部为超级用户 `phoenix_bootstrap`（PoC 之前）|
| app 可执行 | 55 | 写入接口（见 `release/01` 第 4 节）+ 只读辅助 |
| binder 可执行 | 6 | `auth.bind_context`（旧入口，见 `DATABASE_OWNER_SECURITY_DECISION` 的 S-2）、`auth.issue_context_ticket`、`auth.clear_context`、`auth.cleanup_ephemeral_state`、`auth.cleanup_stale_contexts`、`auth.resolve_external_identity` |
| reader 可执行 | 15 | 判定辅助函数（只读）|
| migrator 可执行 | 3 | `auth.install_service_principal`、`auth.disable_service_principal`、`auth.sweep_expired_authorizations` |

完整签名清单：`evidence/v1.9-inventory-pg16.txt` 的 APP / BINDER / READER / MIGRATOR 段。

## 5. 与 `release/00–10` 的核对

| 文件 | 存在 | 核对结论 |
|---|---|---|
| 00 剩余工作登记 | 是 | 与本库存一致。待更正：W-26 中"125 个悬空卷"为核验时的数量，见 `FOUNDER_DECISION_REQUIRED_V1.9` |
| 01 Schema 最终说明 | 是 | 表数、函数数、RLS 数均一致。**更正：** 该文档称"约 100 个函数"与实测 100 一致；未提 RLS 启用但无策略的 2 张表，本文件补充 |
| 02 Migration 清单 | 是 | 哈希一致。**更正：** 0017 的"首次提交"写为"V1.8 提交"，已改为 `c5e81e6` |
| 03 测试矩阵 | 是 | PG16 / PG17 结果与证据文件一致 |
| 04 安全审计 | 是 | 函数数、属主、权限与本库存一致 |
| 05 备份恢复报告 | 是 | 已修正为 8–9 秒 |
| 06 数据迁移计划 | 是 | 仅为计划，无执行 |
| 07 部署手册 | 是 | 手册步骤已在本地演练 |
| 08 回滚手册 | 是 | 未在生产执行 |
| 09 风险与 HOLD | 是 | 与本库存一致 |
| 10 交接报告 | 是 | **更正：** 提交表漏列 `58096af`（悬空卷清理）和 `32f6b1b`（演练证据刷新），已在 `release/10` 中补列（本轮修正）|

## 6. 模块状态（本库存视角）

| 模块 | 状态 | 依据 |
|---|---|---|
| 身份、家庭、成员、学生档案 | IMPLEMENTED | 表 + 写入接口 + F10 |
| 监护、民事能力、Consent | IMPLEMENTED | 0003、0011、0013 + D6 / G1–G5 |
| 顾问分配、渠道授权 | IMPLEMENTED | 0004、0013、0016 + T2 |
| 教育申请与状态、官方事实 | IMPLEMENTED（范围窄）| 0004、0009、0011 |
| 文档、版本、提交清单 | IMPLEMENTED（只存元数据）| 0005、0009、0011、0015 |
| 审计（双写、对账）| IMPLEMENTED | 0014、D-9 对账 |
| 外部身份映射、请求编号 | IMPLEMENTED | 0017、`f10_v18` |
| 学历、成绩、语言考试、目标学校、Offer、签证、套餐、合同、回款 | MISSING | 库中无对应表 |
| 启明堂课程与教学 | MISSING | 库中无表；源文档未找到 |
| ASKWISE 学习与认知 | MISSING | 库中无表；源文档部分找到（见 `ASKWISE_CANONICAL_MAPPING_V1.0.md`）|
| Family OS 成长摘要 | MISSING | 库中无表 |
