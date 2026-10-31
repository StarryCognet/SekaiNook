# SekaiNook · 仓库与发版约定（给 AI 助手看）

本仓库 `E:\Git\SekaiNook` 同时住着四样东西：

| 目录 | 是什么 | 规则 |
|---|---|---|
| `app/` | **Flutter 客户端**（Android + Web 一套代码） | 看 `app/AGENTS.md`，改那里的代码先读它 |
| `functions/` `migrations/` `workers/` | **后端业务代码**（Cloudflare Pages Functions 写法） | 看 `.trae/rules/project_rules.md`。**别加 Node 专用写法**：线上 CF 与自建服务器共用这一份 |
| `server/` | **Node 适配层**：让 `functions/` 原样跑在国内服务器上（D1→better-sqlite3、R2→本地目录、HTTP→http.Server） | 改完 `functions/` 后要确认它在 `server/` 下也能跑 |
| `src/` `public/` | React 版网页端（过渡期保留） | 主域名不再服务它，只留作回滚 |

> 2026-10 已把原先游离的 `E:\Git\SekaiNook-App` 用 `git subtree` 并入 `app/`（完整历史保留）。
> 原目录在文件系统上还留着当退路，但**不再是开发入口** —— 所有命令都在本仓库根执行。

后端接口/建表/前端调用的规范见 `.trae/rules/project_rules.md` 与 `README.md` 的「开发规则（铁律）」，不在这里重复。

---

## ⭐ 后端跑在哪：两套环境，一份代码

2026-10-30 起，家里的正式入口是**自建的腾讯云轻量服务器**；Cloudflare 那套保留作回退。

| | 自建（正式） | Cloudflare（回退） |
|---|---|---|
| 地址 | `http://140.143.240.238` | `https://sn.starrymiku.com` |
| 后端 | `/opt/sekainook`：`server/` 适配层跑 `functions/`，**Docker 容器** `sekainook-backend`（127.0.0.1:8788），由 nginx 容器反代 `/api/` | Pages Functions |
| 数据库 | SQLite `/opt/sekainook/data/sekainook.db` | D1 库 `sekainook` |
| 图片 | 本地目录 `/opt/sekainook/data/r2/` | R2 桶 `starrymiku` |
| 前端 | nginx 容器 `sekainook-web`（静态文件来自宿主机 `/opt/sekainook/web`，挂在 `/usr/share/nginx/html`） | Pages 项目 `sekainook` |
| 谁在用 | 网页版 + 2.11.1 起的 App | 还没更新的旧版 App |

- 服务器完整说明（初始化 / nginx / 备份 / 恢复 / 日常命令）见 `docs/国内轻量服务器-后端测试站部署方案.md`。
- **两边数据各自独立**，不会自动同步：只往自建写时，CF 那边还是旧数据（反之亦然）。真要合并，得手工导快照。
- 提醒推送 Worker（`workers/reminder`）仍部署在 CF，读的也是 CF 的 D1 —— 给自建站记的账它看不到。

---

## ⭐ 以后怎么更新

### 先看懂现在跑的是什么（2026-10-31 起的形态，容器化）

```
公网 80 ─→ nginx 容器 sekainook-web（配置在 deploy/nginx/web-container.conf）
            ├── /              → 1Panel 面板（宿主机 127.0.0.1:18001）
            ├── /sekainook/    → SekaiNook 网页版（Flutter Web，base-href=/sekainook/）
            ├── /api/v1/ /api/v2/ → 1Panel 自己的 API（前缀更长，优先命中）
            ├── /api/          → sekainook-backend 容器（127.0.0.1:8788）
            └── /harness/      → DeepSeek Harness（宿主机 10443）
公网 10443 ─→ DSH 自带 Caddy（自签 HTTPS，可直连）
```

- 后端是**容器**：代码 COPY 进镜像（不是挂载），所以**改代码必须重建镜像**，光重启没用。
- 前端是**静态文件**：`/opt/sekainook/web` 以 bind mount 进 web 容器。
- 服务器上**没有 Flutter SDK、也没有 Node** —— 构建端全在本机。这不是省事，是故意的：
  2026-10-30 服务器侧增量编译缓存产出过一版坏掉的 `main.dart.js`（点几次底部 tab 就整页卡死，
  而同一份源码在本机构建完全正常）。现在构建只在干净的本机做。

