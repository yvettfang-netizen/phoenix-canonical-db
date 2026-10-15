# Phoenix Canonical PostgreSQL — Claude 独立审计报告 V1.0

| 项 | 值 |
|---|---|
| 审计执行 | Claude（独立于 Codex 实施方） |
| 审计时间 | 2026-10-15 10:19–10:45（Asia/Shanghai, +08:00） |
| 审计依据 | `phase2-gate/CLAUDE_CANONICAL_DATABASE_AUDIT_INSTRUCTION_V1.0.md`（SHA-256 前缀 `b051be873bf742ec`），以及 Founder 在会话中提交的同等审计要求 |
| 审计范围 | 仅 `canonical-db/`：代码、Migration、测试、部署包、执行报告、`phase2-gate/` 合同、审批与证据文件 |
| 仓库 / 工作树 | `D:\CODEX\01_PHOENIX\01_NOVA\_worktrees\canonical-postgresql-phase1` |
| 分支 | `codex/canonical-postgresql-phase1`（领先 `origin/main` 13 个提交；merge-base `846f77c120cd00a49d89635dd4297b020af7d03a`） |
| HEAD | `c34fd3eab6f3fe9d1e83dce392fbd8041c585450`（2026-10-14 10:45:14 +0800，`feat(canonical-db): complete greenfield phase 3`） |
| 工作树状态 | **不干净**：7 个已跟踪文件有未提交修改，5 个文件及 2 个证据目录未跟踪（见 §2.1） |

## 0. 一页结论

```text
CODE_AUDIT               = CONDITIONAL
LOCAL_RUNTIME            = CONDITIONAL
TENCENT_ISOLATED_RUNTIME = EVIDENCE_MISSING
PRODUCTION_READY         = NO
```

| 层级 | 结论 | 一句话理由 |
|---|---|---|
| 本地代码 | **CONDITIONAL** | Migration 机制（独立命名空间、SHA-256 锁定、重复执行、漂移拒绝、原子回滚）均成立。但访问控制代码有 **4 项高危缺陷已实测确认**：重启后会话上下文可被新连接继承；跨家庭泄露顾问分配记录；binder 与 app 分离凭据的设计无法工作；应用角色没有任何写入通道。 |
| 本地 PG16/PG17 | **CONDITIONAL** | 在一次性隔离容器中，Codex 的 6 套验收在 PG16.15 与 PG17.11 上全部复现通过。但本审计另行编写的独立反向测试中，**9 项与合同或隔离目标不符**（§5），两个版本结果一致。 |
| 腾讯云隔离运行时 | **EVIDENCE_MISSING** | 按本次指令未连接腾讯云。Codex 的 PASS 结论只有其报告文字和命令记录，**没有原始输出**。本审计最后一次直接观察是 2026-10-14 16:41，当时数据库**尚未安装**。部署包配置层面无 5432 主机端口映射、镜像摘要已锁定，但运行时状态无法独立核实。 |
| 正式生产就绪 | **NO** | Founder 决策登记 FD-1 至 FD-8 全部空白；证据 EV-1 至 EV-8 全部缺失（`evidence/incoming/` 与 `approved/` 只有 `.gitkeep`）；应用鉴权在技术上尚不可行（F-01、F-02）；未做过跨集群灾备恢复（F-11）。宿主机仍处于安全事件状态 NOT TRUSTED。 |

> **隔离空库通过不等于真实生产切换通过。** 本地或腾讯云的空库能初始化、能迁移、能通过合成测试，只能证明 Schema 机制可运行。它不证明身份合同已生效，不证明应用鉴权可用、可在新主机恢复，也不等于获准导入真实数据或切换生产。

## 1. 审计方法与边界

### 1.1 证据等级

| 等级 | 含义 |
|---|---|
| **VERIFIED-RUN** | 本审计在一次性隔离容器中实际执行，并读取到输出 |
| **VERIFIED-FILE** | 本审计直接读取文件或 Git 对象核对，包括 SHA-256 计算 |
| **OBSERVED-PRIOR** | 本审计在此前会话（2026-10-14 16:38–16:41）对腾讯云做过只读观察，时间点早于数据库安装 |
| **REPORTED** | 只有 Codex 的报告或聊天记录陈述，本审计无法独立核实 |
| **EVIDENCE_MISSING** | 无可用证据 |

### 1.2 实际执行的操作

- 读取全部列明文件：`README.md`、`PHASE1_REPORT.md`、`PHASE2A_EXECUTION_REPORT.md`、`PHASE2B_EXECUTION_REPORT.md`、`PHASE2B_AUDIT_REPORT.md`、`PHASE2C_EXECUTION_REPORT.md`、`PHASE3_EXECUTION_REPORT.md`、`TENCENT_DEPLOYMENT_EXECUTION_REPORT.md`；`phase2-gate/` 下的全部合同、审批、方案和证据请求文件；0001–0006 全部 Migration；`tests/`、`scripts/db.ps1`、`compose.yaml`、`deploy/tencent/`。另读取 Founder 提供的 Codex 会话导出（`数据库new.docx`，602,368 字符，保存于 2026-10-15 10:13）作为 REPORTED 线索。
- **独立运行时复现**：启动一次性容器，参数为 `--network none`、仓库只读挂载、纯合成数据；结束后删除容器。使用的镜像：
  - PG16：`postgres@sha256:ca0bd484cb98bf4b24eb1010e73fb3fcbd6714d240fbc1a10eea5b7dbecb641d`，与腾讯部署包锁定的摘要相同，`POSTGRES_INITDB_ARGS` 也与腾讯 compose 一致。
  - PG17：`postgres@sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3`，即本机当前的 `postgres:17`。
- 迁移执行器按 `deploy/tencent/install.sh` 的算法复刻：先算 SHA-256，再查账本；剥离外层 `BEGIN/COMMIT` 后，正文与账本写入在同一事务内完成，并持 advisory lock。

