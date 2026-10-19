# 数据库属主与 SECURITY DEFINER 安全决策 V1.0（P5）

**状态：** 决策草案，**待 Founder 决定**（`FOUNDER_DECISION_REQUIRED_V1.9` D-1）。本文件没有修改任何正式开发库的属主，也没有修改任何历史 Migration。
**PoC 范围：** 只在一次性容器（`--network none`，无端口，合成数据）中进行。
**证据：** `evidence/v1.9-owner-poc-pg16.txt`、`evidence/v1.9-owner-poc-pg17.txt`（完整 F10，退出码 0）；`evidence/v1.9-inventory-pg16.txt`（属主与权限清单）。

## 1. 现状（只读核实）

| 对象 | 数量 | 属主 | 说明 |
|---|---|---|---|
| 业务 schema 内的表 | 27 | `phoenix_bootstrap`（超级用户）| 全部 |
| 标识列序列 | 3 | 随表 | — |
| 函数 | 100 | `phoenix_bootstrap`（超级用户）| — |
| SECURITY DEFINER 函数 | 94 | `phoenix_bootstrap` | 固定 `search_path`；无动态 SQL；PUBLIC 无执行权 |
| RLS 强制（`FORCE`） | 0 张 | — | 属主绕过 RLS |

**逐函数清单：** `evidence/v1.9-secdef-functions-pg16.txt`，共 94 行，每行给出函数签名、属主、属主是否超级用户、`search_path`，以及 app / reader / binder / migrator / PUBLIC 各自是否有 EXECUTE 权限。核实结果：PUBLIC 可执行为 0，全部 94 个都有固定 `search_path`。

**实际风险：** 94 个 SECURITY DEFINER 函数以超级用户身份执行。目前没有已知的利用路径（函数体固定，参数经过类型与格式校验，没有动态 SQL），但一旦有任何一个函数存在注入、校验遗漏或逻辑缺陷，后果等同于超级用户权限。

## 2. 方案

**目标方案：**
- 新增 NOLOGIN、NOSUPERUSER、NOBYPASSRLS 的属主角色 `phoenix_canonical_schema_owner`；
- 9 个业务 schema 的表、序列、函数全部转移给它；
- 为它授予 CREATE（建函数所需）；
- 为它授予 `pg_read_all_stats`（见第 3 节，PoC 发现的必需项）。

超级用户 `phoenix_bootstrap` 保留，仅用于安装和 Migration（与现在一致）。

## 3. PoC 过程与发现（全部已修复并复测）

| 序号 | 现象 | 原因 | 处理 |
|---|---|---|---|
| P-1 | 转移时报错 `cannot change owner of sequence` | 标识列序列随表转移，不能单独 `ALTER SEQUENCE ... OWNER` | 只对表与函数转移，序列跟随表 |
| P-2 | 种子数据阶段报 `CONTEXT_BACKEND_NOT_FOUND`，所有上下文校验失败（故障关闭，安全但功能全断）| `pg_stat_activity` 只对同一会话用户或 `pg_read_all_stats` 成员可见。属主函数以属主身份执行，读不到自己的 `backend_start`（`auth.current_backend_start()` 被 RLS 与上下文校验全部依赖）| 授予属主 `pg_read_all_stats`，并且必须 `WITH INHERIT TRUE`（属主是 NOINHERIT；不带 INHERIT 时授权无效，已单独验证）|
| P-3 | 恢复阶段报 `role "phoenix_canonical_schema_owner" does not exist` | 源库的 ACL 中有对该角色的 GRANT，转储保留了它，恢复集群中没有此角色 | 恢复前先创建属主角色（测试脚本已加入条件创建）|
| P-4（运维）| 恢复后所有对象属主变回 `phoenix_bootstrap` | 三条恢复路径（测试脚本、`restore.sh`、`restore_drill.sh`）都使用 `pg_restore --no-owner` | PoC 中恢复后重新执行属主转移（脚本幂等），并检查结果；生产恢复方式见第 5 节 D-1b |

**PoC 最终结果（PG16 与 PG17 相同）：**
- 属主转移：30 个关系（27 张表 + 3 个序列）与 100 个函数全部属于 `phoenix_canonical_schema_owner`；
- 属主角色：NOSUPERUSER、NOLOGIN、NOBYPASSRLS；
- 属主继承 `pg_read_all_stats`；
- 完整 F10 通过：基线 6 套、API 播种、F10 分离 LOGIN 回归（含 7 个 D6 会话）、C1–C10、R-20（12 种组合）、G1–G5、T1–T4、0016 分配范围、0017 身份与连接池、D-9 对账（249 条日志，248 条与数据库匹配，1 条为预期的回滚记录）、不可修改回归、安装器权限、socket 认证、0009 漂移拒绝、强制失败原子回滚；
- 全新集群恢复（属主恢复后重转移）：账本 17、表 27、策略 20，恢复后的目录回归通过；
- **意外失败：0**（唯一的 FAIL 行是守卫断言的预期拒绝）。

**未测：** 属主转移 PoC 尚未通过 pwsh 路径执行；生产恢复路径；性能；迁移由属主角色执行的情况（PoC 中迁移仍由 bootstrap 执行）。普通 0001–0017 基线的 pwsh 跨路径验收已于 2026-10-19 通过，不等同于属主转移 PoC 通过。

