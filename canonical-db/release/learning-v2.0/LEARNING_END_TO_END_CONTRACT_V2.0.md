# 启明堂 Learning 端到端契约 V2.0（设计）

**状态：** 设计，未实现，未执行。规则标记为 PROPOSED。
**范围：** 最小闭环（报名、教师分配、排课、考勤、课后卡片、家长发布）；ASKWISE 会话关联与成长摘要接口；与 Education Compass、Family OS、Founder OS 的契约；失败降级；审计。

## 1. 最小闭环

| 步骤 | 触发主体 | 前置条件 | 写入 | 后置条件 | 失败时 |
|---|---|---|---|---|---|
| S1 报名 | 教务主管（经学习服务函数）| 课程版本 ACTIVE；班级 OPEN 且未满；权益引用 ACTIVE 且在有效期；学生档案存在 | enrollment（PENDING）| 报名 PENDING | 拒绝并审计，原因代码 |
| S2 激活报名 | 学习服务 | 报名 PENDING；LEARNING_RECORD Consent 已就绪（见 S2a）| enrollment 改为 ACTIVE；status_event | 报名 ACTIVE；可加入班级 | 保持 PENDING，不影响权益 |
| S2a 授予同意 | 成年学生本人，或监护人（LEARNING 范围）| 学生存在；未成年人必须有 VERIFIED 监护 | consent.grants（LEARNING_RECORD）| 同意有效 | 报名保持 PENDING，明确告知原因 |
| S3 教师分配 | 教务主管 | 教师 people 记录存在；TEACHER 主体已签发（D-5）| teacher_assignment（ACTIVE）| 教师可访问该班 | 拒绝分配 |
| S4 排课 | 教务主管 | 班级 PLANNED 或 OPEN；教师有效分配；无时段冲突 | schedule_slot（SCHEDULED）| 时段可考勤 | 拒绝排课，返回冲突原因 |
| S5 加入班级 | 教务主管 | 报名 ACTIVE；班级 OPEN 且未满 | enrollment_class（ACTIVE）| 学生在名单中 | 拒绝，原因代码 |
| S6 考勤 | 教师（有效分配）| 时段 SCHEDULED；学生在班级名单中 | attendance_record | 每位学生一条考勤 | 写入失败则时段保持 SCHEDULED，教师可重试 |
| S6a 更正考勤 | 教务主管 | 原考勤存在 | attendance_correction（追加）| 当前状态取更正记录 | 拒绝 |
| S7 课后卡片草稿 | 教师（作者）| 时段 COMPLETED 或 SCHEDULED；学生在班级名单中 | after_class_card（DRAFT）| 草稿存在 | 拒绝 |
| S7a 提交卡片 | 教师（作者）| 草稿存在 | 状态 SUBMITTED | 等待发布审批 | 退回草稿 |
| S8 发布 | 教务主管（N-8）| 卡片 SUBMITTED；家长有 LEARNING 监护与有效 Consent | publication（PUBLISHED）；卡片 PUBLISHED | 家长可见 | 保持未发布，不通知家长 |
| S9 家长读取 | 家长（R2）| 卡片 PUBLISHED | 无（读取）| 家长看到卡片 | 无数据或拒绝，不报错泄露 |
| S10 撤回发布 | 教务主管 | 存在有效发布 | publication（RETRACTED）；卡片状态 RETRACTED | 家长不再可见 | 保持原状态 |

**闭环的验收标准（设计）：** S1 至 S9 在一个合成班级中连续执行；S2 之前的任何教师或家长访问都被拒绝；S8 之前的家长读取为空；S10 之后家长读取为空。

## 2. 状态时序约束

- 考勤只能在时段进行或完成后写入。时段 CANCELLED 后不得写入考勤。
- 卡片只能在对应时段存在考勤后提交（建议）。**该条件是 PROPOSED，需要确认是否允许无考勤的卡片。**
- 撤回报名（WITHDRAWN）时，已写入的考勤与卡片保留，不删除，只把相关 enrollment_class 设为 DROPPED。

## 3. 与 Education Compass 的契约

| 项 | 内容 |
|---|---|
| 关系 | Education 与学习域共享 `core.student_profiles`，但学习域不引用 Education 的申请。两者互不依赖 |
| 数据流 | 无直接数据流。升学规划结果不自动生成报名 |
| 历史 ID | Education Compass 的历史 Student ID 只通过 `integration.legacy_id_mappings` 映射（见映射契约），学习域不直接使用它 |
| 冲突 | Education Compass 迁移 012 的 `askwise.teacher_student_assignments` 与学习域的 `teacher_assignment` 语义相近但不同（前者是旧的文本 ID 分配）。**学习域不得复用其表名或数据**。这一冲突需要在 0021 之前由 Founder 确认是否迁移旧数据（N-10）|
| Education 不可用时 | 学习域照常运行（无依赖）|

