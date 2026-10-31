# 重装与重建手册（1Panel + 容器化 SekaiNook）

> 更新：2026-10-31
> 前提：完整快照已拉回本地 —— `C:\Users\zkdwd\Desktop\sekainook-backup\20261031-134348\sekainook-full-20261031-134417.tar.gz`（34.4 MB，SHA256 已验证）
> 目标：Ubuntu 24.04 → Docker → 1Panel → SekaiNook 跑在 1Panel 管的容器里

---

## 0. 最终长什么样

```
公网 80/443
    │
    ▼
┌─────────────────────────────────────────────┐
│ 1Panel 的 OpenResty（它自己占 80/443）        │
│   网站 sekainook（域名 = 140.143.240.238）    │
│     ├─ 静态  /opt/sekainook/web  ← 软链      │
│     └─ 反代  /api/ → 127.0.0.1:8788          │
└─────────────────────────────────────────────┘
                        │
                        ▼
              ┌──────────────────────┐
              │ 容器 sekainook-backend│  ← 1Panel 容器页可见/可管
              │   HOST=0.0.0.0:8788   │
              │   volume: /opt/sekainook/data → /app/data
              └──────────────────────┘
                        │
                 /opt/sekainook/data/
                   ├─ sekainook.db
                   └─ r2/  （图片）

1Panel 面板：http://140.143.240.238:18000/<安全入口>   （安全组只放自己 IP）
```

---

## 1. 重装前的准备（现在就能做）

### 1.1 把快照复制一份到别的地方

现在只有桌面一份，重装过程中它是唯一的退路。

```powershell
Copy-Item "$env:USERPROFILE\Desktop\sekainook-backup\20261031-134348" -Destination "E:\sekainook-backup" -Recurse
```

### 1.2 记下要复用的口令

| 用途 | 值 |
|---|---|
| 站点 Basic Auth | 账号 `family` / 口令 `3398` |
| 页面管理员口令 | `sekainook-test`（在 `.env` 的 `ADMIN_PASSWORD`） |

### 1.3 （可选）拉每日备份

`/opt/sekainook-backups` 里有 14 天的历史 db，重装会清掉。最新的已经在完整快照里，历史版本价值有限。

```powershell
ssh ubuntu@140.143.240.238 "du -sh /opt/sekainook-backups"
.\server\pull-backup.cmd -WithDaily      # 小于 300MB 就拉
```

### 1.4 确认快照能解开（30 秒，值得做）

```powershell
$pkg = "C:\Users\zkdwd\Desktop\sekainook-backup\20261031-134348\sekainook-full-20261031-134417.tar.gz"
tar -tzf $pkg | Select-Object -First 15
```

应该能看到 `./data/sekainook.db`、`./.env`、`./web/`、`./server/`、`./RESTORE.md`。

---

## 2. 控制台重装系统

腾讯云控制台 → 轻量应用服务器 → 找到 `Ubuntu-AbDU`（`lhins-01mmpr6w`）→ **更多 → 重装系统**

- 镜像：**Ubuntu 24.04 LTS 64bit**（纯净版，**不要**选任何"1Panel 应用镜像"）
- 登录方式：设置密码（记住它，后面要用）
- 确认：勾选"已知悉，重装后系统盘数据将被清空"

耗时 1~3 分钟。IP 不变。

> ⚠️ 重装会清空系统盘：`/opt/sekainook`、`/opt/flutter-sdk`、`/opt/sekainook-backups` 全部消失。
> 这就是为什么第 1 步必须先做。

---

## 3. 本机清掉旧的主机密钥再登录

重装后服务器 SSH 主机密钥会变，不清掉会一直报 `REMOTE HOST IDENTIFICATION HAS CHANGED`。

```powershell
ssh-keygen -R 140.143.240.238
ssh ubuntu@140.143.240.238
```

首次会问 `Are you sure you want to continue connecting?` → 输 `yes`。

---

## 4. 系统基线

```bash
sudo apt update && sudo apt -y upgrade
sudo timedatectl set-timezone Asia/Shanghai
sudo apt install -y curl wget git vim htop unzip sqlite3 ca-certificates
```