### 1.3 未执行的操作（遵守审计边界）

- 未连接腾讯云，未使用任何生产密钥，未读取任何 `.env` 或 `.local-roles.env` 的内容（只检查了是否存在和文件大小）。
- 未修改任何代码、Migration、Compose、脚本或合同文件。本报告是唯一新增文件。
- 未执行部署、Push、Merge、DROP、TRUNCATE，也未重置 Codex 的任何数据库。Codex 的 `db.ps1 -Action test/restore-test/audit-backup` 会重置白名单测试库，因此**未重跑**，只做了代码审阅。`mock-object-store.ps1` 会向工作树 `runtime/` 写入文件，因此也未重跑。
- 环境变化披露：审计开始时 Docker Desktop 未运行，本审计启动了它，用于一次性容器。Codex 的本地容器 `phoenix-canonical-foundation-pg16-1` 与 `-pg17-1` 保持 `Exited` 状态，未启动、未改动。
- 本报告不含任何密钥值、真实个人信息或 IP 地址。

## 2. 事实：Git、文件与 Migration

### 2.1 工作树与已部署内容的关系（VERIFIED-FILE）

`git status` 显示，以下已跟踪文件相对 HEAD `c34fd3e` 有未提交修改：

| 文件 | 工作树 SHA-256 前缀 | HEAD 中的 SHA-256 前缀 |
|---|---|---|
| `deploy/tencent/compose.yaml` | `377fef87424f5194` | `ffb6c2fbb1eff20e` |
| `deploy/tencent/install.sh` | `a6a747dd91dbc027` | `85482415b8b08fab` |
| `deploy/tencent/health.sh` | `82d3f05394a6dfbb` | `754d3b70af353e4e` |
| `deploy/tencent/backup.sh` | `78d51e755f178623` | `8cbf84db38b6d328` |
| `deploy/tencent/README.md` | `a187a2f008d3ebce` | `9d8a9b86e82c3d44` |
| `deploy/tencent/.env.example` | `cb0405675ab1ec7e` | `cb0405675ab1ec7e`（相同） |
| `PHASE3_EXECUTION_REPORT.md`、`README.md` | 已修改 | — |

未跟踪：`TENCENT_DEPLOYMENT_EXECUTION_REPORT.md`，以及 `phase2-gate/` 下的 `CLAUDE_CANONICAL_DATABASE_AUDIT_INSTRUCTION_V1.0.md`、`PRODUCTION_DATABASE_EVIDENCE_REQUEST_V1.0.md`、`PRODUCTION_DATABASE_FOUNDER_DECISION_REGISTER_V1.0.md`、`PRODUCTION_DATABASE_PACKAGE_README.md`、`PRODUCTION_DATABASE_SOLUTION_V1.0_DRAFT.md`，和 `evidence/approved/`、`evidence/incoming/`（两个目录都只有 `.gitkeep`）。

**事实：** 按 Codex 的陈述，腾讯云运行的是工作树里的部署文件，不是任何 Git 提交中的版本。腾讯运行时无法从提交复现（见 F-14）。

### 2.2 Migration 清单与哈希（VERIFIED-FILE + VERIFIED-RUN）

| Migration | 实测 SHA-256 | 与 `PHASE3_APPROVAL_REGISTER.md` 一致 |
|---|---|---|
| `0001_foundation.sql` | `eea8d1deece72afdc3832d075fcfb42b71b4c1fe4fdccc8900104a0e0ca78a2d` | 是 |
| `0002_education_identity_skeleton.sql` | `bef7d9a902e8ad34491b7455987d7791667dcb8a5ab31945cf609a6aa97e4e7f` | 是 |
| `0003_core_consent_access.sql` | `7dc0c5060237fae9069915ba8a1ecc39323cf74ab8ea0d49dd832ef9d8330618` | 是 |
| `0004_casework_education_identity.sql` | `aec2be38c6ad363f5594d65016b8a2dfcb79fe76e77a225271379bb991a443e9` | 是 |
| `0005_documents_submissions.sql` | `7bd581d16bb8c21278bd5bc013496779fe08f509d84bf74b652e5ce3b21cdbec` | 是 |
| `0006_access_decision_api.sql` | `2a3d6cd19febd62b7128c9ad4a2d7c94abdb9a4e11d499f36f4050eb2c2ed9d8` | 是 |

- Migration 账本是独立的 `canonical_migrations.applied`，目录 `migrations/canonical/` 下只有 0001–0006，**未复用**旧 EC `006`、PR #14 `0010+` 或 SQLite 系列。**PASS**
- 自 Phase 3 提交以来，6 个 Migration 文件字节未变（与 HEAD 一致）。**PASS**

## 3. CODE_AUDIT — 本地代码

### 3.1 Schema 与约束（VERIFIED-RUN，PG16 与 PG17 结果相同）

| 指标 | 实测 |
|---|---|
| Schema | `audit, auth, canonical_migrations, casework, consent, core, docs, education, identity, integration`；**没有** `documents` |
| 业务表 | 24 张；20 张启用 RLS，0 张 FORCE RLS |
| 未启用 RLS 的表 | `auth.principals`、`auth.session_contexts`、`integration.public_ids`、`integration.legacy_id_mappings`（app 与 reader 对这些表无表权限，见 §3.3） |
| 约束 | FK 42，UNIQUE 12，PK 24，CHECK 70 |
| 索引 | 37，其中部分唯一索引 1 个（`one_verified_legacy_mapping`） |
| RLS 策略 | 20 条，**全部为 SELECT** |
| 触发器 | 8 |
| SECURITY DEFINER 函数 | 21，全部固定了 `search_path`；PUBLIC 可执行的函数为 0 |
| 自然人主数据 | 只有 `core.people` 一个；Student 是 `core.student_profiles`（以 person_id 为 PK）；Guardian 是 `core.guardian_authorities` 关系。**未发现重复的自然人或家庭主数据表。** |
| 历史 ID | `integration.legacy_id_mappings` 只有表结构、无数据；要求 `source_system + entity_kind + legacy_id`，每个来源最多一条 VERIFIED 映射。**未发现未经批准的历史映射或真实数据迁移。** |
| 隐含业务语义 | Education 状态 `DRAFT/READY/SUBMITTED/DECIDED/WITHDRAWN`、Identity 状态、Consent 用途与数据分类、公开 ID 前缀 `per_/fam_/stu_/gdn_`，都来自 Codex 起草的 `CANONICAL_BUSINESS_CONTRACT_V1.0_EFFECTIVE.md`，未见签署记录（F-17、F-18） |

