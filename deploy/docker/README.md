# deploy/ —— 服务器重装与自建服务

这台机器的定位：**1Panel 统一管理**，SekaiNook 跑在 1Panel 管的 Docker 里，
80/443 由 1Panel 的 OpenResty 托管，你在面板界面里建站点、配反代、开密码访问。

## 从这里开始

👉 **[reinstall.md](reinstall.md)** —— 重装系统 → 装 1Panel → 恢复 SekaiNook 的完整流程

## 文件索引

| 文件 | 用途 |
|---|---|
| `reinstall.md` | 重装与重建的完整操作手册（主文档） |
| `docker/Dockerfile` | SekaiNook 后端镜像：`functions/` + `server/` → 容器 |
| `docker/sekainook.compose.yml` | SekaiNook 后端编排（贴进 1Panel 编排，或命令行 `docker compose`） |
| `docker/extras.compose.yml` | 其他自建服务（Uptime Kuma 等），单独一个编排项目 |
| `docker/daemon.json` | Docker 日志轮转 / live-restore / 网段，装完 Docker 立刻放 |
| `nginx/sekainook.conf` | **兜底方案**：不用 1Panel OpenResty、改用宿主机 nginx 时才需要 |

## 铁律

1. **80 / 443 归 1Panel 的 OpenResty**。不要在系统层再装 nginx —— 两个都要 80，装了就打架。
2. **端口映射一律 `127.0.0.1:宿主机端口:容器端口`**，绝不写 `8080:80`（那会绑到 `0.0.0.0` 直接上公网）。要公网，用 1Panel 建站反代。
3. **每个容器都要 `mem_limit`**。总共 4G，SekaiNook 后端占 1.2G 上限，剩下的要分匀。
4. **数据 bind mount 到宿主机固定路径**（如 `/opt/sekainook/data/`），别用匿名 volume —— 备份脚本要够得着。
5. **不装 1Panel 的 MySQL / Redis / PHP**。SekaiNook 用 SQLite，其他服务各自带数据库，装了纯占内存。
6. 后端容器内 `HOST=0.0.0.0`（否则只监听容器 loopback，映射出来也连不上）。

## 目录约定

```
/opt/sekainook/              代码 + 数据（来自完整快照）
├── functions/               业务代码（Cloudflare Pages Functions 写法，CF 与自建共用）
├── server/                  Node 适配层 + 依赖
├── data/
│   ├── sekainook.db         SQLite
│   └── r2/                  图片
├── web/                     Flutter Web 构建产物（OpenResty 静态站根目录）
├── .env                     ADMIN_PASSWORD 等
└── deploy/docker/           就是本目录

/opt/1panel/                 1Panel 自身（面板、OpenResty、编排项目）
```