可选：加 2G swap 兜底（4G 内存跑 1Panel + 容器，有 swap 更从容）

```bash
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

---

## 5. 装 Docker

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker ubuntu
sudo systemctl enable --now docker
```

**退出 SSH 重新登录一次**（让 docker 组生效），然后验证：

```bash
docker version
docker compose version     # 需要 v2，输出 Docker Compose version v2.x
```

### 5.1 立刻放 daemon.json

不配这个，容器日志会无限增长把 70G 系统盘写满。

```bash
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true,
  "default-address-pools": [
    { "base": "172.30.0.0/16", "size": 24 }
  ]
}
EOF
sudo systemctl restart docker && docker info | grep -A2 "Logging Driver"
```

---

## 6. 装 1Panel

```bash
curl -sSL https://resource.fit2cloud.com/1panel/package/quick_start.sh -o quick_start.sh
sudo bash quick_start.sh
```

交互项：

| 提问 | 填什么 |
|---|---|
| 安装目录 | 回车用默认 `/opt` |
| 端口 | **`18000`**（默认 10086，改成 18000 和我们的端口规划一致） |
| 安全入口 | 回车用默认随机值 —— **截图记下来** |
| 用户名 / 密码 | 回车用默认随机值 —— **截图记下来** |

装完会打印类似：

```
面板地址: http://140.143.240.238:18000/abcd1234
用户名: xxxxx
密码: yyyyy
```

### 6.1 放行面板端口（只给自己）

安全组 → 添加规则：`TCP:18000`，来源填**你自己的公网 IP**，别填 `0.0.0.0/0`。

浏览器打开面板地址登录。

### 6.2 初始化向导里的应用选择

1Panel 首次进入会问装哪些应用：

| 应用 | 装不装 | 原因 |
|---|---|---|
| **OpenResty** | ✅ **必须装** | 它接管 80/443，后面建站点靠它 |
| MySQL | ❌ 不装 | SekaiNook 用 SQLite |
| Redis | ❌ 不装 | 用不上，白占 100MB+ |
| PHP | ❌ 不装 | 用不上 |
| 其他 | ❌ 不装 | 按需以后再加 |

装完 OpenResty 后，输 `http://140.143.240.238` 可能会看到一个 1Panel 默认页 —— 正常，第 9 步会用我们自己的站点覆盖。

---

## 7. 恢复代码与数据

### 7.1 上传快照

在**本机** PowerShell：

```powershell
scp "C:\Users\zkdwd\Desktop\sekainook-backup\20261031-134348\sekainook-full-20261031-134417.tar.gz" ubuntu@140.143.240.238:/tmp/
```

### 7.2 解包

在**服务器**：

```bash
sudo mkdir -p /opt/sekainook
sudo tar -xzf /tmp/sekainook-full-20261031-134417.tar.gz -C /opt/sekainook
ls -la /opt/sekainook
```

应看到：`data/  etc/  git-hooks/  git-repo/  web/  server/  functions/  .env  META.txt  RESTORE.md`

### 7.3 核对数据完整性

```bash
sudo sqlite3 /opt/sekainook/data/sekainook.db "SELECT COUNT(*) FROM family_ledger;"
# 必须输出 206
ls /opt/sekainook/data/r2 | wc -l
# 必须输出 114
sudo cat /opt/sekainook/.env
# 应有 ADMIN_PASSWORD=sekainook-test
```

对不上就别往下走，先停下来查。

> `etc/`、`git-hooks/`、`git-repo/` 这三个目录在新架构下暂时不用（那是旧 systemd + 系统 nginx 的配置），
> 留着作参考，别删也别乱用。

---

## 8. 构建并启动 SekaiNook 后端

### 8.1 构建 + 启动

```bash
cd /opt/sekainook
sudo docker compose -f deploy/docker/sekainook.compose.yml up -d --build
```

首次构建 1~3 分钟（`better-sqlite3` 要在容器里编译或下预编译包）。

### 8.2 看结果

```bash
sudo docker compose -f deploy/docker/sekainook.compose.yml ps
sudo docker logs --tail 40 sekainook-backend
curl -s http://127.0.0.1:8788/api/ledger/summary
```