## 4. 新方案的安全影响

| 编号 | 影响 | 评估 | 建议 |
|---|---|---|---|
| R-1 | **属主可读取其他会话的 SQL 文本**（PoC 中实测：属主可见 6 个其他会话的查询）。查询文本中可能包含一次性票据的 UUID（应用在兑换票据时的 SQL 中含票据字面量）| 中。属主是 NOLOGIN，没有任何会话直接以属主身份运行，它只在固定函数体内生效，攻击者需要先能让函数执行任意 SQL，而函数体没有动态 SQL。但这是一项新增的读取能力，必须明示 | 需要 Founder 接受此风险，或选择替代方案（见 R-1a）|
| R-1a | 替代方案：不让属主读 `pg_stat_activity`，改用其他方式获得后端启动时间 | 已尝试：未授权时 `pg_stat_get_backend_start` 同样返回 NULL（已测）；授权后的行为未单独测试。其他替代需要重新设计上下文绑定（例如由应用侧提供并验证），属于架构变更 | 作为后续设计项，不在本次批准范围 |
| R-2 | RLS 不约束属主（未设 `FORCE`）| 与现状相同：超级用户绕过 RLS，新属主也绕过。RLS 只约束 app / reader / binder | 维持现状；在文档中写明 |
| R-3 | 属主转移后，未来的迁移需要以 bootstrap 执行或以属主角色成员身份执行 | 操作性问题，不影响安全 | 迁移流程保持 install.sh 以 bootstrap 执行 |
| R-4 | 属主角色必须在恢复前存在 | 已验证（P-3）| 写入恢复手册 |
| R-5 | `--no-owner` 使恢复后属主丢失 | 已验证（P-4）；是现有的运维缺陷，与本方案无关，但本方案使其变得重要 | 见 D-1b |
| R-6 | 旧入口 `auth.bind_context` 仍可由 binder 执行（S-2）| 低：binder 只能绑定自己的后端，且 binder 无任何表权限。但它是绕过票据流程的入口 | 作为 0018 的一部分撤销执行权 |
| R-7 | **顾问可在个案关闭后读取学生基本展示信息（E-R6）** | 中（P1）：代码审读确认，`core.can_read_subject_basics` 的顾问分支不检查 `casework.cases.status`。0016 没有覆盖这条路径。属于现有缺陷，与属主方案无关 | 作为 0018 第一项修复，先写失败用例 |

## 5. 推荐的调整计划（需 Founder 批准后执行）

| 步骤 | 内容 | 执行位置 | 可回退性 |
|---|---|---|---|
| 1 | 修复 E-R6（R-7），先写失败测试 | 0018 | 向前修复 |
| 2 | 撤销 binder 对 `auth.bind_context` 的执行权（R-6）| 0018 | 可重新授予 |
| 3 | 在 install.sh（超级用户步骤，与服务主体创建同类）中创建属主角色 | install.sh | 删除角色（需无依赖）|
| 4 | 授予属主 CREATE 与 `pg_read_all_stats WITH INHERIT TRUE`（若接受 R-1）| install.sh | 撤销授权 |
| 5 | 转移 27 张表、3 个序列、100 个函数的属主 | 0018（或安装步骤，需决定）| `ALTER ... OWNER TO phoenix_bootstrap` 可逆；回退也可从备份恢复 |
| D-1b | **恢复方式：** 去掉 `--no-owner`，并保证恢复前属主角色存在；恢复后执行属主检查 | restore.sh、restore_drill.sh | 需要重新演练 |
| 6 | 验证：F10 完整回归（PG16 / PG17）、全新集群恢复、E-R6 测试、属主不能登录、app 不能 ALTER OWNER、app 不能在业务 schema 建对象 | 测试 | — |

**回退方案：** 属主转回 `phoenix_bootstrap`，撤销 `pg_read_all_stats`，恢复 binder 的 `bind_context` 执行权（若需要）。最终回退是从变更前的已校验备份在新卷上恢复（见 `08` 情形 C）。

## 6. 推荐结论

1. **批准方向：** 将属主从超级用户转移到非超级用户的 NOLOGIN 角色。理由：94 个 SECURITY DEFINER 函数以超级用户执行是比 R-1 更大的风险；PoC 表明功能行为不变（F10 全部通过）。
2. **前置条件：** 先完成 R-7（E-R6）与 R-6（bind_context）的修复，并写出对应的失败测试。
3. **需要明示接受的风险：** R-1（属主可读其他会话的 SQL 文本）。如果不接受，则保持现状，并把"属主为超级用户"写入风险登记，作为待办。
4. **恢复方式必须同步修改**（D-1b）。否则恢复后的库会失去属主模型。
5. 在 Founder 批准之前，**不修改任何正式开发库或腾讯环境的属主**。

## 7. 其他工程项（非属主，但在本决策范围内登记）

| 项 | 状态 | 说明 |
|---|---|---|
| pwsh 属主转移 PoC | NOT RUN | 普通 0001–0017 基线的 pwsh 验收已通过；`F10_OWNER_TRANSFER=1` 的属主转移路径仍未通过 pwsh 执行 |
| 125 个历史匿名测试卷 | 未处理 | 只含合成数据。**不执行无范围限制的 `docker volume prune`**；如需清理，应列出具体的卷名后逐一删除，并经 Founder 批准 |
