# 已初始化数据卷安全切换 pg_hba 方案

**状态：方案文件；不连接、不执行、不修改现有腾讯云数据卷。**

## 目标

将旧数据卷从 `local all all trust` 切换为本地 socket 也必须认证，同时保持迁移、健康检查和备份脚本可回滚。

## 预检

1. 确认容器内已存在 bootstrap、reader、app、binder、migrator、backup 角色及对应受保护凭据。
2. 在一次性测试容器验证 `scram-sha-256` 的 local/host 规则和 pgpass 文件权限 `0600`。
3. 对现有 `pg_hba.conf`、容器配置和卷状态做只读备份，记录 SHA-256。
4. 确认没有任何脚本依赖无口令 local trust。

## 切换步骤（由授权管理员执行）

1. 在维护窗口内写入等价的 `local all all scram-sha-256` 和受限 `host` 规则。
2. 执行 `SELECT pg_reload_conf()`，先用 reader、backup、binder 的受保护 pgpass 文件做连接验证。
3. 运行只读 `health.sh` 和备份演练，确认失败时不会回退到 bootstrap。
4. 记录 `pg_hba_file_rules` 原始输出、时间戳、规则文件 SHA-256 和验证输出。
5. 若验证失败，恢复预检时保存的配置并重新加载；不得删除或重置数据卷。

## 边界

此方案不关闭宿主机安全事件，不改变公网防火墙，也不批准真实数据或生产切换。现有数据卷只有在 FD-7、EV-8 和宿主机安全门禁通过后才能执行。
