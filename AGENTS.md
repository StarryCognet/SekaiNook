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
| 后端 | `/opt/sekainook`：`server/` 适配层跑 `functions/`，systemd `sekainook.service`（端口 8788），nginx 反代 `/api/` | Pages Functions |
| 数据库 | SQLite `/opt/sekainook/data/sekainook.db` | D1 库 `sekainook` |
| 图片 | 本地目录 `/opt/sekainook/data/r2/` | R2 桶 `starrymiku` |
| 前端 | nginx 静态站点 `/opt/sekainook/web` | Pages 项目 `sekainook` |
| 谁在用 | 网页版 + 2.11.1 起的 App | 还没更新的旧版 App |

- 服务器完整说明（初始化 / nginx / 备份 / 恢复 / 日常命令）见 `docs/国内轻量服务器-后端测试站部署方案.md`。
- **两边数据各自独立**，不会自动同步：只往自建写时，CF 那边还是旧数据（反之亦然）。真要合并，得手工导快照。
- 提醒推送 Worker（`workers/reminder`）仍部署在 CF，读的也是 CF 的 D1 —— 给自建站记的账它看不到。

---

## ⭐ 以后怎么更新

### 通道一：后端 + 网页版 = push 到服务器（一条命令）

服务器上有个裸仓库，**push 即部署**（`post-receive` 钩子 → `server/deploy.sh`）：

```powershell
cd E:\Git\SekaiNook
git push tencent main
```

`deploy.sh` 按本次改动的路径做增量的事：

1. `server/package.json` 变了 → 装后端依赖
2. `app/` `src/` `public/`、`server/deploy.sh` 或根 `package.json` 变了 → **`flutter clean` + 构建 Flutter Web**（约 1~2 分钟）→ 更新 `/opt/sekainook/web`
3. `src/config/changelog.ts` 变了 → 把版本日志写进服务器本地 D1
4. 重启 `sekainook.service`

⚠️ **构建前必须 `flutter clean`（已写进 `deploy.sh`）**。2026-10-30 踩过的坑：服务器增量编译缓存
（`app/.dart_tool`）从 2.11.0 一路增到 2.11.1 后，产出的 `main.dart.js` 是**坏的** ——
点几次底部 tab 就整页卡死（卡在 CanvasKit/WASM 层，连 DevTools 的 `Debugger.pause` 都断不开），
而同一份源码在本机构建完全正常。三次对照实验（线上 2.11.0 JS / 本机构建 2.11.1 JS / 服务器构建 2.11.1 JS）
确认是**服务器侧产物**的问题，不是源码。以后要改构建参数也一样，别让增量缓存带着跨版本的脏状态。

⚠️ **AI 助手推不了这个**：本机没有 SSH 私钥，`git push tencent` 会 `Permission denied`。
代码改完、本地验证过之后，让**用户在 PowerShell 里执行**上面那条命令，再去
`http://140.143.240.238/version.json` 看版本号对不对。

### 通道二：App = 打包发版

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

### 只改前端 / 只改后端时

- **只改 `app/`** → 服务器会自动重建 Web 版；但**已装 App 的人不会变**，要发新版 APK 才会更新。
- **只改 `functions/` 或 `server/`** → 服务器重启后端就够了；网页版刷新即生效，App 不用动。
- **改了 `functions/` 的表结构/新接口** → 记得 `migrations/` 也加一份，并确认 CF（D1）与自建（SQLite）
  两边都能跑；自建侧由 `deploy.sh` 之外的 `sqlite3` 手工应用迁移（见部署文档 §16）。

### 发完怎么确认

```powershell
curl.exe --noproxy '*' http://140.143.240.238/version.json
curl.exe --noproxy '*' http://140.143.240.238/api/ledger/summary
```

服务器上常用运维命令：

```bash
ssh ubuntu@140.143.240.238
systemctl status sekainook            # 后端服务
journalctl -u sekainook -n 50         # 后端日志
sudo nginx -t && sudo systemctl reload nginx
sqlite3 /opt/sekainook/data/sekainook.db '.tables'
ls /opt/sekainook-backups             # 每天 03:00 自动备份（db + r2）
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
