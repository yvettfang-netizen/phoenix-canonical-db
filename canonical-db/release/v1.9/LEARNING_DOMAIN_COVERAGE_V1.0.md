# 启明堂线上学习与课程交付领域覆盖审查 V1.0（P2）

**产品名称：** 启明堂。旧称凤启学苑、Phoenix Academy，只作为历史代码与历史证据引用。
**状态分级：** `IMPLEMENTED` / `PARTIAL` / `DESIGN_ONLY` / `MISSING` / `BLOCKED`。

## 0. 来源核实（先决条件）

| 检索范围 | 结果 |
|---|---|
| 主仓库 `phoenix`（全部文件类型，排除依赖与缓存）| "启明堂"、"九灵兽"、"凤启学苑" 均未命中 |
| `D:\CODEX` 全树（超时前）| 同上；全树检索有超时，结论为"仓库内未找到"，不是"全盘确认不存在" |
| 唯一命中 | `docs/architecture/four-portals-v1.1/FEISHU_OPERATING_MODEL_V0.5_CLEAN_MASTER_SOURCE.md` 第 210 行：`Default Service Owner | Phoenix Academy`（作为服务负责人，属历史表述）|

**结论：启明堂的产品设计文档在本次审查可访问的范围内不存在。** 课程、班级、排课、考勤、作业、课后反馈等领域的需求没有可引用的正式来源。本文件的所有状态判断仅针对数据库，不代表产品设计已经完成。

**需要 Founder 提供（见 `FOUNDER_DECISION_REQUIRED_V1.9` D-3）：** 启明堂正式产品设计文档，以及课程与教学交付的数据字典或原型。

## 1. 覆盖表

| # | 需求 | 状态 | 数据库实际情况 | 与现有 Canonical 的关系 | 缺口 |
|---|---|---|---|---|---|
| 1 | Course / Course Version | MISSING | 库中无表 | 课程与版本应为启明堂 `learning` 域；不属于 Core | 全部 |
| 2 | Module / Lesson | MISSING | 无表 | 同上 | 全部 |
| 3 | Enrollment（学生报课）| MISSING | 无表 | 应引用 `core.student_profiles.person_id`，不得新建学生主档 | 全部 |
| 4 | Tutor / Teacher Assignment | MISSING | 无表；教师没有登录主体类型（`principal_kind` 无 TEACHER）| 教师需要登录主体与分配关系，类似 `casework.advisor_assignments`；类型决定需要 Founder（D-5）| 全部 |
| 5 | Class / Schedule | MISSING | 无表 | 班级与排课 | 全部 |
| 6 | Attendance | MISSING | 无表 | 出勤属于学习数据敏感度 | 全部 |
| 7 | Homework / Submission | MISSING | 无表。Canonical 的 `docs.submission_manifests` 是**申请材料**提交，不能复用为作业提交 | 作业提交应有独立的 learning 域表；附件可复用 `docs.documents` 的元数据模式，但需要单独的数据类别 | 全部 |
| 8 | Lesson Feedback / After-class Card | MISSING | 无表 | 课后反馈是教师写给学生与家长的内容，需要可见性规则 | 全部 |
| 9 | Progress Report | MISSING | 无表 | 进度报告与 ASKWISE 的成长摘要存在边界问题，见 `ASKWISE_CANONICAL_MAPPING` | 全部 |
| 10 | Learning Entitlement（学习权益）| MISSING | 无表 | 权益与购买记录属于 Operations；学习权益只能引用权益号，不得自动获得学生敏感学习数据访问权（任务书要求）| 全部 |

## 2. 三端权限与数据范围（设计要求，当前未实现）

| 角色 | 允许 | 不允许 | 当前实现 |
|---|---|---|---|
| 学生本人 | 自己的课程、作业、反馈、进度 | 他人数据 | 无学习表，无法实现 |
| 家长（有 VERIFIED 监护与 EDUCATION 范围）| 授权范围内的学习摘要 | 原始 AI 对话、认知诊断细节（属 ASKWISE 域）| 监护授权与 Consent 已存在，学习数据无表 |
| 教师 | 被分配班级或学生的作业与反馈 | 未分配的学生；家庭的非学习数据 | 无教师主体类型，无分配表 |
| 顾问 | 通过个案分配可见的教育申请 | 学习数据（除非明确授权）| 个案分配已实现，学习数据无表 |

## 3. 必须遵守的边界

1. **不建第二套学生身份主表。** 启明堂的学生只能是 `core.student_profiles` 的引用（person_id）。
2. **购买课程不自动授予学习敏感数据访问权。** 需要单独的 Consent（建议用途 `LEARNING_RECORD`，数据类别 `LEARNING`，新增）。该规则需要 Founder 确认（D-5）。
3. **学习权益与合同分离。** 权益号由 Operations 签发，启明堂只保存"权益引用 + 有效期"，判定时检查引用是否有效。
4. **ASKWISE 不可用时，课程与课后反馈流程仍须运行。** 因此课程域不能依赖 ASKWISE 表（外键方向：ASKWISE 引用启明堂，不反过来）。
5. **Family OS 不复制启明堂的完整原始数据**，只接收经授权的摘要（见 `DOMAIN_ACCESS_AND_ENTITLEMENT_MATRIX`）。

## 4. 结论

- 启明堂在数据库中**全部为 MISSING**，没有任何已实现的表、函数或测试。
- 产品设计来源在本审查范围内**不存在**，因此在提供来源前，启明堂的 Migration 设计**不得开始**（BLOCKED）。
- 现有 Canonical 可以提供的基础：学生档案、家庭、监护与 Consent、顾问分配、权益引用的模式（将来）。这些是复用点，而不是已实现的学习能力。
- 建议的开发顺序见 `CANONICAL_MIGRATION_NEXT_PHASE_PLAN_V1.0`：来源到位后，先做 Course / Enrollment / Teacher Assignment，再做作业与反馈，最后做进度报告。

## R1 更正（2026-10-17）

- 原文"启明堂产品设计未找到"（来源缺失）**已更正**：Notion 中存在启明堂 Founder Decision Freeze 页面（`3d8c31ee15bb81808f88c8340de41b09`），上一会话已读取。
- 本轮该页 **ACCESS BLOCKED**（连接器 404，浏览器空白）。因此学习域的任何规则都不能标记为 VERIFIED。
- 所有依赖该页的学习规则，现在标记为 PROPOSED。见 `NOTION_SOURCE_VERIFICATION_R1.md` 与 `../learning-v2.0/`。
- 上文"未找到"的判断来自主仓库检索，它不代表 Notion 中不存在。
