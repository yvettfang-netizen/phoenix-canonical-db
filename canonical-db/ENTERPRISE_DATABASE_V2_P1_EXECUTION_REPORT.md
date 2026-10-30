# Phoenix Canonical PostgreSQL V2.0 — P1 CRM 执行报告

执行日期：2026-10-30

分支：`codex/canonical-enterprise-v2-core`

前置提交：`e5d2b6efd974a3ddfac4b4c426ce5a5e9248b7b5`
结论：**P1 CRM FOUNDATION = PASS（本地隔离开发）**

## 1. 实际完成

新增 `0027_crm_lead_deal_foundation.sql`，没有修改 `0001–0026`：

- 建立 `crm.leads`、`lead_sources`、`lead_events`、`lead_identity_links`、`consultations`、`client_relationships`、`deals`、`deal_items`、`referrals`、`follow_ups`、`campaigns`。
- Lead 在身份未核验时可以独立存在；没有姓名、电话、微信 OpenID 的自动去重或自动 Person 映射。
- Lead 身份关联使用 PENDING → 不同 CRM SERVICE 主体复核 → VERIFIED；错误关联可 REVOKE。
- Lead 合并只写 `MERGED` 和目标 Lead，不删除来源记录；合并和撤销均写不可变事件及受保护审计。
- 多个 Lead 可经独立复核映射到同一 `crm.clients`；不创建新的 Client、Family 或 Person 主表。
- Deal 强制引用现有 Client/family；primary Lead 必须先有 VERIFIED Client link。
- Deal 金额为 `NUMERIC(18,2)`；Child / Education / Family Compass 通过 Deal Item 独立归因。
- 指定 `canonical_crm_v2` SERVICE 主体，使用一次性票据；跨家庭、错误主体、未知 Client、直接表写入均 fail-closed。
- 11 张新增表全部启用并强制 RLS；app/reader/binder 无直接表权限，PUBLIC 无 CRM 函数执行权限。

## 2. 已实现与暂缓

| 能力 | 状态 |
|---|---|
| Campaign / Lead Source 受控创建 | PASS |
| 未核验 Lead 创建、重复 Lead 保留 | PASS |
| Lead 身份提议、双主体复核、撤销 | PASS |
| Lead 合并留痕 | PASS |
| Lead → Client → Deal 主链 | PASS |
| 多 Compass Deal Item | PASS |
| Consultation / Client Relationship / Referral / Follow-up 表与约束 | PASS |
| 上述四类对象的应用写入 API 与业务状态命令 | HOLD（表保持 fail-closed） |
| 真实联系人、员工、客户与渠道数据 | HOLD |

## 3. Migration 与 Catalog

`0027_crm_lead_deal_foundation.sql` SHA-256：

`81976bd7835a7ada6ab8d0e335ac751d3fd98432a53b0dc4d343c750456e78cc`

Catalog：27 条 ledger、63 张业务表、54 条 RLS policy。

## 4. PG16 / PG17 实际验收

命令：

```powershell
pwsh -NoProfile -File .\tests\f10_local_acceptance.ps1 -Version 16
pwsh -NoProfile -File .\tests\f10_local_acceptance.ps1 -Version 17
```

两版本均通过：全新初始化、重复执行、缺失/多余 Migration、checksum 漂移、原子回滚、分离 LOGIN、一次性票据、跨家庭拒绝、双主体身份复核、错误关联撤销、Lead 合并留痕、三 Compass Deal、NUMERIC 金额、直接 DML 拒绝、不可变事件、备份导出、摘要校验和全新集群恢复。

恢复后 catalog 为 `27/63/54`，P0/P1 永久回归均再次通过。

原始 transcript：

- PG16：`evidence/v2.0-0027-pwsh-f10-pg16.txt`，SHA-256 `4ffc692bae13dda2042e9aa940159a20e0de07ae39ad0037eca584c5e22c48fb`
- PG17：`evidence/v2.0-0027-pwsh-f10-pg17.txt`，SHA-256 `f69ab2f22a641cf1997b3cae09a4a386544918b9667853f1a377dd325b3d39e0`

`0027` 已前向应用到现有本地 PG16/PG17 开发库；旧 Migration 全部 checksum-verified SKIP，未重置数据卷。

## 5. 边界

- 只使用合成数据；没有连接腾讯云、生产数据库或生产密钥。
- 没有真实数据迁移、生产部署、合并或 PR。
- CRM 真实数据分类、保留期、员工/渠道责任归属及四类暂缓写入 API 在生产启用前需要数据治理复核。

`HANDOFF_REQUIRED: 白虎｜守正关（CRM 数据分类、保留、真实身份关联与业务用途）`