### 3.2 Migration 机制（VERIFIED-RUN）

| 检查 | PG16.15 | PG17.11 | 证据 |
|---|---|---|---|
| 全新执行 0001–0006 | PASS | PASS | 6 条 `APPLIED`，哈希与 §2.2 一致 |
| 重复执行 | PASS | PASS | 6 条 `SKIP … checksum verified` |
| 漂移拒绝（在 scratch 副本中给 0002 追加一行注释） | PASS | PASS | `REFUSED … registered bef7d9a902e8… vs file 888558f39b36…`；账本仍为 `bef7d9a902e8ad34` |
| 强制失败的原子回滚（`tests/9000_atomicity_probe.sql`） | PASS | PASS | `ERROR: SYNTHETIC FORCED MIGRATION FAILURE`；无残留 schema，账本无 9000 记录，总数仍为 6 |
| `install.sh` 的嵌套事务检查 | — | — | 代码审阅：`db.ps1` 会拒绝正文内的 `BEGIN/COMMIT/ROLLBACK`，`install.sh` **没有这项检查**（F-20） |

### 3.3 角色与权限（VERIFIED-RUN + VERIFIED-FILE）

| 角色 | 实测或代码属性 | 结论 |
|---|---|---|
| `phoenix_bootstrap` | LOGIN、SUPERUSER、BYPASSRLS | 安装用超级用户；`install.sh` 通过容器本地 socket 使用它，无需口令（见 F-12） |
| `phoenix_canonical_migrator` | NOLOGIN、NOINHERIT；可对各 schema 做 DDL，可读写账本 | PASS |
| `phoenix_canonical_app` | NOLOGIN；可 SELECT 19 张表；**INSERT/UPDATE/DELETE/TRUNCATE 授权为 0**；可执行 16 个函数，其中 4 个 VOLATILE（审计写入 1 个、授权判断 3 个） | 没有任何业务写入路径（F-10） |
| `phoenix_canonical_reader` | NOLOGIN；与 app 相同的 RLS 读取，外加 `audit.access_events` 读取 | PASS（只读） |
| `phoenix_canonical_context_binder` | NOLOGIN；只能执行 `auth.bind_context` 和 `auth.clear_context` | 角色本身 PASS；分离凭据的设计无法工作（F-02） |
| `phoenix_canonical_backup_runtime`（只在 `deploy/tencent/install.sh` 工作树版本中） | LOGIN、NOSUPERUSER、**BYPASSRLS**、继承 `pg_read_all_data`、**无口令**，只经本地 socket 使用 | 可读全库，绕过 RLS；用于备份可以接受，但需受控（F-19） |
| `*_runtime` 登录角色 | `GRANT … WITH INHERIT TRUE, SET FALSE` | 实测无法 `SET ROLE` 切换到其他能力角色。PASS |

**health 与 backup 是否绕过 bootstrap：**

- 工作树版本的 `health.sh` 用 `phoenix_canonical_reader_runtime` 执行 `pg_isready`，用 `phoenix_canonical_migrator_runtime` 执行查询；`backup.sh` 用 `phoenix_canonical_backup_runtime`。两者都不再用 `env PGPASSWORD` 传递 bootstrap 口令。**按文件判定：PASS**
- 但 `pg_hba` 实测为 `local all all trust`（F-12）：容器内任何 socket 连接都可以无口令以任意角色登录，**包括 bootstrap 超级用户**。"不使用 bootstrap"只是脚本自愿遵守，不是技术强制。用 DDL 角色 migrator 做健康检查也属于权限过大。
- HEAD `c34fd3e` 中的版本仍然用 bootstrap 并在命令行传口令；修正只存在于未提交的工作树（F-14）。

### 3.4 文档、提交与对象存储（VERIFIED-RUN + 代码审阅）

| 规则 | 结论 | 证据 |
|---|---|---|
| 文档版本不可静默覆盖或删除 | PASS | 触发器 `immutable_document_version`；Codex 验收与本审计 T12b 都被 `DOCUMENT_VERSION_IMMUTABLE` 拒绝 |
| 已提交 Manifest 及其条目不可修改或删除 | PASS | 触发器 `protect_submission_manifest`、`validate_submission_item`；Codex 验收通过 |
| 已撤回的文档不能进入新提交，既有快照保留 | PASS | Codex 验收与 Phase 2C 结果复现通过 |
| Legal Hold 阻止清除判定 | PASS（仅判定函数） | `docs.can_purge_document` |
| **物理清除路径** | **HOLD** | `can_purge_document` 返回 true 时，版本行仍无法删除（T12/T12b）。DS-5 规定的清除流程无法实现（F-08） |
| Manifest 目标的引用完整性 | **FAIL** | `target_id` 不是外键；家庭 A 的 Manifest 可以指向家庭 B 的申请，也可以指向不存在的 Identity Case（T8/T8b，F-07） |
| 对象存储 | **HOLD（只有 Mock）** | 只有 `scripts/mock-object-store.ps1`（未重跑）。Tencent 只部署了元数据。**没有任何真实 COS 或私有对象存储的生产证据** |

### 3.5 已确认的代码缺陷（详见 §5 测试与 §7 发现表）

