# 启明堂 Learning 角色与权限矩阵 V2.0（设计）

**状态：** 设计。所有规则标记为 PROPOSED，因为启明堂 Freeze 本轮 ACCESS BLOCKED。需要 Founder 决定的项见 `LEARNING_MIGRATION_PLAN_V2.0.md` 第 6 节。
**原则：** 最小权限；RLS 只约束读取；写入只经 SECURITY DEFINER 函数；权益不授予访问；购买不自动产生 Consent；SERVICE 与 ASKWISE 服务不读取学习业务数据。

## 1. 角色与主体

| 角色 | 登录主体（现有或建议）| 渠道 | 状态 | 说明 |
|---|---|---|---|---|
| 成年学生 | FAMILY（主体即学生本人）| FAMILY | 现有 | 可以为自己撤回或授予 LEARNING_RECORD Consent |
| 未成年学生 | FAMILY（主体为学生）| FAMILY | 现有 | 不能自行授予 Consent；只能查看自己的已发布内容与报名 |
| 家长 / 监护人 | FAMILY（主体为监护人）| FAMILY | 现有 | 需要 VERIFIED 监护，范围包含 LEARNING（范围需新增）|
| 教师 | **TEACHER**（建议）| **STAFF**（建议）| **未批准**（D-5）| 只能访问有效分配的班级 |
| 教务主管 | **SUPERVISOR**（建议）| **STAFF**（建议）| **未批准** | 排课、分配、发布审批 |
| 学习服务 | SERVICE | INTERNAL | 现有 | 只通过函数写入；不能直接读取业务表 |
| ASKWISE 服务 | **ASKWISE_SERVICE**（建议，D-6）| INTERNAL（建议）| **未批准** | 只写入会话引用与 ASKWISE 自己的数据 |
| Family OS 读取服务 | **FAMILY_OS_READER**（建议）| INTERNAL（建议）| **未设计** | 只通过 ASKWISE 授权接口读取摘要 |
| Operations 服务 | SERVICE（外部编号）| INTERNAL | 现有（SERVICE），权益函数未实现 | 推送权益引用与撤销通知（D-8）|
| Founder OS | 不作为学习域主体 | — | 未设计 | 只接收聚合指标，不接收个人记录（待决定）|

**STAFF 渠道的必要性：** 现有 `auth.validate_context_request` 的渠道映射只有 FAMILY、ADVISOR、PARTNER、INTERNAL。教师与教务不能用 INTERNAL（它禁止非服务的人员访问），也不能用 ADVISOR（ADVISOR 的读取依赖个案分配，而班级不是个案）。因此需要新增 STAFF 渠道。这是数据库 CHECK 的变更，属于 D-5 的一部分。

## 2. 教师身份的签发（未设计，必须单独决定）

- 教师的 `core.people` 记录由 SERVICE 通过函数创建（与顾问 `register_external_person` 同类）。
- TEACHER 主体只能由教务主管的 SERVICE 流程创建，并绑定到唯一的 `teacher.teacher_person_id`。
- 教师的会话绑定沿用现有票据机制（`auth.issue_context_ticket`），票据有效期不超过 60 秒。
- **未设计的部分：** 教师如何完成真实的登录认证（这不是数据库问题，而是身份提供方问题）。在此之前，TEACHER 主体只能用于测试。

## 3. 对象矩阵

**符号：** 允 = 允许；拒 = 拒绝；条 = 有条件（条件见第 4 节）；函 = 只能经函数写入；— = 不适用。

