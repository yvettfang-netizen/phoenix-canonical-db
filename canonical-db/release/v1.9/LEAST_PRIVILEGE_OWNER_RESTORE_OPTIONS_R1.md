# 最小权限属主与恢复方式比较 R1（V1.9-R1 P2）

**结论：** 本轮比较四个属主方案。只有方案 B（非超级用户的 NOLOGIN 属主 + `pg_read_all_stats WITH INHERIT TRUE`）在 PG16 与 PG17 上通过了完整 F10；它的代价是 R-1（属主可读取其他会话的 SQL 文本）。
**`pg_restore --no-owner` 在本轮不得移除。** 去掉它之前，必须先完成第 4 节列出的验证，而这些验证**本轮 NOT RUN**。
测试通过不等于生产安全；本文件不把隔离容器的结果当作生产结论。

## 1. 现状（VERIFIED，源码与开发库只读核实）

- 27 张表、3 个标识列序列、100 个函数（94 个 SECURITY DEFINER）的属主都是超级用户 `phoenix_bootstrap`。
- 94 个 SECURITY DEFINER 函数全部有固定 `search_path`，PUBLIC 无执行权（`evidence/v1.9-secdef-functions-pg16.txt`）。
- 三条恢复路径（`tests/f10_ephemeral_restore.sh`、`deploy/tencent/restore.sh`、`restore_drill.sh`）都使用 `pg_restore --no-owner`。

## 2. 四个方案

| 方案 | 描述 |
|---|---|
| **A** 维持现状 | 属主为超级用户；94 个 SECURITY DEFINER 函数以超级用户执行 |
| **B** 非超级用户 NOLOGIN 属主 | `phoenix_canonical_schema_owner`：NOSUPERUSER、NOLOGIN、NOBYPASSRLS；授予 CREATE；授予 `pg_read_all_stats WITH INHERIT TRUE, SET FALSE`；转移 27 张表、3 个序列（随表）、100 个函数 |
| **C** 与 B 相同，但不授予 `pg_read_all_stats` | 纯最小权限 |
| **D** 重新设计绑定机制，不依赖 `pg_stat_activity` | 例如由服务端另行验证后端启动时间。**未设计，未验证** |

## 3. 比较

| 维度 | A 维持超级用户 | B 非超级 NOLOGIN 属主 | C 不授予 pg_read_all_stats | D 重新设计绑定 |
|---|---|---|---|---|
| F10 兼容（PG16）| 通过（现行基线）| **通过**（`evidence/v1.9-owner-poc-pg16.txt`，`F10_OWNER_TRANSFER=1`）| **失败**：`CONTEXT_BACKEND_NOT_FOUND`，全部上下文校验失败（PoC P-2，已记录）| 未验证 |
| F10 兼容（PG17）| 通过 | **通过**（`evidence/v1.9-owner-poc-pg17.txt`）| 未单独测试（PG16 已失败，结论相同）| 未验证 |
| 会话隔离 | 超级用户可读全部 | 属主可读 `pg_stat_activity` 中其他会话的查询文本（PoC 实测：6 个其他会话）| 同 B 的读取能力被移除 | 视设计 |
| 票据泄露风险 | 票据 UUID 已在超级用户的视图中 | **R-1**：查询文本中可能含票据 UUID（应用在兑换时的 SQL 字面量）。利用需要先让函数执行任意 SQL，而函数体无动态 SQL | 同 C 不适用 | 视设计 |
| RLS 与 SECURITY DEFINER 兼容 | 超级用户绕过 RLS | 属主绕过 RLS（未设 FORCE）。与现状行为相同。F10 的 RLS 断言全部通过 | 不适用 | 视设计 |
| 备份/恢复的属主一致性 | 恢复后属主变为恢复执行者（`--no-owner`），与现状相同 | **恢复后属主丢失**（PoC P-4）；必须先创建属主角色（PoC P-3）| 同 B | 视设计 |
| 替换 `--no-owner` 所需的改动 | 无 | 需要恢复前建角色、恢复后检查属主与 ACL（见第 4 节）| 同 B | 同 B |
| 风险等级（本轮判断）| 94 个 SECURITY DEFINER 函数以超级用户执行，**比 R-1 更大** | R-1 中等，需要明示接受 | 未通过 F10，不可用 | 架构变更，另立项 |

**不能作为结论的测试：** 方案 B 的 F10 通过只说明功能行为未变，不说明生产安全。生产环境的属主迁移仍需经过 D-1、D-1b 的批准。

## 4. 恢复方式（D-1b）：去掉 `--no-owner` 之前必须验证的事项

| 验证项 | 内容 | 状态 |
|---|---|---|
| 目标角色预创建 | 恢复前在目标集群创建属主角色，以及 dump 中引用的全部角色（app、reader、binder、migrator、backup、属主）| **NOT RUN**（已有 PoC 记录：缺少属主角色会在 GRANT ACL 阶段失败，PoC P-3）|
| 恢复后的属主 | 去掉 `--no-owner` 后，表、序列、函数的属主应为属主角色 | **NOT RUN** |
| 恢复后的权限（ACL）| 与源库逐项比对 `has_table_privilege` / `has_function_privilege` | **NOT RUN** |
| `owner_transfer_check.sql` | 恢复后直接运行，不需要重新转移 | **NOT RUN** |
| 失败路径 1：属主角色缺失 | 应当 fail closed（`pg_restore --exit-on-error` 返回非零），不得部分成功 | **NOT RUN**（PoC 观察到错误，但未在去掉 `--no-owner` 的条件下测试）|
| 失败路径 2：属主角色存在但 NOINHERIT、无 `pg_read_all_stats` | 应当被 `owner_transfer_check.sql` 捕获 | **NOT RUN** |
| 失败路径 3：目标是 PG16 备份恢复到 PG17（或反向）| 版本兼容性 | **NOT RUN** |
| 恢复后的 F10 回归 | 完整套件通过 | **NOT RUN**（只在方案 B 批准后执行）|

**计划的验证脚本（未编写）：** 在一次性容器中（源库与目标库各一个），源库执行迁移 + 属主转移，`pg_dump -Fc` 生成 dump；目标库先创建全部角色，再执行 `pg_restore`（不带 `--no-owner`），然后运行检查。失败路径用单独的目标库构造。

## 5. 建议

1. **维持 `--no-owner`**，直到第 4 节全部为 VERIFIED。
2. 若 Founder 接受 R-1，则选择**方案 B**，并把"恢复前建角色、恢复后检查"写入 `restore.sh` 与 `restore_drill.sh` 的设计，**作为 D-1b 的一部分批准后再实施**。
3. 若 Founder 不接受 R-1，则**维持方案 A**，并在风险登记册中记录"属主为超级用户"为待办。
4. 方案 C 不可用。方案 D 需要另立项，不属于 0018。
5. 本轮不修改任何开发库、腾讯环境或恢复脚本的属主设置。

## 6. 与其他文件的关系

- 风险 R-1、R-5（`--no-owner` 丢失属主）、D-1、D-1b：见 `DATABASE_OWNER_SECURITY_DECISION_V1.0.md` 与 `FOUNDER_DECISION_REQUIRED_V1.9.md`。
- 0018 的属主相关范围：**不包含**（见 `MIGRATION_0018_READINESS_DECISION_R1.md`）。