F-01、F-02、F-03、F-10 为高危，F-04 至 F-09 为中危。**代码在修复前不得承载真实数据。**修复应通过新的 `0007+` Migration 完成，不改动 0001–0006。

## 4. LOCAL_RUNTIME — 本地 PG16 / PG17

### 4.1 Codex 验收套件复现（VERIFIED-RUN）

| 测试文件 | PG16.15 | PG17.11 |
|---|---|---|
| `foundation.sql` | PASS | PASS |
| `rls_probe.sql` | PASS | PASS |
| `docs_probe.sql` | PASS | PASS |
| `contract_neutral_probe.sql` | PASS | PASS |
| `trusted_context_probe.sql` | PASS | PASS |
| `phase3_acceptance.sql` | PASS | PASS |
| 测试后 `acceptance_probe` 已清除，业务表行数为 0 | PASS | PASS |

**方法局限：** Codex 的套件全部以超级用户运行，在**同一个后端连接**里用 `SET ROLE phoenix_canonical_context_binder` 绑定上下文，再 `SET ROLE phoenix_canonical_app` 查询（`phase3_acceptance.sql` 第 106–214 行）。真实部署中的登录角色是 `SET FALSE`，无法这样切换。因此套件没有覆盖真实的凭据分离场景（见 T4 与 F-02）。

### 4.2 本地开发库当前状态

Codex 的 `phoenix-canonical-foundation-pg16-1` 与 `-pg17-1` 在审计时处于 `Exited` 状态（Docker Desktop 此前未运行）。本审计未启动它们。最近一次只读目录查询是本审计在 2026-10-14 做的，结果：6 个 Migration、24 张表、20 条策略、0 行业务数据，与报告一致。**当前状态：EVIDENCE_MISSING（容器停止），历史值：OBSERVED-PRIOR 一致。**

### 4.3 备份、恢复与篡改（VERIFIED-RUN + 代码审阅）

| 检查 | 结论 | 证据 |
|---|---|---|
| Codex 本地 `restore-test`、`audit-backup`（篡改拒绝） | **REPORTED + 代码审阅通过，未重跑** | 重跑会重置白名单库，审计边界禁止。代码确认先校验 manifest 和摘要，再重置恢复库 |
| 用 backup 角色（BYPASSRLS + pg_read_all_data）导出 | PASS | 134,371 字节的自定义格式导出 |
| 同集群恢复（角色已存在，`--no-owner`） | PASS | 0 错误，20 条策略 |
| **恢复到全新集群**（模拟新主机灾备） | **FAIL** | 71 个错误，全是 `role "…" does not exist`；恢复后 24 张表、**0 条策略、0 个 canonical 角色**、账本 6 行（F-11） |
| 字节篡改 | CONDITIONAL | 导出文件改动 1 个字节后，`pg_restore -l` 仍能列出目录，只有 manifest 中的 SHA-256 能发现；manifest 未签名，且与导出文件放在一起（F-13） |
| 镜像摘要 | CONDITIONAL | 腾讯 compose 锁定 `ca0bd484…`；本地 `compose.yaml` 用的是**标签** `postgres:16` 和 `postgres:17`，未锁摘要（F-15） |

## 5. 独立反向测试结果（VERIFIED-RUN，PG16 与 PG17 结果相同，T5 只在 PG16 上做）

测试使用纯合成数据：家庭 A（家长 A1、学生 A2）、家庭 B（家长 B1、学生 B2）、一名顾问（只分配到家庭 B 的一个案件）、一个渠道主体（只对 B2 有授权）。SQL 全文见附录 A。

| ID | 测试 | 期望（合同或隔离目标） | 实测 | 判定 |
|---|---|---|---|---|
| T1 | 家庭 A 成员查询 `casework.advisor_assignments` | 只能看到本家庭的记录 | **可见 1 行，正是家庭 B 案件的分配记录**；对照项 `casework.cases` 可见 0 行 | **FAIL（跨家庭泄露）** |
| T2 | 渠道主体只对 B2 有授权，查询 `core.people` | 只能看到 B2 | **可见 B1 和 B2**；memberships 2 行、student_profiles 1 行 | **FAIL（越出授权主体）** |
| T3 | 顾问无 Consent，查询 `core.people` 与 memberships | 合同规定须同时有分配和 Consent | **可见 B1、B2 和 2 条 memberships**；对照项 `education.applications` 为 0 | **FAIL（无 Consent 即可读取）** |
| T4 | binder 与 app 用**两个真实登录角色**分别连接 | app 能使用 binder 绑定的上下文 | binder 的绑定只存在于它自己的后端（pid 580/577）；app 新连接 `current_family_id=NULL`、可见家庭 0；app 调用 `bind_context` 报 `permission denied`；`SET ROLE` 报 `permission denied` | **FAIL（设计无法工作）** |
| T4b | binder 断开连接但未调用 `clear_context` | 上下文随之失效 | **残留 1 行，剩余有效期 22 小时 59 分** | **FAIL** |
| T5 | 残留上下文 → 重启 → 新的 app 连接（从未绑定） | 无上下文 | 3 轮中第 2 轮：新连接 pid 46 **继承了家庭 A 的上下文，可见 1 个家庭、2 个人** | **FAIL（高危，可复现）** |
| T6 | Consent 撤回后重新授予，或重新激活 | 应可以重新同意 | 新授予被 `unique_violation` 阻止；重新激活被 `CONSENT_TRANSITION_INVALID` 阻止 | **FAIL（业务死锁）** |
| T7 | app 直接调用 `audit.record_access_event('…','ALLOW','FORGED_BY_APP_ROLE')` | 审计事件只能由受控判定产生 | **写入成功，伪造的 ALLOW 记录 1 行** | **FAIL（审计可伪造）** |
| T8 | 家庭 A 的 Manifest 指向家庭 B 的申请，或指向不存在的 Identity Case | 拒绝 | **两项都被接受** | **FAIL** |
| T12 | 已过保留期、无 Legal Hold、未提交的版本，执行物理清除 | 合同规定可清除 | 判定 `can_purge_document=true`，但 DELETE 被 `DOCUMENT_VERSION_IMMUTABLE` 阻止 | **FAIL（清除路径无法实现）** |
| T13 | 监护人 A1（VERIFIED，scope=EDUCATION），有 DOCUMENT_READ/EDUCATION Consent，读取 A2 的 EDUCATION 文档 | 应当允许 | 可见 0 行；`authorize_document_read=false`，原因为 `CONSENT_AUTHORITY_OR_CHANNEL_DENIED` | **FAIL（scope=EDUCATION 不起作用）** |
| T10 | 容器 `pg_hba` | 应要求口令 | `local all all trust`：t_backup 与 phoenix_bootstrap 经 socket 无口令登录成功 | **CONDITIONAL**（F-12） |

