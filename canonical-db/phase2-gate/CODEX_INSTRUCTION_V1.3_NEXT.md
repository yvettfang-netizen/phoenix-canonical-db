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

C2、C3、C4、C5、C8 原属待决事项，现已全部由 Founder 批准（见 D5、D6）。各项的新期望：

| 探针 | 新期望 | 依据 |
|---|---|---|
| C2 | 回滚后，服务器日志仍有对应的 `PHOENIX_AUDIT` 行 | D-9 |
| C3 | INTERNAL 服务不绑定家庭即可创建首个家庭；SERVICE 主体不对应自然人 | D-10 / D-11 |
| C4、C5、C8 | 拒绝 | D-12 / D-13 / D-14 |

实现完成后，这些都纳入永久回归。

## D5 · 实现已批准的 D-9 / D-10 / D-11（Founder 2026-10-15 17:06 批准）

依据 `phase2-gate/FOUNDER_DECISION_ADDENDUM_V1.2_R9_R10_R11.md`。批准版 SHA-256 为 `925c83f4d079ec6a1fd9d211786a961d988eaf0d0f033547f1e5ba485552616e`；开工前先核对，不一致就停止并报 HOLD。原 D5"只写设计草案"作废。

- **编号顺序：** 先完成 D6 的 0011，再用 0012 及以后的编号实现本节；不修改 0001–0011。实现顺序建议 D-11 → D-10 → D-9，实现方可以调整，但须在报告中说明。
- **D-11 服务主体不占自然人：**
  - `auth.principals.person_id` 对 SERVICE 为空、对其他主体必须非空，用 CHECK 强制；SERVICE 主体增加服务名称字段；
  - INTERNAL 上下文的 `actor_person_id` 为空；
  - 服务操作的操作人记录改为记 principal，具体字段由实现方提出；
  - 签发和绑定的校验按补充文件第 3 条执行。
- **D-10 引导与管理接口：**
  - INTERNAL 服务上下文可以不绑定家庭（只用于创建家庭和管理操作）；
  - 服务主体只由安装或运维流程以 migrator 或 bootstrap 创建，不对 app 开放；
  - 管理接口（只允许 SERVICE 主体调用）覆盖：案件的创建和关闭、顾问分配的建立和撤销、监护授权的建立和撤销（`VERIFIED` 必须附证据引用；`SELF_DECLARED_LEGACY` 不能经 API 新建）、渠道授权的建立和撤销、FAMILY / ADVISOR / CHANNEL 登录主体的建立和停用；
  - 测试夹具（例如 `f10_ephemeral_seed.sh`）改为通过这些 API 建立数据，除安装或 Migration 外不再以超级用户写业务表。
- **D-9 审计双写：**
  - 每一次写入判定（允许或拒绝）都追加一条 `RAISE LOG` 结构化日志，前缀 `PHOENIX_AUDIT`，只写 ID 和代码；
  - 提供只读对账脚本：比对服务器日志与 `audit.access_events`，识别被回滚的尝试，在一次性容器中演示；
  - 日志采集目的地和网关审计仍为 HOLD（FD-7 / FD-6），不要自行选择目的地。
- **测试：**
  - 补充文件"实施与验收要求"一节列出的全部正反例；
  - 更新 C2、C3 的期望并纳入永久回归；
  - 原有测试中依赖"服务主体是自然人"或"超级用户写夹具"的部分，按新规则更新，并逐条列出改动；
  - PG16 与 PG17 都做，用分离 LOGIN 加一次性票据，并做全新集群恢复。

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

## D7 · 实现已批准的 FD-6 / FD-7 本地部分（Founder 2026-10-15 17:57 批准）

依据 `phase2-gate/FOUNDER_DECISION_ADDENDUM_V1.3_FD6_FD7.md`。批准版 SHA-256 为 `956fcd5a557f82892d2b3fb2886366efb181fc11b5830d1bbb70852acd0177af`；开工前先核对，不一致就停止并报 HOLD。

- **顺序与编号：** 在 D5 完成后进行，Migration 编号接在 D5 之后；不修改已有 Migration。
- **数据库侧（FD-6）：**
  - 外部身份映射表：签发方 + subject → principal，二元组唯一；只经 D-10 管理接口建立和停用；未登记的身份一律拒绝；
  - 把票据的 `request_nonce` 带入上下文、`audit.access_events` 和 `PHOENIX_AUDIT` 日志行。
- **连接池符合性测试（FD-6 第 5、6 条）：**
  - 同一连接清除上下文后再用，读不到任何家庭数据；
  - 票据复用、票据过期、跨主体兑换都被拒绝；
  - 停用映射或主体后签发被拒绝；
  - 清除失败的连接被丢弃（用测试驱动模拟）；
  - 在报告中写明：事务级连接池为什么会破坏上下文绑定。
- **运维脚本（FD-7，放在 `deploy/tencent/`，LF 换行）：**
  - `backup.sh` 增加 `pg_restore --list` 校验；
  - 保留期清理脚本：默认只预演，至少保留最近 3 份校验通过的备份；
  - 一次性容器恢复演练脚本：核对迁移账本校验和与 `health.sh`，记录耗时；
  - `PHOENIX_AUDIT` 提取脚本：按天生成只追加文件和 SHA-256 链式清单，并提供链校验；
  - 告警检查脚本：覆盖补充文件 FD-7 第 6 条的全部条件，**只写本地文件，不向任何外部渠道发送**；
  - 服务器日志按天轮转（compose 或 PostgreSQL 配置，由实现方提出）。
- **全部只在本机执行：**
  - 不连接腾讯服务器，不在服务器上安装定时任务；
  - 不创建 COS 存储桶、子账号或告警渠道；
  - 不使用真实密钥。
- **测试：** PG16 与 PG17 都要做；合成数据；包括全新集群恢复；每个脚本都要有正例和反例（例如篡改一天的审计文件后，链校验必须报错）。

## 待 Founder 决定（只列出，不替 Founder 决定）

- 既有 HOLD：F-08 清除、F-13 运维、F-16 凭据、EV-1 至 EV-8、服务器安全事件闸门 G-1 至 G-8
- FD-6 / FD-7 的事实字段（身份提供方、`iss`、`aud`、JWKS 地址、应用 / binder 负责人、异地存储桶、加密密钥、告警渠道）：实施时填写，不由 Codex 自行选择
- 管理操作是否需要双人复核（D-10 第 6 条，目前不要求）
- ~~FD-6 / FD-7 规则~~：已于 2026-10-15 17:57 批准，见 D7
- ~~R-9 / R-10 / R-11~~：已于 2026-10-15 17:06 批准，见 D5
- ~~R-12 / R-13 / R-14~~：已于 2026-10-15 17:00 批准，见 D6

## 停止条件

遇到以下任一情况，停止该项并标 HOLD，说明原因后继续其他项：

- 需要修改 0001–0009；
- 需要连接腾讯服务器；
- 需要真实数据或口令；
- 需要自行选择业务语义；
- 测试结果与 Claude 的记录冲突且无法解释。

## 交付

- 新 Migration 0010、0011、0012 及以后各个文件的 SHA-256；
- `FIX_EXECUTION_REPORT_V1.3.md`：按 D1–D7 逐项写明修改内容、原始输出路径、PASS / FAIL / HOLD；
- D-9 对账脚本，以及它在一次性容器中的演示输出；
- D7 各运维脚本的 SHA-256，以及它们在本机的演示输出；
- 本地提交哈希。

任务量较大，可以分三批交付：第一批 D1–D4 加 D6，第二批 D5，第三批 D7。每批完成后各自回报复审。

完成后回报，由 Claude 复审。