`ps` 里 `STATUS` 应该显示 `Up (healthy)`（healthcheck 每 30 秒跑一次，刚起来等 30 秒再看）。

### 8.3 常见报错对照

| 报错 | 原因 | 处理 |
|---|---|---|
| `SQLITE_CANTOPEN` | 数据目录权限 | `sudo chown -R root:root /opt/sekainook/data`（容器用 root） |
| `ERR_DLOPEN_FAILED` / `better_sqlite3.node` | 装进了 Windows 版原生模块 | 说明 `.dockerignore` 没生效，确认 `server/node_modules` 没被打进镜像 |
| `node-gyp` 编译失败 | 缺编译工具 | Dockerfile 已装 `python3 make g++`；若仍失败看 `docker logs` |
| `EADDRINUSE :8788` | 端口被占 | `sudo ss -ltnp \| grep 8788` 找占用者 |
| 容器反复重启 | 看日志 | `docker logs sekainook-backend` |

### 8.4 关于"在 1Panel 里看见它"

回到 1Panel → **容器 → 容器列表**，应该能看到 `sekainook-backend`，状态运行中。
点进去可以：看日志、看监控、重启、停止、进终端 —— 日常管理都在这里，不用再敲命令。

> 1Panel 的「编排」页面里暂时看不到它，因为我们用的是命令行 compose。
> 这没关系：容器列表才是管理入口，编排只是创建方式之一。
> 以后想把它变成 1Panel 编排项目，把 `deploy/docker/sekainook.compose.yml`
> 的内容贴进「编排 → 创建编排」即可，但**两份 compose 会不同步**，别同时用。

---

## 9. 1Panel 里建站（静态 + 反代 + 密码）

这一步全在 1Panel 界面操作，不用敲命令（除了 9.2 的一条软链）。

### 9.1 创建静态网站

1Panel → **网站 → 网站 → 创建网站**

| 字段 | 填什么 |
|---|---|
| 类型 | **静态网站** |
| 域名 | `140.143.240.238`（IP 可以直接填进域名框） |
| 备注 | `SekaiNook` |
| 端口 | 80 |

提交后等它创建完成。

> 如果 1Panel 提示 80 端口被占用，说明 OpenResty 还没装好或没启动：
> 应用商店 → 已安装 → OpenResty → 启动。

### 9.2 让网站根目录指向 Flutter 产物

1Panel 建的站点目录是 `/opt/1panel/apps/openresty/www/sites/140.143.240.238/index`。
我们不往里拷文件，直接软链到 `/opt/sekainook/web` —— 以后更新前端只要换 `/opt/sekainook/web` 的内容就生效。

```bash
sudo rm -rf /opt/1panel/apps/openresty/www/sites/140.143.240.238/index
sudo ln -sfn /opt/sekainook/web /opt/1panel/apps/openresty/www/sites/140.143.240.238/index
ls -l /opt/1panel/apps/openresty/www/sites/140.143.240.238/
```

应该是 `index -> /opt/sekainook/web`。

### 9.3 加反向代理（把 /api/ 转给容器）

网站列表 → 点 `140.143.240.238` → **反向代理 → 创建反向代理**

| 字段 | 填什么 |
|---|---|
| 名称 | `api` |
| 代理地址 | `http://127.0.0.1:8788` |
| 代理路径 | `/api` |
| 其他 | 默认 |

提交。

### 9.4 开密码访问（Basic Auth）

还在这个网站里 → **密码访问 → 开启**

| 字段 | 填什么 |
|---|---|
| 用户名 | `family` |
| 密码 | `3398` |

### 9.5 关掉 OpenResty 的默认站点（如果输 IP 还是面板页）

1Panel → 网站 → 如果列表里除了 `140.143.240.238` 还有一个 `default` 站点把它删掉，
或者应用商店 → OpenResty → 配置里把默认 server 块注释掉。

---

## 10. 验证

服务器上：

```bash
# 后端直连（不经过 OpenResty）
curl -s http://127.0.0.1:8788/api/ledger/summary

# 经过 OpenResty（会返回 401，说明 Basic Auth 生效）
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1/

# 带口令访问
curl -s -u family:3398 http://127.0.0.1/api/ledger/summary

# 版本号
curl -s -u family:3398 http://127.0.0.1/version.json
```

