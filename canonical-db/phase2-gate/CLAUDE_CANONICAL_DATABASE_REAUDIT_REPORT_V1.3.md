# Phoenix Canonical PostgreSQL — Claude 第四轮复审报告 V1.3（0009 应用写入接口 + 任务 A 续做）

| 项 | 值 |
|---|---|
| 执行 | Claude |
| 时间 | 2026-10-15 16:33–17:00（Asia/Shanghai, +08:00） |
| 复审对象 | `migrations/canonical/0009_application_write_api.sql`（Codex 编写，SHA-256 `2a48d016c0b2dd952d56a15853c8092895df057e6a0d69f5ab391803ca0747c2`）；`FIX_EXECUTION_REPORT_V1.2_A/B/C.md` |
| 本轮另做 | 任务 A 续做（Codex 因额度上限中断，Founder 指示 Claude 接续），以及 `scripts/db.ps1` 缺陷修复 |
| 基线 | 分支 `codex/canonical-postgresql-phase1`，HEAD `c3b1341`（Codex 最后提交），本轮改动另行提交 |
| 前序报告 | V1.0 / V1.1 / V1.2，均保持原样 |

## 0. 一页结论

```text
CODE_AUDIT (0001–0009)    = PASS（安全机制）；业务语义 CONDITIONAL（R-12 ~ R-14 待 Founder 决定）
LOCAL_RUNTIME             = PASS（PG16.15 / PG17.11 全新集群 + 本地开发库）；R-8 待修
TENCENT_ISOLATED_RUNTIME  = PAUSED（Founder 15:10 决定）；运行版本仍为 0001–0006，独立证据仍为 EVIDENCE_MISSING
PRODUCTION_READY          = NO
```

> **独立性说明：** 0009 由 Codex 编写，本报告对它的复审是独立的。任务 A 的续做和 `db.ps1` 修复由 Claude 自己完成，不能算独立复审，建议 Codex 在有 pwsh 的环境中重跑 `db.ps1` 的全部测试，交叉核对。

> **隔离空库通过不等于真实生产切换通过。**

## 1. 任务 A：续做结果

详见 `FIX_EXECUTION_REPORT_V1.2_A.md` 文末"续做"一节。

**根因：** 本地 `.env` 的 bootstrap 口令是 48 位，而 0007 轮后的 `db.ps1` 只接受 64 位。不匹配时，PowerShell 返回空集合，导致守卫失效、不抛错，脚本带着空口令连接，认证失败。

**修复：** `db.ps1` 改为同时接受 48 / 64 位，新建 `.env` 改为 64 位，并强制把结果转为字符串，使守卫真正生效。已用合成输入在 Windows PowerShell 5.1 验证。

**结果：** PG16 和 PG17 开发库均为：
- 0001–0009 首次执行、重复跳过，账本 9 行，哈希与文件逐一一致；
- `pg_hba` 全部 SCRAM，不带口令的 socket 被拒绝；
- 六套原有验收 PASS；
- 25 张表、20 条策略、业务行 0。

**R-8：** reader 账号缺少 schema 级授权，读不了迁移账本（见 §4）。

**NOT_RUN：** `db.ps1` 自带的 test / audit-* / restore-test，以及两个 `.ps1` 回归脚本。本机没有 pwsh，原因是工具缺失，不代表测试失败。

## 2. 0009 代码审阅（VERIFIED-FILE，逐行）

| 方面 | 结论 |
|---|---|
| 写入通道 | 20 个 `SECURITY DEFINER` 写入函数，全部固定 `search_path`；撤销 PUBLIC 后只授予 app。app 对业务表的 INSERT/UPDATE/DELETE 授权为 0 |
| 可信上下文 | 每次写入都用 `clock_timestamp()` 重新检查上下文是否有效（长事务内过期也会拒绝）；INTERNAL 渠道必须是 ACTIVE 的 SERVICE 主体 |
| 授权 | 家庭写入要求是家庭成员，且是本人或对应范围、VERIFIED 的监护人；顾问写入要求有分配且有 Consent；渠道方（PARTNER）没有写入能力；所有拒绝都返回 false 并写审计 |
| 状态机 | Education：`DRAFT→READY→SUBMITTED→DECIDED`，`WITHDRAWN` 只能从未决定的状态进入；Identity：`DRAFT→EVIDENCE_PENDING→UNDER_REVIEW→RESOLVED/CLOSED`。与 FD-2 第 6 条一致 |
| 文件 | 只接受 `mock/` 存储键和 SHA-256；版本号必须连续；不处理真实字节；不涉及物理清除（F-08 HOLD） |
| R-7 | 原地修改 `evidence_level` 会被触发器拒绝；授权的新建、撤销、过期都写审计 |
| 动态 SQL | 没有，因此没有注入面 |

**未发现高危安全缺陷。** 业务语义和覆盖范围的问题见 §4。

## 3. 运行时复核（VERIFIED-RUN，PG16.15 与 PG17.11 结果完全相同）

方法：用 bash 等价复现 `tests/f10_local_acceptance.ps1` 的全流程。一次性容器，`--network none`，不发布端口，用合成 env 文件，结束后全部清除。在此之上加入 Claude 的独立探针（`tests/claude_f10_reaudit_probes.sh`）。