**合计：独立反向测试 13 项，FAIL 9 类，CONDITIONAL 1 类。PG16 与 PG17 结果相同。**

## 6. TENCENT_ISOLATED_RUNTIME — 腾讯云隔离运行时

### 6.1 Codex 报告的结论（REPORTED，未独立核实）

`TENCENT_DEPLOYMENT_EXECUTION_REPORT.md`（SHA-256 前缀 `cf078276e4e0a66f`）称：

- 部署路径 `/home/ubuntu/phoenix-canonical-db-deploy`，数据库 `phoenix_canonical_dev`，PostgreSQL 16.15，Docker 29.1.3 / Compose 2.40.3。
- 6/6 Migration 已执行，24 张表，20 条 RLS 策略，0 行业务数据。
- 容器 `tencent-postgres-1` 健康，无主机端口映射，宿主机 5432 只监听 127.0.0.1。
- 备份 `backups/phoenix_canonical_20261014T092721Z.dump`，SHA-256 `4d80b750…`，`pg_restore -l` 列出 299 项，文件权限 600。

Codex 的会话导出中**只有命令和文字总结，没有原始输出**。本审计未连接服务器，**上述每一项都是 EVIDENCE_MISSING（独立核实）**。

### 6.2 本审计可核实的部分

| 检查 | 结论 | 等级 |
|---|---|---|
| 部署 compose 没有 `ports:`，网络为 `internal: true` | PASS（配置层面） | VERIFIED-FILE；`docker compose config --quiet` 通过 |
| 镜像摘要锁定 `mirror.ccs.tencentyun.com/library/postgres@sha256:ca0bd484…`，与本地测试的 PG16 镜像 ID 相同 | PASS（配置层面） | VERIFIED-FILE |
| 部署包中没有恢复脚本、定时备份、异地副本、保留策略或加密 | **HOLD** | VERIFIED-FILE（检索 `restore`、`cron`、`cos`、`retention` 均无结果） |
| 部署包与 Git 提交的对应关系 | **FAIL**：只存在于未提交的工作树 | VERIFIED-FILE（§2.1） |
| 部署凭据保存在本机 | `deploy/tencent/.env` 存在（500 字节，2026-10-14 16:39），已被 gitignore 忽略，内容未读 | VERIFIED-FILE（F-16） |
| 数据库安装前的宿主机状态（2026-10-14 16:38–16:41） | 刚安装 Docker（16:35:49），16:40:43 拉取镜像，**当时还没有 canonical 容器**；宿主机原生 PG16 监听 127.0.0.1:5432；sshd `PasswordAuthentication yes`、`PermitRootLogin yes`；fail2ban 未运行 | OBSERVED-PRIOR |
| 宿主机安全状态 | `D:\CODEX\2026-10-11\incident-P0\06_RESIDUAL_RISK_AND_FOUNDER_GATE.md`：A0 未通过、A4 OPEN、NOT TRUSTED；G-1 至 G-8 未关闭 | VERIFIED-FILE（审计范围外的参考） |
| 流程事实 | Codex 自述：Founder 要求"暂停在 install.sh 之前"时，已在运行的远端安装仍完成了 6 个 Migration；旧上传目录 `/home/ubuntu/phoenix-canonical-db` 只做了部分清理 | REPORTED；当前状态 EVIDENCE_MISSING |

**判定：TENCENT_ISOLATED_RUNTIME = EVIDENCE_MISSING。** 配置层面隔离（无主机端口、私有网络、摘要锁定）成立。运行时是否健康、端口是否确实未发布、库是否为空、账本哈希与角色是否正确、备份文件是否存在，都需要按 §9 第 4 项取得原始输出。

## 7. 发现、风险与证据汇总

