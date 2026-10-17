# 教育 / 启明堂学习 / ASKWISE 修订 ERD R1（V1.9-R1 P4）

**范围：** 三层所有权模型，以及它们与 Canonical 核心（身份与授权）的关系。
**标记：** `[已实现]` = 表在开发库中存在（VERIFIED，源码核实）；`[设计]` = 只是设计，库中不存在；`[BLOCKED]` = 来源不可访问，不得据此编写代码。
**来源状态：** 启明堂 Freeze、ASKWISE 两页、Family OS 页本轮均 ACCESS BLOCKED（见 `NOTION_SOURCE_VERIFICATION_R1.md`）。所有 `[设计]` 条目的业务规则都是 PROPOSED。九灵 Runtime 为 **BLOCKED**。

## 1. 三层所有权（修订后）

| 层 | 负责的业务 | 数据所有者 | 与 Canonical 核心的关系 |
|---|---|---|---|
| **Canonical 核心** | 自然人、家庭、监护、Consent、登录主体、分配、审计、外部标识映射 | Canonical（唯一权威）| 身份与授权的唯一来源，其他层只引用 `person_id` |
| **Education（教育）** | 学生档案、升学规划、学校与项目申请、Offer、签证、服务交付 | Education（Canonical 中的 `education` schema）| 申请通过 `student_person_id` 引用 `core.student_profiles` |
| **启明堂 Learning（学习）** | 课程、报名、教师、排课、考勤、课后卡片、阶段报告 | Learning（新 schema，设计阶段）| 报名引用 `student_profiles.person_id`；教师是 Canonical 的登录主体，见 `learning-v2.0/` |
| **ASKWISE（AI 学习）** | 学习任务、AI 交互、认知诊断、错因标签、知识状态、成长 | ASKWISE 系统（外部）| 只引用 `person_id`；原始数据不进入 Canonical，也不进入 Family OS |
| **Family OS（读取层）** | 家庭视图，读取成长摘要 | 无业务数据所有权 | 只能通过授权接口读取摘要，不复制 ASKWISE 原始思考与原始数据 |
| **九灵 Runtime** | 协作与权限执行系统（不是默认的九个业务数据库）| **BLOCKED** | 只有在核对 Runtime 与 Operations 契约之后，才考虑持久化 Agent 注册表、执行记录与审计 |

**修订要点（相对 V1.9 的 `UNIFIED_STUDENT_ERD_V1.0.md`）：**
1. 明确 ASKWISE 与启明堂 Learning 是两个所有权不同的域。V1.0 中把学习记录与 ASKWISE 诊断放在同一图中，会误导为同一个所有者。
2. Family OS 不拥有数据，只通过摘要接口读取。V1.0 的 `askwise.growth_summary` 表归属 ASKWISE（由 ASKWISE 服务写入），Family OS 只读视图。
3. 九灵 Runtime 不作为数据库域。V1.0 中没有九灵，本修订也不新增九灵表。

## 2. 实体关系（文字 ERD）

```
Canonical 核心 [已实现]
  core.people ──────────────── 唯一的自然人主数据（person_id）
    ├─ core.student_profiles [已实现] ── 学生身份（person_id，一对一；不另建学生主表）
    ├─ core.family_memberships [已实现] ── 家庭成员（family_id, person_id）
    ├─ core.guardian_authorities [已实现] ── 监护（guardian → subject，范围，证据等级，有效期）
    ├─ consent.grants [已实现] ── Consent（授权人、被授权人、对象，用途，数据类别）
    ├─ auth.principals [已实现] ── 登录主体（FAMILY / ADVISOR / CHANNEL / SERVICE）
    ├─ auth.external_identities [已实现] ── 外部签发方 + subject → 主体（0017）
    └─ integration.channel_grants [已实现] ── 渠道方对某家庭的授权

  casework.cases [已实现] ── 通用个案（subject_person_id，family_id，status OPEN/PAUSED/CLOSED）
    └─ casework.advisor_assignments [已实现] ── 顾问分配（lifecycle ACTIVE/REVOKED/EXPIRED）
  integration.public_ids [已实现]      ── 公开 ID（stu_ + 32 位十六进制）
  integration.legacy_id_mappings [已实现] ── 外部 ID 映射（见 STUDENT_ID_MAPPING_CONTRACT_R1.md）
  audit.access_events [已实现]          ── 审计

Education [已实现 / 设计]
  education.applications [已实现] ── 升学申请（student_person_id，family_id）
    ├─ education.application_status_events [已实现]
    └─ education.external_facts [已实现] ── 官方回执与决定
  education.planning [设计] ── 升学规划（学生、目标、阶段）
  education.offer [设计] ── Offer（引用 application_id；不存金额）
  education.visa_case [设计] ── 签证（引用 application_id）
  education.service_delivery [设计] ── 服务交付记录（引用 subject，权益外部引用）
  identity.cases [已实现] ── 身份案件（subject_person_id）
    └─ identity.external_facts / case_status_events [已实现]
  docs.documents / document_versions / submission_manifests / submission_items [已实现]

启明堂 Learning [设计，BLOCKED 来源]
  learning.course / course_version [设计]
  learning.enrollment [设计] ── 报名（student_person_id → student_profiles；course_version_id）
  learning.teacher_assignment [设计] ── 教师分配（teacher_person_id → 登录主体 TEACHER）
  learning.class / schedule_slot [设计]
  learning.attendance [设计] ── 考勤（enrollment_id）
  learning.after_class_card [设计] ── 课后卡片（enrollment_id；发布后家长可见）
  learning.stage_report [设计] ── 阶段报告
  learning.external_order_ref [设计] ── 权益引用（外部订单号与有效期；不存金额）
  → 学生引用只能是 person_id，并且必须存在对应的 student_profiles；不建学生主表

ASKWISE [设计，来源 BLOCKED]
  askwise.learning_session / daily_task / ai_interaction [设计，只在 ASKWISE 库内]
  askwise.cognitive_diagnosis / error_label / knowledge_state [设计，只在 ASKWISE 库内]
  askwise.growth_summary [设计，由 ASKWISE 写入；Canonical 不保存原始诊断]
  → 与 Canonical 的唯一接口：person_id 引用、摘要读取接口、外部身份映射

Family OS 读取层 [设计]
  family_os.growth_view ── 只读视图或接口，返回 growth_summary 的授权字段
  → 不复制 ASKWISE 原始对话与诊断明细

Operations 引用 [设计，外部归属]
  外部订单号、权益号、有效期 → Canonical 只存引用，金额保存在 Operations
```