原始输出：`evidence/claude-v1.3-C-f10-reaudit-pg16.txt`、`-pg17.txt`。

| 检查 | 结果 |
|---|---|
| 0001–0009 全新执行与重复执行 | PASS；ledger 9、tables 25、policies 20 |
| 六套原有验收 | 6/6 PASS |
| Codex F10 回归（分离 LOGIN 加一次性票据） | 18 项 PASS；ALLOW 36 / DENY 43，与 Codex 报告一致 |
| 漂移拒绝与原子回滚 | `DRIFT_REFUSED 0009`；`atomic_schema_exists=false`，ledger 仍为 9 |
| backup 账号导出后恢复到新集群 | PASS；恢复后 7 套验收 PASS |
| 不带口令的 socket | 拒绝 |
| C1 app 直接 INSERT `core.people` | `permission denied`，PASS |
| C6 绑定家庭 A 的服务向家庭 B 新建人员 | false，PASS |
| C7 非 Mock 存储键、跳过版本号 | 均为 false，PASS |
| **C2 审计可被回滚抹除** | 家庭 B 越权尝试在客户端 ROLLBACK 后，DENY 记录为 **0**；同样尝试提交后为 1（**R-9**） |
| **C3 无法从空库启动** | 服务主体无法绑定到尚不存在的家庭（外键拒绝），首个家庭无法经 API 创建（**R-10**） |
| **C3b 服务主体占用自然人表** | SERVICE 主体必须对应一条 `core.people` 记录（**R-11**） |
| **C4 学生自行授权** | 学生可把自己的 `IDENTITY_SENSITIVE` 文件读取权授予渠道方，返回 true（**R-12**） |
| **C5 家庭自行判定 DECIDED** | 学生本人可把申请推进到 DECIDED，且没有任何外部官方事实记录（**R-13**） |
| **C8 确认人与提交人相同** | 已提交的 2/2 份清单中，`confirmed_by = submitted_by`（**R-14**） |
| **C9 API 覆盖** | 没有任何 app 可调用的函数能创建 casework / 顾问分配 / 监护授权 / 登录主体 / 渠道授权（属于 **R-10**） |

## 4. 发现与处理建议

| ID | 严重度 | 发现 | 建议 |
|---|---|---|---|
| R-8 | 中 | reader 缺少 `canonical_migrations` 的 schema USAGE；`health.sh` 用 reader 查账本会失败 | 0010：`GRANT USAGE ON SCHEMA canonical_migrations TO phoenix_canonical_reader`，并加回归测试 |
| R-9 | 中 | 拒绝审计与业务事务同提交同回滚，客户端回滚即可抹除越权尝试的记录（Codex 已披露） | 在 FD-6 网关中加外部审计，或使用独立连接或日志写入；需 Founder 决定 |
| R-10 | 中 | 缺少引导与管理接口：首个家庭、服务主体、顾问分配、监护授权、渠道授权都只能由超级用户写入 | 设计"引导与管理"接口或受控的初始化流程（F10 草案外扩展），需 Founder 批准 |
| R-11 | 低–中 | 服务主体必须占一条 `core.people` 记录，与"core.people 是唯一自然人主数据"冲突 | 修订合同：允许 SERVICE 主体不关联自然人（例如 `person_id` 可空并加 CHECK），需 FD-2 修订 |
| R-12 | 语义 | 未成年人或学生可自行授予 Consent，包括身份敏感数据（PIPL 规定未满 14 周岁须监护人同意） | Founder 决定 Consent 授予的年龄与监护规则（与 FC-4 一并） |
| R-13 | 语义 | 家庭可自行把申请标为 DECIDED，无需外部官方事实 | Founder 决定：DECIDED 是否只能依据 `external_facts`，或只允许顾问或服务设置 |
| R-14 | 语义 | 确认人与提交人记为同一人，没有双人复核 | Founder 决定是否要求两个不同的人确认和提交 |
| R-15 | 低 | 本机 `core.autocrlf=true`，`deploy/tencent/` 没有 `.gitattributes`，`git archive` 导出的 `.sh` 变成 CRLF，这是任务 B3 失败的根因 | 加 `deploy/tencent/.gitattributes`（`*.sh text eol=lf` 等），恢复任务 B 前完成并验证导出字节 |
| R-16 | 已修 | `db.ps1` 只接受 64 位口令，且守卫失效（任务 A 的根因） | 本轮已修复；待 Codex 用 pwsh 实跑确认 |

## 5. 门禁状态（相对 V1.2 的变化）

| 门禁 | V1.2 | V1.3 |
|---|---|---|
| Schema / Migration / RLS / 可信上下文 | PASS | **PASS**（含 0009） |
| 应用写入通道（F-10） | HOLD | **CONDITIONAL**：机制已实现并通过；R-9、R-10 与语义项 R-12 ~ R-14 待决 |
| 本地开发库（R-6） | HOLD | **PASS**（R-8 除外；`db.ps1` 测试 NOT_RUN） |
| 腾讯隔离运行时 | EVIDENCE_MISSING | **PAUSED**；R-15 须先修 |
| FD-6 应用鉴权、EV-1 至 EV-8、F-08、安全事件闸门 G-1 至 G-8 | HOLD / EVIDENCE_MISSING | 未变 |

FINAL AUDIT VERDICT = HOLD
