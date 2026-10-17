# 启明堂 Learning 字段字典 V2.0（设计）

**约定（与现有 Canonical 一致）：**
- 主键为 UUIDv7，以 core.is_uuid_v7(...) 做 CHECK。
- 时间戳为 timestamptz，默认 transaction_timestamp()。
- family_id 出现在每张含学生数据的表上，并通过复合外键与报名保持一致（L-K10）。
- 状态字段使用 text 加 CHECK，不使用数据库枚举类型（与现有迁移一致）。
- 不存储金额。权益与订单只保存外部编号与有效期。
- 标注含义：PK 主键，FK 外键，UQ 唯一，IX 索引，NN 非空，CK 检查。

## 1. M1 课程目录

### learning.course
| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| course_id | uuid | PK，CK uuid7 | |
| course_code | text | UQ，NN，CK 长度 1–60 | 课程编码 |
| title | text | NN，CK 长度 1–300 | 展示名（禁用品牌名规则待核对，见 Freeze）|
| status | text | NN，CK 取值 DRAFT / PUBLISHED / ARCHIVED | |
| created_at | timestamptz | NN，默认 | |

### learning.course_version
| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| course_version_id | uuid | PK，CK uuid7 | |
| course_id | uuid | NN，FK 到 course | |
| version_no | integer | NN，CK ≥ 1，UQ (course_id, version_no) | |
| effective_from | timestamptz | NN | |
| effective_until | timestamptz | 可空，CK 大于 effective_from | |
| status | text | NN，CK 取值 DRAFT / ACTIVE / RETIRED | |
| IX | | (course_id, status) | |

状态机：course 为 DRAFT → PUBLISHED → ARCHIVED；course_version 为 DRAFT → ACTIVE → RETIRED。已有报名的版本不得删除，只能 RETIRED。

## 2. M2 报名与权益引用

### learning.external_entitlement_ref
| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| entitlement_ref_id | uuid | PK，CK uuid7 | |
| external_entitlement_no | text | UQ，NN，CK 长度 1–100 | Operations 的权益号 |
| external_order_no | text | NN，CK 长度 1–100 | Operations 的订单号 |
| product_kind | text | NN，CK 取值 COURSE | 本表只服务课程；升学与 ASKWISE 权益另在 0020 设计 |
| course_id | uuid | NN，FK 到 course | |
| student_person_id | uuid | NN，FK 到 core.student_profiles(person_id) | |
| family_id | uuid | NN，FK 到 core.families | |
| valid_from | timestamptz | NN | |
| valid_until | timestamptz | NN，CK 大于 valid_from | |
| status | text | NN，CK 取值 ACTIVE / REVOKED / EXPIRED | 由 Operations 通知驱动（D-8）|
| recorded_at | timestamptz | NN | |
| UQ | (entitlement_ref_id, family_id, student_person_id) | | 供复合外键使用 |
| IX | (student_person_id, course_id, status) | | |

状态机：ACTIVE 到 REVOKED；ACTIVE 到 EXPIRED（由 valid_until 驱动）。不得从 REVOKED 或 EXPIRED 回到 ACTIVE；续期必须是新的权益号。

### learning.enrollment
| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| enrollment_id | uuid | PK，CK uuid7 | |
| family_id | uuid | NN，FK 到 core.families | |
| student_person_id | uuid | NN，FK 到 core.student_profiles(person_id) | |
| course_version_id | uuid | NN，FK 到 course_version | |
| entitlement_ref_id | uuid | NN，复合 FK (entitlement_ref_id, family_id, student_person_id) | 保证权益属于同一家庭与学生（L-K10）|
| status | text | NN，CK 取值 PENDING / ACTIVE / SUSPENDED / COMPLETED / WITHDRAWN | |
| created_by_principal_id | uuid | NN，FK 到 auth.principals | |
| created_at | timestamptz | NN | |
| UQ（部分）| (student_person_id, course_version_id) 仅当 status 为 PENDING、ACTIVE 或 SUSPENDED | | L-K2 |

