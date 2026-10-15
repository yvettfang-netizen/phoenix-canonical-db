# 部署凭据存放方案提案

**状态：等待 Founder 确认；本轮不读取、不删除、不移动 `deploy/tencent/.env`。**

## 推荐方案

将腾讯部署凭据从工作树 `.env` 移入受控凭据管理器或服务器本地 root-only 文件：

- 本机只保存短时、不可提交的引用或临时会话凭据。
- 服务器端保存 `/etc/phoenix-canonical/credentials.env`，所有者 root、权限 `0600`，不进入 Git。
- Docker Compose 通过受保护的 `--env-file` 或 secret 文件读取。
- 脚本只创建容器内 `0600` 的临时 pgpass，执行完立即删除。
- 轮换时先添加新凭据、验证 health/backup，再撤销旧凭据。

## 需要 Founder 决定

- 使用云凭据管理器、服务器 root-only 文件，还是其他组织批准方案。
- 凭据轮换责任人、周期、审计保留和应急撤销流程。

确认前保持现有部署文件不变，不执行凭据迁移，不连接腾讯云。
