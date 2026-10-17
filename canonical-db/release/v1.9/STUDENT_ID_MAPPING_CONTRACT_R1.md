# 统一学生 ID 映射契约 R1（V1.9-R1 P3）

**范围：** 自然人、学生、外部系统标识之间的映射规则。
**依据：** 数据库 schema 的源码核实（`migrations/canonical/0003_core_consent_access.sql`、`0007`、`0012`、`0017`）。字段级 ASKWISE 规则依赖 Notion Student Model，本轮 **ACCESS BLOCKED**，相关条目标记为 PROPOSED。
**状态：** 约束与唯一性 = **VERIFIED（源码）**；映射规则 = **PROPOSED**；冲突与人工复核的流程 = **PROPOSED**；两家庭三学生测试 = **NOT RUN**（仅设计）。

## 1. 身份层级（契约）

| 层 | 对象 | 权威来源 | 说明 |
|---|---|---|---|
| 自然人 | `core.people`（`person_id`，UUIDv7）| **Canonical，唯一权威** | 同一个人只有一条记录。不得按姓名、手机号或相似度另建第二条 |
| 学生身份 | `core.student_profiles`（`person_id`，与 `people` 一对一）| Canonical | "学生"是 `people` 上的受控关联，不是另一套人员主档 |
| 家庭与监护 | `core.families`、`core.family_memberships`、`core.guardian_authorities` | Canonical | 未成年人的业务访问必须同时满足监护（VERIFIED）与 Consent |
| 登录主体 | `auth.principals`（FAMILY / ADVISOR / CHANNEL / SERVICE）| Canonical | SERVICE 不对应自然人。ASKWISE 等外部系统的登录身份经 `auth.external_identities` 映射（0017）|
| 外部标识（学生）| `integration.legacy_id_mappings`（`entity_kind = 'STUDENT_PROFILE'`）| 映射表 | 保存外部 ID，不生成新的人员记录 |
| 公开标识 | `integration.public_ids`（`stu_` + 32 位十六进制）| Canonical | 供 API 对外使用，与外部 ID 不混用 |

## 2. 已核实的数据库约束（VERIFIED，源码）

**`integration.legacy_id_mappings`（0003）：**
- `source_system`：1–100 字符，非空。
- `entity_kind`：只允许 `PERSON`、`FAMILY`、`STUDENT_PROFILE`、`GUARDIAN_AUTHORITY`。
- `legacy_id`：1–300 字符，非空。
- `canonical_id`：必须是 UUIDv7。
- `mapping_status`：只允许 `PENDING`、`VERIFIED`、`REVOKED`、`SUPERSEDED`。
- `evidence_ref`：非空。
- `decided_by`（引用 `core.people`）与 `decided_at`：当且仅当 `VERIFIED` 时必须同时存在。
- 唯一索引 `one_verified_legacy_mapping`：`(source_system, entity_kind, legacy_id)` 上，仅对 `VERIFIED` 行唯一。

**`integration.public_ids`（0003）：**
- `public_id` 必须匹配 `^(per|fam|stu|gdn)_[0-9a-f]{32}$`。
- 主键 `(entity_kind, public_id)`，唯一 `(entity_kind, canonical_id)`。

**由此推出的事实（VERIFIED）：**
1. ASKWISE 的 `stu_2026_001` **不能**写入 `public_ids`（格式不匹配），只能写入 `legacy_id_mappings`。两者不会在约束层冲突，但在日志、接口与人工表格中仍可能被误读，因此需要规则（第 4 节）。
2. 同一个外部学生 ID 在同一来源内，只能有一条 `VERIFIED` 映射。
3. `PENDING` 行没有唯一约束，因此可以存在多条待复核记录。这是有意的，它就是人工复核队列。

**待补的缺口（PROPOSED，不在 0018 范围）：** 目前没有约束阻止**同一个 `canonical_id` 在同一来源内映射到两个不同的外部 ID**。建议增加 `UNIQUE (canonical_id, source_system, entity_kind) WHERE mapping_status = 'VERIFIED'`，但需要先确认 Education Compass 历史数据是否已存在一对多的情况，否则迁移会失败。

## 3. 三类外部标识

