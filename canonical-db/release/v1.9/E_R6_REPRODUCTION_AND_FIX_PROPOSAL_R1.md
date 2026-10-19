# E-R6 复现与修复方案 R1（V1.9-R1 P1）

**结论：** E-R6 **已复现**（PG16 与 PG17 结果一致）。它不是跨家庭泄露，而是**个案关闭后，已绑定的顾问会话仍可读取学生基本展示信息**，且存在一组同类读取路径。绑定上下文的有效期（最长 60 秒）限制了暴露窗口，但它仍违反"个案关闭后不得读取"的规则。

**状态标记：** 复现 = **VERIFIED**（隔离容器，合成数据）；候选修复的效果 = **VERIFIED**（隔离容器）；修复本身 = **PROPOSED**（未批准，未写入任何迁移，冻结的 0001–0017 未修改）。

## 1. 复现环境

- 一次性容器，`--network none`，无宿主端口，合成数据，结束后删除（`tests/f10_v19_e_r6_driver.sh`）。
- 合成角色：两个家庭 F1、F2；两个学生 S1（F1）、S2（F2）；监护人 G1（F1）、G2（F2）；顾问 A1 在两个家庭各有一个分配。
- 每项检查输出 `PASS`（符合合同）、`FINDING`（违反合同）或 `OBSERVE`（当前代码正确，需要 Founder 决定）。
- 执行入口：`canonical-db/tests/f10_v19_e_r6_repro.sh`（容器内），`canonical-db/tests/f10_v19_e_r6_driver.sh <16|17> [证据文件]`（宿主侧）。

## 2. 结果（PG16 与 PG17 相同）

| 编号 | 场景 | 期望 | 实际 | 判定 |
|---|---|---|---|---|
| T-A | 基线：个案开放、分配有效、Consent 有效，顾问读 S1 基本信息、个案行、分配行、学生档案、成员关系、申请 | 全部 1 | 全部 1 | PASS |
| T-B | 跨家庭：顾问绑定 F1 读 S2；绑定 F2 读 S1 基本信息与 APP1；绑定 F2 读 S2（对照）| 0 / 0 / 0 / 1 | 0 / 0 / 0 / 1 | PASS（无跨家庭泄露）|
| T-C | 监护人撤回 EDUCATION_CASE Consent 后，顾问读 APP1 | 0 | 0 | PASS |
| T-C | 同上，顾问读 S1 基本信息 | — | 1 | OBSERVE：基本信息不受 Consent 约束（见第 5 节）|
| T-E | F2 中分配被撤销，已绑定会话读 S2 基本信息 | 0 | 0 | PASS |
| T-F | F2 中分配到期（valid_until 后 8 秒），已绑定会话读 S2 基本信息 | 到期前 1，到期后 0 | 1 / 0 | PASS |
| T-D1 | **个案关闭后**，已绑定会话读 APP1 | 0 | 0 | PASS（0016 已保护申请）|
| T-D2 | **个案关闭后**，已绑定会话读 S1 基本信息（`core.people`）| 0 | **1** | **FINDING（E-R6）** |
| T-D3 | 同上，读 S1 学生档案（`core.student_profiles`）| 0 | **1** | **FINDING** |
| T-D4 | 同上，读 S1 成员关系（`core.family_memberships`）| 0 | **1** | **FINDING** |
| T-D5 | 同上，读 C1 个案行（`casework.cases`）| 0 | **1** | **FINDING** |
| T-D6 | 同上，读 AS1 分配行（`casework.advisor_assignments`）| 0 | **1** | **FINDING** |
| T-D7 | 个案关闭后，同一顾问的新绑定 | 拒绝 | 拒绝 `CONTEXT_ADVISOR_ASSIGNMENT_INVALID` | PASS |
| T-D8 | 绑定超过 `expires_at`（约 50 秒）后，同一会话读 S1 基本信息 | 0 | 0 | PASS（上下文过期即失效）|
| OBSERVE | 关闭后 AS1 行状态 | — | `ACTIVE`、未撤销、当前有效 | 根因之一：关闭个案不结束分配（见第 3 节）|
| OBSERVE | 关闭后 C1 状态 | — | `CLOSED` | — |
| OBSERVE | `auth.session_contexts` 字段 | — | 含 `expires_at`（从票据复制，最长 60 秒）| 暴露窗口由此限定 |

**汇总：** PG16 与 PG17 均为 `SUMMARY findings=5`（T-D2 至 T-D6）。候选修复后为 `findings=0`，且 27 项检查全部 PASS（22 + 5 = 27）。

证据文件：
- `canonical-db/evidence/v1.9-e-r6-repro-pg16.txt`、`v1.9-e-r6-repro-pg17.txt`（现行代码）
- `canonical-db/evidence/v1.9-e-r6-candidate-pg16.txt`、`v1.9-e-r6-candidate-pg17.txt`（候选修复）

## 3. 根因（代码审读 + 复现确认）

| 位置 | 问题 |
|---|---|
| `migrations/canonical/0007_security_boundary_fixes.sql`：`core.can_read_subject_basics`，顾问分支 | 只检查分配的有效期、撤销与生命周期，**没有检查 `casework.cases.status`** |
| 同文件：`casework.is_current_advisor_for_case`（唯一调用方是 `cases_read` 策略）| 同样没有个案状态检查 |
| 同文件：策略 `assignments_read` 的顾问分支 | 同样没有个案状态检查 |
| `migrations/canonical/0013_management_write_api.sql`：`casework.close_case` | 只更新 `casework.cases.status`，**不结束**该个案下的分配，分配保持 `ACTIVE` |
| `migrations/canonical/0012_service_principal_and_context.sql`：`auth.validate_context_request` | 只在**绑定时**检查个案状态，因此关闭后无法新建绑定，但已绑定的会话不再复查 |

