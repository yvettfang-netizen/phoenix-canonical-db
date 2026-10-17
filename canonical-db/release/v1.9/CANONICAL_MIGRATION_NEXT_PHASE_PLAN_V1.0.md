# Canonical 下一阶段 Migration 路线 V1.0（P6，设计，不执行）

**本文件只做设计。** 不新增、不执行 0018 或之后的任何 Migration。每一批开工前都必须通过 `FOUNDER_DECISION_REQUIRED_V1.9` 中对应的决定。
**依据：** `CANONICAL_SCHEMA_ACTUAL_INVENTORY_V1.9.md`（实际 27 张表）、`DOMAIN_ACCESS_AND_ENTITLEMENT_MATRIX_V1.0.md`、`UNIFIED_STUDENT_ERD_V1.0.md`、三份领域覆盖文档。
**命名：** 候选分域 `core`、`education`、`learning`、`askwise`、`family_os` 是任务书给出的候选，**已与现有 schema 核对**：`core`、`education`、`identity`、`casework`、`docs`、`consent`、`integration`、`auth`、`audit` 已存在；`learning`、`askwise`、`family_os`、`operations_ref` 是新增的。

## 1. 总体顺序与依赖

```
0018 安全与契约修复（无新领域）
  └─ 0019 教育主数据与档案（education 扩展）
       └─ 0020 权益引用（operations_ref，供 education / learning / askwise 判断）
            └─ 0021 学习核心（learning：课程、报名、班级、作业、反馈）
                 └─ 0022 ASKWISE 域（askwise：会话、诊断、知识状态、学生模型）
                      └─ 0023 Family OS 授权视图（family_os：成长摘要、时间线）
```

**依赖的外部决定：**

| 批次 | 必须先有的决定 |
|---|---|
| 0018 | D-1（属主模型）、D-2（bind_context）、E-R6 的修复方式确认 |
| 0019 | D-4（学历、成绩、语言考试归属；文案角色）、主数据来源（E-2）|
| 0020 | D-8（Operations 引用契约）|
| 0021 | D-3（启明堂设计文档）、D-5（学习敏感数据 Consent 用途与教师主体类型）|
| 0022 | D-3（ASKWISE Data Architecture V1.0 与 Student Model V1.0）、D-6（ASKWISE 身份方式）、错因词表（K1–K7、P1–P5 的定义）|
| 0023 | D-7（Family OS 可见的成长摘要范围）|

## 2. 0018 · 安全与契约修复

**目标：** 修复已知缺陷，不增加业务领域。

| 项 | 内容 |
|---|---|
| E-R6 | `core.can_read_subject_basics` 的顾问分支增加 `c.status IN ('OPEN','PAUSED')` 检查；同时审查 `casework.cases` 读取策略（`is_current_advisor_for_case`）是否需要同样的检查，并作出决定 |
| S-2 | 撤销 binder 对 `auth.bind_context` 的执行权（只保留票据流程）|
| 属主模型（若 D-1 批准）| 创建属主角色（在 install.sh 中）、转移属主、授予 pg_read_all_stats（若接受 R-1）|
| 恢复 | 调整 restore.sh / restore_drill.sh（D-1b）|
| 审计 | 在合同中写明"RLS 过滤的读取不产生审计行" |

**字段字典：** 无新表。
**索引：** 无新索引。
**权限矩阵：** 顾问读取学生基本信息：有效分配 **且** 个案 OPEN / PAUSED。binder：只执行票据函数与解析函数。
**测试（先失败后通过）：**
- E-R6：个案关闭后顾问读取学生基本信息被拒（新增，先失败）；
- 个案 OPEN 时允许（正例）；
- binder 执行 `auth.bind_context` 被拒（新增）；
- 属主模型：F10 完整回归（PG16 / PG17），全新集群恢复，属主检查。
**回滚：** 前向修复。属主变更可通过 `ALTER ... OWNER TO phoenix_bootstrap` 逆转；最终可从备份恢复（`08` 情形 C）。

## 3. 0019 · 教育主数据与档案

**目标：** 补齐学生升学所需的结构化记录，并建立院校与专业的主数据，避免自由文本重复。

| 表（候选）| 关键字段 | 说明 |
|---|---|---|
| `education.institution` | id（uuidv7）、name、country、status、version | 院校主数据，受控；名称变更须新版本 |
| `education.program` | id、institution_id → institution、name、level、status | 专业主数据 |
| `education.academic_record` | id、student_person_id → student_profiles、level、school_name、graduation_date、evidence_document_id（可空）| 学历；证据引用 `docs.documents` |
| `education.score_record` | id、student_person_id、subject、score、exam_date、source | 成绩；只追加 |
| `education.language_test` | id、student_person_id、test_kind、score_json、test_date、evidence_document_id | 语言考试 |
| `education.plan` | id、student_person_id、goal_text、status、created_by_principal_id | 教育规划 |
| `education.plan_target` | plan_id → plan、institution_id、program_id | 目标学校 |

