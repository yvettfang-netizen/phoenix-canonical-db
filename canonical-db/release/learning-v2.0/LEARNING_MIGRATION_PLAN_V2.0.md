# 启明堂 Learning 迁移计划 V2.0（候选，未实现）

**状态：** 候选计划。**没有任何迁移被创建、执行或部署。** 0018 之后的批次都以 `CANONICAL_MIGRATION_NEXT_PHASE_PLAN_V1.0.md` 的编号为准。
**前提：** 0018 的开工条件未满足（见 `../v1.9/MIGRATION_0018_READINESS_DECISION_R1.md`）。
**不在本计划内的事项：** 腾讯环境、生产数据、`phoenix_core`、Founder OS D1 数据。

## 1. 批次与依赖

| 批次 | 内容 | 依赖 | 状态 |
|---|---|---|---|
| 0018 | 安全修复：E-R6 状态检查（候选已在容器验证）；D-2 撤销 bind_context 执行权（待验证）| 无 | 未就绪（N-2、D-2）|
| 0019 | 教育主数据与档案（education 扩展）| 0018 | 设计见 NEXT_PHASE 第 3 节 |
| 0020 | 权益引用（operations_ref）：外部订单号、权益号、有效期；课程权益函数 | 0019；**D-8** | 未设计 |
| 0021 | 学习核心：授权词汇扩展（A）+ 六个模块的表与函数（B）| 0018、0019、0020；**D-1、D-1b、D-5、N-7、N-9、N-10** | 设计见本目录 |
| 0022 | ASKWISE 域（ASKWISE 自己的 schema，与学习域的会话引用）| 0021；**D-6、错因词表** | 来源 BLOCKED |
| 0023 | Family OS 授权视图（成长摘要接口）| 0022；**D-7** | 来源 BLOCKED |

**关于 0021 的范围：** 0021 包含两部分。(A) 授权词汇扩展：`auth.principals` 的 TEACHER、SUPERVISOR；渠道 STAFF；`consent.grants` 的用途 LEARNING_RECORD 与数据类别 LEARNING；`core.guardian_authorities` 的范围 LEARNING。(B) 学习表、函数、策略与测试。两部分同属一个迁移文件，不拆分，以免 CHECK 与依赖的表出现时间差。

**编号风险（N-13）：** 如果 0021 体量过大需要拆分，拆分后的文件必须有唯一的四位编号，因此 0022 与 0023 需要顺延。这会影响 NEXT_PHASE 文件中的所有依赖关系，必须由 Founder 决定，不由工程自行调整。

## 2. 0021（A）授权词汇扩展

| 变更 | 当前 CHECK | 建议变更 | 影响 |
|---|---|---|---|
| auth.principals.principal_kind | FAMILY、ADVISOR、CHANNEL、SERVICE | 增加 TEACHER、SUPERVISOR；SERVICE 与 ASKWISE_SERVICE 按 D-6 决定 | `validate_context_request` 的渠道映射需同步；R-20 映射表新增两行 |
| 渠道 | FAMILY、ADVISOR、PARTNER、INTERNAL | 增加 STAFF | `validate_context_request` 的 CHECK 与映射；现有测试需更新 |
| consent.grants.purpose | DOCUMENT_READ、EDUCATION_CASE、IDENTITY_CASE | 增加 LEARNING_RECORD | `consent.actor_can_grant` 需要新的映射 |
| consent.grants.data_class | GENERAL、EDUCATION、IDENTITY_SENSITIVE | 增加 LEARNING | 同上 |
| core.guardian_authorities.scope | GENERAL、EDUCATION、IDENTITY | 增加 LEARNING | `create_guardian_authority` 的范围检查需要同步（0016 的版本）|

**验证要求：** 每个 CHECK 变更都必须有对应的负向测试（旧值仍被接受，新值被正确映射），并保留 0003 至 0018 的原有测试通过。

## 3. 0021（B）学习表与函数

| 模块 | 表（来自字段字典）| 函数（写入）| 策略（读取）|
|---|---|---|---|
| M1 | course、course_version | 创建、发布、归档（教务）| 目录对所有主体只读，无个人数据 |
| M2 | external_entitlement_ref、enrollment、enrollment_status_event | 登记权益引用（学习服务，经 0020）；创建与状态变更（教务）| 按权限矩阵（R1、R2）|
| M3 | teacher、teacher_assignment | 教师登记（SERVICE）；分配与撤销（教务）| 教师读本人；教务读全部 |
| M4 | class、enrollment_class、schedule_slot | 班级与排课（教务）；加入班级（教务）| 按分配与报名（R3、R4）|
| M5 | attendance_record、attendance_correction、after_class_card | 考勤写入（教师，R3）；更正（教务，R4）；卡片草稿与提交（作者）| 按 R2、R3、R4 |
| M6 | publication、stage_report | 发布与撤回（教务，N-8）| 已发布：家长（R2）与本人 |
| 跨域 | askwise_session_link | 写入（ASKWISE 服务，D-6）| 教务只读引用 |

**函数约定：** 全部写入函数为 SECURITY DEFINER，固定 `search_path`，PUBLIC 无执行权（与现有 94 个函数一致）；每个函数调用 `audit.record_write_decision`。

**策略约定：** 所有学习表启用 RLS，且只对 `phoenix_canonical_app`、`phoenix_canonical_reader` 授予 SELECT。应用角色没有 INSERT、UPDATE、DELETE 权限，写入只经函数。

## 4. 回滚

