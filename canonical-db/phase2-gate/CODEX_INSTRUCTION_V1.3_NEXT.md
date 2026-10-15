# Codex 执行指令 V1.3：0010 修复、换行固定、pwsh 交叉验收、引导与审计设计草案

**签发：** Founder 于 2026-10-15 会话中要求"继续下一步"；指令由 Claude 起草。
**依据：** `phase2-gate/CLAUDE_CANONICAL_DATABASE_REAUDIT_REPORT_V1.3.md` 第 4 节（R-8 至 R-16）。
**当前状态：**
- 任务 A 已由 Claude 续做完成，PG16/17 开发库为 0001–0009；
- 任务 B 仍为 PAUSED；
- 0009 机制复审通过，业务语义项待 Founder 决定；
- 分支已推送到私有仓库 `yvettfang-netizen/phoenix-canonical-db`，推送由 Claude 负责。

## 共同边界（与上一轮相同）

1. 只在工作树 `codex/canonical-postgresql-phase1` 内工作。允许本地 commit，**禁止** push、merge、PR（推送由 Claude 统一做敏感信息扫描后执行）。
2. 不修改 0001–0009 的任何字节，只新增 0010 及以后的 Migration。
3. **任务 B 继续暂停：** 不连接腾讯服务器，不部署。
4. 只用合成数据；口令不进命令行、日志、报告或聊天。
5. 业务语义不自行决定，按"默认拒绝"实现，并列入待决清单。
6. 每一步都附原始命令和原始输出（保存到 `evidence/`，文件名带 `v1.3`）。

## D1 · 0010：修复 R-8（reader 读不到迁移账本）

- 新增 `0010_reader_ledger_usage.sql`：`GRANT USAGE ON SCHEMA canonical_migrations TO phoenix_canonical_reader;`。不授予 CREATE，也不授予其他 schema。
- 回归测试：reader 登录可以 `SELECT count(*) FROM canonical_migrations.applied`；仍不能 INSERT，不能在该 schema 建对象；app 和 binder 仍然读不到账本。
- 在本地开发库上，用 reader 账号模拟一次 `deploy/tencent/health.sh` 中的查询，记录输出。

## D2 · 修复 R-15（导出脚本换行被转成 CRLF）

- 新增 `canonical-db/deploy/tencent/.gitattributes`：`*.sh text eol=lf`、`*.yaml text eol=lf`、`*.md text eol=lf`、`.env.example text eol=lf`。
- 把 `canonical-db/tests/.gitattributes` 扩展为覆盖 `*.sh`（包括 `claude_f10_reaudit_probes.sh`）。
- 验收：在本机 `core.autocrlf=true` 不变的前提下，执行 `git archive HEAD canonical-db/deploy/tencent canonical-db/migrations/canonical`，解包后逐个检查 `.sh` 首行没有 `0d`，并记录各文件 SHA-256。只做本地验证，不上传。

## D3 · pwsh 交叉验收（核对 Claude 的任务 A 续做和 R-16 修复）

在有 pwsh 的环境中，对现有开发库依次运行下列命令，**不重建数据卷**：

```text
db.ps1 -Action provision-local-roles -Version 16 / 17
db.ps1 -Action test -Version 16 / 17
db.ps1 -Action probe -Version 16 / 17
db.ps1 -Action audit-migration -Version 16 / 17
db.ps1 -Action audit-backup -Version 16 / 17
phase3_defect_regression.ps1 -Version 16 / 17
phase3_fresh_cluster_restore.ps1 -Version 16 / 17
f10_local_acceptance.ps1 -Version 16 / 17
```

- 确认 `db.ps1` 能用现有的 48 位 `.env` 正常连接（验证 R-16 修复）。
- 在合成的 `.env` 副本上验证"缺失或格式错误时守卫抛错"。不要改动真实的 `.env`。
- 任何一项与 Claude 的结果（`FIX_EXECUTION_REPORT_V1.2_A.md` 续做一节）不一致，都如实记录并标 FAIL。

## D4 · 把 Claude 探针中的机制项固化为回归

把 `tests/claude_f10_reaudit_probes.sh` 中**属于机制**的项纳入 F10 回归，作为永久断言：

- C1：app 不能直接写表；
- C6：服务不能跨家庭写入；
- C7：非 Mock 存储键、跳过版本号均被拒绝。

C2、C3、C4、C5、C8 属于待决事项。在 Founder 决定之前**不要**为它们写"期望行为"断言，只保留观测性输出。

