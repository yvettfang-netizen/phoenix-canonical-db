# Founder 决策补充 V1.2：R-9 / R-10 / R-11

**状态：** APPROVED，Founder 于 2026-10-15 17:06 +0800（Asia/Shanghai）在会话中以 typed approval 确认，原话："R-9、R-10、R-11 也按推荐方案处理"。
**方案起草：** Claude，依据 `CLAUDE_CANONICAL_DATABASE_REAUDIT_REPORT_V1.3.md` §4。
**与已签名文件的关系：** 本文件是 `PRODUCTION_DATABASE_FOUNDER_DECISION_REGISTER_V1.0.md`（签名版 `ed1d5838…`）FD-2 的补充裁定，与 `FOUNDER_DECISION_ADDENDUM_V1.1_R12_R13_R14.md`（`1b6a58f5…`）并列，不修改上述任何文件。
**适用范围：** 只适用于新库。不涉及真实数据，不批准真实数据导入、生产切换或恢复任务 B。
**共同原则：**
- 默认拒绝，并写审计；
- 超级用户只用于安装和 Migration，不用于日常业务操作；
- 依赖 FD-6（应用鉴权）或 FD-7（运维）的部分，继续保持 HOLD。

## D-9 · 拒绝审计不能被回滚抹除（R-9）

1. **数据库侧：双写审计。** 每一次写入判定（允许或拒绝），除了写入 `audit.access_events` 外，还要以 `RAISE LOG` 写一条结构化日志。PostgreSQL 服务器日志不随事务回滚，所以客户端回滚抹不掉它。
2. **日志格式：** 固定前缀 `PHOENIX_AUDIT`，后接动作、资源类型、资源 ID、判定、原因代码、principal ID、后端 PID 和时间。**只写 ID 和代码，不写姓名、联系方式、文件内容或任何口令。**
3. **对账：** 提供只读的对账方案，把服务器日志里的 `PHOENIX_AUDIT` 与 `audit.access_events` 逐条比对。日志中有、表中没有的，就是"被回滚的尝试"，作为告警线索。对账脚本只读，本阶段只做设计和本地演示。
4. **仍为 HOLD：**
   - 日志采集目的地、保留期和防篡改存储，依赖 FD-7，以及 COS 密钥轮换 SR-7；
   - 网关侧请求级审计，依赖 FD-6。

## D-10 · 引导与管理接口（R-10）

1. **INTERNAL 服务上下文可以不绑定家庭。** 当渠道为 `INTERNAL` 且主体为 SERVICE 时，`family_id` 允许为空，只能用于"创建家庭"和下面列出的管理操作。凡是作用于某个家庭内部的操作，仍然必须绑定那个家庭。这样，首个家庭可以经 API 创建，不再需要虚设家庭。
2. **服务主体只能在安装时创建。** SERVICE 主体的创建、停用，只能由安装或运维流程以 migrator 或 bootstrap 执行，必须写审计，且不对 app 开放。
3. **管理接口：** 全部为 `SECURITY DEFINER`，只允许 INTERNAL 渠道的 SERVICE 主体调用，默认拒绝，并写审计（同时适用 D-9 的双写）：
   - 案件：创建、关闭 `casework.cases`；
   - 顾问分配：建立、撤销；
   - 监护授权：建立和撤销。`VERIFIED` 必须附证据引用并记录核验人；`SELF_DECLARED_LEGACY` **不能**经 API 新建，只留给以后另批的旧数据对账；
   - 渠道授权：建立、撤销，按授权对象逐一建立；
   - 登录主体：为 FAMILY / ADVISOR / CHANNEL 建立和停用登录主体，每个主体必须对应一个自然人。
4. **D-12 民事能力的设定**，同样由这组管理接口承担（已在 D6 中实现）。
5. **超级用户：** 日常业务不得再以超级用户直接写入。测试夹具改为通过上述 API 建立数据；Migration 和安装流程除外。
6. **双人复核：** 管理操作暂不要求双人复核。以后如需对监护授权等高风险操作引入，另行决定。

## D-11 · 服务主体不占用自然人主数据（R-11）

1. **`auth.principals.person_id` 改为：** SERVICE 主体为空，其他主体必须非空。用 CHECK 约束 `(principal_kind = 'SERVICE') = (person_id IS NULL)` 强制。SERVICE 主体另设服务名称字段（例如 `service_label`）。
2. **INTERNAL 上下文中，`actor_person_id` 为空。** 审计和各表的操作人记录改为记 principal：例如提交清单、状态事件中的操作人字段，在服务操作时记录服务主体，而不是虚构一个自然人。具体字段设计由实现方提出，复审时核对。
3. **校验规则：** 签发和绑定上下文时，`INTERNAL` 渠道要求 SERVICE 主体且 `actor_person_id` 为空；其他渠道要求 `actor_person_id` 与主体对应的自然人一致（维持现状）。
4. **合同修订：** `CANONICAL_BUSINESS_CONTRACT_V1.0_EFFECTIVE.md` 中"A principal may reference one Person"一句，按本条解释为："FAMILY / ADVISOR / CHANNEL 主体必须对应且仅对应一个自然人；SERVICE 主体不对应自然人。"`core.people` 仍是唯一的自然人主数据。合同文件本身不改动，以本补充为准。
5. **测试数据：** 现有测试中作为服务主体的合成自然人（如 "Synthetic Service"）在新测试中改用无自然人的 SERVICE 主体。没有真实数据需要迁移。

## 实施与验收要求（交给 Codex）

- **只新增 Migration：** 在 0011 之后新增 0012 及以后的编号；不修改 0001–0011。所有新函数：固定 `search_path`，撤销 PUBLIC 执行权，只授予需要的角色，默认拒绝，审计双写。
- **D-9：**
  - 回滚后，服务器日志中仍能找到对应的 `PHOENIX_AUDIT` 行（用一次性容器的 `docker logs` 或日志文件取证）；
  - 日志中没有姓名或口令；
  - 对账演示能识别出被回滚的尝试。
- **D-10：**
  - INTERNAL 服务不绑定家庭也能创建首个家庭；
  - 未绑定家庭时，家庭内操作被拒绝；
  - 管理接口逐项做正反例测试：非 SERVICE 主体调用、跨家庭操作、`SELF_DECLARED_LEGACY` 新建、缺少证据引用的 `VERIFIED`，都必须拒绝；
  - 测试夹具改为经 API 建立。
- **D-11：**
  - SERVICE 主体无自然人记录；
  - 非 SERVICE 主体缺少自然人会被约束拒绝；
  - 服务操作的审计与操作人记录正确；
  - 原有全部测试在新规则下更新后通过（逐条列出改动）。
- **测试方式：** PG16 与 PG17 都要做；用分离 LOGIN 加一次性票据；合成数据；包括全新集群恢复。

## 批准记录

- 批准人：Founder
- 时间：2026-10-15 17:06 +0800（Asia/Shanghai）
- 方式：会话中的 typed approval，原话："R-9、R-10、R-11 也按推荐方案处理"
- 记录人：Claude（只记录，不代为决定）
- 本文件 SHA-256：见 `evidence/approved/FOUNDER_DECISION_ADDENDUM_V1.2_APPROVAL.md`
