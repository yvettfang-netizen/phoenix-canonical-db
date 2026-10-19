# 03 · PG16 / PG17 完整测试矩阵

**版本：**
- PostgreSQL 16.15：`postgres:16@sha256:ca0bd484cb98bf4b24eb1010e73fb3fcbd6714d240fbc1a10eea5b7dbecb641d`
- PostgreSQL 17.11：`postgres:17@sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3`

**环境：** Windows 11 + Docker 29.8.2；git-bash 与 PowerShell 7.6.5 两条验收路径。每轮测试都在一次性容器中进行（`--network none`，没有端口映射，合成凭据，结束即清理）。
**代码基线：** `c5e81e6`（0001–0017）；PowerShell 交叉验收与证据提交 `072ea74`。
**数据：** 只用合成数据。

## 1. 测试套件与结果

| # | 套件 | 覆盖 | 命令 | PG16 | PG17 | 证据 |
|---|---|---|---|---|---|---|
| 1 | Migration 顺序与守卫 | 先装 0001–0010，再装其余；重复执行逐个校验摘要；多一个文件、缺一个文件、未编号文件，三种情况都被拒；漂移被拒；原子回滚 | `tests/f10_local_acceptance.sh <16\|17>` | PASS | PASS | `evidence/v1.8-f10-sh-pg16.txt` / `-pg17.txt` |
| 2 | 基线 6 套 | foundation、rls_probe、docs_probe、contract_neutral、trusted_context、phase3_acceptance | 同上 | PASS | PASS | 同上 |
| 3 | API 播种 | bootstrap 只建 LOGIN 和安装器服务主体，业务数据全部经 API 建立 | 同上 | PASS | PASS | 同上 |
| 4 | F10 分离 LOGIN 回归 | 家庭 / 顾问 / 渠道 / 服务会话；D6（D-12 / 13 / 14）；D-10 管理接口全生命周期；监护证据 | 同上 | PASS | PASS | 同上 |
| 5 | C1–C10 探针 | 直接写表被拒；回滚后审计在日志中留存；C3 无家庭服务；C4 / C5 / C8 | 同上 | PASS | PASS | 同上 |
| 6 | R-20 | 12 种主体类型 / 渠道不匹配组合 | `tests/f10_v15_channel_kind.sh` | PASS | PASS | 同上 |
| 7 | G1–G5 | 官方事实前提；家庭录入事实被拒；确认人 ≠ 提交人；确认锁；顾问确认被拒 | `tests/f10_v15_gap_regression.sh` | PASS | PASS | 同上 |
| 8 | T1–T4 | 成员关系、改名；顾问读文件须有分配；文档撤回；身份案件提前结案 | `tests/f10_v16_contract_gaps.sh` + 文档触发器 | PASS | PASS | 同上 |
| 9 | 0016 分配范围 | 个案关闭后读写被拒；资源与个案主体一致；重复授权返回审计拒绝 | `tests/f10_v17_assignment_scope.sh` | PASS | PASS | 同上 |
| 10 | 0017 / FD-6 | 外部身份映射；请求编号进入审计行和日志行；连接池符合性；事务级连接池隐患 | `tests/f10_v18_identity_pool.sh` | PASS | PASS | 同上 |
| 11 | D-9 对账 | 日志 249 条，与数据库对上 248 条，仅在日志中 1 条（预期的回滚）；日志中没有名称；请求编号在日志行中 | 同 #1 | PASS | PASS | 同上 |
| 12 | 不可修改与安装器 | D6 不可改写；D-11 安装器只能创建 / 停用 | 同 #1 | PASS | PASS | 同上 |
| 13 | 认证 | 不带口令的 socket 被拒；pg_hba 全部为 scram | 同 #1 | PASS | PASS | 同上 |
| 14 | 全新集群恢复 | backup LOGIN 导出 → 新集群恢复：账本 17、表 27、策略 20；9 个恢复后套件 | 同 #1 | PASS | PASS | 同上 |
| 15 | 升级路径 0006→0017 | 带合成数据；预检报出阻断；0012 整体回滚；修正后升级成功，数据保持 | `tests/upgrade_path_acceptance.sh <16\|17>` | PASS | PASS | `evidence/v1.8-upgrade-path-pg16.txt` / `-pg17.txt` |
| 16 | 开发库顺序升级 | 0011→0016→0017（每次先跑预检） | 见证据 | PASS | PASS | `evidence/v1.7-dev-db-upgrade.txt`、`v1.8-dev-db-upgrade.txt` |
| 17 | 安全目录审计 | 角色、成员关系、schema / 表 / 函数权限、RLS、属主、pg_hba、默认权限 | `tests/security_catalog_audit.sql` | PASS（S-1 待决定） | PASS（S-1 待决定） | `evidence/v1.8-security-catalog-pg16.txt` / `-pg17.txt` |
| 18 | 部署包加运维全流程演练（14 步） | 安装（幂等）、健康检查、运行账号 API 写入、备份与校验、恢复与篡改拒绝、保留期清理、恢复演练、审计链、告警、篡改检测、口令日志加固 | `tests/deploy_package_rehearsal.sh <dir>` | PASS | 不适用：部署包固定使用 PG16 | `evidence/v1.8-deploy-rehearsal.txt` |
| 19 | 独立复核（Claude 探针） | V1.5 / V1.6 收尾复跑；P1–P3 缺陷发现 | `evidence/claude-v1.6-closeout-run_f10.sh` | PASS，发现 3 项缺陷（已由 0016 修复） | 同左 | `evidence/claude-v1.6-closeout-pg16.txt` / `-pg17.txt` |
| 20 | PowerShell 跨路径验收 | F10、缺陷回归、SCRAM、全新集群恢复；覆盖 0016 / 0017 | `tests/f10_local_acceptance.ps1`、`tests/phase3_*.ps1` | PASS | PASS | `evidence/v1.9-pwsh-*.txt`；`release/v1.9/PWSH_CROSS_ACCEPTANCE_REPORT_V1.0.md` |

