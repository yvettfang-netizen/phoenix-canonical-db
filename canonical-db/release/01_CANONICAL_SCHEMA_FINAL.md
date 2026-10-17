# 01 · Canonical Schema 最终说明（0001–0017）

**依据：**
- 本地开发库（PG16，已升级到 0017）的目录导出：`evidence/v1.8-schema-catalog-pg16.txt`，包括全部表、状态约束、触发器、策略、app 可执行函数；
- 已生效合同：EV-1（`3f73f167…`）、EV-3（`0d9fb898…`）、EV-4（`6e6c970d…`），以及补充 V1.1–V1.4；
- 代码：`migrations/canonical/0001–0017`（哈希见 `02`）。

**总量：** 10 个 schema，28 张表（27 张业务表加迁移账本），20 条 RLS 策略，100 个函数（其中 94 个为 SECURITY DEFINER）。

## 1. 架构原则

1. **唯一真相源：** PostgreSQL 是唯一的权威业务事实库。内部主键一律为 UUIDv7，在数据库边界校验（`core.is_uuid_v7`）。
2. **写入只经受控函数：** app 对任何业务表都没有 INSERT / UPDATE / DELETE 权限。每个写入函数都是 SECURITY DEFINER、固定 `search_path`、默认拒绝；每次判定（允许或拒绝）都写 `audit.access_events` 和 `PHOENIX_AUDIT` 服务器日志（D-9）。
3. **读取经 RLS：** 读取由可信上下文（`auth.session_contexts`）驱动。上下文只能通过一次性票据建立：binder 签发，app 兑换，有效期不超过 60 秒。上下文绑定在后端进程（PID + 启动时间）上；连接归还前必须清除。
4. **历史只追加：** 民事能力、官方事实、文档版本、已提交清单、状态事件，只能追加，不能修改。修正通过新增记录完成。

## 2. Schema 与表

| Schema | 表 | 要点 |
|---|---|---|
| `canonical_migrations` | `applied` | 迁移账本（文件名 + SHA-256）；reader 可读 |
| `auth` | `principals` | 登录主体，类型为 FAMILY / ADVISOR / CHANNEL / SERVICE；SERVICE 不对应自然人，其他类型必须对应且仅对应一个自然人（D-11）；状态为 ACTIVE / DISABLED |
| | `session_contexts` | 可信上下文：后端 PID + 启动时间、主体、操作人、家庭、渠道、请求编号、过期时间；INTERNAL 渠道没有操作人，可以不绑定家庭（D-10 / D-11） |
| | `context_exchange_tickets` | 一次性票据，有效期不超过 60 秒，兑换即删除，兑换时重新校验 |
| | `external_identities` | 签发方 + subject → 主体，同一组合只允许一条 ACTIVE（FD-6，0017）；开启 RLS，没有策略，只经函数访问 |
| `core` | `people` | 唯一的自然人主数据（展示名称） |
| | `families`、`family_memberships` | 家庭；成员关系有角色（PRIMARY / MEMBER）和有效期 |
| | `student_profiles` | 学生是自然人的一对一档案 |
| | `guardian_authorities` | 监护授权：证据等级 VERIFIED / SELF_DECLARED_LEGACY；范围 GENERAL / EDUCATION / IDENTITY，精确匹配；生命周期 ACTIVE / REVOKED / EXPIRED；证据引用与核验人 |
| | `civil_capacity_history` | 民事能力 ADULT_VERIFIED / MINOR_VERIFIED / UNVERIFIED，只追加；没有记录即为 UNVERIFIED（D-12） |
| `consent` | `grants` | 授权人、被授权人、主体、用途（DOCUMENT_READ / EDUCATION_CASE / IDENTITY_CASE）、数据类别；状态 ACTIVE / WITHDRAWN / EXPIRED，到期以判定时刻为准 |
| `casework` | `cases`、`advisor_assignments` | 通用个案（OPEN / PAUSED / CLOSED），可以引用一个申请或身份案件，但必须同一家庭、同一主体（0016）；顾问分配有有效期和生命周期 |
| `education` | `applications`、`application_status_events`、`external_facts` | 申请状态：DRAFT → READY → SUBMITTED → DECIDED，未决定前可以 WITHDRAWN；进入 DECIDED 须有 DECISION 事实（D-13） |
| `identity` | `cases`、`case_status_events`、`external_facts` | 案件状态：DRAFT → EVIDENCE_PENDING → UNDER_REVIEW → RESOLVED / CLOSED；DRAFT 与 EVIDENCE_PENDING 也可以直接 CLOSED（T4）；进入 RESOLVED 须有 DECISION 事实 |
| `docs` | `documents`、`document_versions`、`submission_manifests`、`submission_items` | 只存元数据，存储键须为 `mock/`；保留期必填；撤回只能设置一次（T3）；清单流程：准备 → 家庭确认 → 顾问或服务提交，确认人 ≠ 提交人，确认后锁定（D-14） |
| `integration` | `public_ids`、`legacy_id_mappings`、`channel_grants` | 公开 ID `per_ / fam_ / stu_ / gdn_`；旧 ID 映射（本阶段不使用）；渠道授权 |
| `audit` | `access_events` | 判定审计：attempt_id、请求编号、主体、操作人、家庭、动作、资源、判定、原因代码 |

