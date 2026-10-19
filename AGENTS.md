# SekaiNook · 仓库与发版约定（给 AI 助手看）

本目录 `E:\Git\SekaiNook` 是 **网页端 + 后端**（Cloudflare Pages Functions + D1 + R2 + React 18）。
Flutter 客户端（Android + Web）在隔壁：**`E:\Git\SekaiNook-App`**，它有自己的 `AGENTS.md`，改动那边的代码先读它。

后端接口/建表/前端调用的规范见 `.trae/rules/project_rules.md` 与 `README.md` 的「开发规则（铁律）」，不在这里重复。

---

## ⭐ 发版（更新推送）—— 改完 Flutter 端就不能忘

家里人用的是**手机上装的 APK**。Flutter 端改完代码**不发版 = 用户手机上毫无变化**。
版本日志的唯一真源在**本仓库** `src/config/changelog.ts`，所以发版必然跨这两个仓库：

```powershell
# 1) 本仓库：改 APP_VERSION + 在 CHANGELOG 头部插一条 {version, date, title, changes}
#    多条需求可以拆成两版发，让每版日志都名副其实
cd E:\Git\SekaiNook
npm run changelog:fallback     # → 重新生成 E:\Git\SekaiNook-App\lib\config\changelog.dart（别手改）
npm run changelog:sync         # → 写进线上 D1；核对 https://sn.starrymiku.com/api/changelog

# 2) App 仓库：升 pubspec.yaml 的 version（+ 后面必须递增，那是安卓 versionCode）
cd E:\Git\SekaiNook-App
$env:ANDROID_HOME='E:\IDE\Android\Sdk'
.\tool\publish_apk.ps1 -Changelog '这一版改了什么（会显示在更新弹窗里）'

# 3) 核对线上清单与本地 APK 完全一致
Invoke-RestMethod https://pub.starrymiku.com/sekainook/latest.json
```

- 清单：`https://pub.starrymiku.com/sekainook/latest.json`；APK 在 R2 桶 `flclash-updates` 前缀 `sekainook/`
  （`wrangler r2 object put` **必须 `--remote`**，否则只写本地模拟存储，公网 404）。
- App 是**每次打开都查一次**清单（也可在 设置 → 关于 → 检查更新 手动查）；清单缓存 60 秒，APK 缓存一年。
- 用户端首次装完会有一次系统「允许安装未知应用」，之后就能一路点下去。
- 版本日志改一处两端生效：网页版读 `/api/changelog`，Flutter 端读同一份，云端够不着才退回 bundle 里的兜底。

## 改图标（工作台 `.icon-work/`，已 gitignore，不进版本库）

```powershell
cd E:\Git\SekaiNook\.icon-work
python icon-v3.py          # 改几何 / 配色：出 v3\taper-detail.png 与 v3\palettes.png 供挑选
python export-v3.py cyber  # 导出 out\ 全套尺寸（cyber / bsky / klein / plum / emerald … 也可用序号）
python land.py --apply     # 落进两个仓库（覆盖前自动备份到 .icon-work\backup\<时间戳>\）
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

- **签名库在 App 仓库**：`android/app/sekainook-release.jks` + `android/app/key.properties`（都在 `.gitignore` 里）。
  丢了就再也无法覆盖升级，只能全家卸载重装 —— 别删、别覆盖，提醒用户备份。
- **`versionCode` 必须变大**：只改 `versionName` 不改 `+N`，没人会收到更新；Flutter 的 `--split-per-abi` 会给版本号加
  `1000 × ABI 序号` 偏移，所以发版脚本固定单 ABI 构建（详见 App 仓库 `docs/android-update.md` 第 6 节）。

## 网页版不用发版

网页版 `git push` 后由 Cloudflare Pages 自动构建，用户刷新页面就是最新版 —— 上面这一整套只为安卓端。