### 通道一：改后端（`functions/` `server/` `migrations/`）—— 一条命令

```powershell
cd E:\Git\SekaiNook
git push tencent main
```

`post-receive` 钩子（在 `/opt/sekainook/git-repo/sekainook.git/hooks/`）会 checkout 到
`/opt/sekainook`，再跑 `server/deploy-container.sh`，按本次 diff 的路径做增量：

| 改了 | 钩子做什么 |
|---|---|
| `server/` `functions/` `migrations/` `deploy/docker/Dockerfile` | 重建镜像 + 重启 backend 容器（30~60 秒） |
| `deploy/nginx/web-container.conf` | `nginx -t` 校验，**过了才** reload（错了保留旧配置继续跑） |
| `deploy/docker/sekainook.compose.yml` | `docker compose up -d` |
| `app/` | 只打印提示（服务器构建不了，见通道二） |

⚠️ 钩子里必须用 `/bin/sh /opt/sekainook/server/deploy-container.sh` 调用，**不能直接执行脚本**：
git 在 Windows 上不记录可执行位（`core.filemode=false`），checkout 出来的文件是 644，直接跑会 `Permission denied`。

⚠️ `deploy-container.sh` 里所有终端输出都用英文。它的输出会经 `git push` 回显到 Windows 的 PowerShell
控制台（GBK 编码），中文会变乱码 —— `server/full-backup.sh` 已经踩过同一个坑。

### 通道二：改前端（`app/`）—— 本机构建 + 上传

```powershell
cd E:\Git\SekaiNook
.\server\deploy-web.ps1
```

它做四件事：`flutter build web --base-href /sekainook/` → 打包 tar → scp 到服务器 → 原地解包并报出版本号。

也可以双击 `server\deploy-web.cmd`（包装器，绕开 PowerShell 执行策略）。

⚠️ `base-href` 必须是 `/sekainook/` —— 这个站挂在子路径下，改成 `/` 会白屏。
在 MSYS bash 里手敲命令要加 `MSYS_NO_PATHCONV=1`，否则 MSYS 把 `/sekainook/` 转成
`C:/Users/.../sekainook/`，Flutter 报 `--base-href should start and end with /`。脚本里已处理。

⚠️ **替换 web 产物不能 `mv` 目录**：`/opt/sekainook/web` 是 bind mount，mv 换掉 inode 后容器还服务旧树。
脚本用的是原地 `find -mindepth 1 -delete` + 解包。

⚠️ **只 push 不跑 `deploy-web.ps1`，网页版不会更新** —— 钩子只会打印一行提示。

### 只改后端 / 只改前端，分别要做什么

| 改了什么 | 要做什么 | 已装的 App 会变吗 |
|---|---|---|
| `functions/` `server/` | `git push tencent main` | 会（App 也打这份 API） |
| `app/`（Flutter） | `git push` + `.\server\deploy-web.ps1` | **不会**，要发新 APK |
| `deploy/nginx/*.conf` | `git push tencent main` | 不会 |
| `migrations/` 加表 | `git push` + 在服务器上手动应用 SQL（见下方运维命令） | — |
| 图标 | 落盘后仍要发新 APK | **不会**，图标在包里 |

- 改了 `functions/` 的表结构 → `migrations/` 也加一份，并确认 CF（D1）与自建（SQLite）两边都能跑。
  自建的 SQLite **不会**自动套用迁移，得手工执行（命令见下）。
- 本机推得动：`git remote tencent` 已配 `core.sshCommand` 指向 `C:\Users\zkdwd\.ssh\txysh.pem`
  （仓库级配置，不动全局 ssh config），AI 助手也能直接 push。

### 通道三：App = 打包发版

```powershell
cd E:\Git\SekaiNook

# 1) 改 src/config/changelog.ts：APP_VERSION + 头部插一条 {version, date, title, changes}
npm run changelog:fallback      # → 重新生成 app/lib/config/changelog.dart
npm run changelog:sync          # → 写 CF 线上 D1（先清代理，见下节）

# 2) 升 app/pubspec.yaml 的 version（+ 后面的数字必须递增，那是安卓 versionCode）

# 3) 打包 + 上传 R2 + 生成更新清单
$env:ANDROID_HOME='E:\IDE\Android\Sdk'
.\app\tool\publish_apk.ps1 -Changelog '这一版改了什么（会显示在更新弹窗里）'

# 4) 核对线上清单
Invoke-RestMethod https://pub.starrymiku.com/sekainook/latest.json
```