**对现有表的修改（非破坏）：**
- `education.applications` 增加可空的 `institution_id`、`program_id`（引用主数据）；保留 `institution_label`、`program_label` 作为展示。迁移时不回填真实数据（当前为空）。
- `docs.documents` 的材料类别改为受控词表（新增外键到 `docs.document_kind`，或在应用层约束）。

**字段决定依赖：** 学历、成绩、语言考试是否属于 Education（D-4）。

**索引：**
- `academic_record(student_person_id)`、`score_record(student_person_id, exam_date)`、`plan(student_person_id)`、`plan_target(plan_id)`；
- `program(institution_id)`；
- 唯一：`institution(name, country, version)`。

**权限矩阵：**
- 学生本人、有 EDUCATION 范围监护的家长：读取；写入：经函数（学生本人或监护）；
- 有分配的顾问：读取；写入经函数（有分配 + Consent）；
- 主数据（院校、专业）：所有已登录主体可读；写入只经 SERVICE（需要两人复核，因为会影响多个申请）。

**测试：**
- 跨家庭读取被拒；
- 监护范围 EDUCATION 才可读学历；GENERAL 不覆盖；
- 主数据版本只追加；
- 申请引用不存在的院校被拒；
- 学历证据引用必须指向同一学生的文档。

**回滚：** 新表可删除（空表阶段）；申请的新列可删除。真实数据阶段须先回滚到备份。

## 4. 0020 · 权益引用

| 表（候选）| 关键字段 | 说明 |
|---|---|---|
| `operations_ref.entitlement_ref` | id、external_entitlement_id（外部编号）、product_kind（EDUCATION_SERVICE / COURSE / ASKWISE）、subject_person_id、family_id、course_id（可空）、valid_from、valid_until、status | 只存引用与有效期，不存金额 |

**函数：** `operations_ref.has_valid_entitlement(subject, product_kind, course_id)`，SECURITY DEFINER，只读。

**依赖：** D-8（Operations 引用契约：外部编号格式、来源系统、撤销通知方式）。

**索引：** `(subject_person_id, product_kind)`、`(external_entitlement_id)` 唯一。

**权限：** 写入只经 SERVICE（来源：Operations 同步）；读取：本人与同家庭监护（只读自己的引用）；判断函数对 app 开放。

**测试：**
- 权益缺失或过期 → 申请写入被拒（`ENTITLEMENT_MISSING`，待定义的原因代码）；
- 课程权益不开放 ASKWISE（三种权益互相独立）；
- 撤销引用后下一次判断即失效。

**回滚：** 空表阶段可删除。

## 5. 0021 · 学习核心（启明堂）

**前提：** 启明堂设计文档到位（D-3）；学习敏感数据 Consent 用途（D-5）；教师主体类型（D-5）。

| 表（候选）| 关键字段 |
|---|---|
| `learning.course` | id、title、status、created_at（不含学生数据）|
| `learning.course_version` | id、course_id、version_no、effective_from（只追加）|
| `learning.module` / `learning.lesson` | 课程结构；与版本关联 |
| `learning.enrollment` | id、student_person_id → student_profiles、course_version_id、entitlement_ref_id → operations_ref、status |
| `learning.teacher_assignment` | id、teacher_principal_id、class_id、valid_from、valid_until、revoked_at（类似顾问分配）|
| `learning.class` / `learning.schedule` | 班级、排课 |
| `learning.attendance` | enrollment_id、session_id、status、recorded_by_principal_id |
| `learning.homework` / `learning.submission` | 作业；提交引用 `docs.documents`（data_class `LEARNING`，需新增）|
| `learning.feedback` | lesson_id、student_person_id、teacher_principal_id、body（**课后反馈是独立于 ASKWISE 的**）|

**索引：** `enrollment(student_person_id, course_version_id)` 唯一（同一学生同一版本只报一次）；`teacher_assignment(teacher_principal_id)`；`attendance(enrollment_id)`；`feedback(student_person_id, created_at)`。

**权限矩阵（见访问矩阵）：**
- 学生：本人的报名、作业、反馈、出勤；
- 教师：被分配班级的学生数据（不含其他班级，不含未授权的学习敏感数据）；
- 家长：经学习 Consent（LEARNING_RECORD）授权的摘要；
- 购买课程本身不授予任何学习敏感数据访问（D-5）。

**测试（必须包括）：**
- E-P5（购买后家长读取报名摘要）：有 Consent 时允许，无 Consent 时拒绝；
- E-P6（ASKWISE 不可用，课程与课后反馈照常）：本批次应包含一个"ASKWISE schema 不存在时仍可运行"的测试（通过在测试库中不装 0022 来实现）；
- 教师跨班级读取被拒；
- 课程版本只追加。