本机浏览器：`http://140.143.240.238` → 弹出登录框 → `family` / `3398` → 应该看到 SekaiNook 界面。

**验收清单：**

- [ ] `docker ps` 里 `sekainook-backend` 是 `Up (healthy)`
- [ ] `curl 127.0.0.1:8788/api/ledger/summary` 返回 JSON
- [ ] 浏览器输 IP 弹出密码框（说明 Basic Auth 生效，不是直接 404）
- [ ] 输入 `family` / `3398` 后能看到页面
- [ ] 页面里数据正常（账单 206 条）
- [ ] 上传一张图片能成功（验证 r2 目录可写）
- [ ] 1Panel 容器列表能看到 `sekainook-backend`

---

## 11. 加固

### 11.1 安全组

| 端口 | 来源 | 说明 |
|---|---|---|
| 22 | 自己 IP | SSH |
| 80 | 0.0.0.0/0 | 网站 |
| 443 | 0.0.0.0/0 | 以后上 HTTPS |
| 18000 | **自己 IP** | 1Panel 面板，绝不对公网开放 |

### 11.2 SSH 改密钥登录

先在**本机**生成密钥：

```powershell
ssh-keygen -t ed25519 -C "sekainook-tencent" -f "$env:USERPROFILE\.ssh\sekainook"
type "$env:USERPROFILE\.ssh\sekainook.pub" | ssh ubuntu@140.143.240.238 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
```

**先用密钥登录成功一次，再禁密码**：

```powershell
ssh -i "$env:USERPROFILE\.ssh\sekainook" ubuntu@140.143.240.238
```

确认能进去后，在服务器上：

```bash
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart ssh
```

⚠️ 禁之前务必确认密钥能登 —— 否则会把自己锁在外面（只能去控制台 VNC 救）。

### 11.3 1Panel 自身

面板 → 设置：开两步验证、确认端口 18000、安全入口别泄露。

---

## 12. 之后要做的（不在本次）

| 事项 | 说明 |
|---|---|
| 域名备案 | 备案通过后，1Panel 建站加域名 + 申请 Let's Encrypt 证书 |
| App 重新打包 | `apiBase` 可改成域名；`app/lib/config/app_constants.dart` + `--dart-define` |
| 前端更新流程 | 本地 `flutter build web` → 上传覆盖 `/opt/sekainook/web`（软链已指向那里，立即生效） |
| 部署链路改造 | `server/deploy.sh` 从"flutter build + systemctl restart"改成"docker compose up -d --build" |
| 每日备份 | 快照里的 `/etc/cron.d/sekainook-backup` 可以照原样恢复：db 挂在宿主机 `/opt/sekainook/data/`，宿主机 `sqlite3 .backup` 照样能热备 |
| 其他服务 | 照 `deploy/docker/extras.compose.yml` 加，或在 1Panel 应用商店装（Gitea / Memos / Alist 等都有） |

---

## 13. 出问题了怎么回滚

快照还在，最坏情况就是再重装一次重来：

1. 控制台再重装 Ubuntu 24.04
2. 重跑本文档第 4~10 步
3. 数据从快照里再解一次

不会丢的东西：`/tmp` 会被清，但快照在本机，随时能重传。

---

## 附：常用运维命令（新架构下）

```bash
# 后端
cd /opt/sekainook
sudo docker compose -f deploy/docker/sekainook.compose.yml ps
sudo docker compose -f deploy/docker/sekainook.compose.yml logs -f
sudo docker compose -f deploy/docker/sekainook.compose.yml restart
sudo docker compose -f deploy/docker/sekainook.compose.yml up -d --build   # 改代码后重建

# 数据库（宿主机直接看，不用进容器）
sudo sqlite3 /opt/sekainook/data/sekainook.db '.tables'

# OpenResty / 站点
sudo /opt/1panel/apps/openresty/openresty/bin/openresty -t     # 配置检查
ls /opt/1panel/apps/openresty/www/sites/

# 1Panel 服务
systemctl status 1panel
1pctl user-info          # 忘了面板账号密码时用
```
