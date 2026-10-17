# 域访问与权益矩阵 V1.0（P4 / P5 的授权部分）

**读法：** 每个单元格给出该角色对该数据对象的结论，并标明执行点与状态。
- 允许 / 拒绝 / 条件（条件 = 需要某个 Consent、监护或分配）
- 执行点：RLS 策略（读）、SECURITY DEFINER 函数（写）或尚未实现
- 状态：`IMPLEMENTED`（有 Migration 与测试）、`DESIGN_ONLY`（仅设计）、`MISSING`（对象不存在）

**关于 SERVICE 列（修正版）：** RLS 策略只对 FAMILY、ADVISOR、PARTNER 渠道开放读取。`core.can_read_subject_basics` 在 INTERNAL 渠道下返回 false（已在开发库上核实），`families_read`、`documents_read`、`applications_read` 等策略的读取条件都不包含 INTERNAL。因此 **SERVICE 通过 RLS 读不到任何业务数据**，只能经 SECURITY DEFINER 函数写入同一家庭的数据。下表中 SERVICE 列对读取的结论，是根据策略定义推断的，**尚无专门测试**。

## 1. 角色

| 角色 | 登录主体类型 | 在库中是否存在 |
|---|---|---|
| 学生本人 | FAMILY（自然人 = 学生）| 是（`auth.principals`）|
| 家庭成员 / 监护人 | FAMILY | 是 |
| 顾问 | ADVISOR | 是 |
| 渠道方 | CHANNEL（经 `integration.channel_grants`）| 是 |
| 系统服务 | SERVICE（不对应自然人）| 是 |
| 教师 | — | **否**：没有 TEACHER 主体类型，见学习域文档 |
| ASKWISE 服务 | — | **否**：没有登录主体，ASKWISE 目前是独立应用 |
| Family OS 服务 | — | **否** |
| Operations 服务 | — | **否**（外部归属）|

## 2. 对象矩阵

| 对象 | 学生本人 | 本家庭监护人（VERIFIED）| 本家庭其他成员 | 分配顾问 | 渠道方（有授权）| SERVICE（同家庭）| 其他家庭 |
|---|---|---|---|---|---|---|---|
| 人员基本信息 `core.people` | 允许 | 允许 | 允许 | 允许（有分配，**见 E-R6 缺陷**）| 允许（有授权）| 读取拒绝（RLS）| 拒绝 |
| 家庭 `core.families` | 允许 | 允许 | 允许 | 拒绝 | 拒绝 | 读取拒绝（RLS）| 拒绝 |
| 成员关系 | 允许 | 允许 | 允许 | 拒绝 | 拒绝 | 读取拒绝（RLS）；写入经函数 | 拒绝 |
| 学生档案 `core.student_profiles` | 允许 | 允许 | 允许 | 允许（有分配，**见 E-R6**）| 允许（有授权）| 读取拒绝（RLS）| 拒绝 |
| 监护授权 | 允许（本人）| 允许（本人）| 拒绝 | 拒绝 | 拒绝 | 读取拒绝（RLS）；建立与撤销经函数 | 拒绝 |
| Consent | 允许（本人为授权人或对象）| 允许（授权人或对象）| 拒绝（除非是授权人）| 拒绝 | 拒绝 | 读取拒绝（RLS）；撤回经函数 | 拒绝 |
| 教育申请 `education.applications` | 允许 | 允许 | 允许 | 条件：有分配 + EDUCATION_CASE Consent | 拒绝（除非授权）| 读取拒绝（RLS）；状态推进经函数 | 拒绝 |
| 申请状态事件 | 同申请 | 同申请 | 同申请 | 同申请 | 拒绝 | 读取拒绝（RLS）| 拒绝 |
| 官方事实 `external_facts` | 同申请（读）| 同申请（读）| 同申请（读）| 条件：有分配 + Consent；**可写** | 拒绝 | 读取拒绝（RLS）；**可写**（经函数）| 拒绝 |
| 身份案件 `identity.cases` | 允许 | 允许 | 允许 | 条件：有分配 + IDENTITY_CASE Consent | 拒绝 | 读取拒绝（RLS）；写入经函数 | 拒绝 |
| 文档元数据 | 条件：DOCUMENT_READ Consent | 条件：Consent + 监护范围 | 拒绝 | 条件：Consent + 有分配 | 条件：渠道授权 + Consent | 读取拒绝（RLS）；登记经函数（同家庭）| 拒绝 |
| 文档版本 | 同文档 | 同文档 | 同文档 | 同文档 | 同文档 | 读取拒绝（RLS）；追加经函数 | 拒绝 |
| 提交清单 | 确认：本人（ADULT_VERIFIED）| 确认：本人或 VERIFIED 监护（范围匹配）| 拒绝 | 提交：有分配 + Consent | 拒绝 | 提交：经函数（同家庭）；读取拒绝（RLS）| 拒绝 |
| 个案 `casework.cases` | 允许 | 允许 | 允许 | 允许（有效分配；**个案关闭后的读取见 E-R6**）| 拒绝 | 读取拒绝（RLS）；创建与关闭经函数 | 拒绝 |
| 审计 `audit.access_events` | 拒绝 | 拒绝 | 拒绝 | 拒绝 | 拒绝 | 拒绝（只能经函数写入）| 拒绝 |
| 民事能力 `core.civil_capacity_history` | 拒绝（无策略）| 拒绝 | 拒绝 | 拒绝 | 拒绝 | 设定经函数（INTERNAL）| 拒绝 |
| 外部身份映射 | 拒绝 | 拒绝 | 拒绝 | 拒绝 | 拒绝 | 管理经函数；**binder 解析** | 拒绝 |
| 学习记录（课程、作业、反馈）| **MISSING** | **MISSING** | **MISSING** | **MISSING** | **MISSING** | — | — |
| ASKWISE 原始 AI 对话与诊断 | **DESIGN_ONLY**：仅本人与 ASKWISE 服务 | DESIGN_ONLY：拒绝 | 拒绝 | 拒绝 | 拒绝 | DESIGN_ONLY：ASKWISE 服务写入 | 拒绝 |
| Family OS 成长摘要 | **DESIGN_ONLY**：本人可见 | DESIGN_ONLY：Consent 范围内可见 | 拒绝 | 拒绝 | 拒绝 | DESIGN_ONLY：ASKWISE 服务写入 | 拒绝 |
| 订单、合同、权益 | 外部（Operations）| 外部 | 外部 | 外部 | 外部 | 外部 | 外部 |