| 对象 | 成年学生 | 未成年学生 | 家长 | 教师 | 教务主管 | 学习服务 | ASKWISE 服务 | Family OS 读取 | Operations | Founder OS |
|---|---|---|---|---|---|---|---|---|---|---|
| course / course_version 读取 | 允 | 允 | 允 | 允 | 允 | 拒 | 拒 | 拒 | 拒 | 拒 |
| course 写入 | 拒 | 拒 | 拒 | 拒 | 函 | 函 | 拒 | 拒 | 拒 | 拒 |
| external_entitlement_ref 读取 | 拒 | 拒 | 条（本家庭，不含金额）| 拒 | 允 | 拒 | 拒 | 拒 | 拒 | 拒 |
| external_entitlement_ref 写入 | 拒 | 拒 | 拒 | 拒 | 拒 | 函 | 拒 | 拒 | 函 | 拒 |
| enrollment 读取 | 允（本人）| 允（本人）| 条 R2 | 条 R3 | 条 R4 | 拒 | 拒 | 拒 | 拒 | 拒 |
| enrollment 创建与状态变更 | 拒 | 拒 | 拒 | 拒 | 函 | 函 | 拒 | 拒 | 拒 | 拒 |
| enrollment_status_event 读取 | 拒 | 拒 | 拒 | 拒 | 允 | 拒 | 拒 | 拒 | 拒 | 拒 |
| teacher 读取 | 拒 | 拒 | 拒 | 允（本人）| 允 | 拒 | 拒 | 拒 | 拒 | 拒 |
| teacher_assignment 读取 | 拒 | 拒 | 拒 | 允（本人）| 允 | 拒 | 拒 | 拒 | 拒 | 拒 |
| teacher_assignment 创建与撤销 | 拒 | 拒 | 拒 | 拒 | 函 | 函 | 拒 | 拒 | 拒 | 拒 |
| class 读取 | 条（本人已报名的班）| 条（同左）| 条（子女所在的班）| 条（有效分配的班）| 允 | 拒 | 拒 | 拒 | 拒 | 拒 |
| enrollment_class 读取（名单）| 拒 | 拒 | 拒 | 条（有效分配）| 允 | 拒 | 拒 | 拒 | 拒 | 拒 |
| schedule_slot 读取 | 条（已报名）| 条（已报名）| 条（子女已报名）| 条（有效分配）| 允 | 拒 | 拒 | 拒 | 拒 | 拒 |
| schedule_slot 写入 | 拒 | 拒 | 拒 | 拒 | 函 | 函 | 拒 | 拒 | 拒 | 拒 |
| attendance_record 读取 | 条（本人）| 条（本人）| 条 R2 | 条 R3 | 条 R4 | 拒 | 拒 | 拒 | 拒 | 拒 |
| attendance 写入与更正 | 拒 | 拒 | 拒 | 函（有效分配，R3）| 函（更正，R4）| 函 | 拒 | 拒 | 拒 | 拒 |
| after_class_card 草稿读取 | 拒 | 拒 | 拒 | 条（作者本人）| 条（R4）| 拒 | 拒 | 拒 | 拒 | 拒 |
| after_class_card 草稿写入与提交 | 拒 | 拒 | 拒 | 函（作者）| 函（退回）| 拒 | 拒 | 拒 | 拒 | 拒 |
| publication 发布与撤回 | 拒 | 拒 | 拒 | 拒 | 函（发布审批，N-8）| 函 | 拒 | 拒 | 拒 | 拒 |
| 已发布卡片读取 | 允（本人，成年或未成年）| 允（本人）| 条 R2 | 条（R3）| 条（R4）| 拒 | 拒 | 拒（不直接读取，见第 5 节）| 拒 | 拒 |
| stage_report 读取（已发布）| 允（本人）| 允（本人）| 条 R2 | 条 R3 | 条 R4 | 拒 | 拒 | 条 | 拒 | 拒 |
| askwise_session_link 写入 | 拒 | 拒 | 拒 | 拒 | 拒 | 拒 | 函（ASKWISE 服务主体）| 拒 | 拒 | 拒 |
| askwise_session_link 读取 | 拒 | 拒 | 拒 | 拒 | 允（只读引用，不含内容）| 拒 | 拒 | 拒 | 拒 | 拒 |
| LEARNING_RECORD Consent 授予 | 允（自己，成年）| 拒 | 条（LEARNING 范围的 VERIFIED 监护）| 拒 | 拒 | 拒 | 拒 | 拒 | 拒 | 拒 |
| LEARNING_RECORD Consent 撤回 | 允（自己，成年）| 拒 | 条（同授予）| 拒 | 拒 | 拒 | 拒 | 拒 | 拒 | 拒 |
| audit 读取 | 拒 | 拒 | 拒 | 拒 | 拒 | 拒 | 拒 | 拒 | 拒 | 拒（仅 reader 角色）|