| ID | 严重度 | 发现 | 证据 | 影响 | 关闭所需证据 |
|---|---|---|---|---|---|
| F-01 | **高** | 可信上下文只按 `backend_pid` 存储在普通表中：断开后不清除，重启后保留；PID 复用时新连接会继承他人上下文 | T4b、T5；`0003` 中 `auth.session_contexts` 与 `auth.current_*()` | 未鉴权的连接读取某个家庭的数据 | 新 Migration 把上下文绑定到会话唯一标识（如 `backend_start` 加随机 nonce，或 UNLOGGED 表加启动清理），并在真实登录角色下复测 T4b、T5 |
| F-02 | **高** | binder 与 app 分离凭据时，上下文无法传给 app；Codex 测试只在超级用户 `SET ROLE` 下通过 | T4；合同 §Trusted session binding 第 1 条 | 合同规定的生产鉴权模型无法实施；若把 binder 权限交给 app，又会失去防伪造能力 | 经批准的可信上下文机制（EV-7），并有分离凭据下的 PG16/17 实测 |
| F-03 | **高** | `assignments_read` 策略缺少家庭过滤，任一家庭成员可读取全库顾问分配记录 | T1；`0004` 中 `assignments_read` | 跨家庭泄露案件与顾问关联 | 新策略限定在 `case.family_id = current_family`，并加入 T1 回归测试 |
| F-04 | 中高 | PARTNER 与 ADVISOR 渠道可读取整个家庭的 `core.people`、memberships 和 student profiles，不受授权主体或 Consent 限制 | T2、T3；合同 §Consent and authority 第 4 条 | 越出授权主体的身份信息暴露 | 按渠道细化 core 策略并回归测试 |
| F-05 | 中 | app 可直接写入任意 decision/reason 的审计事件 | T7 | 审计可被伪造或污染 | 撤销 app 对 `audit.record_access_event` 的 EXECUTE，只保留内部调用 |
| F-06 | 中 | Consent 撤回后无法重新授予（唯一约束加触发器）；`advisor_assignments`、`guardian_authorities` 的唯一键也有同样结构（代码审阅） | T6 | 正常业务流程被卡死 | 唯一约束改为只约束有效记录，或采用版本化记录 |
| F-07 | 中 | Manifest 的 `target_id` 没有引用完整性，跨家庭目标可被接受 | T8 | 递交证据可能挂错案件或家庭 | 外键或校验触发器；DS-2 最终决定 |
| F-08 | 中 | 物理清除路径无法实现 | T12 | DS-5 保留与清除合同无法落地 | EV-3 与 EV-6，以及受控清除流程 |
| F-09 | 低中 | 监护 scope=EDUCATION 对 EDUCATION 文档不起作用；scope=GENERAL 隐含覆盖 IDENTITY | T13；`0005` 中 `docs.can_read_document` | 授权语义与字段含义不符 | Founder 确定 scope 语义（FD-2），修正映射 |
| F-10 | **高（功能）** | app 没有任何 INSERT/UPDATE/DELETE 授权或写入函数；状态流转规则只有审计、没有约束 | §3.3 目录查询 | 任何应用都无法写入业务数据；"数据库已完成"只对空 Schema 成立 | 获批的写入 API 或函数 Migration，并有对应的 RLS 和反向测试 |
| F-11 | 中 | 新集群灾备恢复失败：缺角色，策略为 0 | §4.3 | 宿主机损坏后无法按现有材料恢复 | 角色与全局对象的引导流程，新主机恢复演练，RPO/RTO（EV-8） |
| F-12 | 中 | `pg_hba local trust`：容器内无口令即可成为任意角色，包括超级用户 | T10 | 宿主机 docker 组或 ubuntu 账户失陷等于数据库超级用户失陷；该宿主机密码登录仍开启（OBSERVED-PRIOR） | 设置 `--auth-local` 为 scram 或 peer 并限制；完成宿主机加固（事件闸门 G-1） |
| F-13 | 中 | 备份 manifest 未签名且与导出同处；包内没有定时、异地副本、保留期和加密 | §4.3、§6.2 | 备份可被替换而不被发现；单机故障导致数据丢失 | FD-7 与 EV-8；备份目的地与签名或异地哈希 |
| F-14 | 中 | 腾讯运行的部署包未提交 Git；HEAD 中仍是旧的不安全版本 | §2.1 | 运行时不可复现、不可审计 | 经批准后提交，并以提交哈希重新登记部署 |
| F-15 | 低中 | 本地 compose 使用浮动标签，未锁摘要 | §4.3 | PG17 兼容性结论依赖当时拉取的镜像 | 本地 compose 锁定摘要 |
| F-16 | 中 | 腾讯数据库运行凭据以明文存放在本机工作树（已被 gitignore 忽略） | §6.2 | 工作站失陷即凭据泄露 | 改用凭据管理工具，或在使用后从工作站移除 |
| F-17 | 中（治理） | "EFFECTIVE"业务合同与 Phase 3 审批登记由 Codex 起草，依据只是"会话中的 Founder 指令"，没有签署人和日期；生产决策登记 9 个签署栏全部空白。Phase 2C 报告当日上午还写明 0003+ 无法在不编造语义的前提下推导 | `phase2-gate/` 文件；登记 SHA-256 前缀 `e48259478f06f519` | Phase 3 PASS 只证明 SQL 符合 Codex 自己写的合同 | Founder 签署 FD-2，或提供 EV-1、EV-3、EV-4 |
| F-18 | 低 | 公开 ID 前缀 `per_/fam_/stu_/gdn_`；principal 没有公开 ID（候选稿中有 `usr_`） | `0003` 中 `integration.public_ids` | 对外 ID 兼容性未决 | FD-2 / EV-2 |
| F-19 | 低 | backup 角色 BYPASSRLS + 读全库且无口令；health 用 DDL 角色 migrator | `install.sh`、`health.sh`（工作树） | 权限过大 | 健康检查改用专用只读角色；为 backup 角色制定受控使用规则 |
| F-20 | 低 | `install.sh` 缺少嵌套事务检查 | 代码审阅 | 将来的 Migration 可能破坏原子性 | 与 `db.ps1` 的检查对齐 |
| F-21 | 信息 | 腾讯库名为 `phoenix_canonical_dev`（Codex 记录称 Founder 已确认） | REPORTED | 命名语义与生产环境不符 | FD-8 指定目标环境与库名 |

## 8. 生产门禁：PASS / CONDITIONAL / HOLD / EVIDENCE_MISSING 清单