## 4. 与 Family OS 的契约

| 项 | 内容 |
|---|---|
| 读取范围 | 已发布的课后卡片与阶段报告（经 R2 条件）；成长摘要只通过 ASKWISE 接口（第 5 节）|
| 写入 | Family OS 不写入学习域 |
| 不可用时 | 家长端显示"暂不可用"，不缓存学习数据到 Family OS 本地（PROPOSED）|
| 三类 Compass 边界 | Family OS 的 Education 主体使用 family_id 与 student_id；Identity 不得使用 Education 的 student_id（上一会话记录，本轮未核对）|

## 5. ASKWISE 会话关联与成长摘要接口

**会话关联（写入）：**
1. ASKWISE 服务以 ASKWISE_SERVICE 主体调用 `learning.askwise_session_link` 的写入函数，传入 enrollment_id 与外部会话引用。
2. 函数检查：报名为 ACTIVE；ASKWISE 主体有效（D-6）；会话引用未被使用（唯一约束）。
3. 写入审计。失败返回拒绝原因，不影响学习闭环。

**成长摘要（读取，经 ASKWISE 接口）：**
1. Family OS 读取服务调用 ASKWISE 的授权接口，携带调用者的身份上下文（票据）。
2. ASKWISE 接口调用 Canonical 的检查函数（设计）：当前主体是否为该学生的成年本人，或为 LEARNING 范围的 VERIFIED 监护；LEARNING_RECORD Consent 是否有效。
3. 通过后，ASKWISE 只返回授权字段（级别与趋势，D-7 决定范围）。
4. 不通过时返回拒绝，不返回部分数据。

**降级：**
- ASKWISE 不可用：会话关联失败，报名、考勤、卡片、发布照常。Family OS 的成长摘要显示"暂不可用"。这对应 E-P6 与 E-A1 的要求。
- ASKWISE 的 schema（0022）未安装：学习域仍能运行，因为学习表不引用 askwise schema（L-K11）。

## 6. 审计

| 事件 | 记录方式 |
|---|---|
| 所有写入（成功与拒绝）| 经 `audit.record_write_decision`，与现有模式一致，包括 attempt_id |
| 读取拒绝 | 由 RLS 过滤，**不产生审计行**。这是设计如此，但在本合同中明确写明，与 V1.9 的 DOMAIN_ACCESS 矩阵的说明一致 |
| 读取成功 | 当前现有实现不记录读取成功。**学习域的敏感读取是否需要记录，需要决定（N-11）** |
| 审计内容 | 不包含个人信息，只含主体 ID、对象 ID、原因代码 |

## 7. Founder OS 的契约（PROPOSED，未设计）

- Founder OS 只接收聚合指标（例如报名数、班级数、出勤率的汇总），不接收个人级别的记录、卡片内容或考勤明细。
- 聚合的最小人数阈值（例如少于 5 人不展示）待决定（N-12）。
- Founder OS 不持有学习域的 SERVICE 主体。

## 8. 失败降级汇总

| 故障 | 影响 | 降级行为 |
|---|---|---|
| ASKWISE 不可用 | 会话关联与成长摘要不可用 | 闭环照常；家长端显示暂不可用 |
| Education Compass 不可用 | 无直接依赖 | 无影响 |
| Family OS 不可用 | 家长端入口不可用 | 学习域数据不受影响；家长通过其他入口读取（待定）|
| Operations 通知延迟 | 权益状态未及时更新 | 权益仍为 ACTIVE 时，新报名会被允许；已报名不受影响。**这是一项已知风险**，需要 D-8 规定通知时限 |
| 教师分配系统故障 | 无法新增分配 | 已有有效分配不受影响，教师可继续考勤至分配到期 |
| 考勤写入失败 | 单次写入失败 | 教师可重试；时段状态不变 |
| 发布失败 | 卡片未发布 | 家长不可见，不产生部分发布 |

## 9. 本契约的验收

- 第 1 节闭环在合成数据上完整执行，每一步的写入与审计可核对。
- 第 5 节 ASKWISE 不可用时，第 1 节闭环仍然通过（对应 E-P6）。
- 第 3 节的冲突通过映射与不复用表名的检查。
- **状态：NOT RUN。** 本契约不得以"已通过"报告，直到学习表与函数存在并在隔离容器中执行。