## 4. 条件定义（PROPOSED）

| 条件 | 规则 |
|---|---|
| R1 | 成年学生读取自己的记录，不需要 Consent |
| R2 | 家长读取子女记录，需要同时满足：①VERIFIED 监护，范围含 LEARNING；②有效的 LEARNING_RECORD Consent（授权人为学生或监护人，对象为该学生）；③该记录属于该家庭。**不满足任一项即拒绝** |
| R3 | 教师读取或写入某班记录，需要同时满足：①TEACHER 主体（未批准）；②该班存在 ACTIVE 且在有效期内的 teacher_assignment；③班级状态为 OPEN 或 RUNNING；④对于读取学生个人记录，需要该学生的 LEARNING_RECORD Consent 且被授权人为机构（**被授权人模型待 N-9 决定**）|
| R4 | 教务主管的读取与 R3 相同，但不限于单个班级，范围由教务的 scope 决定（scope 模型未设计）|
| 购买规则（L-K4）| enrollment 或 external_entitlement_ref 的存在与有效，**不得单独**满足 R2、R3、R4 中的任何一个 |
| 未成年规则 | 未成年学生不能自行授予 Consent。他的任何学习记录访问都必须经过监护（R2）|

## 5. 成长摘要（Family OS 读取，PROPOSED）

- 摘要只由 ASKWISE 服务写入，存放在 ASKWISE 自己的 schema 或服务中。
- Family OS 通过 ASKWISE 的授权接口读取，接口调用时在 Canonical 中检查：当前主体身份、家庭关系、LEARNING_RECORD Consent 有效性。
- 字段范围由 D-7 决定。建议只包含级别与趋势，不包含题目、错因明细、原始对话。
- Learning 服务与 Canonical 本身不保存成长摘要。

## 6. 通用拒绝规则

- 对于不满足条件的读取，RLS 返回空集（与现有行为一致，不返回错误），并经审计记录拒绝原因代码（沿用 `audit.record_write_decision` 模式的写入拒绝；读取拒绝由 RLS 过滤，不产生审计行，这一点需要在合同中写明，见端到端契约第 6 节）。
- 对于写入，函数返回拒绝并写审计，原因代码固定，不包含个人信息。

## 7. 权限测试矩阵（设计，NOT RUN）

测试在隔离容器中以合成数据执行。每个用例给出编号、主体、操作、期望结果。正向与负向各列出，以便覆盖"允许"与"拒绝"两面。

### 7.1 正向用例

| 编号 | 主体 | 操作 | 期望 |
|---|---|---|---|
| LP-01 | 成年学生 S1 | 读取自己的报名 | 允许 |
| LP-02 | 未成年学生 S2 | 读取自己已发布的课后卡片 | 允许 |
| LP-03 | 监护人 G1（VERIFIED，LEARNING 范围）+ 有效 Consent | 读取子女 S2 的考勤 | 允许（R2）|
| LP-04 | 监护人 G1 | 读取子女 S2 的已发布卡片 | 允许（R2）|
| LP-05 | 教师 T1（有效分配 C1，C1 为 RUNNING）+ 机构 Consent | 读取 C1 名单与考勤 | 允许（R3）|
| LP-06 | 教师 T1 | 为 C1 当前时段写入考勤 | 允许（函数）|
| LP-07 | 教师 T1 | 提交本人作为作者的课后卡片 | 允许（函数）|
| LP-08 | 教务主管 M1 | 发布已提交的卡片 | 允许（函数，N-8）|
| LP-09 | 教务主管 M1 | 为班级创建分配 | 允许（函数）|
| LP-10 | 学习服务 | 创建报名（有效权益引用）| 允许（函数）|
| LP-11 | 学习服务 | 把 ACTIVE 的权益引用标记为 REVOKED（经 Operations 通知）| 允许（函数，D-8）|
| LP-12 | ASKWISE 服务 | 写入 askwise_session_link | 允许（函数）|
| LP-13 | 家长 G1 | 授予 LEARNING_RECORD Consent（子女 S2）| 允许（LEARNING 范围）|
| LP-14 | 成年学生 S1 | 撤回自己的 LEARNING_RECORD Consent | 允许 |
| LP-15 | 教务主管 M1 | 更正考勤（追加 attendance_correction）| 允许（函数）|

