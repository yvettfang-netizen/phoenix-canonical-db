# Claude 复审报告 V1.4：Codex V1.3 第一批（D1–D4 机制项）

**复审时间：** 2026-10-16 10:00–10:20 +0800
**对象：** Codex 提交 `8ecc77c`、`a93ce1a`、`f41a183`，以及 `FIX_EXECUTION_REPORT_V1.3.md`
**方式：** 只读复核，加本地只读查询。没有重建数据卷，没有连接腾讯服务器，没有使用生产密钥。
**本机限制：** 本机没有 pwsh，Codex 的 `.ps1` 验收脚本无法在本机重跑。D3 依据 Codex 的原始输出和代码差异判断，下表标为 VERIFIED-EVIDENCE。

## 1. 独立核对

| 项 | 我做的核对 | 结果 |
|---|---|---|
| D1 / R-8 | PG16、PG17 开发库：账本行数、0010 哈希、reader / app / binder 的 schema 与表权限、业务行数 | 两库账本均为 10 行，最后一条是 `0010_reader_ledger_usage.sql`，哈希 `eb05a55b…` 与文件一致。reader：USAGE 有，SELECT 有，CREATE 无，INSERT 无。app、binder 均无 USAGE。业务行数为 0。**PASS** |
| D2 / R-15 | 本机（`core.autocrlf=true`）执行 `git archive HEAD`，解包后逐字节统计 `\r`，覆盖全部 `.sh`、`.sql`、`.yaml` 共 40 个文件 | 全部 `.sh`、全部 Migration、`deploy/tencent/*` 均为 LF。4 个部署脚本的 SHA-256 与 Codex 证据一致。**PASS**；另见 R-17 |
| D3 / R-16 | 审阅 `db.ps1` 差异，审阅两个新增 `.ps1` 测试，抽查原始输出 | `Start-Database` 写入容器 pgpass 时，增加了 backup 账号的条目；reader 本地校验改为"应有账本读权限"；守卫回归测试使用合成 `.env` 副本。**VERIFIED-EVIDENCE PASS**；另见 R-18 |
| D4 C1 / C6 / C7 | 审阅测试差异；在 `v1.3-D4-pg16/17-full.txt` 中检索断言 | 测试用真实的 app LOGIN 直接 INSERT，被拒绝（`permission denied`）。新增版本号跳号拒绝。PG16 / PG17 各出现一次 `PASS C1` 和 `PASS C6/C7`，没有 FAIL 断言。**PASS** |
| 凭据扫描 | 对 52 个变更文件扫描私钥、令牌、`PASSWORD=` 与 48 / 64 位十六进制串 | 十六进制串都是 Migration 哈希、镜像摘要、备份摘要和 `docker run -d` 返回的容器 ID，与本地凭据文件没有重合。**CLEAN** |

## 2. 新发现

| 编号 | 严重度 | 问题 | 影响 | 处理 |
|---|---|---|---|---|
| R-19 | 中 | `tests/f10_ephemeral_init.sh` 第 13 行用 `/opt/migrations/000*.sql` 匹配 Migration。 | 0010 及以后的 Migration 会被**悄悄跳过**：F10 一次性回归和全新集群恢复都测不到 0010 及以后的 Migration。D5、D6、D7 新增的 Migration 也不会被 F10 覆盖，且不会报错。Codex 报告中已注明"仅加载 0001–0009"，但没有修复。 | 下一批第一步就修，见指令 V1.4 的 E1 |
| R-18 | 低 | `Start-Database` 整体重写容器 pgpass，只保留 bootstrap 与 backup 两项。 | 任何会启动数据库的 `db.ps1` 动作之后，reader、app、binder 的本地登录条目都会丢失（本次复核时 reader 登录就因此报 `no password supplied`）。`reader_ledger_regression.ps1` 因此依赖之前先跑过 provision，单独运行会失败。 | E2 |
| R-17 | 低 | `tests/.gitattributes` 只覆盖 `f10_*.sql`。 | 另外 8 个测试 `.sql` 在本机归档里仍是 CRLF。psql 能执行，但与"导出件统一 LF"的目标不一致。另外，Codex 的归档检查只检查 shebang 行，不检查全文。 | E3 |

## 3. 结论

| 项 | 结论 |
|---|---|
| V1.3 第一批（D1、D2、D3、D4 机制项） | **PASS**，附 R-17、R-18、R-19 三项待修 |
| D4 业务探针 C2–C5、C8，以及 D5、D6、D7 | NOT_STARTED（与 Codex 报告一致） |
| 任务 B / 腾讯服务器 | PAUSED / NOT TRUSTED，未变 |
| 生产就绪 | 否 |

剩余阻断项：
- D5、D6、D7 未实施；
- R-19 修复前，F10 不能为 0010 及以后的 Migration 作证；
- EV-1 至 EV-8；
- 安全事件闸门 G-1 至 G-8；
- FD-6、FD-7 中的具体事实字段；
- F-08、F-16。

FINAL AUDIT VERDICT = HOLD
