# Codex 执行指令 V1.5：第三批 D5（D-9 / D-10 / D-11）与 R-20

**签发：** 2026-10-16，Claude 复审第二批通过后起草。
**依据：** `phase2-gate/CLAUDE_CANONICAL_DATABASE_REAUDIT_REPORT_V1.5.md`。复审结论：第二批（E1、E2、E3、D6 / 0011）PASS。
**内容要求：** D5 以 `CODEX_INSTRUCTION_V1.3_NEXT.md` 的 D5 节和补充 V1.2 为准；本文件补充新发现 R-20，并写明与已实现 0011 的衔接点。
**边界：**
- 禁止 push、merge、PR；
- 不连接腾讯服务器；
- 只用合成数据；
- 口令不进命令行、日志、报告或聊天；
- 不修改 0001–0011 的任何字节，新 Migration 从 0012 起。

## 开工前

- 核对补充 V1.2 的 SHA-256：`925c83f4d079ec6a1fd9d211786a961d988eaf0d0f033547f1e5ba485552616e`，不一致就停止并报 HOLD。
- 另有补充 V1.4（`b783e03e…`，剩余待决项）已批准。其中与本批相关的只有一点：管理操作双人复核**本阶段不实现**，留到导入真实数据前。

## D5 · 实现 D-11 → D-10 → D-9（0012 起）

按 V1.3 指令 D5 执行，以下衔接点必须处理：

1. **`auth.is_internal_service()`（0009）** 目前要求 `p.person_id = auth.current_actor_person_id()`。D-11 之后 SERVICE 主体的 `person_id` 为空，INTERNAL 上下文的 `actor_person_id` 也为空，此判断须改为按 principal 判定。
2. **0011 中以 `auth.current_actor_person_id()` 作为操作人写入的字段**，在服务操作时会变为空，按 D-11 第 2 条改为同时记录 principal，并逐一列出：
   - `docs.submission_manifests.submitted_by`（服务提交时）；
   - `core.civil_capacity_history.verified_by_principal_id`（已经是 principal，确认不受影响）；
   - 状态事件、审计中的操作人字段。
3. **D-14 的"确认人 ≠ 提交人"** 目前按自然人比较。服务提交时自然人为空，规则自然成立；须补一条回归：服务提交后，`confirmed_by` 与提交方 principal 均有记录。
4. **固定数值同步更新：**
   - `tests/f10_ephemeral_init.sh` 的默认期望 Migration 数（当前为 11）；
   - `tests/f10_ephemeral_restore.sh` 中的 `ledger=11`、`tables=26`。
   - 这两处是有意写死的守卫。新增 Migration 时必须同步修改，并在报告中写明新值。

## R-20 · 签发上下文时，渠道必须与主体类型一致（低，随 D-11 一起做）

**问题：** 现有 `auth.validate_context_request` 不检查主体类型与渠道是否对应。例如 FAMILY 类主体可以申请 ADVISOR 渠道的票据，目前只因为没有顾问分配才被拒（复审探针已观察到 `CONTEXT_ADVISOR_ASSIGNMENT_INVALID`）。

**要求：** 在 0012 及以后的 Migration 中增加对应关系，不一致直接拒绝：

| 主体类型 | 允许的渠道 |
|---|---|
| FAMILY | FAMILY |
| ADVISOR | ADVISOR |
| CHANNEL | PARTNER |
| SERVICE | INTERNAL |

**回归：** 每一种不匹配组合都要有反例测试。

## 测试与交付

- 补充 V1.2"实施与验收要求"中的全部正反例，加上 R-20 的反例，以及上面第 3 条的回归。
- 探针期望改为：
  - C2：回滚后，服务器日志中仍有 `PHOENIX_AUDIT` 行；
  - C3：INTERNAL 服务不绑定家庭也能创建首个家庭，SERVICE 主体不对应自然人。
  - 两者都纳入永久回归。
- 把 Claude 缺口探针 G1–G5（`evidence/claude-v1.5-d6-gap-probes.sh`）改写为永久 F10 回归：
  - G1：已授权方在没有 DECISION 事实时推进被拒，有事实后允许；
  - G2：家庭记录官方事实被拒；
  - G3：确认人 ≠ 提交人；
  - G4：确认后经 API 加条目被拒，且拒绝原因为确认锁；
  - G5：顾问确认清单被拒。
  
  注意 D-11 之后服务操作的操作人字段会改变，G3 的断言须按新字段调整。
- 原有测试中依赖"服务主体是自然人"或"超级用户写夹具"的部分，按新规则更新，并逐条列出。
- PG16 与 PG17 都做，使用分离 LOGIN 加一次性票据，并做全新集群恢复。
- 交付：
  - `FIX_EXECUTION_REPORT_V1.5.md`（证据文件名带 `v1.5`）；
  - 各新 Migration 的 SHA-256；
  - D-9 对账脚本，及其在一次性容器中的演示输出；
  - 本地提交哈希。

## 之后

第四批 D7（FD-6 / FD-7 本地部分）在本批复审通过后进行。开工前核对补充 V1.3 的 SHA-256：`956fcd5a557f82892d2b3fb2886366efb181fc11b5830d1bbb70852acd0177af`。

## 停止条件（同前）

遇到以下任一情况，停止该项并标 HOLD，写明原因后继续其他项：

- 需要修改已有 Migration；
- 需要连接腾讯服务器；
- 需要真实数据或口令；
- 需要自行选择业务语义或事实字段；
- 测试结果与 Claude 的记录冲突且无法解释。
