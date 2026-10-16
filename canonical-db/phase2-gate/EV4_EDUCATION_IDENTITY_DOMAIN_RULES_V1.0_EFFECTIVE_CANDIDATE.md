# EV-4 Education / Identity 领域规则 V1.0（生效候选版）

**状态：** EFFECTIVE CANDIDATE —— **未生效**。须 Founder 对本文件及其 SHA-256 单独批准后才生效。
**起草：** Claude，2026-10-16。授权依据：决策补充 V1.4 第 2 节（`b783e03e…`）。
**适用范围：** 只适用于新库（空库与合成数据阶段）。
**写法：**
- 以已实现并复审的 0004、0009、0011 为底稿，并入 D-13；
- 每条规则后标注**来源**和**实现状态**；
- 缺口列在第 8 节，**只列出，不裁定**。

## 来源登记

| 代号 | 文件 | SHA-256（前 16 位） | 地位 |
|---|---|---|---|
| BC | `CANONICAL_BUSINESS_CONTRACT_V1.0_EFFECTIVE.md` | `f89a1bbe3cff78ed` | 已批准的新库基线（FD-2） |
| FD-2.6 | 登记表 FD-2 第 6 条补充裁定，批准 `F10_APPLICATION_WRITE_API_DESIGN_DRAFT.md`（`1eb356cb…`） | `ed1d5838ef54e45c` | 已签名 |
| D-10、D-13、D-14 | 补充 V1.2（`925c83f4…`）、补充 V1.1（`1b6a58f5…`） | — | 已批准 |
| M0004 / M0007 / M0009 / M0011 | `migrations/canonical/` 下对应文件 | `aec2be38…` / `49ec7373…` / `2a48d016…` / `acc638a3…` | 已实现并复审 |

## 1. 通用个案（casework）

1. `casework.cases` 是通用的顾问协作个案，状态为 OPEN / PAUSED / CLOSED。（BC Casework 第 1 条）【已实现：M0004】
2. **与教育申请、身份案件的关系：**
   - 个案可以引用一个教育申请或一个身份案件（`resource_kind` + `resource_id`，软引用）；
   - 个案**不拥有、也不复制**它们的领域状态。
   
   （BC Casework 第 1、5 条）【已实现：M0004】
3. **顾问分配：**
   - 挂在个案上，有有效期，可以撤销；
   - 生命周期为 ACTIVE / REVOKED / EXPIRED，同一个案与顾问只允许一条 ACTIVE。
   
   （M0004；M0007）【已实现】
4. 个案的创建与关闭、顾问分配的建立与撤销，只经 SERVICE 管理接口进行。（D-10 第 3 条）【待实现：0012 起】

## 2. 教育申请

1. **字段（白名单）：**
   - 申请 ID、家庭 ID、学生自然人 ID（须已有学生档案）；
   - 院校名称、项目名称、申请季；
   - 状态，以及创建时间、更新时间。
   
   扩展字段须另行批准；院校特定的材料规则属于数据库之外的配置。（BC Casework 第 2 条；FD-2.6）【已实现：M0004】
2. **谁能创建，以及推进非终局状态：**
   - FAMILY 渠道：学生本人，或 `EDUCATION` 范围的 VERIFIED 监护人；
   - ADVISOR 渠道：有指向该申请的有效分配，并持有 `EDUCATION_CASE` / `EDUCATION` Consent。
   
   （FD-2.6；M0009 `education.can_write_application`）【已实现】
3. **状态流转：**

   | 当前状态 | 可以进入 | 谁可以 |
   |---|---|---|
   | DRAFT | READY、WITHDRAWN | 第 2 条所列的家庭一方或顾问 |
   | READY | SUBMITTED、WITHDRAWN | 同上 |
   | SUBMITTED | WITHDRAWN | 同上 |
   | SUBMITTED | **DECIDED** | **只有**有分配并持有 Consent 的顾问，或 INTERNAL 服务，且必须**已有 DECISION 事实** |
   | DECIDED、WITHDRAWN | —（终局） | — |

   - 不允许跳级；
   - WITHDRAWN 只能从尚未决定的状态进入；
   - 家庭一方不能推进到 DECIDED。
   
   （FD-2.6；D-13 第 1、4 条）【已实现：M0011】
4. **状态事件：** 每次状态变化追加一条状态事件，记录原状态、新状态、时间和操作人；服务操作时，操作人记录为 principal。（BC Casework 第 4 条；D-11 第 2 条）【前半已实现：M0004；principal 记录待实现】

## 3. 身份案件

1. **字段（白名单）：**
   - 案件 ID、家庭 ID、主体自然人 ID；
   - 案件类型（1–100 字的文本）；
   - 状态，以及创建时间、更新时间。
   
   （BC Casework 第 3 条；FD-2.6）【已实现：M0004】
2. **谁能创建，以及推进非终局状态：**
   - FAMILY 渠道：本人，或 `IDENTITY` 范围的 VERIFIED 监护人；
   - ADVISOR 渠道：有指向该案件的有效分配，并持有 `IDENTITY_CASE` / `IDENTITY_SENSITIVE` Consent。
   
   （FD-2.6；M0009 `identity.can_write_case`）【已实现】
3. **状态流转：**

   | 当前状态 | 可以进入 | 谁可以 |
   |---|---|---|
   | DRAFT | EVIDENCE_PENDING | 第 2 条所列的家庭一方或顾问 |
   | EVIDENCE_PENDING | UNDER_REVIEW | 同上 |
   | UNDER_REVIEW | CLOSED（不涉及官方结论的结案） | 同上（维持原规则） |
   | UNDER_REVIEW | **RESOLVED** | **只有**有分配并持有 Consent 的顾问，或 INTERNAL 服务，且必须**已有 DECISION 事实** |
   | RESOLVED、CLOSED | —（终局） | — |

   （FD-2.6；D-13 第 2、4 条）【已实现：M0011】
