# Claude 复审报告 V1.5：Codex 第二批（E1、E2、E3、D6 / 0011）

**复审时间：** 2026-10-16 15:43–16:00 +0800
**对象：** Codex 提交 `85df24f`、`24fe28b`，以及 `FIX_EXECUTION_REPORT_V1.4.md`
**方式：**
- 逐行审读 0011 及其依赖函数；
- 在一次性容器（`--network none`、无端口、合成数据）中，用 bash 独立复跑 F10 全流程（本机没有 pwsh），并加跑我自己的缺口探针；
- 只读核对开发库与归档。

没有连接腾讯服务器，没有使用生产密钥。

## 1. 0011 代码审读

| 规则 | 实现要点 | 结论 |
|---|---|---|
| D-12 民事能力 | `core.civil_capacity_history` 只追加（UPDATE / DELETE 触发器拒绝），没有记录即为 `UNVERIFIED`；只有绑定本家庭的 INTERNAL SERVICE 可以设定，必须有证据引用，核验人记为 principal。自行授权要求本人为 `ADULT_VERIFIED`，否则须有范围匹配的 VERIFIED 监护人。撤回只要求本人或有效监护人，不设能力门槛。 | 符合补充 V1.1 |
| D-13 官方事实 | 两个 `record_external_fact` 只允许 SERVICE，或者有分配且有 Consent 的顾问调用；观测时间不得晚于当前时间；事实表只追加。DECIDED / RESOLVED 要求权限，**并且**存在 DECISION 事实；CLOSED 维持原规则。 | 符合 |
| D-14 确认与提交 | `confirm_manifest` 只允许 FAMILY 渠道的本人（`ADULT_VERIFIED`）或范围匹配的 VERIFIED 监护人。确认后，条目被触发器锁定，清单只能再变为 SUBMITTED。提交只允许 SERVICE 或有权限的顾问，并要求自然人与确认人不同；表上另有约束 `confirmed_by <> submitted_by`。 | 符合 |
| 权限 | 新函数均为 `SECURITY DEFINER` 并固定 `search_path`，撤销 PUBLIC 后只授予 app；新表开启 RLS 且没有策略（app 不能直接读写）。 | 符合 |

## 2. 独立复跑结果（PG16 / PG17，结果一致）

原始输出：`evidence/claude-v1.5-f10-reaudit-pg16.txt`、`-pg17.txt`；脚本：`evidence/claude-v1.5-run_f10.sh`、`claude-v1.5-d6-gap-probes.sh`。

| 项 | 结果 |
|---|---|
| E1 | 先只放 0001–0010，得到 `ledger=10`、`tables=25`；再加 0011，得到 `ledger=11`、`tables=26`；重复运行逐个校验摘要。三种反例都在迁移前被拒：多一个空 0012、藏起 0011、多一个**未编号的 `.sql`**（最后一个是我加的）。 |
| Codex 套件 | 6 个基线套件、F10 分离 LOGIN 回归（含 7 个 D6 会话）、C1–C10 探针（C4 / C5 / C8 已改为断言）、D6 不可改写回归：全部 PASS。 |
| **Claude 缺口探针**（补补充 V1.1 中 Codex 没有直接断言的 5 项） | G1：已授权的服务在**没有** DECISION 事实时推进到 DECIDED，被拒（审计 `STATE_OR_DECISION_FACT_DENIED`）；记录事实后，同一推进被允许。G2：家庭记录官方事实，被拒。G3：表约束存在，已提交清单的确认人都不等于提交人。G4：确认后经 API 再加条目，被拒，拒绝原因是确认锁，而不是重复检查。G5：顾问确认清单，被拒。**共 20 项 PASS。** |
| 其他 | 无口令的本地 socket 被拒；0009 漂移被拒；原子回滚后不留残余 schema。 |
| 恢复 | 用专用 backup LOGIN 导出，在全新集群恢复：账本 11 条、业务表 26 张、策略 20 条，8 个套件 PASS（含 D6 不可改写）。两个容器都是 `network=none`，没有端口映射。 |

**过程说明：** 第一次复跑时，我的探针选用了已被 Codex 测试撤回的申请 4003，前置步骤因此失败，属于我的测试准备错误。改为新建申请后重跑，全部通过。失败的那次输出原样保留在 `*-run1-probe-setup-error.txt`。

## 3. 开发库与归档

| 项 | 结果 |
|---|---|
| 开发库（PG16 / PG17） | 账本 11 条，0011 哈希为 `acc638a3…`；业务数据 0 行 |
| E2 | reader 登录条目现在在启动后仍然保留，单独运行 reader 登录成功 |
| E3 | `git archive HEAD` 中 49 个 `.sh` / `.sql` / `.yaml` 文件的 `\r` 字节数全部为 0，与 Codex 报告一致 |
| 凭据扫描 | 两个提交中的 74 个长十六进制串与本地凭据文件没有任何重合，也没有私钥、令牌或 `PASSWORD=` 值 |

## 4. 新发现

| 编号 | 严重度 | 内容 | 处理 |
|---|---|---|---|
| R-20 | 低 | `auth.validate_context_request` 不检查主体类型与渠道是否对应。例如 FAMILY 类主体可以申请 ADVISOR 渠道的票据，目前只因为没有顾问分配才被拒（探针已观察到 `CONTEXT_ADVISOR_ASSIGNMENT_INVALID`）。不影响 D-14：比较的是自然人，而且一人只能有一个主体。 | 指令 V1.5，随 D-11 一起做 |
| N-1 | 提示 | `f10_ephemeral_init.sh` 默认期望 11 个 Migration，restore 断言 `ledger=11`、`tables=26`。这是有意写死的守卫，新增 Migration 时必须同步修改。 | 指令 V1.5 第 4 条 |
| N-2 | 提示 | 0011 用 `auth.current_actor_person_id()` 记录提交人；D-11 之后，服务操作的提交人会变为空。`auth.is_internal_service()` 也依赖服务主体对应自然人。 | 指令 V1.5 第 1–3 条 |

## 5. 结论

| 项 | 结论 |
|---|---|
| 第二批（E1、E2、E3、D6 / 0011） | **PASS**（代码审读加 PG16 / PG17 独立复跑） |
| D5、D7 | NOT_STARTED，第三批、第四批进行 |
| 任务 B / 腾讯服务器 | PAUSED / NOT TRUSTED，未变 |
| 生产就绪 | 否 |

剩余阻断项：
- D5、D7 未实施；
- EV-1、EV-3、EV-4 生效版合同（Claude 起草后待批准）；
- 安全事件闸门 G-1 至 G-8；
- FD-6 / FD-7 事实字段。

FINAL AUDIT VERDICT = HOLD
