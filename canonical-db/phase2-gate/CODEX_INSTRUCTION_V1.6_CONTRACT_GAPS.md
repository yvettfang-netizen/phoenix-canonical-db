# Codex 执行指令 V1.6：实现 EV-1 / EV-3 / EV-4 已批准的缺口决定

**签发：** 2026-10-16。Founder 批准 EV-1、EV-3、EV-4，缺口按建议处理；指令由 Claude 起草。
**依据：** `phase2-gate/evidence/approved/EV1_EV3_EV4_CONTRACTS_V1.0_APPROVAL.md` 第 2 节。

开工前核对三份合同的 SHA-256，任一不一致就停止并报 HOLD：

| 合同 | SHA-256 |
|---|---|
| EV-1 | `3f73f16793bb0c3ad4049605e69d86d5ba328b3f54c9582f64b83e56fc17e85b` |
| EV-3 | `0d9fb898e9e3b3bb1b9289a8decdc9fbf7159a3f8fa6eb5abf3f81a3aea2dd2f` |
| EV-4 | `6e6c970d8b8fd42b716e5fd4d02ab8614710d75930e8ec9c9729b973a102afb3` |

**批次顺序（调整）：**

| 批次 | 内容 |
|---|---|
| 第三批（进行中） | D5 + R-20，按 V1.5 |
| **第四批** | 本指令 T1–T4 |
| 第五批 | D7（原第四批顺延），按 V1.5 / V1.3 |

**合并到第三批的条件：** T1 属于 D-10 管理接口的扩充。第三批如尚未交付，可以把 T1 并入第三批，并在报告中写明。

**边界（同前）：**
- 禁止 push、merge、PR；
- 不连接腾讯服务器；
- 只用合成数据；
- 口令不进命令行、日志、报告或聊天；
- 不修改已有 Migration，在第三批之后的编号上新增。

**所有新函数统一要求：**
- `SECURITY DEFINER`，固定 `search_path`；
- 撤销 PUBLIC 后只授予 app；
- 默认拒绝；
- 写审计，原因代码稳定；D-9 已实现时，同时写 `PHOENIX_AUDIT`。

## T1 · 家庭成员关系与展示名称（EV-1 缺口 E1-2）

**新增管理接口：** 只允许 INTERNAL 渠道的 SERVICE 主体调用，且须绑定该家庭（属于家庭内操作）。

1. **结束成员关系：** 设置 `valid_until`。
   - 只能提前，不能延长；
   - 不得早于当前时间，也不得早于 `valid_from`；
   - 已结束的成员关系不能再修改。
2. **修改自然人展示名称：** 该自然人须属于当前家庭；长度规则同建表约束。
3. **修改家庭展示名称。**
4. **审计限制：** 只记录 ID 和原因代码，**不把旧名或新名写进审计或服务器日志**。

**回归测试：**
- 非 SERVICE 调用、跨家庭调用、延长有效期、改已结束的关系，都被拒绝；
- 成员关系结束后，该成员的 FAMILY 渠道票据被拒（`CONTEXT_FAMILY_MEMBERSHIP_INVALID`）。

## T2 · 顾问读文件须有覆盖该主体的分配（EV-1 E1-4 / EV-3 E3-6）

1. **收紧判断：** 修改 `docs.can_read_document` 的 ADVISOR 分支。除现有的 Consent 外，还须存在一个本家庭的 `casework.cases`，同时满足：
   - 个案的主体就是被读的主体；
   - 当前顾问在该个案上有有效分配：ACTIVE、处于有效期内、未撤销。
2. **连带影响：** `docs.add_submission_item`、`docs.confirm_manifest`、`docs.submit_manifest` 中对顾问的读取检查都经过该函数，会随之收紧。在报告中逐一列出受影响的函数和测试。
3. **不受影响：** FD-2 第 1 条的"基本展示信息无需额外 Consent"维持不变。

**回归测试：**
- 顾问只分配到主体 A、但持有主体 B 的 DOCUMENT_READ Consent：读 B 的文件被拒；
- 分配覆盖 B 之后，允许读取；
- 分配撤销或过期后，再次被拒。

## T3 · 文档撤回接口（EV-3 缺口 E3-1）

**新增 `docs.withdraw_document(p_document_id)`：**

1. **谁可以撤回：**
   - FAMILY 渠道：主体本人（不论民事能力），或范围匹配的有效监护人。范围对应关系为 GENERAL→GENERAL、EDUCATION→EDUCATION、IDENTITY_SENSITIVE→IDENTITY，可复用 `core.actor_can_manage_subject`；
   - 绑定该家庭的 INTERNAL SERVICE。
2. **只能设置一次：** `withdrawn_at` 只能从空变为有值。重复撤回返回拒绝（原因代码自定，例如 `ALREADY_WITHDRAWN`）。
3. **防回退：** 增加触发器保护——`withdrawn_at` 一旦有值，不可清空或修改；同时确认文档的其他字段不会被这条路径改动。
4. **效果：**
   - 已撤回的文档不能进入新清单（现有规则）；
   - 尚未提交的清单中已有该文档时，提交被拒（现有触发器 `WITHDRAWN_DOCUMENT_NEW_USE_DENIED`）；
   - 已提交的清单及其可读性不变。

**回归测试：**
- 本人和监护人撤回成功；
- 顾问、渠道方、范围不匹配的监护人撤回被拒；
- 重复撤回被拒；
- 撤回后加入新清单被拒；
- 撤回后，含该文档、已确认但未提交的清单，提交被拒；
- 已提交的清单仍可读；
- 直接把 `withdrawn_at` 改回空被拒。

## T4 · 身份案件在审核前可以结案（EV-4 缺口 E4-3）

`identity.advance_case` 增加 DRAFT→CLOSED、EVIDENCE_PENDING→CLOSED 两个流转。执行人与其他非终局推进相同（`identity.can_write_case`）。RESOLVED 的规则不变。

**回归测试：**
- 家庭一方从 DRAFT 和 EVIDENCE_PENDING 结案成功；
- 没有分配或没有 Consent 的顾问被拒；
- CLOSED 之后不能再推进。

## 测试与交付

- PG16 与 PG17 都做，使用分离 LOGIN 加一次性票据，并做全新集群恢复。同步更新 F10 的 Migration 数和表数守卫。
- 原有测试中受 T2 影响的部分（顾问读文件、加条目、提交），逐条列出改动。
- 交付：
  - `FIX_EXECUTION_REPORT_V1.6.md`（证据文件名带 `v1.6`）；
  - 新 Migration 的 SHA-256；
  - 本地提交哈希。

完成后由 Claude 复审。

## 停止条件（同前）

遇到以下任一情况，停止该项并标 HOLD，写明原因后继续其他项：

- 需要修改已有 Migration；
- 需要连接腾讯服务器；
- 需要真实数据或口令；
- 需要自行选择业务语义；
- 测试结果与 Claude 的记录冲突且无法解释。