| 批次 | 回滚方式 | 限制 |
|---|---|---|
| 0018 | 前向修复：新迁移恢复旧函数体（旧函数体保存在候选文件的历史版本中，需要先备份）| 账本是前向的，不删除已应用的迁移；回滚即新迁移 |
| 0021（A）| 前向：CHECK 扩展只能放宽，不能直接收紧；收紧需要数据检查 | 已写入的新值需要先迁移再收紧 |
| 0021（B）| 开发库：可以 `DROP SCHEMA learning CASCADE`（仅限一次性容器）。生产与腾讯：**不得删除**，只能前向修复或从已校验备份恢复 | 备份恢复依赖 D-1b 的恢复方式（当前使用 `--no-owner`，属主丢失）|
| 0022、0023 | 同 0021 | 同 0021 |

**通用规则：** 任何批次应用前都必须有已校验的备份（`backup.sh` 与 manifest），并在一次性容器中完整演练（新集群恢复后重新执行 F10）。

## 5. 阻塞项（实现前必须解决）

| 编号 | 阻塞项 | 类型 | 解决方式 | 决定项 |
|---|---|---|---|---|
| B-1 | E-R6 P1 缺陷未修复 | 安全 | 0018 | N-2 |
| B-2 | 属主模型与恢复方式未决定 | 基础设施 | 学习表应在最终属主模型下创建；`--no-owner` 的验证未完成 | D-1、D-1b |
| B-3 | 权益引用不存在（0020 未设计）| 依赖 | 0020 设计与批准 | D-8 |
| B-4 | TEACHER、SUPERVISOR 主体与 STAFF 渠道不存在 | 授权 | 0021（A）| D-5、N-7 |
| B-5 | LEARNING_RECORD 用途与 LEARNING 数据类别不存在 | 授权 | 0021（A）| D-5 |
| B-6 | 监护范围 LEARNING 不存在 | 授权 | 0021（A）| D-5 |
| B-7 | LEARNING_RECORD 的被授权人模型未定（个人、机构还是报名）| 授权 | 决定后写入权限矩阵 R3 | N-9 |
| B-8 | Education Compass 迁移 012 中的教师分配（文本 ID）与学习域的分配冲突 | 数据 | 决定是否迁移旧数据；学习域不复用表名 | N-10 |
| B-9 | 学生 ID 映射中"同一 canonical 同一来源只能一条 VERIFIED"的约束缺失 | 数据 | 先核对历史数据，再决定是否加约束 | 映射契约第 2 节 |
| B-10 | 学习敏感读取是否需要审计 | 合规 | 决定 | N-11 |
| B-11 | Founder OS 聚合的最小人数阈值 | 产品 | 决定 | N-12 |
| B-12 | 启明堂 Freeze 与 ASKWISE 两页、Family OS 页 ACCESS BLOCKED | 来源 | 恢复访问后重新核对本计划的所有 PROPOSED 条目 | 用户处理（见 Notion 核验文件）|
| B-13 | 排课排除约束需要 btree_gist，扩展可用性未核实 | 技术 | 在隔离容器中核实 | 无需决定 |
| B-14 | pwsh 脚本补跑 | **CLOSED（2026-10-19）** | PG16 / PG17 全部 PASS | N-5 已关闭 |

## 6. 需要 Founder 决定的事项（学习域）

| 编号 | 决定 | 建议 |
|---|---|---|
| D-5 | 学习域权限规则（LEARNING_RECORD、购买不授予、TEACHER）| 批准 LEARNING_RECORD；购买不授予访问；批准 TEACHER |
| N-7 | 教师主体与班级范围 | 批准 TEACHER 与 STAFF 渠道；访问限于有效分配的班级 |
| N-8 | 卡片发布是否需要教务审批 | 教务审批后发布（教师只能提交）|
| N-9 | LEARNING_RECORD Consent 的被授权人模型 | 待定：(a) 逐个教师；(b) 机构主体；(c) 按报名。需要先确定机构在系统中的表示方式 |
| N-10 | 是否迁移 Education Compass 的旧教师分配数据 | 不迁移；旧数据保留在旧库，学习域从零开始（需要确认）|
| N-11 | 学习敏感数据的读取是否审计 | 建议审计读取（至少对监护人与教师的读取）|
| N-12 | Founder OS 聚合的最小人数阈值 | 待定，建议 5 人 |
| N-13 | 0021 是否拆分（会顺延 0022、0023）| 建议不拆分，以保持依赖关系 |
| D-6 | ASKWISE 服务主体类型（ASKWISE_SERVICE）| 批准新类型 |
| D-7 | Family OS 成长摘要范围 | 建议只含级别与趋势 |
| D-8 | Operations 引用契约（编号格式、通知方式、有效期规则）| 需要 Operations 负责人确认 |

## 7. 验证门槛（进入实现后）

1. 0021（A）的每个 CHECK 变更都有正向与负向测试，且旧测试全部通过。
2. 0021（B）的表、索引、唯一约束与外键与字段字典一致（目录检查）。
3. `learning-v2.0/LEARNING_ROLE_PERMISSION_MATRIX_V2.0.md` 第 7 节的 LP 与 LN 用例全部实现为可执行测试，并在 PG16 与 PG17 上通过。
4. ASKWISE 不可用（0022 未安装）时，闭环仍通过（E-P6）。
5. 完整 F10 套件（PG16、PG17）通过，且与 0018 之后的基线相同。
6. 新集群恢复后，学习表的属主与权限与源库一致（依赖 D-1b 的验证）。

**本计划的状态：** 候选；所有批次未开工；没有任何迁移文件存在。
