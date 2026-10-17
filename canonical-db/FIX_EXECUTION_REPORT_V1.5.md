# Phoenix Canonical PostgreSQL — V1.5 第三批本地执行报告

**结论：D5（D-11 → D-10 → D-9）与 R-20 = PASS（本地合成验收）；Claude 复审 = PENDING。任务 B = PAUSED。** 本批没有连接腾讯云，没有部署、push、merge 或创建 PR，没有使用真实数据或生产凭据。

## 依据、边界与提交

- 执行依据：`phase2-gate/CODEX_INSTRUCTION_V1.5_NEXT.md`、`phase2-gate/FOUNDER_DECISION_ADDENDUM_V1.2_R9_R10_R11.md`。
- 开工前核验的 V1.2 完整 SHA-256：`925c83f4d079ec6a1fd9d211786a961d988eaf0d0f033547f1e5ba485552616e`，与指令一致。
- 实现与原始证据提交：`4a9a29e63186212d1572781c07c3c3c0e9000a58`。
- `0001`–`0011` 未修改；`evidence/v1.5-final-state.txt` 保存了分支、哈希、旧 Migration 差异和测试命令摘要。

## 新 Migration

| Migration | 内容 | SHA-256 |
|---|---|---|
| `0012_service_principal_and_context.sql` | SERVICE 不对应自然人；INTERNAL actor 可为空；按 principal 判断内部服务；状态事件与提交清单记录 principal；R-20 主体类型与渠道对应；票据兑换时重校验 | `385206d698db33cd6a26b7ea48ab5362f2fa2e4256ec96740c336429ad54afa8` |
| `0013_management_write_api.sql` | 无家庭绑定的 SERVICE 创建首个家庭；installer-only SERVICE 生命周期；案件、顾问分配、监护授权、渠道授权、登录主体管理 API；操作 principal 归属字段 | `fcbeeea5b8fc35c0993b7b7b9dbe956fd0c6edc4a6142e49cb329fad41a320cb` |
| `0014_rollback_resistant_write_audit.sql` | 每次写判定写入固定前缀 `PHOENIX_AUDIT` 服务器日志与数据库审计表；以 `attempt_id` 对账事务回滚后的日志独有记录 | `92328ac4bf51b54980da63e96681220437ac20e4557fc008ab51431793ba4209` |

## 分项验收

| 要求 | 实际结果 | 原始证据 | 状态 |
|---|---|---|---|
| D-11 服务主体 | SERVICE 的 `person_id` 必须为空，其他主体必须有自然人；INTERNAL 上下文 actor 为空；`auth.is_internal_service()` 按 principal 判定。服务提交清单及状态事件保存 principal。约束正反例和 installer-only 创建/停用通过。 | `evidence/v1.5-f10-pg16.txt`、`v1.5-f10-pg17.txt` 中 `PASS D11 person-kind...` 与 G3 | PASS |
| D-10 引导和管理接口 | 无家庭绑定 SERVICE 通过一次性票据创建首个家庭；未绑定时家庭内操作拒绝。案件、分配、监护、渠道、登录主体 API 的创建/关闭/撤销/停用正例通过；非 SERVICE、跨家庭、`SELF_DECLARED_LEGACY`、缺证据均拒绝。合成夹具经 API 创建，bootstrap 仅创建数据库 LOGIN 和安装 SERVICE。 | 两版 F10 的 `PASS C3`、`PASS D10 management lifecycle`、seed 输出及拒绝探针 | PASS |
| D-9 回滚抗性审计 | PG16/17 均生成 170 条结构化服务器日志；169 条与数据库 `attempt_id` 对应，1 条为客户端回滚后仅存在于日志的拒绝记录。日志字段仅含 ID、动作、资源、判定、原因、principal、PID 和时间。 | `evidence/v1.5-audit-log-pg16.txt` / `pg17.txt`、`v1.5-audit-db-ids-*`、`v1.5-audit-reconcile-*` | PASS |
| R-20 | 允许映射固定为 FAMILY→FAMILY、ADVISOR→ADVISOR、CHANNEL→PARTNER、SERVICE→INTERNAL。其余 12 种组合逐一签发票据，全部以 `CONTEXT_PRINCIPAL_CHANNEL_MISMATCH` 拒绝。 | 两版 F10 中 12 行 `PASS R20 ...`；永久脚本 `tests/f10_v15_channel_kind.sh` | PASS |
| C2 新期望 | 家庭 B 的跨家庭写判定在事务回滚后，数据库审计行数为 0；对应 `PHOENIX_AUDIT` 仍在服务器日志，并由只读对账识别为 `ROLLED_BACK_ATTEMPT`。提交控制组保留 1 条数据库拒绝审计。 | `claude_f10_reaudit_probes.sh` + `f10_audit_reconcile.ps1`；两版对账输出 | PASS |
| C3 新期望 | 无家庭绑定的 SERVICE 创建首个家庭；SERVICE 主体没有 `core.people` 记录。两项均为永久断言。 | 两版 F10 的 `PASS C2/C3...` 与 `f10_seed_unbound.sql` | PASS |
| G1–G5 | G1 无 DECISION 事实拒绝、有事实后允许；G2 家庭记录官方事实拒绝；G3 家庭确认后 SERVICE 提交，确认人和提交 principal 均有归属；G4 确认后 API 加条目以确认锁原因拒绝；G5 顾问确认拒绝。 | `tests/f10_v15_gap_regression.sh`；两版输出 `PASS permanent G1-G5...` | PASS |
| PG16 / PG17 和恢复 | 两版均在 `--network none` 一次性源集群运行 0001–0014、重复执行、库存缺失/额外拒绝、漂移拒绝、原子回滚、分离 LOGIN 与一次性票据测试。专用 backup LOGIN 导出后，在全新集群校验摘要并恢复为 14 条账本、26 张表、20 条 RLS 策略，基线套件通过；一次性容器和卷已清理。 | `evidence/v1.5-f10-pg16.txt`、`v1.5-f10-pg17.txt` 及 invocation 输出 | PASS |

