# 统一学生数据关系图与端到端用例 V1.0（P4）

**实体名以实际 Schema 为准**（见 `CANONICAL_SCHEMA_ACTUAL_INVENTORY_V1.9.md`）。标注 `[已实现]` 的实体在库中存在；标注 `[设计]` 的实体在库中**不存在**，只是候选，不能按已存在的表编写代码。

## 1. 数据关系（文字 ERD）

```
core.people [已实现]  ── 唯一的自然人主数据（person_id）
  │
  ├─ core.family_memberships [已实现] ── 家庭成员（family_id, person_id, 角色, 有效期）
  │
  ├─ core.student_profiles [已实现] ── 学生档案（person_id，一对一，不另建学生主表）
  │     │
  │     ├─ education.applications [已实现] ── 升学申请（student_person_id → student_profiles）
  │     │     ├─ education.application_status_events [已实现]
  │     │     └─ education.external_facts [已实现] ── 官方回执 / 决定
  │     │
  │     ├─ identity.cases [已实现] ── 身份案件（subject_person_id → people）
  │     │
  │     ├─ docs.documents [已实现] ── 文档（subject_person_id；data_class EDUCATION / IDENTITY_SENSITIVE）
  │     │     └─ docs.document_versions [已实现]
  │     │
  │     ├─ core.guardian_authorities [已实现] ── 监护（guardian → subject，范围、证据等级、有效期）
  │     ├─ consent.grants [已实现] ── Consent（grantor / grantee / subject，用途、数据类别）
  │     └─ casework.cases [已实现] ── 通用个案（subject_person_id；可引用一个申请或案件）
  │           └─ casework.advisor_assignments [已实现] ── 顾问分配
  │
  ├─ auth.principals [已实现] ── 登录主体（FAMILY / ADVISOR / CHANNEL / SERVICE；SERVICE 不对应自然人）
  ├─ auth.external_identities [已实现] ── 签发方 + subject → 主体（0017）
  └─ integration.channel_grants [已实现] ── 渠道方对某主体的授权

学习域 [设计，见 LEARNING_DOMAIN_COVERAGE]
  learning.course / course_version / module / lesson / enrollment / class / schedule / attendance / homework / feedback
  → 每个学生相关记录只引用 student_profiles.person_id；不新建学生主表

ASKWISE 域 [设计，见 ASKWISE_CANONICAL_MAPPING]
  askwise.learning_session / daily_task / ai_interaction / cognitive_diagnosis / knowledge_state / student_model_snapshot / review / mastery
  → 只引用 person_id；原始 AI 对话不出域

Family OS 授权视图 [设计]
  askwise.growth_summary（ASKWISE 服务写入）、family_os.timeline_view（授权读取）
  → 不复制各域的原始数据

Operations 引用 [设计，外部归属]
  order / contract / package / entitlement 的外部编号 → 只存引用与有效期，不存金额细节
```

**不变量（必须在数据库层成立）：**
1. 一个自然人只有一个权威 `core.people` 记录；学生身份只通过 `core.student_profiles` 体现。
2. 任何 learning / askwise / education 记录的学生引用，都是 `person_id`，且必须存在对应的 `student_profiles`。
3. 同一个学生可以有多个课程报名（learning）和多个 ASKWISE 学习计划（askwise），彼此不互相约束。
4. 升学服务、课程权益、ASKWISE 权益分别判断，没有共用的开关。

## 2. 虚构测试数据

| 编号 | 名称（虚构） | 家庭 | 角色 |
|---|---|---|---|
| S1 | 测试学生甲 | F1 | 学生；有申请、有顾问分配、有监护 |
| S2 | 测试学生乙 | F1 | 学生；F1 的兄弟姐妹，无顾问分配 |
| S3 | 测试学生丙 | F2 | 学生；有申请，监护人为 G2 |
| G1 | 测试监护人甲 | F1 | VERIFIED 监护人（S1、S2 的家长）|
| G2 | 测试监护人乙 | F2 | VERIFIED 监护人（S3 的家长）|
| A1 | 测试顾问甲 | — | 被分配到 S1 的个案（不属于任何家庭）|
| P1 | 测试渠道方甲 | — | 获得对 S3 的渠道授权 |

**两个家庭：** F1（S1、S2、G1）与 F2（S3、G2）。

## 3. 端到端用例

**状态列：** `COVERED` = 已有通过的 F10 断言覆盖（写出文件）；`NEW` = 需要新增测试；`BLOCKED` = 依赖未实现的领域。**本轮没有执行新的 E2E 脚本**，表中的 COVERED 是指已有测试覆盖了同样的规则。

### 3.1 正向

