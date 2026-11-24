# 账号服务（account-server）

UU 风格客户端使用的自建账号服务：注册、登录、设备自动绑定，以及与客户端现有地址簿协议兼容的设备列表。

- 监听端口：`21114`（与 hbbs/hbbr 并存，不占用它们的端口）
- 数据存储：SQLite（默认 `/data/account.db`）
- 依赖：无外部数据库；Rust 单二进制，运行镜像约 150 MB
- 构建：Dockerfile 默认使用 rsproxy.cn 镜像下载 crates，国内服务器构建更快

## 功能与接口

| 接口 | 说明 |
|---|---|
| `POST /api/register` | 注册并直接返回登录 token |
| `POST /api/login` | 用户名 + 密码登录 |
| `POST /api/currentUser` | 校验 token，刷新设备在线信息 |
| `POST /api/logout` | 注销 token |
| `GET /api/login-options` | 返回 `[]`（不使用第三方登录） |
| `GET/POST /api/ab` | 账号地址簿，设备列表在这里同步 |
| `POST /api/heartbeat` | 设备心跳，更新最后在线时间 |
| `POST /api/sysinfo` | 设备信息（主机名 / 系统 / 用户名）更新 |
| `GET /api/users`、`GET /api/peers` | 供客户端设备分组面板使用 |
| `GET /api/health` | 健康检查 |

设备在每次登录、`/api/currentUser` 时自动绑定到账号，并合并进该账号的地址簿；同一账号的其它客户端登录后即可看到全部设备。在线状态由 hbbs 的 `OnlineRequest`（21115 端口）直接提供，无需账号服务参与。

## 本地运行

```bash
cd account-server
ACCOUNT_DB=/tmp/account.db ACCOUNT_BIND=127.0.0.1:21114 cargo run
```

## Docker 部署

在服务器上：

```bash
mkdir -p /opt/rustdesk-account
# 将本目录上传到 /opt/rustdesk-account 后：
cd /opt/rustdesk-account
docker compose up -d --build
docker logs -f rustdesk-account-api
```

确认服务正常：

```bash
curl http://127.0.0.1:21114/api/health   # 输出 ok
```

### 端口与安全组

- 在云服务器安全组放行 TCP `21114`（客户端需要直接访问）。
- 如果服务器启用了 ufw/firewalld，同样放行 `21114`。

### 数据与备份

SQLite 数据在 `./data/account.db`（WAL 模式，备份时一并复制 `-wal`/`-shm`，或先 `docker compose stop`）。

```bash
tar czf account-backup-$(date +%F).tar.gz data/
```

### 升级

```bash
cd /opt/rustdesk-account
docker compose up -d --build
```

### 重置数据（清空所有账号与设备）

```bash
cd /opt/rustdesk-account
docker compose down
rm -f data/account.db data/account.db-wal data/account.db-shm
docker compose up -d
```

## 安全说明

默认通过 HTTP（21114）直连，登录密码与 token 在网络上是明文传输。个人 / 小范围使用可以接受；如果要长期暴露在公网，建议在前面加一层 HTTPS 反向代理（并让客户端把 API 服务器设为对应的 https 地址）。服务端密码以 Argon2 加盐哈希存储，token 为 32 字节随机值。

## 客户端默认值

客户端在首次启动且未配置服务器时，会自动填入：

- rendezvous / relay：`120.26.144.120`
- key：`/opt/rustdesk-server/data/id_ed25519.pub` 的内容

这些默认值在 `flutter/lib/custom_ui/uu_defaults.dart` 中维护；用户之后在设置里修改过服务器则不会被覆盖。