| 门禁 | 状态 | 具体所需证据 |
|---|---|---|
| Greenfield Schema 与 Migration 机制 | **PASS** | — |
| 访问控制与隔离 | **HOLD** | 修复 F-01 至 F-07、F-09，并在 PG16/17 上用真实分离登录角色回归 §5 全部测试 |
| Family Context 正式原件与生效修订 | **EVIDENCE_MISSING** | EV-1：原件字节与 SHA-256；或由 Founder 签署 FD-2，批准替代基线，写明签署人、日期、文件哈希 |
| Founder OS Freeze 原件与 ID 决议 | **EVIDENCE_MISSING** | EV-2：在 commit `3d5d6758…` 中执行 `git show …:PHOENIX_FOUNDER_DECISION_FREEZE_V1.md` 取得原文字节和哈希 |
| Founder OS / Operations OS / D1 复用决定 | **HOLD** | FD-3 签署（不复用，或具体复用计划） |
| Legacy ID 清单、冲突策略与迁移授权 | **EVIDENCE_MISSING** | EV-5：来源系统、表或文件、负责人、ID 格式、冲突与取代规则；FD-4 签署 |
| Docs & Submission 最终合同 | **HOLD** | EV-3：DS-1 至 DS-5 定稿，并修复 F-07、F-08 |
| Education / Identity 业务状态与负责人 | **HOLD** | EV-4：业务负责人签署字段、状态、流转与验收用例（当前状态集由 Codex 起草） |
| 对象存储、保留期、Legal Hold、清除与备份合同 | **HOLD** | EV-6：提供方、区域、加密、保留期、清除权限、跨境规则；FD-5 签署（当前只有 Mock） |
| Web 鉴权、JWKS、可信上下文、连接池生命周期 | **HOLD（含技术阻断）** | EV-7 与 FD-6，并修复 F-01、F-02 |
| RPO、RTO、监控、值班、回滚与切换批准 | **EVIDENCE_MISSING** | EV-8 与 FD-7；新主机恢复演练（F-11）；备份异地副本与签名（F-13） |
| 真实数据导入与应用生产切换批准 | **HOLD** | FD-8 签署，以及上述门禁全部 PASS |
| 腾讯云隔离运行时 | **EVIDENCE_MISSING** | 见 §9 第 4 项 |
| 宿主机可信状态 | **HOLD**（审计范围外的参考） | 安全事件闸门 G-1 至 G-8 关闭 |

**CONDITIONAL 项汇总：** CODE_AUDIT（机制成立，访问控制须修复）；LOCAL_RUNTIME（Codex 套件复现通过，独立反向测试失败）；T10 `pg_hba` 设置；备份字节篡改检测（只依赖未签名 manifest）；本地镜像未锁摘要。

## 9. 只读、可逆的下一步建议

本审计不执行以下任何一项，仅供 Founder 和 Codex 决策参考。

1. **Founder：** 填写并签署 `PRODUCTION_DATABASE_FOUNDER_DECISION_REGISTER_V1.0.md`，其中 FD-2 用于确认或替换 Codex 起草的业务合同；把 EV-1 至 EV-8 放入 `evidence/incoming/`。
2. **Codex，在获批后：** 用新的 `0007+` Migration 修复 F-01 至 F-09，不改动 0001–0006。把本报告附录 A 中的 T1–T13 纳入验收套件，并**改用真实的分离登录角色**执行，不再依赖超级用户 `SET ROLE`。
3. **Codex，在获批后：** 提交 `deploy/tencent/` 的修改和腾讯部署报告，用提交哈希重新登记已部署版本（F-14）。
4. **授权管理员，只读：** 在腾讯云上取得原始输出，并附上时间戳和 SHA-256，用于关闭 §6 的 EVIDENCE_MISSING：
   - `docker ps`，以及对 canonical 容器执行 `docker port`（应为空）
   - 宿主机 `ss -lnt`
   - `canonical_migrations.applied` 中的名称和哈希
   - `pg_roles` 中的角色属性
   - `pg_hba_file_rules`
   - 业务表行数，以及 `auth.session_contexts` 的行数
   - 备份文件的 `sha256sum` 与 manifest 对照
   - 旧目录 `/home/ubuntu/phoenix-canonical-db` 的现状
5. **恢复演练：** 在一次性的新容器中，先建立角色和全局对象，再恢复腾讯备份，并对比目录查询结果（F-11）。在通过前，不得宣称"可恢复"。
6. **安全事件：** 在 G-1 至 G-8 关闭前，腾讯宿主机只可作为空库演练环境，不得承载真实数据（F-12）。

## 附录 A：独立反向测试脚本（纯合成数据）

<details><summary>A.1 夹具（setup.sql 摘要）</summary>

```sql
-- 家庭 A：A1(PRIMARY) A2(MEMBER, student)；家庭 B：B1(PRIMARY) B2(MEMBER, student)
-- principals：A1=FAMILY，advisor=ADVISOR，partner=CHANNEL
-- 家庭 B：education.application(B2) + casework.case(EDUCATION_APPLICATION) + advisor_assignment(advisor)
-- integration.channel_grant(partner, family B, subject B2, 'PARTNER')
-- core.guardian_authorities(A1 -> A2, VERIFIED, scope 'EDUCATION')
-- consent.grants(A, grantor A1, grantee A1, subject A2, DOCUMENT_READ, EDUCATION, ACTIVE)
-- docs.documents(A, subject A2, EDUCATION)
CREATE ROLE t_app LOGIN;     GRANT phoenix_canonical_app TO t_app WITH INHERIT TRUE, SET FALSE;
CREATE ROLE t_binder LOGIN;  GRANT phoenix_canonical_context_binder TO t_binder WITH INHERIT TRUE, SET FALSE;
CREATE ROLE t_backup LOGIN NOSUPERUSER BYPASSRLS; GRANT pg_read_all_data TO t_backup WITH INHERIT TRUE, SET FALSE;
```
所有 UUID 均为合成的 v7 形态常量（例如 `01940000-0000-7000-8000-0000000000a1`）。
</details>

<details><summary>A.2 关键探针语句</summary>

