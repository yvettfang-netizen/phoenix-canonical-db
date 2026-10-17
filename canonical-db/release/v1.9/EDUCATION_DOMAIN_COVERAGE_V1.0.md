# 学生升学管理领域覆盖审查 V1.0（P1）

**状态分级：** `IMPLEMENTED` / `PARTIAL` / `DESIGN_ONLY` / `MISSING` / `BLOCKED`。没有证据不得填写 IMPLEMENTED。
**证据：** 库存 `CANONICAL_SCHEMA_ACTUAL_INVENTORY_V1.9.md`；Migration 编号；测试名称。

## 1. 字段归属原则

| 归属 | 管理者 | 本次审查结论 |
|---|---|---|
| **Core** | Canonical `core`、`auth`、`consent` | 自然人、家庭、成员关系、学生档案（一对一）、监护授权、登录主体、Consent。唯一的人员主数据是 `core.people` |
| **Education** | Canonical `education`（升学申请领域）| 申请、申请状态、官方事实。学历、成绩、语言考试、目标学校、Offer、签证、入学结果目前均不在库中 |
| **Founder OS / Operations** | 运营与商务（架构文档：`operations` 商务数据 Owner）| 服务套餐、合同、交付、回款。FD-3 规定本期不复用 Founder OS 数据，因此**不进入 Canonical**，只能经引用 |

**需要 Founder 确认（见 `FOUNDER_DECISION_REQUIRED_V1.9` D-4）：**
- 学历、成绩、语言考试：归 Education（Canonical）还是 Founder OS？建议归 Education，因为它们是申请判断的依据，且有 PII 与合规要求。
- 目标学校与专业主数据：归 Education 的独立主数据（建议），而不是申请上的自由文本。
- 服务套餐、合同、回款：归 Operations，Canonical 只保存"套餐引用"与"权益引用"（见 `DOMAIN_ACCESS_AND_ENTITLEMENT_MATRIX`）。

## 2. 覆盖表

| # | 业务需求 | 状态 | 实际实现 | 缺口 | 证据 |
|---|---|---|---|---|---|
| 1 | 学生主档与 Person / Family 关系 | IMPLEMENTED | `core.people`、`core.families`、`core.family_memberships`、`core.student_profiles`（person_id 为主键外键）；经 `core.create_student_profile` 创建；学生档案只能是自然人的一对一档案 | 学生主档的展示字段只有姓名（`core.people.display_name`）；出生日期、性别、学校等未建 | 0003、0009、0013；F10 seed family A/B；`f10_family_create_regression` |
| 2 | 学历 | MISSING | 库中无表 | 学历层次、学校、毕业时间，无结构化记录 | — |
| 3 | 成绩 | MISSING | 库中无表 | 成绩单、科目、分数，无结构化记录 | — |
| 4 | 语言考试 | MISSING | 库中无表 | 考试类型、分数、日期，无结构化记录 | — |
| 5 | 材料档案 | PARTIAL | `docs.documents` 可按 `data_class = EDUCATION` 登记元数据，版本与提交清单均已实现 | 材料类别不是受控词表（`document_kind` 为自由文本）；没有材料清单（DSC DS-5，按决定属数据库外配置）| 0005、0011、0015；`f10_family_create_regression`、`f10_v16_contract_gaps` |
| 6 | 教育规划 | MISSING | 库中无表 | 规划目标、阶段、时间线，无结构化记录 | — |
| 7 | 目标学校 | MISSING | 申请上只有 `institution_label`（自由文本，1–300 字）| 没有院校主数据；无法跨申请统计或去重 | 0004 |
| 8 | 院校及专业申请 | PARTIAL | `education.applications`：家庭、学生、院校标签、项目标签、申请季、状态；学生必须有学生档案（外键）| 院校与项目为文本，无主数据；无申请人身份以外的申请字段 | 0004、0009；`f10_family_create_regression` |
| 9 | 申请状态 | IMPLEMENTED | 状态 DRAFT → READY → SUBMITTED → DECIDED，可在未决定前 WITHDRAWN；每次变化写 `education.application_status_events`；进入 DECIDED 须有 DECISION 官方事实（D-13）| 无后续状态（录取后接受、入学）— 见 E-7 | 0004、0011、0012；`f10_d6_advisor_final`、G1 |
| 10 | Offer | MISSING | 库中无表 | Offer 条件、院校决定、接受与否，无结构化记录；只能用官方事实（DECISION）的文本间接表示 | — |
| 11 | 签证 | MISSING | 库中无表 | 签证类型、申请、结果，无记录 | — |
| 12 | 入学结果 | MISSING | 库中无表 | 入学日期、学校、注册，无记录 | — |
| 13 | 顾问分配 | IMPLEMENTED | `casework.cases`（OPEN / PAUSED / CLOSED，可引用申请）、`casework.advisor_assignments`（有效期、生命周期、撤销）；建立与撤销经 SERVICE 管理接口 | — | 0004、0007、0013、0016；`f10_v17_assignment_scope`、T2 |
| 14 | 文案人员分配 | MISSING | `principal_kind` 只有 FAMILY、ADVISOR、CHANNEL、SERVICE；文案无专门类型 | 需要决定：文案是 ADVISOR 的子角色，还是 CHANNEL？（D-4）| 0003 |
| 15 | 服务套餐 | MISSING（Operations 归属）| 库中无表 | 套餐定义属于 Operations，Canonical 只需要引用 | — |
| 16 | 合同 | MISSING（Operations 归属）| 库中无表 | 同上 | — |
| 17 | 交付 | MISSING（Operations 归属）| 库中无表 | 交付记录属于 Operations | — |
| 18 | 回款引用 | MISSING（Operations 归属）| 库中无表 | 只需要引用字段（外部订单号、权益号）；需先定义引用契约 | — |
| 19 | 家长授权 | IMPLEMENTED | 监护授权 `core.guardian_authorities`（VERIFIED、范围 EDUCATION、有效期、撤销）+ Consent `consent.grants`（用途 EDUCATION_CASE，数据类别 EDUCATION）| — | 0003、0011、0013；`f10_guardian_evidence_regression`、D6 |
| 20 | 学生进度查询 | PARTIAL | 家庭成员通过 RLS 能读取本家庭的申请与状态（`education.applications` 策略）| 没有"进度视图"实体，也没有面向家长的摘要接口 | 0004、0006 |