## 3. 权益矩阵（独立判断）

任务书要求：升学服务、课程权益、ASKWISE 权益**分别判断**，购买课程不得自动获得学生敏感学习数据访问权。

| 权益类型 | 授予来源 | 在 Canonical 中的表示 | 判断方式 | 状态 |
|---|---|---|---|---|
| 升学服务 | Operations 订单 | 引用：外部订单号 + 产品类型 `EDUCATION_SERVICE` + 有效期 | 申请写入前检查该引用有效 | MISSING |
| 课程权益 | Operations 订单 | 引用：外部权益号 + 产品类型 `COURSE` + 课程 ID + 有效期 | 课程访问前检查；**不授予学习敏感数据访问** | MISSING |
| ASKWISE 权益 | Operations 订单 | 引用：外部权益号 + 产品类型 `ASKWISE` + 有效期 | ASKWISE 服务启动学习计划前检查 | MISSING |
| 学习敏感数据访问 | **Consent**（新用途 `LEARNING_RECORD`，数据类别 `LEARNING`，需新增）| `consent.grants` | 与权益无关，只看 Consent | MISSING（需要决定，见 FOUNDER D-5）|

**规则：**
1. 三种权益互不影响：升学服务到期不影响课程，课程权益不开放 ASKWISE。
2. 权益引用不存金额细节，金额由 Operations 保存。
3. 权益缺失或过期 → 拒绝，并写审计原因代码（例如 `ENTITLEMENT_MISSING`，待定义）。
4. 不得因为"购买"这个事实自动创建 Consent。

## 4. 执行点汇总

| 执行点 | 已实现的规则 | 缺口 |
|---|---|---|
| RLS 策略（20 条）| 家庭隔离、分配、Consent、监护范围、渠道授权（经函数）；INTERNAL 不读取业务数据 | `core.people` / `student_profiles` 的顾问分支缺少个案状态检查（E-R6）|
| SECURITY DEFINER 函数（94 个）| 写入门禁、状态机、官方事实、确认与提交分离、主体类型与渠道对应、票据校验 | 权益判断函数不存在 |
| binder 解析（`auth.resolve_external_identity`）| 未登记或停用的身份返回空 | — |
| 审计（`PHOENIX_AUDIT` + `audit.access_events`）| 每次写判定与所有拒绝都记录 | RLS 过滤掉的读取不产生审计行；这是设计如此，但合同中尚未写明 |

## 5. 结论

- 学生、家庭、监护、顾问、渠道方之间的访问规则，对 **现有实体** 已经能够成立，并有测试覆盖。
- SERVICE 只能写不能读（经 RLS），这保证了服务账户不会获得全库读取能力，但也意味着服务端的任何读取都必须经过函数。
- 学习域与 ASKWISE 域的访问规则只能是 **设计**（MISSING / DESIGN_ONLY），不能视为已实现。
- 权益判断不存在。在它实现前，任何"购买即开通"的流程都不应上线。
- 已知 P1 缺陷 E-R6 影响顾问对学生基本信息的读取，需在下一批修复。