## D-9 对账演示原始输出

PG16：

```text
LOG_ATTEMPTS=170
PERSISTED_MATCHES=169
LOG_ONLY_ATTEMPTS=1
ROLLED_BACK_ATTEMPT attempt_id=2be11afa-d127-41eb-8999-e87dda2da09c action=CREATE resource_id=018f0000-0000-7000-8000-000000009902 decision=DENY reason=FAMILY_ADVISOR_CONSENT_OR_INPUT_DENIED
PASS D9 log/database read-only reconciliation identified client rollback
```

PG17：

```text
LOG_ATTEMPTS=170
PERSISTED_MATCHES=169
LOG_ONLY_ATTEMPTS=1
ROLLED_BACK_ATTEMPT attempt_id=a17f5fe4-aa82-4f4f-be2a-2a4bebb3e385 action=CREATE resource_id=018f0000-0000-7000-8000-000000009902 decision=DENY reason=FAMILY_ADVISOR_CONSENT_OR_INPUT_DENIED
PASS D9 log/database read-only reconciliation identified client rollback
```

## 受影响旧测试的逐条改动

| 旧文件 | 改动 |
|---|---|
| `tests/f10_ephemeral_init.sh` | 默认 Migration 数从 11 更新为 14；继续断言执行文件数 = 目录文件数 = 账本行数。 |
| `tests/f10_ephemeral_restore.sh` | 恢复账本断言从 11 更新为 14；表数保持 26、策略数保持 20。 |
| `tests/f10_local_acceptance.ps1` | E1 分段改为暂存 0011–0014；额外/缺失反例使用 0015/0014；加入 R-20、G1–G5、D-9 对账和 SERVICE schema 正反例；PG16/17 证据使用 v1.5 文件名。 |
| `tests/f10_ephemeral_seed.sh` | 删除 bootstrap 对业务表的直接 INSERT；bootstrap 只建立分离 LOGIN 和 installer SERVICE；家庭、自然人、主体、案件、分配、监护与渠道授权全部经一次性票据和管理 API 建立。 |
| `tests/f10_ephemeral_regression.sh` | SERVICE 会话 actor 改为空；新增 app 无权安装 SERVICE、管理生命周期正反例；监护证据测试改用分离 LOGIN 和票据。 |
| `tests/claude_f10_reaudit_probes.sh` | SERVICE actor 改为空；C2 固化“数据库回滚、服务器日志保留”的两段断言；C3 固化无家庭 SERVICE 创建首个家庭且无自然人记录。 |
| `tests/f10_service_regression.sql` | 移除绑定 SERVICE 创建家庭和把 SERVICE 加入家庭成员的旧假设；增加跨家庭管理 API 拒绝。 |
| `tests/f10_family_create_regression.sql` | 增加 FAMILY 主体调用全部管理 API 的拒绝测试。 |
| `tests/f10_guardian_evidence_regression.sql` | 删除 bootstrap 直接写夹具；通过 API 断言 legacy 和缺证据拒绝、VERIFIED 创建、撤销及新记录替换。 |

新增的永久测试为 `f10_v15_channel_kind.sh`、`f10_v15_gap_regression.sh`、`f10_v15_management_lifecycle.sql`、`f10_v15_schema_installer.sql`、三个 API seed 文件，以及只读 `f10_audit_reconcile.ps1`。

## 保留边界

- D-9 的日志采集目的地、保留期、防篡改存储及网关审计继续依赖 FD-7/FD-6，本批未自行决定。
- 双人复核按 V1.5 指令留到真实数据导入前，本批未实现。
- 本地 PASS 不代表已部署或生产可用；腾讯任务 B 继续 PAUSED。
