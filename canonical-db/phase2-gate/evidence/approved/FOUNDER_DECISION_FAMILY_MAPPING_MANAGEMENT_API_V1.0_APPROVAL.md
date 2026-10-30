# Founder Decision — Family Mapping Management API V1.0：批准记录

| 项 | 值 |
|---|---|
| 文件 | `canonical-db/phase2-gate/FOUNDER_DECISION_FAMILY_MAPPING_MANAGEMENT_API_V1.0.md` |
| 批准版 SHA-256 | `41dc44d03dd9ba6cdd6b5812d0b050e07445ac5db129f2693d304b29f9501475` |
| 批准人 / 角色 | 方琳媛 / Founder |
| 日期 | 2026-10-29（Asia/Shanghai；会话 typed approval） |
| 批准原话 | “批准，继续下一步动作” |
| 记录人 | Codex（只记录批准，不扩大批准范围） |

## 生效范围

- FM-1 至 FM-8 全部按批准版文件中的推荐值生效。
- 允许从前向 Migration `0024` 起，在本地实现受控 family mapping
  proposal / verify / revoke / supersede API。
- 允许使用纯合成数据完成 PostgreSQL 16、PostgreSQL 17、重复迁移、
  漂移拒绝、原子回滚及全新集群恢复验收。

## 效力边界

本批准不授权真实身份或家庭映射登记，不授权读取或导入真实数据，不授权
连接或更新腾讯云，不授权部署、生产切换、Push 到公开 `origin`、Merge 或 PR。

被批准文件保持原字节不变；本批准记录以其 SHA-256 绑定批准内容。被批准
文件如有任何字节变化，须重新取得 Founder 批准并生成新的批准记录。

