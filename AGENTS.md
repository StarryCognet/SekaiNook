# SekaiNook App（Flutter 端）· 工作约定

这个仓库是 SekaiNook 的 Flutter 客户端（Android + Flutter Web，一套代码）。
网页端 / 后端 / 管理端在 `E:\Git\SekaiNook`（Cloudflare Pages + D1 + R2）。

功能面见 `README.md`；应用内更新与发版的完整说明见 `docs/android-update.md`。

---

## ⭐ 改完必须发版 —— 别只改完代码就说「改好了」

家里人用的是**手机上那个 APK**。只改代码不发版 = 用户手机上**一点变化都没有**。
做完任何用户看得见的改动，默认把下面这条走完（除非用户明说「先不发」）：

1. **写版本日志**（唯一真源在网页仓库，改一处两端都看得见）
   `E:\Git\SekaiNook\src\config\changelog.ts`：`APP_VERSION` 改成新版本号，并在 `CHANGELOG` 头部插一条
   `{ version, date, title, changes: [...] }`。多条需求可以拆成两版发，让每版日志都名副其实。
2. `cd E:\Git\SekaiNook && npm run changelog:fallback`
   → 重新生成本仓库 `lib/config/changelog.dart`（本机兜底，**别手改这个文件**）
3. `npm run changelog:sync`
   → 写进线上 D1；核对 `https://sn.starrymiku.com/api/changelog` 的 `version` 已经是新版
4. **升版本号**：本仓库 `pubspec.yaml` 的 `version: 1.31.6+8` → `1.31.7+9`
   （`+` 后面是安卓 `versionCode`，App 就是拿它比大小，**必须递增**）
5. **发布**
   ```powershell
   $env:ANDROID_HOME='E:\IDE\Android\Sdk'
   .\tool\publish_apk.ps1 -Changelog '这一版改了什么（这句话会进更新弹窗）'
   ```
6. **核对线上**：`Invoke-RestMethod https://pub.starrymiku.com/sekainook/latest.json` 的
   `versionName` / `versionCode` / `sha256` / `size` 与本地 APK 一致
   （本地：`build/app/outputs/flutter-apk/app-release.apk`，`aapt2 dump badging` + `Get-FileHash -Algorithm SHA256`）

清单 `https://pub.starrymiku.com/sekainook/latest.json`；APK 存 R2 桶 `flclash-updates` 前缀 `sekainook/`（wrangler 已登录，
`r2 object put` **必须带 `--remote`**，否则只写本地模拟存储）。

> **签名库 `android/app/sekainook-release.jks` 与 `android/app/key.properties` 丢了就再也无法覆盖升级**
> （只能让全家卸载重装）。两者都在 `.gitignore` 里，别删、别覆盖、另行备份。

---

## 硬约束（都是踩过的坑）

- **不要跑 `dart format`**：仓库用的是旧格式化风格，Dart 3.13 的 tall style 会把整个仓库重排。新代码按既有风格手写。
- **不要用 `--split-per-abi`**：Flutter 会给每个包加 `1000 × ABI 序号` 偏移，`versionCode` 不再单调递增 → 「发了新版手机不提示」。`publish_apk.ps1` 固定 `--target-platform android-arm64`（真要照顾 32 位机用 `-Universal`）。
- 验证用 `flutter analyze --no-pub`（不加 `--no-pub` 会先隐式跑 pub get，弱网能卡十几分钟）与 `flutter test --no-pub`。
- `test/garden_flow_test.dart` 打的是**生产后端**，会因服务端状态偶发失败（如 `Expected: <395> Actual: <385>`）。怀疑回归时先 `git stash` 在 HEAD 上对照，别直接当自己的锅。
- 导航一律 `context.go(...)`（go_router 的 replace 语义，历史只有一条）。**二级页面要让「系统返回」回上一级，挂 `BackIntentHandler`**（`lib/ui/shell/back_intent.dart`）；不要自己套 `PopScope` —— 外层 `MainShell` 已有一个 `PopScope(canPop: false)`，嵌套会两边同时触发。
- 卡片一律走 `AppCard`。**别再往卡片上叠 `BackdropFilter` 做毛玻璃/液体玻璃**：1.31.6 试过一版（`GlassSurface` + 出厂毛玻璃），真机实测太卡，1.31.8 已整体回滚（相关文件、设置项、测试、文档全删）。底座导航栏同理 —— 可复用组件也别偷偷读 Provider（它得能在裸 pump 的 widget 测试里跑）。
- 更新相关的文件别乱动：`lib/state/update_state.dart`（检查/跳过/下载状态机）、`lib/data/models/app_update.dart`（清单字段校验：缺字段、非 https、sha256 非 64 位一律当没读到）、`lib/core/apk_installer*.dart`（条件导入，Web 走 stub）。
- **图标别手改**：`android/app/src/main/res/mipmap-*`、`web/icons/*`、`web/favicon.png`、`public/icon.svg` 都由网页仓库 `.icon-work/` 的管线生成（`icon-v3.py` → `export-v3.py <配色>` → `land.py --apply`），比例与做法见那边 `AGENTS.md` 的「改图标」一节。

## 交付习惯

- 说清楚**哪一步没实跑过**：真机链路（应用内更新：下载 → sha256 校验 → 调起系统安装器 → 允许未知来源后重试）只能在设备上算数；涉及动画/模糊这类开销，用户说「卡」就当没有商量余地（1.31.6 的卡片模糊就是这么回滚的）。
- 用户看得见的效果，能出一张对照图就出一张（`flutter test --update-goldens` 可以拿真实渲染管线落 PNG）。
- 别顺手提交或改动用户自己的进行中改动（`git status` 里的 WIP 文件）。