状态机：PENDING 到 ACTIVE（权益有效且 Consent 已就绪）；ACTIVE 与 SUSPENDED 互转；ACTIVE 到 COMPLETED；PENDING、ACTIVE、SUSPENDED 到 WITHDRAWN。COMPLETED 与 WITHDRAWN 为终态。

### learning.enrollment_status_event
| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| event_id | uuid | PK，CK uuid7 | |
| enrollment_id | uuid | NN，FK 到 enrollment | |
| from_status | text | 可空 | |
| to_status | text | NN | |
| reason_code | text | NN，CK 长度 1–60 | 原因代码，不含个人信息 |
| actor_principal_id | uuid | NN，FK 到 auth.principals | |
| occurred_at | timestamptz | NN | |
| IX | (enrollment_id, occurred_at) | | |

## 3. M3 教师与分配

### learning.teacher
| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| teacher_person_id | uuid | PK，FK 到 core.people | 教师是 Canonical 的自然人 |
| status | text | NN，CK 取值 ACTIVE / INACTIVE | |
| created_at | timestamptz | NN | |

说明：教师的登录主体（TEACHER）需要 D-5 批准，并修改 auth.principals.principal_kind 的 CHECK。在批准之前，本表只是设计。

### learning.teacher_assignment
| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| assignment_id | uuid | PK，CK uuid7 | |
| class_id | uuid | NN，FK 到 class | |
| teacher_person_id | uuid | NN，FK 到 teacher | |
| role | text | NN，CK 取值 LEAD / ASSISTANT | |
| valid_from | timestamptz | NN | |
| valid_until | timestamptz | NN，CK 大于 valid_from | |
| status | text | NN，CK 取值 ACTIVE / ENDED / REVOKED | |
| revoked_at | timestamptz | 可空 | |
| UQ（部分）| (class_id) 仅当 role 为 LEAD 且 status 为 ACTIVE | | 每班最多一位主教 |
| UQ（部分）| (class_id, teacher_person_id) 仅当 status 为 ACTIVE | | 同一教师同一班只能有一条有效分配 |
| IX | (teacher_person_id, status, valid_until) | | 读取策略使用 |

状态机：ACTIVE 到 ENDED（到期或班级结束）；ACTIVE 到 REVOKED（撤销，记录 revoked_at）。终态。

## 4. M4 排课与班级

### learning.class
| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| class_id | uuid | PK，CK uuid7 | |
| course_version_id | uuid | NN，FK 到 course_version | |
| class_code | text | UQ，NN，CK 长度 1–60 | |
| capacity | integer | NN，CK 1–200 | |
| status | text | NN，CK 取值 PLANNED / OPEN / RUNNING / CLOSED | |
| starts_on | date | NN | |
| ends_on | date | NN，CK 不早于 starts_on | |

状态机：PLANNED 到 OPEN 到 RUNNING 到 CLOSED。CLOSED 为终态。

### learning.enrollment_class
| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| enrollment_id | uuid | PK（复合），FK 到 enrollment | |
| class_id | uuid | PK（复合），FK 到 class | |
| family_id | uuid | NN，与 enrollment 一致（复合 FK）| |
| status | text | NN，CK 取值 ACTIVE / DROPPED | |
| joined_at | timestamptz | 可空 | |
| left_at | timestamptz | 可空 | |
| IX | (class_id, status) | | 教师读取名单使用 |

约束：报名的课程版本必须与班级的课程版本一致；容量上限由写入函数检查（外键无法表达，不用触发器以外的方式绕过）。

### learning.schedule_slot
| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| slot_id | uuid | PK，CK uuid7 | |
| class_id | uuid | NN，FK 到 class | |
| teacher_person_id | uuid | NN，FK 到 teacher | 排课时确定的授课教师 |
| starts_at | timestamptz | NN | |
| ends_at | timestamptz | NN，CK 大于 starts_at | |
| room_label | text | 可空，CK 长度不超过 100 | |
| status | text | NN，CK 取值 SCHEDULED / COMPLETED / CANCELLED | |
| 排除约束（设计）| 同一教师的时段不得重叠 | | 需要 btree_gist 扩展；**扩展是否可用本轮未核实，列为待验证** |
| IX | (class_id, starts_at) | | |