- App 的 API 地址是**编译期常量**（`app/lib/config/app_constants.dart` 里 `apiBase` 的默认值 =
  `http://140.143.240.238`）。**已经发出去的包改不了地址**，要换只能重新打包。
- 更新清单和 APK 继续放 CF R2（`https://pub.starrymiku.com/sekainook/latest.json`），**故意不跟着后端搬**：
  这样自建服务器挂了也能推更新。
- 明文 HTTP 已在 `app/android/app/src/main/res/xml/network_security_config.xml` 白名单里
  （只放行 `140.143.240.238` 与本地调试地址）。
- `publish_apk.ps1` 会核对 `https://sn.starrymiku.com/api/changelog` 的版本与本包一致，
  所以 `changelog:sync` 必须排在打包之前。

### 发完怎么确认

```powershell
# 网页版版本号（构建时 --dart-define 打进去的）
curl.exe --noproxy '*' http://140.143.240.238/sekainook/version.json
# 后端活着
curl.exe --noproxy '*' http://140.143.240.238/api/ledger/summary
# 容器状态
ssh -i C:\Users\zkdwd\.ssh\txysh.pem ubuntu@140.143.240.238 "sudo docker ps"
```

服务器上常用运维命令（容器化之后**没有 systemd 单元了**，`systemctl` 那套已作废）：

```bash
ssh -i C:\Users\zkdwd\.ssh\txysh.pem ubuntu@140.143.240.238

# --- 容器 ---
sudo docker ps
sudo docker compose -f /opt/sekainook/deploy/docker/sekainook.compose.yml ps
sudo docker logs -f sekainook-backend      # 后端日志
sudo docker logs -f sekainook-web          # nginx 日志

# --- nginx 配置都在容器里 ---
sudo docker exec sekainook-web nginx -t
sudo docker exec sekainook-web nginx -s reload

# --- 数据库（WAL 模式：别只拷 sekainook.db，要连 -wal/-shm 一起）---
sudo docker exec sekainook-backend ls -l /app/data

# 手动应用迁移（服务器上没有 sqlite3 命令，用容器里的 better-sqlite3）
sudo docker exec -i sekainook-backend node --input-type=module -e "
  import Database from 'better-sqlite3';
  import fs from 'node:fs';
  const db = new Database('/app/data/sekainook.db');
  db.exec(fs.readFileSync(0, 'utf8'));
" < migrations/0008_xxx.sql

# --- 备份（每天 03:00 自动跑，也可手动）---
sudo bash /opt/sekainook/server/backup.sh
ls -lh /opt/sekainook/backups

# --- 1Panel / DSH ---
sudo 1pctl status
sudo docker ps | grep -i harness

# --- 磁盘 ---
df -h /
du -sh /opt/sekainook/data /opt/sekainook/web /var/lib/docker
```

---

## 本机网络：wrangler 的 D1 / R2 要走直连

`wrangler d1 execute --remote`（`changelog:sync`）与 `wrangler r2 object put --remote`（发 APK）
在本机 `HTTP_PROXY=http://127.0.0.1:7890` 下都会 `✘ fetch failed`，发版会断在这两处；临时清掉代理就通：

```powershell
$env:HTTP_PROXY=''; $env:HTTPS_PROXY=''; $env:NO_PROXY='*'
```

`wrangler pages deploy` 不受影响（能过代理）。curl 同理 —— 加 `--noproxy '*'` 才不会空手回来。
另：`app/tool/publish_apk.ps1` 的 `flutter build apk` 带 `--no-pub`，正是因为隐式 `pub get`
在同样的代理环境下会 `SocketException: 远程计算机拒绝网络连接` 直接断掉。

### 但 Gradle 编译 APK 是反过来的：得**绕开**代理

`E:\gradle-home\gradle.properties`（本机全局，不随项目走）写死了
`systemProp.http.proxyHost=127.0.0.1` / `proxyPort=7890`。代理软件正常时没事，可它一旦不通，
`flutter build apk` 会卡在拉 AGP 上：

```
Could not resolve com.android.tools.build:gradle:9.0.1
  > Connect to 127.0.0.1:7890 failed: Connection refused: getsockopt
```