## D5 · 设计草案（只写方案，不写 Migration）

| 编号 | 主题 | 内容 |
|---|---|---|
| R-9 | 审计持久性 | 拒绝审计不能被客户端回滚抹除。比较三种方案：网关侧外部日志、独立连接写审计、PostgreSQL 日志加采集。写出与 FD-6 的依赖关系 |
| R-10 | 引导与管理接口 | 覆盖：首个家庭、服务主体、顾问分配、监护授权（含证据审核）、渠道授权、登录主体的创建、吊销与审计；谁有权调用；如何避免超级用户日常操作 |
| R-11 | 服务主体与自然人主数据 | 例如允许 `auth.principals.person_id` 对 SERVICE 为空，并加 CHECK 约束；列出需要修订的合同条款 |

## D6 · 实现已批准的业务规则 D-12 / D-13 / D-14（Founder 2026-10-15 17:00 批准）

依据 `phase2-gate/FOUNDER_DECISION_ADDENDUM_V1.1_R12_R13_R14.md`。批准版 SHA-256 为 `1b6a58f56e9d7132e67788d0028f308959a7bb3f57727626691bed85adb0bcfe`；开工前先核对该哈希，不一致就停止并报 HOLD。

- **只新增 Migration：** 在 0010 之后新增 0011（如需要可再加 0012），不修改 0001–0010。所有新增写入函数都必须：`SECURITY DEFINER`、固定 `search_path`、撤销 PUBLIC 后只授予 app、默认拒绝、写审计。
- **D-12 民事能力：**
  - 新增民事能力属性（`ADULT_VERIFIED` / `MINOR_VERIFIED` / `UNVERIFIED`，默认 `UNVERIFIED`），保留历史、不可原地修改，只有 INTERNAL 渠道的 SERVICE 主体可以设定；
  - `consent.create_grant`：本人只有在 `ADULT_VERIFIED` 时才能自行授予，否则只能由 VERIFIED 监护人代授；
  - 撤回规则不变。
- **D-13 外部官方事实：**
  - 新增"记录外部官方事实"写入函数，只有顾问（有分配且有 Consent）或服务可以调用；
  - `advance_application` 进入 DECIDED、`advance_case` 进入 RESOLVED，必须存在对应的 DECISION 事实，且只有顾问或服务可以推进；
  - 观测时间晚于当前时间的事实一律拒绝。
- **D-14 确认与提交分离：**
  - 新增 `docs.confirm_manifest`，确认人只能是本人（`ADULT_VERIFIED`）或范围匹配的 VERIFIED 监护人；
  - 确认后锁定条目；
  - `submit_manifest` 要求清单已确认，提交人必须是顾问或服务，且不得与确认人为同一人。
- **测试：**
  - 指令补充文件"实施与验收要求"一节列出的全部正反例；
  - 把 `tests/claude_f10_reaudit_probes.sh` 中 C4、C5、C8 的期望改为"拒绝"，纳入永久回归；
  - 既有 F10 回归中依赖旧行为的用例（家庭自行推进到 DECIDED、家庭自行提交清单等）按新规则更新，并在报告中逐条列出改动；
  - PG16 与 PG17 都做，用分离 LOGIN 加一次性票据，并做全新集群恢复。

## 待 Founder 决定（只列出，不替 Founder 决定）

- R-9 审计持久化方案
- R-10 引导与管理接口的范围和调用权限（含民事能力核验服务的接入方式）
- R-11 合同修订：服务主体不进入自然人主数据
- 既有 HOLD：FD-6 应用鉴权、F-08 清除、F-13 运维、F-16 凭据、EV-1 至 EV-8
- ~~R-12 / R-13 / R-14~~：已于 2026-10-15 17:00 批准，见 D6

## 停止条件

遇到以下任一情况，停止该项并标 HOLD，说明原因后继续其他项：

- 需要修改 0001–0009；
- 需要连接腾讯服务器；
- 需要真实数据或口令；
- 需要自行选择业务语义；
- 测试结果与 Claude 的记录冲突且无法解释。

## 交付

- 新 Migration 0010、0011（如有 0012 也一并列出）及其 SHA-256；
- `FIX_EXECUTION_REPORT_V1.3.md`：按 D1–D6 逐项写明修改内容、原始输出路径、PASS / FAIL / HOLD；
- 三份设计草案：R-9、R-10、R-11；
- 本地提交哈希。

完成后回报，由 Claude 复审。