| 来源 | 标识形式 | 映射方式 | 不允许的做法 |
|---|---|---|---|
| **Education Compass 历史 Student ID** | 文本 ID（旧库 `core.students`、`core.members`，见 `phoenix-core-identity-consent-v1/Phoenix Compass/education compass/server/migrations/012_askwise_teacher_intervention.sql`）| 写入 `legacy_id_mappings`，`source_system = 'EDUCATION_COMPASS'`，`entity_kind = 'STUDENT_PROFILE'` | **不得**把旧库的文本 ID 直接作为 Canonical ID；**不得**复用其表名 `core.*`，因为与 Canonical 的 `core` schema 冲突 |
| **ASKWISE 学生 ID** | `stu_2026_001` 类（Notion Student Model 的定义待核对）| 写入 `legacy_id_mappings`，`source_system = 'ASKWISE'`，`entity_kind = 'STUDENT_PROFILE'` | **不得**让 ASKWISE 建立第二套学生主档（见 `FOUNDER_DECISION_REQUIRED_V1.9` D-6）；**不得**把 `stu_2026_001` 写入 `public_ids` |
| **ASKWISE 用户 ID** | `core_auth_users.id`（Family OS 的 AUTH-CANDIDATE-V1 中作为稳定 user_id）| 映射到 `auth.external_identities`（issuer + subject → principal）| 不得把它当作自然人 ID；不得建立第二套认证（与 AUTH-CANDIDATE-V1 的冲突，需要对齐）|

## 4. 冲突与人工复核规则（PROPOSED）

1. **不得自动合并。** 按姓名、手机号、邮箱、出生日期或相似度自动合并两个 `people` 记录，**一律禁止**。
2. 候选匹配只产生 `PENDING` 映射，附带 `evidence_ref`，进入人工复核队列。
3. 只有有权的人员把状态改为 `VERIFIED`，并写入 `decided_by` 与 `decided_at`（由 `legacy_id_mappings` 的 CHECK 强制）。谁有权核定，是 Founder 决定（N-4）。
4. 无法核实的数据（来源不明、证据不足、同一外部 ID 指向多人）保持 `PENDING`，**不得猜测**。
5. 错误映射用 `REVOKED` 或 `SUPERSEDED` 标记，**保留历史行，不删除**。
6. 同一外部 ID 指向多个自然人：所有相关映射进入 `PENDING`，直到人工裁定。
7. 任何映射都不授予访问权限。访问仍然只看 Guardian、Consent、分配与权益。

## 5. 未成年人

- 学生是未成年人时，任何业务访问（包括映射后的查询）都必须同时满足：`core.guardian_authorities` 有效且 `VERIFIED`，且对应范围的 `consent.grants` 有效。
- 映射本身不改变这一点。映射成功但缺少监护，访问仍然被拒绝。
- Family OS 的身份（Identity）读取**不得**使用 Education 的 `student_id`（见 Family OS 接驳页的三类 Compass 边界；**该页本轮 ACCESS BLOCKED**，此条为上一会话记录，待核对）。

## 6. 两家庭、三学生的合成测试设计（NOT RUN）

| 编号 | 合成对象 | 家庭 | 说明 |
|---|---|---|---|
| S1 | 学生甲 | F1 | 有 Education Compass 历史 ID（已核定 VERIFIED）|
| S2 | 学生乙 | F1 | 与 S1 同姓同年龄段，用于测试"不得自动合并"|
| S3 | 学生丙 | F2 | 有 ASKWISE 学生 ID `stu_2026_001`（PENDING）|
| G1 | 监护人甲 | F1 | VERIFIED，范围 EDUCATION |
| G2 | 监护人乙 | F2 | VERIFIED，范围 EDUCATION |

| 用例 | 操作 | 期望 |
|---|---|---|
| M-1 | 以 EDUCATION_COMPASS 的历史 ID 查询 S1 | 通过 `VERIFIED` 映射解析到 S1 的 `person_id` |
| M-2 | 以 EDUCATION_COMPASS 的历史 ID 查询 S2 | 不解析到 S1（两个 ID 不同，不得混淆）|
| M-3 | 插入第二条 `VERIFIED` 映射，相同 `(source_system, entity_kind, legacy_id)` | 唯一索引拒绝 |
| M-4 | 插入 `VERIFIED` 但缺少 `decided_by` | CHECK 拒绝 |
| M-5 | S1 与 S2 姓名相同，尝试以姓名匹配自动合并 | 不合并；只产生 `PENDING` 候选 |
| M-6 | 以 `stu_2026_001` 尝试写入 `integration.public_ids` | 格式 CHECK 拒绝 |
| M-7 | S3 的 ASKWISE 映射为 PENDING 时，ASKWISE 尝试读取 S3 的 Education 申请 | 拒绝（映射未核定，且无分配与 Consent）|
| M-8 | 未成年学生 S2 无监护授权，G1 以 FAMILY 身份读取 S2 | 拒绝 |
| M-9 | G2（F2）尝试以 S1 的历史 ID 解析并读取 | 拒绝（跨家庭）|
| M-10 | 把 S1 的映射由 `VERIFIED` 改为 `REVOKED`，再读取 | 解析失败，历史行保留 |

**执行条件：** 本设计需要在 0018 之后的映射批次中实现，且需要先回答 N-4（核定权限）与第 2 节的一对多缺口。在此之前 **NOT RUN**。