状态机：SCHEDULED 到 COMPLETED（考勤已完成）；SCHEDULED 到 CANCELLED。

## 5. M5 考勤与课后卡片

### learning.attendance_record
| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| attendance_id | uuid | PK，CK uuid7 | |
| slot_id | uuid | NN，FK 到 schedule_slot | |
| enrollment_id | uuid | NN，FK 到 enrollment | |
| family_id | uuid | NN，与 enrollment 一致（复合 FK）| |
| status | text | NN，CK 取值 PRESENT / ABSENT / LATE / LEAVE | |
| recorded_by_teacher_person_id | uuid | NN，FK 到 teacher | |
| recorded_at | timestamptz | NN | |
| UQ | (slot_id, enrollment_id) | | L-K6 |

### learning.attendance_correction
| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| correction_id | uuid | PK，CK uuid7 | |
| attendance_id | uuid | NN，FK 到 attendance_record | |
| new_status | text | NN，CK 取值 PRESENT / ABSENT / LATE / LEAVE | |
| reason_code | text | NN | |
| corrected_by_teacher_person_id | uuid | NN，FK 到 teacher | |
| corrected_at | timestamptz | NN | |

规则：只插入（L-K7）。当前状态取最新的更正记录；没有更正时取 attendance_record.status。

### learning.after_class_card
| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| card_id | uuid | PK，CK uuid7 | |
| slot_id | uuid | NN，FK 到 schedule_slot | |
| enrollment_id | uuid | NN，FK 到 enrollment | |
| family_id | uuid | NN，复合 FK | |
| author_teacher_person_id | uuid | NN，FK 到 teacher | |
| summary_text | text | NN，CK 长度 1–2000 | 教师撰写的摘要；不含 ASKWISE 原始数据 |
| status | text | NN，CK 取值 DRAFT / SUBMITTED / PUBLISHED / RETRACTED | |
| updated_at | timestamptz | NN | |
| UQ | (slot_id, enrollment_id) | | 每课时每学生一张卡 |

状态机：DRAFT 到 SUBMITTED 到 PUBLISHED；SUBMITTED 退回 DRAFT；PUBLISHED 到 RETRACTED。RETRACTED 后的重新发布生成新的 publication 行，不修改原行。

## 6. M6 发布与阶段报告

### learning.publication
| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| publication_id | uuid | PK，CK uuid7 | |
| card_id | uuid | NN，FK 到 after_class_card | |
| family_id | uuid | NN | |
| audience | text | NN，CK 取值 FAMILY | 只允许家庭可见 |
| status | text | NN，CK 取值 PUBLISHED / RETRACTED | |
| published_by_principal_id | uuid | NN，FK 到 auth.principals | 发布人权限见权限矩阵（待 N-8 决定）|
| published_at | timestamptz | NN | |
| retracted_at | timestamptz | 可空 | |
| UQ（部分）| (card_id) 仅当 status 为 PUBLISHED | | 同一卡片同时只有一条有效发布 |

### learning.stage_report
| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| report_id | uuid | PK，CK uuid7 | |
| enrollment_id | uuid | NN，FK 到 enrollment | |
| family_id | uuid | NN，复合 FK | |
| period_label | text | NN，CK 长度 1–60 | |
| status | text | NN，CK 取值 DRAFT / SUBMITTED / PUBLISHED / RETRACTED | 与 after_class_card 相同的状态机 |
| summary_text | text | NN，CK 长度 1–4000 | 不含 ASKWISE 原始数据 |
| UQ | (enrollment_id, period_label) | | |

## 7. 跨域引用

### learning.askwise_session_link
| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| link_id | uuid | PK，CK uuid7 | |
| enrollment_id | uuid | NN，FK 到 enrollment | |
| family_id | uuid | NN | |
| askwise_session_ref | text | NN，UQ，CK 长度 1–200 | 外部引用，无外键到 askwise schema（L-K11）|
| linked_by_principal_id | uuid | NN，FK 到 auth.principals | 必须是 ASKWISE 服务主体（D-6，待批准）|
| linked_at | timestamptz | NN | |

不保存的内容：会话内容、AI 交互、诊断、错因、知识状态。