## 3. 不变量（必须在数据库层成立，或列为待实现）

| 编号 | 不变量 | 状态 |
|---|---|---|
| I-1 | 每个自然人只有一条 `core.people` | [已实现]（`person_id` 主键）|
| I-2 | 学生身份只通过 `core.student_profiles` 体现，没有第二套学生主表 | [已实现]（外键）；学习与 ASKWISE 表待实现后需要同样的约束 |
| I-3 | 任何 learning / askwise / education 记录的学生引用都是 `person_id`，且必须存在对应的 `student_profiles` | Education [已实现]；Learning、ASKWISE [设计] |
| I-4 | 报名（learning）与学习计划（askwise）彼此不互相约束 | [设计] |
| I-5 | 升学服务、课程权益、ASKWISE 权益分别判断，没有共用开关 | [设计]（权益判断函数不存在，见 `DOMAIN_ACCESS_AND_ENTITLEMENT_MATRIX_V1.0.md`）|
| I-6 | 购买不授予学习敏感数据访问；必须有 `LEARNING_RECORD` Consent | [设计]，**需要 Founder 决定 D-5** |
| I-7 | 个案关闭后，顾问不得读取该个案的学生基本信息 | **未满足**（E-R6，见 `E_R6_REPRODUCTION_AND_FIX_PROPOSAL_R1.md`）|
| I-8 | 未成年学生的业务访问需要有效监护与 Consent | Education 与 Canonical 核心 [已实现]；学习与 ASKWISE [设计] |

## 4. 与 V1.0 文件的差异

| V1.0 文件 | 本修订的变化 |
|---|---|
| `UNIFIED_STUDENT_ERD_V1.0.md` | 三层所有权分离；Family OS 改为只读摘要；E-R6 标记为未满足 |
| `LEARNING_DOMAIN_COVERAGE_V1.0.md` | 原判断"启明堂来源未找到"更正为"来源存在但本轮 ACCESS BLOCKED"（见 Notion 核验文件第 4 节）|
| `ASKWISE_CANONICAL_MAPPING_V1.0.md` | 原判断"Data Architecture / Student Model 未找到"更正为"存在，本轮 ACCESS BLOCKED" |
| `DOMAIN_ACCESS_AND_ENTITLEMENT_MATRIX_V1.0.md` | 无变化；其中"学习域 MISSING"与"ASKWISE DESIGN_ONLY"仍然成立 |

## 5. 与代码现状的差异（需要知道的事实）

- 库中**没有**教师（TEACHER）登录主体。`principal_kind` 的 CHECK 只允许 `FAMILY`、`ADVISOR`、`CHANNEL`、`SERVICE`（0003）。学习域需要 D-5 决定。
- 库中**没有**权益判断函数，也没有 `LEARNING_RECORD` 的 Consent 用途（`consent.grants.purpose` 的 CHECK 只有 `DOCUMENT_READ`、`EDUCATION_CASE`、`IDENTITY_CASE`）。
- 监护范围的 CHECK 只有 `GENERAL`、`EDUCATION`、`IDENTITY`，没有 `LEARNING`。
- Education Compass 的历史迁移 012 使用文本 ID 表（`core.members`、`core.students`、`askwise.*`），与 Canonical 的 `core` schema 存在命名冲突。学习域与 ASKWISE 的表名必须避开这些名称，并在映射契约中处理（见 `STUDENT_ID_MAPPING_CONTRACT_R1.md` 第 3 节）。

## 6. 九灵 Runtime（BLOCKED）

- 九灵现行最终基线页 `3e1c31ee15bb8122baa4d690facb0897` 本轮与上一会话都无法读取。
- 因此：不设计九灵的数据表，不假设它的授权模型，不把它列为数据库域。
- 只有在拿到基线页后，才能核对 Runtime 与 Operations 契约，再决定是否持久化 Agent 注册表、执行记录与审计。
- 对应 Founder 决定：D-9（见 `FOUNDER_DECISION_SUMMARY_R1.md`）。