**为什么申请和文件没有泄露：** 0015 与 0016 对 `casework.has_active_advisor_assignment` 与 `docs.can_read_document` 加入了 `status IN ('OPEN','PAUSED')` 检查。T-D1 验证了申请；身份案件、事实表、文件表的读取路径依赖相同的检查（代码审读确认，**未单独执行**）。

**为什么不是跨家庭泄露：** 所有顾问分支都带有 `family_id = auth.current_family_id()` 条件，T-B 验证了这一点。

## 4. 暴露窗口

- 绑定票据的有效期最长 60 秒（`auth.issue_context_ticket` 的 CHECK）。`auth.session_contexts.expires_at` 从票据复制，`auth.current_*` 辅助函数在每条语句中检查它（0007，约第 155–182 行）。
- T-D8 证明：超过 `expires_at` 后，同一会话读取返回 0。
- 因此，**最坏情况下的暴露窗口 = 绑定后剩余的上下文有效期（≤ 60 秒）**。不存在"长期有效的陈旧会话"。
- 这个窗口仍然违反合同。是否可接受、是否需要收紧，属于 Founder 决定（见 `FOUNDER_DECISION_SUMMARY_R1.md` N-2）。

## 5. 与 Consent 的关系（OBSERVE，需要决定）

- 撤回 EDUCATION_CASE Consent 后，顾问**立即**无法读取申请（T-C，PASS）。
- 同一时刻，顾问仍可读取 S1 的基本展示信息（`can_read_subject_basics` 不检查 Consent）。
- 当前代码的行为是合法的，但文档中没有任何规则说明基本信息是否应当受 Consent 约束。这要求 Founder 明确规定（N-1）。

## 6. 修复方案（PROPOSED，未批准）

**候选文件：** `canonical-db/tests/candidates/e_r6_0018_candidate.sql`（位于 `tests/candidates/`，**不是迁移**，只在一次性容器中应用）。

**修复规则：** 顾问的读取路径在个案不再为 `OPEN` 或 `PAUSED` 时关闭。这与 0015、0016 的规则一致。`status` 的取值只有 `OPEN`、`PAUSED`、`CLOSED`（0004 的 CHECK），因此规则是完整的。

**改动范围（三处）：**
1. `core.can_read_subject_basics`：顾问分支增加 `c.status IN ('OPEN','PAUSED')`。影响 `people_read`、`student_profiles_read`、`memberships_read`。
2. `casework.is_current_advisor_for_case`：增加同样条件。唯一调用方为 `cases_read`。
3. 策略 `assignments_read`：顾问分支增加同样条件。家庭成员的读取不变。

**不包含的内容：** 不改变 `lifecycle_status`（取值为 ACTIVE、REVOKED、EXPIRED），不让 `close_case` 结束分配。这是产品决定（N-3），不在本修复范围。

**效果验证：**

| 验证 | 结果 |
|---|---|
| 复现脚本（PG16）：候选前 5 个 FINDING → 候选后 0 个 | VERIFIED |
| 复现脚本（PG17）：同上 | VERIFIED |
| 完整 F10 套件（PG16）：候选与基线的 PASS/FAIL 序列 | **完全相同**（191 PASS，5 项预期拒绝，PID 已规范化）|
| 完整 F10 套件（PG17）：同上 | **完全相同**（191 PASS，5 项预期拒绝）|
| 审计对账（PG16 与 PG17）| 249 条日志，248 条与数据库匹配，1 条为预期的回滚记录（与基线相同）|

证据文件：`canonical-db/evidence/v1.9-f10-baseline-pg16.txt`、`v1.9-f10-candidate-pg16.txt`、`v1.9-f10-baseline-pg17.txt`、`v1.9-f10-candidate-pg17.txt`。

**如果批准：** 把候选内容写成新的迁移 `0018_*.sql`（使用 `CREATE OR REPLACE` 与 `DROP POLICY IF EXISTS` / `CREATE POLICY`），并计算 sha256 写入账本。0001–0017 保持不变。

## 7. 永久负向回归测试

- 负向断言是 `f10_v19_e_r6_repro.sh` 中 T-D2 至 T-D6 的 `check … 0`，它们是永久测试，不随修复删除。
- 在修复批准并应用之前，这组测试**在现行代码上失败**，因此**不加入** F10 的门禁（否则门禁永远红）。
- 修复应用后，把这组测试接入 F10 门禁，并在 `tests/f10_local_acceptance.sh` 中以显式步骤运行。

## 8. 未覆盖与残余风险

| 项 | 状态 |
|---|---|
| 身份案件、身份事实、文件、提交清单在关闭后的读取 | 代码审读 PASS（依赖 0015/0016），**未执行** |
| pwsh 版本的 F10 脚本 | **PASS（2026-10-19）**：PG16 / PG17；当前 0001–0017 基线，未把候选变成迁移 |
| 分配在关闭后仍为 `ACTIVE`（数据不一致）| 已观察到，**未修复**，等待 N-3 决定 |
| 基本信息是否受 Consent 约束 | **OBSERVE**，等待 N-1 决定 |
| 候选修复需要 Founder 批准后才能成为迁移 | **BLOCKED**（见 0018 就绪决定）|
| 生产库 | 未触碰；本批只在一次性容器中测试 |
