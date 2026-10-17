# 启明堂 Learning 域 ERD V2.0（设计）

**状态：** 设计，未实现。所有 `learning.*` 表在开发库中都不存在（已核实）。
**来源：** 启明堂 Freeze 与 Family OS 接驳页本轮 ACCESS BLOCKED（见 `../v1.9/NOTION_SOURCE_VERIFICATION_R1.md`）。依赖这些来源的业务规则标记为 PROPOSED；需要 Founder 决定的规则列在 `LEARNING_MIGRATION_PLAN_V2.0.md` 第 6 节。
**权威基础：** Canonical 的 `core.people`、`core.student_profiles`、家庭与监护、`consent.grants`、`auth.principals`、`audit.access_events` 与 RLS。不设第二套学生主档。
**权益：** Canonical 库中不存在权益判断。权益以外部引用形式进入（`learning.external_entitlement_ref`），由 0020（权益引用批次）提供；本设计不假设权益表已存在。

## 1. 六个模块

| 模块 | 实体 | 依赖 |
|---|---|---|
| M1 课程目录 | course、course_version | 无 |
| M2 报名 | external_entitlement_ref、enrollment、enrollment_status_event | core.student_profiles；0020 |
| M3 教师与分配 | teacher、teacher_assignment | core.people；TEACHER 主体（D-5，未批准）|
| M4 排课与班级 | class、enrollment_class、schedule_slot | M1、M2、M3 |
| M5 考勤与课后卡片 | attendance_record、attendance_correction、after_class_card | M4 |
| M6 发布与阶段报告 | publication、stage_report | M5 |

另有一组跨域引用：askwise_session_link（只存外部会话引用，见第 4 节），不属于六个模块。

## 2. 关系图（文字）

```
core.people 1──1 core.student_profiles (person_id)
                       │ student_person_id
external_entitlement_ref ──< enrollment >── course_version >── course
                               │
                               ├──< enrollment_status_event
                               ├──< enrollment_class >── class ──< schedule_slot
                               │                          │   teacher_person_id ──> teacher ──> core.people
                               │                          └──< teacher_assignment (class_id, teacher_person_id)
                               ├──< attendance_record (slot_id, enrollment_id) ──< attendance_correction
                               ├──< after_class_card (slot_id, enrollment_id) ──< publication (card_id)
                               ├──< stage_report
                               └──< askwise_session_link （外部引用，无外键到 askwise schema）
```

## 3. 关键约束（设计）

| 编号 | 约束 | 实现方式（设计）|
|---|---|---|
| L-K1 | 学生引用只能是 student_person_id，且必须存在对应的 core.student_profiles | 外键到 core.student_profiles(person_id) |
| L-K2 | 同一学生在同一课程版本下，只能有一个有效报名 | 部分唯一索引，status 为 PENDING、ACTIVE 或 SUSPENDED |
| L-K3 | 报名必须引用有效的外部权益；权益只存引用与有效期 | 外键到 external_entitlement_ref；有效期在写入函数中检查 |
| L-K4 | 权益不授予学习敏感数据访问；访问需要 LEARNING_RECORD Consent | 读取策略只看 Consent（见权限矩阵）|
| L-K5 | 教师只能对当前有效分配的班级写入考勤与卡片 | 写入函数检查 teacher_assignment 的 ACTIVE 与有效期 |
| L-K6 | 每个时段每个报名最多一条考勤 | 唯一 (slot_id, enrollment_id) |
| L-K7 | 考勤更正是追加记录，不修改原记录 | attendance_correction 只插入 |
| L-K8 | 卡片只有在 PUBLISHED 后才对家长可见 | 家长端读取条件包含 status = PUBLISHED |
| L-K9 | 撤回发布不删除卡片，只改状态 | publication.status 改为 RETRACTED |
| L-K10 | 所有 family_id 与报名的 family_id 一致 | 复合外键 (enrollment_id, family_id) |
| L-K11 | 学习表不引用 askwise schema | 只存 askwise_session_ref 文本；0022 未安装时学习表仍能运行（E-P6）|

## 4. ASKWISE 会话关联与成长摘要接口

- 会话关联：learning.askwise_session_link 只保存 ASKWISE 的会话引用（文本）、报名 ID、关联时间与关联的服务主体。不保存对话内容、诊断、错因或知识状态。
- 成长摘要：askwise.growth_summary 属于 ASKWISE，由 ASKWISE 服务写入。Canonical 与 Learning 不复制它。Family OS 通过授权接口读取，接口在调用时检查 Canonical 的身份与 LEARNING_RECORD Consent（见端到端契约第 5 节）。
- 不变量：学习域任何表都不得包含 ASKWISE 原始对话、诊断明细或题目级错因。

## 5. 与现有实体的关系（核实）

| 现有实体（已实现）| 学习域的使用方式 |
|---|---|
| core.student_profiles | 报名与考勤的学生引用（L-K1）|
| core.people | 教师身份（teacher.teacher_person_id）|
| core.family_memberships、core.guardian_authorities | 家长读取的前提。监护范围需新增 LEARNING（当前 CHECK 只有 GENERAL、EDUCATION、IDENTITY）|
| consent.grants | 需新增用途 LEARNING_RECORD 与数据类别 LEARNING（当前 purpose CHECK 只有 DOCUMENT_READ、EDUCATION_CASE、IDENTITY_CASE）|
| auth.principals | 需新增 TEACHER、SUPERVISOR 主体类型（当前 principal_kind CHECK 只有 FAMILY、ADVISOR、CHANNEL、SERVICE）|
| audit.access_events | 学习域所有写入与拒绝都经审计函数记录，沿用 audit.record_write_decision 模式 |
| integration.legacy_id_mappings | 学习域不使用外部 ID 映射；学生引用只用 Canonical ID |

## 6. 不在本设计内

- 权益判断函数（属于 0020）。
- 教师登录与认证方式（TEACHER 主体的签发方式另行设计，见权限矩阵第 2 节）。
- 启明堂 Freeze 的 Learn 域边界：来源 BLOCKED，本设计中所有边界都标记为 PROPOSED。