2026-10-31 实测同一时刻：走代理拉 aliyun 仓库返回 `000`，直连同一 URL 返回 `200`。
`env -u HTTP_PROXY ...` **不管用** —— 代理写在 `gradle.properties` 里，不是环境变量。
要么把代理开起来，要么把那 4 行 `systemProp.*.proxy*` 临时注释掉再打包，打完改回来
（其它项目还指着它）。

⚠️ 另一处要注意：APK 打完后 `wrangler r2 object put` 上传**又要清代理**（见上一段），
所以一次完整发版里，构建和上传对代理的要求正好相反 —— 分两步跑最省事：
先构建（可带代理，代理不通就注释 gradle.properties），再
`env -u HTTP_PROXY ... powershell -File app\tool\publish_apk.ps1 -SkipBuild`（清代理上传）。

## Cloudflare 那套（回退用，平时不用动）

- **`sn.starrymiku.com` 仍是 Flutter Web**（Pages 项目 `sekainook`）。偶发需要更新时：
  `npm run web:deploy`（= `flutter build web` + `wrangler pages deploy app/build/web --project-name sekainook --branch main`）。
- ⚠️ 该项目的 **Git 自动构建已关掉**（`deployments_enabled=false`）：push 不再触发构建，
  否则每次 push 都会用 React 产物把 Flutter 版盖回去。
- **React 版仍完整留在仓库**（`src/` + `public/`）。回滚：`npm run deploy`，或在 Dashboard 部署历史里 Rollback。
- **CF 与自建前端是两份独立产物** —— 推自建不会更新 CF，推 CF 也不会更新自建。真要两边都新，得各推一次。

## 改图标（工作台 `.icon-work/`，已 gitignore，不进版本库）

```powershell
cd E:\Git\SekaiNook\.icon-work
python icon-v3.py          # 改几何 / 配色：出 v3\taper-detail.png 与 v3\palettes.png 供挑选
python export-v3.py cyber  # 导出 out\ 全套尺寸（cyber / bsky / klein / plum / emerald … 也可用序号）
python land.py --apply     # 落进 app/ 与 public/（覆盖前自动备份到 .icon-work\backup\<时间戳>\）
cp icon-v3.svg E:\Git\SekaiNook\public\icon.svg   # 网页端矢量版
```

- **图形占多大是唯一容易搞错的点**：自适应前景按 108dp 画布给，而启动器可见区只有 72dp。
  所以 `FRAC_ADAPTIVE = 0.35`（= 可见区的 ~54%）、传统方形 `FRAC_LEGACY = 0.52`、maskable `0.52`。
  改完拿 `ic_launcher_foreground.png` 的 alpha bbox 复核一句，别凭感觉（0.56 那版占了可见区 84%，被用户说「太大」）。
- SVG 光栅化用 `resvg_py.svg_to_bytes(svg_string=..., width=, height=)`；S 是**变宽度的填充轮廓**（`icon-v3.py` 里由中心线 + 宽度曲线生成），别退回等宽 `stroke`。
- 收笔两端的圆帽要自己拼轮廓：`taper_outline()` 的点序是「左链→末端帽→右链倒序→**起始帽**」，
  而且**起始帽必须从 `nangs[0] + π` 起扫**（从右侧链那一侧扫回来）。写成从 `nangs[0]` 起扫会横拉一条弦，
  端头就出现楔形缺口 —— 1.31.9 发出去过一版这样的，1.31.10 修的。改完务必跑
  `python probe-selfcross.py`（自交数必须是 0）并看一眼 `v3/taper-full.png` 的端头。
- 图标在 APK 里 —— 落盘后仍要走上面那套发版流程，不发版手机上一点不变。

## 别忘的两件事

- **签名库在 `app/android/`**：`app/android/app/sekainook-release.jks` + `app/android/app/key.properties`（都在 `.gitignore` 里）。
  丢了就再也无法覆盖升级，只能全家卸载重装 —— 别删、别覆盖，提醒用户备份。
- **`versionCode` 必须变大**：只改 `versionName` 不改 `+N`，没人会收到更新；Flutter 的 `--split-per-abi` 会给版本号加
  `1000 × ABI 序号` 偏移，所以发版脚本固定单 ABI 构建（详见 `app/docs/android-update.md` 第 6 节）。