| ID | 场景 | 期望 | 状态 | 依据 |
|---|---|---|---|---|
| E-P1 | G1 以 FAMILY 身份读取 S1 的申请与状态 | 允许 | COVERED | `applications_read` 策略；`f10_family_create_regression` |
| E-P2 | A1 以 ADVISOR 身份读取 S1 的申请（有分配与 EDUCATION_CASE Consent）| 允许 | COVERED | `f10_advisor_pre/post_regression`；T2 |
| E-P3 | S1 本人在 EDUCATION 范围内读取文档（需 DOCUMENT_READ Consent）| 允许 | COVERED | `docs.can_read_document`；`docs_probe` |
| E-P4 | 监护人（VERIFIED，范围 EDUCATION）代授 S1 的 Consent | 允许 | COVERED | D6；`f10_guardian_evidence_regression` |
| E-P5 | S2 购买课程（learning）后，G1 查看 S2 的课程报名摘要 | 允许（有 LEARNING 范围 Consent 时）| BLOCKED | learning 域未实现 |
| E-P6 | S3 的 ASKWISE 诊断服务不可用，同时课程课后反馈仍可写入 | 课程流程成功 | BLOCKED | learning、askwise 未实现 |

### 3.2 负向：跨家庭

| ID | 场景 | 期望 | 状态 | 依据 |
|---|---|---|---|---|
| E-N1 | G2（F2）以 FAMILY 身份读取 S1 的申请 | 拒绝 | COVERED | `families` / `applications_read` 的家庭条件；`f10_cross_family_regression` |
| E-N2 | G2 为 S1 创建 Consent | 拒绝（非本家庭）| COVERED | `consent.actor_can_grant` 的 `person_in_current_family` 条件 |
| E-N3 | P1（渠道方，对 S3 有授权）读取 S1 的文档 | 拒绝 | COVERED | `can_read_subject_basics` 与 `has_active_channel_grant(subject)`；`f10_partner_regression` |
| E-N4 | SERVICE 在 F1 的上下文中创建 F2 的成员关系 | 拒绝 | COVERED | `core.add_family_member` 的家庭检查；`f10_service_regression` |

### 3.3 负向：学生主体错配

| ID | 场景 | 期望 | 状态 | 依据 |
|---|---|---|---|---|
| E-M1 | S2 的主体（principal）以学生身份为 S1 创建申请 | 拒绝（主体不对应 S1）| COVERED（部分）| `education.can_write_application` 的 `actor_can_manage_subject`；需要新增"学生乙对学生甲"的明确用例 |
| E-M2 | 以 S1 的 person_id 签发 FAMILY 票据，但 actor 填 S2 | 拒绝 | COVERED | `auth.validate_context_request` 的 `person_id` 一致性检查（0007 / 0012）|
| E-M3 | 学生档案不存在时为该人创建申请 | 拒绝 | COVERED | 0004 外键 `student_profiles` |

### 3.4 负向：撤销与失效

| ID | 场景 | 期望 | 状态 | 依据 |
|---|---|---|---|---|
| E-R1 | G1 撤回对 A1 的 EDUCATION_CASE Consent，A1 立即读取 S1 申请 | 拒绝（下一次判定）| COVERED | `has_active_consent` 按判定时刻检查；`f10_family_consent_regression` |
| E-R2 | 监护授权（G1 → S1，EDUCATION）被撤销，G1 读取 S1 申请 | 拒绝 | COVERED | `guardian_authorities` 生命周期；`f10_guardian_evidence_regression` |
| E-R3 | 顾问分配被撤销，A1 读取 S1 文档 | 拒绝 | COVERED | T2 `T2_READ_REVOKED`；`f10_v16_contract_gaps` |
| E-R4 | 票据过期后兑换 | 拒绝 | COVERED | `f10_v18` expired ticket |
| E-R5 | 个案 CLOSED 后，A1 写入 S1 申请的官方事实 | 拒绝 | COVERED | V16-F1，`f10_v17_assignment_scope` |
| E-R6 | 个案 CLOSED 后，A1 **读取 S1 的基本展示信息** | 应当拒绝 | **NEW — 已知缺陷**（见下）| `core.can_read_subject_basics` 的顾问分支未检查个案状态 |

**E-R6 的说明（代码审读发现，待复现）：** `core.can_read_subject_basics(person_id)` 的 ADVISOR 分支只检查分配是否有效，不检查 `casework.cases.status`。因此个案关闭后，顾问仍可通过 `people_read` 与 `student_profiles_read` 策略读取学生的基本展示信息（姓名等）。0016 修复的是申请与官方事实的读写，没有覆盖这一路径。这是 V1.9 新发现的 P1 问题，建议作为 0018 的第一项修复，并先写出能复现它的测试。

### 3.5 ASKWISE 不可用

| ID | 场景 | 期望 | 状态 |
|---|---|---|---|
| E-A1 | ASKWISE 服务不可用时，S3 的课程课后反馈仍可提交 | 成功 | BLOCKED（learning 未实现）|
| E-A2 | ASKWISE 的诊断记录缺失时，AI 回答级别请求 | 拒绝 | BLOCKED（askwise 未实现；见 ASKWISE 映射第 3 节）|

## 4. 结论

- 三个虚构学生、两个家庭的 **身份与授权** 规则，在现有实体上可以成立，并且大部分负向用例已由现有 F10 覆盖。
- **一个新发现的 P1 缺陷**（E-R6）必须在进入学习域开发之前修复。
- 学习域与 ASKWISE 域的正向用例、ASKWISE 不可用用例，需要等对应领域实现后才能执行（BLOCKED）。
- 本轮没有执行新的端到端脚本；下一批应先把 E-R6 写成失败用例，再修复。
