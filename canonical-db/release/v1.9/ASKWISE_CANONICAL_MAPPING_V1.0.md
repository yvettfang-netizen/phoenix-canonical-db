# ASKWISE 与 Canonical 映射 V1.0（P3）

**状态分级：** `IMPLEMENTED` / `PARTIAL` / `DESIGN_ONLY` / `MISSING` / `BLOCKED`。
**两列分开判断：** "代码/文档"列说明 ASKWISE 侧的证据；"Canonical"列说明数据库的实际状态。只有 Canonical 列能写 IMPLEMENTED，而且必须有 Migration 与测试。

## 0. 来源核实

| 任务书要求的文件 | 实际情况 |
|---|---|
| ASKWISE Data Architecture V1.0 | **未找到**（按名称检索无命中）|
| ASKWISE Student Model V1.0 | **未找到**（按名称检索无命中）；代码中有 `student_model.py` |
| Knowledge State | 代码中有相关定义（`student_model.py`，`TopicKnowledge`），L0–L5 的具体定义**未核实** |
| Learning Engine | `learning_engine.py`、`askwise-learning-engine/` 目录 |
| Thinking Palace / Memory Palace / Agent Logic | **未找到**独立文档；`agent_policy.py` 中有策略代码 |
| Student Pilot、Dashboard 设计 | `PILOT_READINESS_REPORT.md`（94 行）；Dashboard 未单独定位 |
| 已有的产品规格 | `docs/product/askwise/ASKWISE_V0.1_PRODUCT_ARCHITECTURE_AND_IMPLEMENTATION_SPEC.md`（2268 行，V0.1）|
| 与 Education Compass 的数据契约 | `ASKWISE_EDUCATION_COMPASS_DATA_CONTRACT_V1.md`（V1.1，258 行）|
| 集成审计、交接、引擎映射 | `ASKWISE_V1_EDUCATION_COMPASS_INTEGRATION_AUDIT.md`、`ASKWISE_EDUCATION_COMPASS_HANDOFF_V1.md`、`askwise-learning-engine/PYTHON_ENGINE_MAPPING.md` |

**需要 Founder 提供（D-3）：** ASKWISE Data Architecture V1.0 与 Student Model V1.0 的正式文本。在没有它们之前，下面的映射只能以现有代码与 V0.1 规格为依据，**不得当作 ASKWISE 的正式领域模型**。

## 1. 身份：最重要的冲突

| 事实 | 来源 | 风险 |
|---|---|---|
| ASKWISE 合同中的学生标识是 `student_id`，示例为 `stu_2026_001`、`stu_david_001` | 数据契约 §2、§5 | 形态像 Canonical 的公开 ID（`stu_` + 32 位十六进制），但**实际不符合**；如果直接当作 Canonical 标识，会被 `integration.public_ids` 的格式约束拒绝，或者在格式放宽后产生第二套身份 |
| 映射规则：`external_student_id`（来自 Education Compass）→ `askwise_student_id`（ASKWISE 本地 `students.id`）| 数据契约 §7 | ASKWISE 自己维护学生主表。这是**第二套学生主档**，违反"不得重新建立第二套 Person、Family、Student、Guardian 身份体系" |
| ASKWISE 有自己的持久化层（`askwise-learning-engine/src/lib/db.ts`）| 代码 | 数据分散在两个库中，没有统一的权威来源 |
| Education Compass / Family OS 的所有权链：`Family ID → Student ID → Assessment ID → Report ID → Order/Entitlement` | `EDUCATION_COMPASS_CURRENT_BUILD_AUDIT.md` 第 61 行 | Family OS 自己也在发放学生 ID（`/v1/me/students/:studentId`）。**这是第三套学生标识**，需要收敛 |
| `family_id` 在 ASKWISE V1 只作为透传的上下文元数据（数据契约 §2.2、§12.3）| 数据契约 | 没有校验，ASKWISE 不能证明学生属于该家庭 |

**映射决定（建议，待 Founder 确认 D-6）：**

1. **权威身份只有一个：** `core.people`（自然人）与 `core.student_profiles`（学生档案）。ASKWISE 的任何学生引用必须是 `person_id`（uuid），不是 ASKWISE 自己的主键。
2. **ASKWISE 的 `students` 表降为派生表**：只保存 `person_id` 引用、ASKWISE 内部技术字段、同步时间。不保存姓名、学校、年龄等身份属性（这些从 `core.people` 读取，经授权）。
3. **外部标识的形态：** `stu_…` 形式的外部标识如需保留，须经 `integration.public_ids` 映射到 `person_id`，并且必须符合 `^stu_[0-9a-f]{32}$`。`stu_2026_001` 这类不符合格式的值**不得**进入 Canonical。
4. **家庭校验：** ASKWISE 的 `family_id` 不再是透传，而是 Canonical 校验后的上下文（服务上下文 + 家庭绑定，见 0012–0013 的 INTERNAL 上下文）。
5. **Family OS 与 Education Compass 的学生 ID** 需要在 `DOMAIN_ACCESS_AND_ENTITLEMENT_MATRIX` 中单独收敛：它们应映射到同一个 `person_id`，而不是各自发放。

## 2. 覆盖映射