**回滚：** 空表阶段可删除；真实数据前须有备份。

## 6. 0022 · ASKWISE 域

**前提：** ASKWISE Data Architecture V1.0 与 Student Model V1.0 的正式文本（D-3）；身份方式（D-6）；错因词表（K1–K7、P1–P5）的定义与管理人。

| 表（候选）| 关键字段 | 约束 |
|---|---|---|
| `askwise.student_link` | person_id → core.student_profiles（主键）、askwise_internal_id（ASKWISE 本地派生键）、synced_at | 唯一身份引用；不存姓名等属性 |
| `askwise.learning_session` | id、student_person_id、started_at、ended_at、source_learning_course_id（可空，**不强制外键到 learning**）| 不依赖课程存在 |
| `askwise.daily_task` | id、session_id、subject_code、status | — |
| `askwise.submission` / `askwise.submission_attachment` | 作业与附件；附件引用 `docs.documents` | 附件版本由 docs 管理 |
| `askwise.ai_interaction` | id、task_id、role、hint_level（1–4 逐级）、content_ref（**原始内容不出域**）| 写入前须存在 `cognitive_diagnosis`（"先诊断后回答"）|
| `askwise.cognitive_diagnosis` | id、task_id、diagnosed_at、error_code（受控）、first_step_ms | 只追加 |
| `askwise.error_code` | code（K1–K7 / P1–P5）、domain（MATH / POLITICS）、definition_version | 受控词表，版本化 |
| `askwise.first_step_observation` | task_id、elapsed_ms、observed_at | 只追加 |
| `askwise.knowledge_state` | student_person_id、topic_code、level（L0–L5）、observed_at | 只追加；当前状态取最新 |
| `askwise.student_model_snapshot` | id、student_person_id、snapshot_json、created_at | 只追加 |
| `askwise.review_schedule` / `askwise.mastery_event` | 复习计划与掌握度变化 | 只追加 |

**"先诊断后回答"的执行位置：** 写入函数 `askwise.record_ai_interaction`，内部检查同一任务存在诊断记录，并且提示级别只能逐级提升；失败写审计。

**索引：** `learning_session(student_person_id, started_at)`；`cognitive_diagnosis(task_id)`；`knowledge_state(student_person_id, topic_code, observed_at desc)`；`student_model_snapshot(student_person_id, created_at)`。

**权限矩阵：**
- ASKWISE 服务（新登录主体类型，需 D-6）：读写 `askwise` 域，经函数；
- 学生本人：读取本人的会话、任务、诊断摘要（不含他人）；
- 家长：只通过 0023 的授权视图，不直接读取 `askwise` 表；
- Family OS：不得直接读取 `askwise` 表。

**测试：**
- "先诊断后回答"：无诊断时写入回答被拒；提示跳级被拒；
- 原始对话不可被家长直接读取；
- ASKWISE 表删除（或未安装）时，`learning` 的课程流程不受影响；
- K / P 错因代码不在词表中被拒。

**回滚：** 空表阶段可删除；真实数据前须有备份。

## 7. 0023 · Family OS 授权视图

| 对象（候选）| 说明 |
|---|---|
| `askwise.growth_summary` | ASKWISE 服务写入的摘要（只追加；字段由 D-7 决定）|
| `family_os.timeline_view` | 只读视图：聚合授权范围内的事件（来源：education 状态、learning 出勤与反馈摘要、growth_summary）|
| Consent 用途 `GROWTH_SUMMARY`（新增）| 与学习 Consent 分开 |

**规则：**
- Family OS 不复制各域的原始数据；
- Consent 撤回后，视图在下一次查询时不再返回对应内容；
- 视图不暴露原始对话与诊断明细。

**测试：** 撤回后视图为空；跨家庭为空；视图列不包含原始内容字段。

**回滚：** 删除视图与摘要表（空表阶段）。

## 8. 通用验收标准（每一批都必须满足）

1. PG16 与 PG17 的完整 F10 回归通过，无意外失败；
2. 新增的正向与负向测试先以失败形式写入，再修复通过；
3. 从上一批的备份恢复到全新集群后，账本、表数、策略数与预期一致；
4. 迁移哈希与执行顺序检查通过；历史迁移未改动；
5. 新表全部开启 RLS（或明确为"只经函数"并在矩阵中注明）；
6. 新函数为 SECURITY DEFINER、固定 `search_path`、PUBLIC 无执行权；
7. 更新 `CANONICAL_SCHEMA_ACTUAL_INVENTORY`、访问矩阵与风险登记；
8. 不连接腾讯，不推送，不使用真实数据。

## 9. 不在本路线内

- 真实数据迁移（FD-4 / 另立项）；
- 对象存储与物理清除（EV-6、F-08）；
- 双人复核的实现（真实数据前设计）；
- 时间点恢复（PITR），需在导入真实数据前决定（FD-7）。