**断言总数**（`PASS` 行，含各套件内部的 NOTICE）：PG16 228，PG17 228；意外 FAIL 为 0。

## 2. 未运行与未验证的项目

| 项 | 状态 | 原因 |
|---|---|---|
| 部署包 PG17 版本 | 不适用 | 部署包按批准固定为 PG16 |
| 真实数据、真实对象存储、腾讯环境 | NOT RUN / HOLD | 不在授权范围内（见 `09`） |
| 性能、并发压测 | NOT RUN | 不在已批准的需求范围内；空库阶段没有基线 |

## 3. 复现

```bash
cd canonical-db
bash tests/f10_local_acceptance.sh 16 evidence/<name>-pg16.txt
bash tests/f10_local_acceptance.sh 17 evidence/<name>-pg17.txt
bash tests/upgrade_path_acceptance.sh 16 evidence/<name>-upgrade-pg16.txt
bash tests/upgrade_path_acceptance.sh 17 evidence/<name>-upgrade-pg17.txt
bash tests/deploy_package_rehearsal.sh "$(pwd)/runtime/rehearsal" evidence/<name>-rehearsal.txt
```

PowerShell 路径：

```powershell
pwsh -NoLogo -NoProfile -File tests/f10_local_acceptance.ps1 -Version 16
pwsh -NoLogo -NoProfile -File tests/f10_local_acceptance.ps1 -Version 17
pwsh -NoLogo -NoProfile -File tests/phase3_defect_regression.ps1 -Version 16
pwsh -NoLogo -NoProfile -File tests/phase3_defect_regression.ps1 -Version 17
pwsh -NoLogo -NoProfile -File tests/phase3_pg_hba_auth_regression.ps1 -Version 16
pwsh -NoLogo -NoProfile -File tests/phase3_pg_hba_auth_regression.ps1 -Version 17
pwsh -NoLogo -NoProfile -File tests/phase3_fresh_cluster_restore.ps1 -Version 16
pwsh -NoLogo -NoProfile -File tests/phase3_fresh_cluster_restore.ps1 -Version 17
```

**前提：**
- Docker 可用，上述两个镜像摘要已在本地缓存（脚本不拉取镜像）；
- 在 Windows 上需要 git-bash，并使用较短的工作路径（深层路径会超过 Win32 的路径长度限制）。