| # | 需求 | ASKWISE 侧证据 | Canonical 状态 | Canonical 中应有的对象（设计）| 缺口 |
|---|---|---|---|---|---|
| 1 | Learning Session 与 Daily Task | `src/lib/db.ts` 含 daily task 类型；UI 计划文档中有 session（17 处）| **MISSING** | `askwise.learning_session`（student_person_id、开始/结束、来源）；`askwise.daily_task`（session 外键、主题、状态）| 全部；且需先决定 ASKWISE 数据是否进 Canonical（D-6）|
| 2 | 学生提交、作业附件及版本 | 代码中**无附件概念**（"attachment / 附件" 零命中）| **MISSING** | 提交表 + 附件引用 `docs.documents` / `docs.document_versions`（需新 data_class `LEARNING`）| 附件类型未定义；需要决定是否复用 docs 模块 |
| 3 | AI Interaction 与 Hint Level | `agent_policy.py` 中 hint 相关策略（26 处）| **MISSING** | `askwise.ai_interaction`（session、角色、提示级别、内容引用）；原始对话保留在 ASKWISE 域 | 全部；原始对话的保留期与可见性未定 |
| 4 | Cognitive Diagnosis | `diagnosis_engine.py` | **MISSING** | `askwise.cognitive_diagnosis`（task、诊断时间、错因代码、先于回答）| 全部；见第 3 节的"先诊断后回答"约束 |
| 5 | 数学 K1–K7 错因 | `diagnosis_engine.py`、`mock-adapter.ts` 中 K1–K7 字样（约 12 处）| **MISSING** | 受控词表 `askwise.error_code`（domain = MATH，K1–K7）+ 外键 | 词表需要领域负责人确认定义 |
| 6 | 政治 P1–P5 错因 | 代码中 P1–P4 命中；**P5 未核实** | **MISSING** | 同上（domain = POLITICS，P1–P5）| P5 需要核实；词表定义需确认 |
| 7 | First-Step Time | `agent_policy.py` 与 `student_model.py`（`MAX_FIRST_STEP_SAMPLES = 10`）| **MISSING** | `askwise.first_step_observation`（task、耗时、时间戳）| 全部 |
| 8 | Knowledge State L0–L5 | `student_model.py` 中有 knowledge state 结构；L0–L5 定义**未核实** | **MISSING** | `askwise.knowledge_state`（student、topic、level、更新时间，历史只追加）| L0–L5 的定义须由 ASKWISE 文本确认 |
| 9 | Student Model 与成长快照 | `student_model.py`（TopicKnowledge 等）；`mock-adapter.ts` 中 snapshot | **MISSING** | `askwise.student_model_snapshot`（只追加）；Family OS 只读取授权摘要，见第 4 节 | 全部 |
| 10 | 再验证、复习、掌握度变化 | `db.ts` 含 review（2 处）；`learning-mode.ts` 含 mastery（4 处）| **MISSING** | `askwise.review_schedule`、`askwise.mastery_event`（只追加）| 全部 |

**汇总：** 10 项在 Canonical 中全部为 MISSING。ASKWISE 侧有实现或策略代码的为 1、3、4、5、6、7、8、9、10；附件（2）在代码中没有对应概念。

## 3. "Diagnose First. Answer Later." 的数据库约束

原则在 ASKWISE 的数据契约与集成审计中有引用（3 处命中）。建议在数据库层强制以下约束，而不是只靠应用：

| 规则 | 实现建议 |
|---|---|
| 同一任务的 AI 回答（提示级别为"答案"）之前，必须存在该任务的 `cognitive_diagnosis` 记录 | `askwise.ai_interaction` 插入前检查（写入函数内部检查，默认拒绝）|
| 诊断记录一旦写入不可修改，修正须追加新诊断 | 只追加表 + 触发器（同 D6 的 append-only 模式）|
| 提示级别只能逐级提升，不能跳级给答案 | 写入函数检查上一级存在 |

## 4. 与 Family OS 的边界

- 原始 AI 对话、认知诊断细节、错因明细由 **ASKWISE 领域** 管理，Family OS 不得直接读取。
- Family OS 只能通过 **授权摘要**（`askwise.growth_summary`，由 ASKWISE 服务写入，范围与 Consent 绑定，用途 `GROWTH_SUMMARY`，数据类别待定义）获得必要的成长信息。
- 摘要必须可撤回：Consent 撤回后，Family OS 的读取在下一次判定时失效（与 EV-1 第 7.3 条一致）。

## 5. 与课程、升学的独立性

- ASKWISE 不可用时，启明堂课程与课后反馈流程必须继续运行。因此 ASKWISE 表只能引用 `core` 与 `learning` 的对象，不能被 `learning` 或 `education` 反向引用。
- ASKWISE 的学习权益（如有）与升学服务、课程权益**分别判断**，各自对应独立的权益引用，不共用一个开关。

## 6. 结论

| 结论 | 说明 |
|---|---|
| 身份存在冲突，必须先解决 | 第 1 节。不解决则不得导入任何 ASKWISE 学生数据 |
| ASKWISE 的 10 项业务对象在 Canonical 中全部 MISSING | 第 2 节 |
| 来源不完整 | ASKWISE Data Architecture V1.0 与 Student Model V1.0 未找到；L0–L5、P5 未核实 |
| 设计可以先行，实现必须等 Founder 决定 | D-3、D-6，见 `FOUNDER_DECISION_REQUIRED_V1.9` |

## R1 更正（2026-10-17）

- 原文"ASKWISE Data Architecture V1.0 未找到"与"ASKWISE Student Model V1.0 未找到"**已更正**：两页在 Notion 中存在（`3c0c31ee15bb81f8ba4aecbadf61c210`、`3c0c31ee15bb81fdba4aecbadf61c210`），上一会话已读取。
- 本轮两页均 **ACCESS BLOCKED**（连接器 404；浏览器未能在本轮打开）。
- 本文件中依赖这两页的字段级映射，标记为 PROPOSED，待恢复访问后重新核对。
- 映射契约中的学生 ID 规则见 `../v1.9/STUDENT_ID_MAPPING_CONTRACT_R1.md`。