4. 状态事件的规则同第 2 节第 4 条。【已实现：M0004；principal 记录待实现】

## 4. 外部官方事实

1. **种类：** `OFFICIAL_RECEIPT`（官方回执）、`DECISION`（官方决定），分别挂在教育申请或身份案件上。（BC Casework 第 4 条）【已实现：M0004】
2. **每条记录必须写明：** 来源、外部编号、观测时间。观测时间不得晚于当前时间。同一"对象 + 种类 + 来源 + 外部编号"只记录一次。（BC Casework 第 4 条；D-13 第 3 条）【已实现：M0004 / M0011】
3. **谁能记录：** 有有效分配并持有对应 Consent 的顾问，或 INTERNAL 渠道的 SERVICE 主体。**家庭成员不能记录**，可以通过上传证明文件辅助顾问记录。（D-13 第 3 条）【已实现：M0011】
4. **只追加：** 事实不可修改或删除。（D-13；M0011）【已实现】
5. **作用范围：** 本阶段只有 DECISION 事实作为状态推进的前提（DECIDED / RESOLVED）；OFFICIAL_RECEIPT 只做记录，不决定任何状态。（D-13）【已实现；见 E4-5】

## 5. 与提交清单的关系

教育申请和身份案件是提交清单的唯一目标。提交流程、确认人、提交人的规则，见 EV-3 第 6 节。清单状态与申请或案件的状态彼此独立：提交清单不会自动推进申请或案件的状态，反之亦然。（BC DS 第 3 条；D-14）【已实现】

## 6. 审计

每一次创建、推进、记录事实的判定（允许或拒绝）都写审计，并带稳定的原因代码，例如 `STATE_OR_DECISION_FACT_DENIED`、`OFFICIAL_FACT_AUTHORITY_OR_INPUT_DENIED`；同时双写 `PHOENIX_AUDIT` 服务器日志。（BC；D-9）【审计表已实现；双写待实现】

## 7. 验收用例（已在 PG16 / PG17 合成数据上通过）

| 规则 | 用例 | 位置 |
|---|---|---|
| 创建与跳级 | 家庭创建申请和案件；跳级推进被拒 | `tests/f10_family_create_regression.sql` |
| 顾问权限 | 没有 Consent 时被拒，有 Consent 后允许推进 | `tests/f10_advisor_pre_regression.sql`、`f10_advisor_post_regression.sql` |
| D-13 | 家庭推进到 DECIDED / RESOLVED 被拒（C5）；未来观测时间被拒；顾问记录 DECISION 后推进成功 | `tests/f10_family_finish_regression.sql`、`f10_d6_advisor_final.sql`、`claude_f10_reaudit_probes.sh` |
| D-13 补充 | 已授权的服务在没有 DECISION 事实时推进被拒，有事实后允许（G1）；家庭记录官方事实被拒（G2） | `evidence/claude-v1.5-d6-gap-probes.sh` |
| 不可修改 | 官方事实不可修改 | `tests/f10_d6_immutability_regression.sql` |
| 恢复 | 全新集群恢复后，以上不可修改断言仍然成立 | `tests/f10_ephemeral_restore.sh` |

## 8. 缺口（只列出，不裁定）

| 编号 | 内容 | Claude 建议（未裁定） |
|---|---|---|
| E4-1 | **没有指定领域负责人：** EV-4 要求有负责人（owner），目前未指定。 | 由 Founder 指定（可以是 Founder 本人），负责批准状态机与字段的后续修改 |
| E4-2 | **没有材料清单（DSC DS-5）：** 院校或身份案件的材料要求未定义；BC 规定它们属于数据库之外的配置。 | 维持在数据库外配置；需要时另立"材料要求"规格，不在数据库里编造 |
| E4-3 | **身份案件进入审核前无法放弃：** 在 UNDER_REVIEW 之前，没有任何途径可以结案或撤回（DRAFT、EVIDENCE_PENDING 都不能进入 CLOSED）。 | 允许 DRAFT、EVIDENCE_PENDING 直接进入 CLOSED，由第 3 节第 2 条所列的人执行 |
| E4-4 | **案件类型是自由文本：** 没有受控词表，统计和权限细分都会受影响。 | 定义受控词表后，用新 Migration 加约束 |
| E4-5 | **SUBMITTED 不需要官方回执：** 目前凭家庭或顾问的声明即可进入。 | 维持现状（D-13 只约束 DECIDED / RESOLVED）；如果需要回执作为前提，另行决定 |
| E4-6 | **顾问创建申请的顺序：** 按现在的实现，顾问必须先有一个个案引用该申请编号，才能创建该申请；而个案由 SERVICE 管理接口建立（D-10）。流程顺序没有写明。 | 明确为：服务先建个案并分配顾问，再由顾问创建申请；或者顾问创建只限家庭已创建的申请 |
| E4-7 | **DECIDED 之后没有后续状态：** 例如录取后接受或拒绝、入学，都没有对应状态。 | 本期维持；需要时由领域负责人提出新状态 |

## 生效条件

1. Founder 对本文件及其 SHA-256 单独批准，并对第 8 节逐项作出决定（可以"按建议"）；
2. "待实现"的条目，在 Codex 后续批次实现并经复审后，才视为已落地；
3. 批准后，本文件取代 EV-4"部分基线"状态，作为 Education / Identity 的领域规则；状态机与字段的任何修改，都须经领域负责人提出、Founder 批准，并以新 Migration 实现。
