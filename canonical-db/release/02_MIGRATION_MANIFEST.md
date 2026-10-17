# 02 · Migration 清单与 SHA-256

**范围：** `canonical-db/migrations/canonical/` 下的 0001–0017。
**执行顺序：** 按文件名的四位编号升序执行。
**完整性保护：**
- 每个文件在执行时由外层包装成一个原子事务：`BEGIN` → `pg_advisory_xact_lock(2202,1)` → 正文 → 写入账本 `canonical_migrations.applied`（文件名 + SHA-256）→ `COMMIT`；
- 已执行的文件，每次运行都会重新比对摘要，不一致即拒绝（DRIFT_REFUSED）；
- 目录中的文件数、执行数、账本行数必须相等，三者任一不符即拒绝（F10 守卫）。

| 编号 | 文件 | SHA-256 | 首次提交 | 内容 |
|---|---|---|---|---|
| 0001 | `0001_foundation.sql` | `eea8d1deece72afdc3832d075fcfb42b71b4c1fe4fdccc8900104a0e0ca78a2d` | `02eec11`（10-11） | 迁移账本、角色、空的领域 schema |
| 0002 | `0002_education_identity_skeleton.sql` | `bef7d9a902e8ad34491b7455987d7791667dcb8a5ab31945cf609a6aa97e4e7f` | `dce9213`（10-12） | education / identity 命名空间 |
| 0003 | `0003_core_consent_access.sql` | `7dc0c5060237fae9069915ba8a1ecc39323cf74ab8ea0d49dd832ef9d8330618` | `c34fd3e`（10-14） | 自然人、家庭、成员关系、学生档案、监护、主体、上下文、Consent、公开 / 旧 ID 映射、渠道授权、审计、RLS |
| 0004 | `0004_casework_education_identity.sql` | `aec2be38c6ad363f5594d65016b8a2dfcb79fe76e77a225271379bb991a443e9` | `c34fd3e` | 通用个案、顾问分配、教育申请、身份案件、状态事件、外部事实 |
| 0005 | `0005_documents_submissions.sql` | `7bd581d16bb8c21278bd5bc013496779fe08f509d84bf74b652e5ce3b21cdbec` | `c34fd3e` | 文档、版本、提交清单与条目 |
| 0006 | `0006_access_decision_api.sql` | `2a3d6cd19febd62b7128c9ad4a2d7c94abdb9a4e11d499f36f4050eb2c2ed9d8` | `c34fd3e` | 访问判定 API（**腾讯暂停库当前停在此处**） |
| 0007 | `0007_security_boundary_fixes.sql` | `49ec737393a4a4bc5f1e287add369db4f04fbde1c021521e8b4cf781f966ff93` | `eea5ac6`（10-15） | 上下文绑定后端进程（PID + 启动时间）、一次性票据、生命周期状态 |
| 0008 | `0008_expiry_and_ephemeral_cleanup.sql` | `51215c0b4d76e242c28197187bf1e017362700128ddd562e2da5d64980a8588d` | `77a757e`（10-15） | 到期归一、临时状态清理 |
| 0009 | `0009_application_write_api.sql` | `2a48d016c0b2dd952d56a15853c8092895df057e6a0d69f5ab391803ca0747c2` | `b6c5304`（10-15） | 应用写入 API（默认拒绝 + 审计） |
| 0010 | `0010_reader_ledger_usage.sql` | `eb05a55b813695ef7c6252ffc00569a0d97920008773fc07b6d0f6109959825a` | `8ecc77c`（10-16） | R-8：reader 可读迁移账本 |
| 0011 | `0011_verified_capacity_official_facts_manifest_confirmation.sql` | `acc638a3d308b9a9c601238843b1f5dea75a4f376cfb4e77a48cd3afb8f1caa8` | `85df24f`（10-16） | D-12 民事能力、D-13 官方事实、D-14 确认与提交分离 |
| 0012 | `0012_service_principal_and_context.sql` | `385206d698db33cd6a26b7ea48ab5362f2fa2e4256ec96740c336429ad54afa8` | `4a9a29e`（10-17） | D-11 服务主体不占自然人、R-20 主体类型与渠道对应 |
| 0013 | `0013_management_write_api.sql` | `fcbeeea5b8fc35c0993b7b7b9dbe956fd0c6edc4a6142e49cb329fad41a320cb` | `4a9a29e` | D-10 引导与 SERVICE 管理接口 |
| 0014 | `0014_rollback_resistant_write_audit.sql` | `92328ac4bf51b54980da63e96681220437ac20e4557fc008ab51431793ba4209` | `4a9a29e` | D-9 审计双写（`PHOENIX_AUDIT` + attempt_id） |
| 0015 | `0015_contract_gap_controls.sql` | `a639f9f10c5130c780f008832bcf9e4852badd00fcec618379e94d4e7c82d683` | `a1ec169`（10-17） | EV 合同缺口 T1–T4 |
| 0016 | `0016_assignment_scope_integrity.sql` | `7b10af1992e548e065c68d947b47bb073cdc88c52e4312b9aa9ccbe1bfa962e4` | `12e7a63`（10-17） | V16-F1 / F2 / F3 缺陷修复 |
| 0017 | `0017_external_identity_request_trace.sql` | `c701f74897ca13d503c8c165fd2182d77a06583afa832760dc80f8dd9524aab6` | `c5e81e6`（V1.8） | FD-6：外部身份映射、请求编号进入审计 |

## 核验结果

- **0001–0016 未被改写：** 每个文件在 Git 历史中只被提交过一次；当前字节的 SHA-256 与历次报告的登记值一致（V1.6 收尾时逐个核对，见 `FIX_EXECUTION_REPORT_V1.6.md` 第 3 节）。
- **全新安装：** PG16 / PG17 一次性容器先装 0001–0010（账本 10），再装其余（账本 17）。
- **重复执行：** 第二次运行时 17 个文件全部 SKIP，摘要逐一校验。
- **漂移：** 改动 0009 的一个字节后，被 DRIFT_REFUSED 拒绝。
- **失败恢复：** 强制失败的合成 Migration 回滚后不留 schema；0006→0017 升级中，阻断数据使 0012 整体回滚，修正后可以继续。
- **守卫：** 多一个文件、缺一个文件、未编号的 `.sql` 文件，三种情况都在执行前被拒绝。

**证据：**
- `evidence/v1.8-f10-sh-pg16.txt`、`-pg17.txt`（每份开头的 MIGRATION_SHA256 段列出完整哈希）；
- `evidence/v1.8-upgrade-path-pg16.txt`、`-pg17.txt`。

## 升级时的数据前提

详见 `07_PRODUCTION_DEPLOYMENT_RUNBOOK.md`。

升级前必须执行 `deploy/tencent/preflight_upgrade.sql`，有阻断项时不得升级：

| 阻断项 | 对应 Migration | 原因 |
|---|---|---|
| SERVICE 主体对应了自然人 | 0012 | 0012 要求 SERVICE 主体不对应自然人 |
| 存在临时上下文或票据 | 0012 | 0012 给这两张表加了约束；须先停止 binder 与应用 |
| 有确认人但没有确认时间的清单 | 0011（尚未应用时） | 需要业务决定如何补确认时间，不得自行填写 |