```sql
-- T1：家庭 A 成员上下文
SET ROLE phoenix_canonical_context_binder;
SELECT auth.bind_context(<A1 principal>, <A1>, <family A>, 'FAMILY', clock_timestamp()+interval '1 hour', <nonce>);
RESET ROLE; SET ROLE phoenix_canonical_app;
SELECT count(*), count(*) FILTER (WHERE case_id = <family B case>) FROM casework.advisor_assignments;  -- 实测 1,1

-- T2：渠道主体（只对 B2 授权）
SELECT string_agg(display_name, ' | ') FROM core.people;  -- 实测 B1 | B2

-- T3：顾问，无 Consent
SELECT string_agg(display_name, ' | ') FROM core.people;  -- 实测 B1 | B2
SELECT count(*) FROM education.applications;              -- 对照：0

-- T4：分离凭据
-- psql -U t_binder -c "SELECT auth.bind_context(...); SELECT pg_backend_pid();"   -> pid 580
-- psql -U t_app    -c "SELECT auth.current_family_id();"                          -> NULL
-- psql -U t_app    -c "SELECT auth.bind_context(...);"  -> permission denied for function bind_context
-- psql -U t_app    -c "SET ROLE phoenix_canonical_context_binder;" -> permission denied to set role

-- T5：每轮先固定 docker restart，t_binder 作为重启后的第一个连接执行绑定后断开（不调用 clear）；
--     再次 docker restart，t_app 作为重启后的第一个连接查询：
SELECT pg_backend_pid(), auth.current_family_id(), (SELECT count(*) FROM core.families);
-- 第 2 轮实测：46 | <family A> | 1

-- T6：Consent 撤回 -> 以相同 (family, grantee, subject, purpose, data_class) 再授予  -> unique_violation
--     UPDATE ... SET status='ACTIVE'                                                 -> CONSENT_TRANSITION_INVALID

-- T7：以 app 角色执行
SELECT audit.record_access_event('READ','DOCUMENT',<doc>,'ALLOW','FORGED_BY_APP_ROLE');  -- 成功

-- T8：家庭 A 的 Manifest 指向家庭 B 的申请，或指向不存在的 Identity Case  -> 两项都被接受

-- T12：版本 retention 已过期 -> docs.can_purge_document() = true；DELETE 版本 -> DOCUMENT_VERSION_IMMUTABLE

-- T13：监护 scope=EDUCATION，Consent 为 DOCUMENT_READ/EDUCATION
SELECT count(*) FROM docs.documents;                 -- 实测 0
SELECT docs.authorize_document_read(<doc>);          -- false，原因 CONSENT_AUTHORITY_OR_CHANNEL_DENIED
```
</details>

<details><summary>A.3 原始输出摘录（PG16.15；PG17.11 除 pid 外逐行相同）</summary>

```text
REFUSED 0002_education_identity_skeleton.sql checksum changed (registered bef7d9a902e8… vs file 888558f39b36…)
FAILED 9000_atomicity_probe.sql: ERROR:  SYNTHETIC FORCED MIGRATION FAILURE
   residue: schema=f ledger_row=0 ledger_total=6
PASS foundation.sql | rls_probe.sql | docs_probe.sql | contract_neutral_probe.sql | trusted_context_probe.sql | phase3_acceptance.sql
tables=24 rls_enabled=20 rls_forced=0
constraints fk=42 unique=12 pk=24 check=70 ; indexes=37 partial_unique=1 ; policies=20 select_only=20 ; triggers=8
secdef_functions=21 without_search_path=0 ; public_execute_functions=0
app_write_grants=0 ; app_select_tables=19 ; app_exec_functions=16 write_capable=4
pg_hba local all all - trust
T1 family-A member: advisor_assignments visible=1; of which family-B case=1
T1b family-A member: casework.cases visible (control)=0
T2 partner (grant for B2 only) core.people visible=SYN B1 parent | SYN B2 student
T3 advisor without Consent: core.people visible=SYN B1 parent | SYN B2 student
T3c advisor without Consent: education.applications visible (control, expect 0)=0
T6 new Consent after withdrawal: BLOCKED (unique_violation on family/grantee/subject/purpose/data_class)
T6b reactivating withdrawn Consent: BLOCKED (CONSENT_TRANSITION_INVALID)
T7b forged ALLOW audit rows present=1
T8 family-A manifest targeting family-B application: ACCEPTED
T8b manifest targeting nonexistent identity case: ACCEPTED
T12 can_purge_document (retention passed, no hold, no submission)=true
T12b physical purge of purge-eligible version: BLOCKED (DOCUMENT_VERSION_IMMUTABLE)
T13 EDUCATION-scope VERIFIED guardian + DOCUMENT_READ/EDUCATION consent: EDUCATION doc rows visible=0
t_binder bound FAMILY context in its own backend pid=580 and disconnected without clear_context()
t_app new connection: pid=587 current_family_id=NULL families_visible=0
t_app calls bind_context: ERROR:  permission denied for function bind_context
t_app SET ROLE binder: ERROR:  permission denied to set role "phoenix_canonical_context_binder"
stale contexts left in auth.session_contexts: 1 row(s); pids=580; latest_expiry_in=22:59:00
round 2: binder pid=46 (first connection after restart, no clear_context) -> after next restart, first t_app connection: pid=46 family=01940000-0000-7000-8000-00000000fa01 families_visible=1 people_visible=2
same cluster (roles exist), --no-owner: errors=0 policies=20
fresh cluster (no canonical roles): errors=71 ( 71 ERROR: role "X" does not exist )
fresh-restore tables=24 policies=0 canonical_roles=0 ledger_rows=6
tampered copy: pg_restore -l on 1-byte-flipped dump => archive still lists (only the manifest SHA-256 detects this)
```
</details>

---

**审计声明：** 本报告由 Claude 独立完成。审计中未修改任何代码、Migration、Compose、脚本或合同文件；未连接腾讯云，未使用任何生产密钥，未读取任何真实数据或口令值；未部署、Push、Merge、DROP 或 TRUNCATE，也未重置任何既有数据库。一次性测试容器已全部删除。**隔离空库通过不等于真实生产切换通过。**

FINAL AUDIT VERDICT = HOLD
