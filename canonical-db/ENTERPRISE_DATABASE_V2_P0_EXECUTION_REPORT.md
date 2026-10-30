# Phoenix Canonical PostgreSQL V2.0 — P0 执行报告

执行日期：2026-10-30  
分支：`codex/canonical-enterprise-v2-core`  
基线：`48bb6c3ae18906f870ea9e8a717c03ebb2da34bd`  
结论：**P0 ENTERPRISE CORE = PASS（本地隔离开发）**

## 1. 实际完成

- 重新 fetch 私有远端，确认 `canonical-private/codex/canonical-postgresql-phase1` 仍为 `48bb6c3`，实际最大 Migration 为 `0025`。
- 新建独立工作树与分支，没有修改 `0001–0025`。
- 新增 `0026_enterprise_core_organization_client.sql`：
  - 保留 `core.people`、`core.families`、`core.student_profiles` 为唯一权威主数据；
  - 将旧家庭成员永久唯一约束在同一事务内替换为非重叠有效期约束，允许关系结束后重新建立且保留历史；
  - 新增 `core.organizations`，机构类型使用受控词表；注册编号只保存 SHA-256 摘要，不保存明文；
  - 新增 `crm.clients`，`client_id` 继续通过强制外键映射 `family_id`；同时有效的家庭客户关系唯一，结束历史保留；
  - 指定 SERVICE 标签 `canonical_enterprise_v2_core`，只允许一次性票据绑定的 INTERNAL 上下文调用受控写函数；
  - 普通 app、reader、binder 没有 Organization / Client 表的直接读写权限；PUBLIC 无函数执行权限；
  - 所有允许和拒绝结果写入既有受保护审计机制。
- 更新 Migration Runner、F10、fresh restore、owner/security catalog 和本地备份零记录检查，使 `crm` 纳入永久门禁。
- 将 `0026` 前向应用到现有本地 PG16 与 PG17 开发库；旧 Migration 全部 checksum-verified SKIP，未重置数据卷。

## 2. Migration

| 文件 | SHA-256 |
|---|---|
| `0026_enterprise_core_organization_client.sql` | `aad3a52829404e1259d89a9751471af7d0f1322af710d498bb2498c5be7119d5` |

Catalog：26 条 ledger、52 张业务表、43 条 RLS policy。

## 3. 实际验收

执行命令：

```powershell
pwsh -NoProfile -File .\tests\f10_local_acceptance.ps1 -Version 16
pwsh -NoProfile -File .\tests\f10_local_acceptance.ps1 -Version 17
pwsh -NoProfile -File .\scripts\db.ps1 -Action migrate -Version 16
pwsh -NoProfile -File .\scripts\db.ps1 -Action migrate -Version 17
```

PG16 与 PG17 均实际通过：

- 全新初始化 `0001–0026`；
- 重复执行 checksum 验证；
- 多余/缺失 Migration 拒绝；
- 旧 Migration 漂移拒绝；
- 强制失败后的原子回滚；
- 分离 app / binder LOGIN 与一次性票据；
- 同一 Person 同时属于两个 Family；
- 同一家庭、同一 Person 的重叠关系拒绝；
- 关系结束后重新建立并保留两段历史；
- Organization 重复主数据拒绝；
- 注册号明文列不存在；
- 同一家庭重复有效 Client 拒绝；
- Client 结束后可建立新的有效关系；
- 跨家庭、错误 SERVICE、直接表写入拒绝；
- 专用备份账号导出、dump 摘要校验和全新集群恢复；
- 恢复后 ledger/table/policy = `26/52/43`，0026 ACL 与历史约束再次通过。

原始输出保存在本机忽略目录：

- `evidence/v2.0-0026-pwsh-f10-pg16.txt`
- `evidence/v2.0-0026-pwsh-f10-pg17.txt`

原始 transcript SHA-256：

- PG16：`b6d90a827611e986183f5ad2090d4f790c93da9c696ecfea6cf3a9dbfd9a3279`
- PG17：`c5b057a967db42bb0f859de3076e711f9edec96d16f913126aebdfd449980bc5`

测试使用纯合成数据；一次性容器、卷和临时凭据已由测试脚本清理。

## 4. 边界与 HOLD

- 没有连接腾讯云、生产数据库或生产密钥。
- 没有导入真实客户、医疗、财务、Feishu 或旧数据库数据。
- 没有重置现有 PostgreSQL 数据卷。
- 没有部署、合并或创建 PR。
- CRM P1、Service P2、Finance P3、Health P4 不计入本报告的 PASS。
- Organization 注册号摘要、Client 生命周期与未来真实数据治理在生产启用前需要白虎复核。

`HANDOFF_REQUIRED: 白虎｜守正关（生产数据分类、保留与注册编号治理）`