## 3. 教育领域缺口汇总

| 编号 | 缺口 | 建议 | 依赖 |
|---|---|---|---|
| E-1 | 学历、成绩、语言考试三类结构化记录缺失 | 新增 `education` 下的 profile 表，以 `student_person_id` 引用 `core.student_profiles` | D-4 归属决定 |
| E-2 | 院校、项目无主数据 | 新增院校与专业主数据表（受控词表 + 版本），申请引用主数据 ID；保留原文本作为展示 | 主数据来源（需要 Founder 提供或授权）|
| E-3 | 目标学校与规划缺失 | 新增规划表与目标学校关联表 | E-2 |
| E-4 | Offer、签证、入学结果缺失 | 扩展官方事实的种类（OFFER、VISA、ENROLLMENT）或新增结果表；保留"官方事实必须有来源"的规则 | 业务规则确认 |
| E-5 | 文案角色未定 | 决定角色类型（D-4）| Founder |
| E-6 | 服务套餐、合同、回款只能是引用 | 定义 Operations 与 Canonical 之间的引用契约（只存外部 ID 与权益号，不存金额细节）| Operations 契约 |
| E-7 | 申请无录取后状态 | 由领域负责人提出状态扩展（与 E-4 一起）| 领域负责人 |
| E-8 | 学生进度视图缺失 | 设计 Family OS 授权视图（见 `DOMAIN_ACCESS_AND_ENTITLEMENT_MATRIX`），而不是复制申请数据 | D-7 |

## 4. 结论

- **已实现：** 学生主档与家庭关系、申请与状态、官方事实门禁、顾问分配、家长授权、材料元数据、版本与提交清单。
- **未实现：** 学历、成绩、语言考试、目标学校主数据、规划、Offer、签证、入学结果，以及文案角色。
- **属于 Operations：** 套餐、合同、交付、回款，Canonical 只保存引用。
- **与本次审查相关的风险：** 申请上的院校与项目是自由文本，如果现在导入真实数据，会产生无法合并的重复院校。这一点应在导入前解决（E-2）。