**每张表的结构统计**（字段数、主键、外键、唯一、CHECK、触发器、RLS、策略数）：见证据文件第 1 节。
**全部状态取值约束：** 见证据文件第 2 节。

## 3. 角色模型

| 角色 | 类型 | 权限 |
|---|---|---|
| `phoenix_bootstrap` | 超级用户（安装用） | 安装、Migration；不是应用凭据 |
| `phoenix_canonical_migrator` | NOLOGIN 能力角色 | 安装器服务主体的创建 / 停用函数 |
| `phoenix_canonical_app` | NOLOGIN 能力角色 | 19 张 RLS 表的 SELECT；55 个函数的执行权；没有写表权限 |
| `phoenix_canonical_reader` | NOLOGIN 能力角色 | 19 张 RLS 表加迁移账本的 SELECT；15 个只读判定辅助函数 |
| `phoenix_canonical_context_binder` | NOLOGIN 能力角色 | 签发票据、清除上下文、解析外部身份；没有任何表权限 |
| `*_runtime`（部署）/ `*_local`（本地） | LOGIN | 各继承一个能力角色：`inherit=true`、`set=false` |
| `phoenix_canonical_backup_runtime` | LOGIN | BYPASSRLS + `pg_read_all_data`，只读，用于整库导出 |

完整清单见 `evidence/v1.8-security-catalog-pg16.txt`。

## 4. 写入 API（app 可执行，节选）

| 领域 | 函数 | 调用方 |
|---|---|---|
| 家庭与自然人 | `core.create_family`（未绑定家庭的服务）、`create_person`、`add_family_member`、`create_student_profile`、`end_family_membership`、`rename_person`、`rename_family`、`core.register_external_person` | SERVICE |
| 主体与身份 | `auth.create_login_principal`、`disable_login_principal`、`register_external_identity`、`disable_external_identity` | SERVICE |
| 授权与分配 | `core.create_guardian_authority` / `revoke_guardian_authority`、`casework.create_case` / `close_case` / `create_advisor_assignment` / `revoke_advisor_assignment`、`integration.create_channel_grant` / `revoke_channel_grant`、`core.set_civil_capacity` | SERVICE |
| Consent | `consent.create_grant` / `withdraw_grant` | 家庭一方（D-12） |
| 教育 / 身份 | `education.create_application` / `advance_application` / `record_external_fact`；`identity.create_case` / `advance_case` / `record_external_fact` | 家庭一方或有分配的顾问；DECIDED / RESOLVED 与官方事实只能由顾问或服务（D-13） |
| 文档与提交 | `docs.create_document` / `append_document_version`（服务）、`withdraw_document`、`create_submission_manifest`、`add_submission_item`、`confirm_manifest`（家庭一方）、`submit_manifest`（顾问或服务） | 见 EV-3 |

完整的函数签名清单见证据文件第 5 节。

## 5. 不在本 Schema 内（按已批准范围）

以下内容在架构文档中出现，但本阶段**未建，也不应自行建立**：
- 架构文档（Four-Portals V1.1）中的 `operations`（商务数据）、`organizations`、`relationships`、`roles` 等；
- 真实对象存储（EV-6）；
- 物理清除（F-08）；
- 双人复核（真实数据导入前另行设计）；
- 旧数据导入（FD-4）。