### 7.2 负向用例

| 编号 | 主体 | 操作 | 期望 | 对应规则 |
|---|---|---|---|---|
| LN-01 | 成年学生 S1 | 读取学生 S3 的报名 | 拒绝（RLS 空集）| 跨学生 |
| LN-02 | 监护人 G2（F2）| 读取 S1（F1）的考勤 | 拒绝 | 跨家庭 |
| LN-03 | 监护人 G1 | 读取子女 S2 的考勤，但 LEARNING 监护范围未授予 | 拒绝 | R2① |
| LN-04 | 监护人 G1 | 读取子女 S2 的考勤，Consent 已撤回 | 拒绝 | R2② |
| LN-05 | 监护人 G1 | 仅凭子女报名的权益有效，读取考勤（无 Consent）| 拒绝 | L-K4、购买规则 |
| LN-06 | 未成年学生 S2 | 自行撤回或授予 LEARNING_RECORD Consent | 拒绝 | 未成年规则 |
| LN-07 | 教师 T2（无分配）| 读取 C1 名单 | 拒绝 | R3② |
| LN-08 | 教师 T1（分配已 ENDED）| 为 C1 写入考勤 | 拒绝 | R3②、L-K5 |
| LN-09 | 教师 T1（分配有效，但班级为 CLOSED）| 为 C1 写入考勤 | 拒绝 | R3③ |
| LN-10 | 教师 T1 | 发布卡片（直接发布，不经教务）| 拒绝 | N-8 |
| LN-11 | 教师 T1 | 修改其他教师作者的卡片 | 拒绝 | 作者规则 |
| LN-12 | 教务主管 M1 | 读取某班的考勤，但 Consent 未授予 | 拒绝 | R4 |
| LN-13 | 学习服务 | 直接 SELECT 学习业务表 | 拒绝（RLS 对 INTERNAL 返回空集）| 已验证的 INTERNAL 规则 |
| LN-14 | ASKWISE 服务 | 读取 attendance_record | 拒绝 | 服务不读学习业务数据 |
| LN-15 | ASKWISE 服务 | 写入 attendance_record | 拒绝（只能经学习函数）| 写入只经函数 |
| LN-16 | Family OS 读取服务 | 直接读取 after_class_card | 拒绝 | 第 5 节 |
| LN-17 | 家长 G1 | 读取子女 S2 的草稿卡片（未发布）| 拒绝 | L-K8 |
| LN-18 | 家长 G1 | 读取权益引用中的订单号 | 拒绝（只允许不含金额的字段；订单号的可见性待 D-8）| 最小字段 |
| LN-19 | 任何主体 | 报名超出班级容量 | 拒绝（写入函数）| 容量 |
| LN-20 | 任何主体 | 同一学生同一课程版本第二次有效报名 | 拒绝（唯一索引）| L-K2 |
| LN-21 | 学习服务 | 为学生创建报名，但权益引用的 student 与报名 student 不一致 | 拒绝（复合外键）| L-K10 |
| LN-22 | 学习服务 | 为过期的权益创建报名 | 拒绝（函数检查）| L-K3 |
| LN-23 | 任何主体 | 在考勤表上修改原记录（UPDATE）| 拒绝（无 UPDATE 权限）| L-K7 |
| LN-24 | 任何主体 | 删除 published 的 publication | 拒绝（只能改状态）| L-K9 |

**执行条件：** 本矩阵依赖 TEACHER、SUPERVISOR、STAFF 渠道、LEARNING_RECORD、LEARNING 监护范围、权益引用函数（0020）与学习表（0021）。在这些批次存在之前，矩阵**只是设计**，不得以"已通过"报告。
