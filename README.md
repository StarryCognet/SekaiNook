# SekaiNook（Flutter 版）

家庭「行为 ↔ 积分银行」App 的 Flutter 客户端。**复用 Web 版同一套 Cloudflare Pages Functions 后端**
（`https://sekainook.pages.dev`），业务语义完全一致，只是把前端从 React + antd 换成 Flutter。

- 姊妹仓库（Web 版 + 后端）：`E:\Git\SekaiNook`
- 目标平台：**Android 手机** + **Flutter Web**（同一份代码）

## 跑起来

```bash
flutter pub get

# 连线上后端（默认）
flutter run -d chrome

# 连本地后端（Web 版仓库里 `npm run dev:api` 起的 8788）
flutter run -d chrome --dart-define=API_BASE=http://127.0.0.1:8788

# Android 真机 / 模拟器
flutter run -d <device-id>
```

`API_BASE` 是编译期常量，默认值在 `lib/config/app_constants.dart`。

### 本地后端

后端代码在 Web 版仓库，本地起服务的步骤：

```bash
cd E:\Git\SekaiNook
npm run dev:api          # wrangler pages dev public --port 8788
```

> 浏览器里 Flutter Web 连本地后端需要 CORS。Web 版仓库已加 `functions/_middleware.ts`
> （**只补 CORS 响应头 + 应答 OPTIONS 预检，不鉴权、不改状态码与响应体**）。

## 平台开关

| 平台 | 命令 | 备注 |
| --- | --- | --- |
| Web | `flutter build web --dart-define=API_BASE=...` | 产物在 `build/web` |
| Android | `flutter build apk --release` | 产物在 `build/app/outputs/flutter-apk/` |

实测产物体积：`build/web` 42 MB（含 canvaskit，部署到 Pages 后走 gzip/brotli 会小很多）；
`app-release.apk` 60.6 MB（未拆分，含 arm64-v8a / armeabi-v7a / x86_64 三个 ABI）。
想要更小的包用 `flutter build apk --release --split-per-abi`。

> Windows 上 Gradle 的 Kotlin 增量编译缓存偶尔关不掉
> （`Could not close incremental caches ... class-fq-name-to-source.tab`），
> 会让 `:shared_preferences_android:compileReleaseKotlin` 直接失败、`assembleRelease` 挂掉；
> `android/gradle.properties` 里已关掉 `kotlin.incremental` 换构建稳定。

## 测试与验证

```bash
# 纯逻辑单测（ISO 周标签，13 个日期用例 + 时区用例）
flutter test --no-pub test/week_label_test.dart

# 接口契约冒烟：只发 GET，对着真实后端核对字段
flutter test --no-pub test/api_smoke_test.dart --dart-define=API_BASE=http://127.0.0.1:8788

# 端到端业务闭环：打卡 → 同 id 重发幂等 → 待审批 → 审批 → 余额 +10 → 删除 → 余额复原
# 注意：会真实写库（跑完自己把那条删掉），别指向生产环境
flutter test --no-pub test/e2e_flow_test.dart --dart-define=API_BASE=http://127.0.0.1:8788

# 花园闭环：背古诗 → pending 出队 → 后端阳光 +10 → 清理本次新增后复原
flutter test --no-pub test/garden_flow_test.dart --dart-define=API_BASE=http://127.0.0.1:8788

# 动效组件回归（12 个用例，不联网）
flutter test --no-pub test/motion_widgets_test.dart

# 悬浮底栏回归（5 个用例：角标 / 点击 / 拖动 / 减少动态效果 / 选中语义）
flutter test --no-pub test/app_nav_bar_test.dart

# 七套主题的对比度回归（42 条：字压在各种底上是否读得清）
flutter test --no-pub test/palette_contrast_test.dart
```

加 `--no-pub` 是因为 `flutter test` 默认会先跑一次 `pub get`，离线环境会卡在那里。

手机视口（390×844）下的实拍验证流程（iframe 取景框 + CDP 截图 + 一键切角色/主题）
见 [tool/webharness/README.md](tool/webharness/README.md)。

已经做过的验证：

- `flutter analyze` 零 error（15 条 info，都是 `prefer_initializing_formals` /
  `unnecessary_brace_in_string_interps` 这类既有提示）
- 上面七个测试文件全部通过（70 个用例，其中 9 个要对本地后端跑）
- Chrome 里逐个跑通 8 个页面：身份门 / 女儿版首页 / 家长版首页 / 家庭账本 / 花园 / 通知 / 周计划 / 设置
- 390×844 手机视口下 7 个主页面实拍留证（`docs/shots/`：
  04 妈妈版首页 / 06 妹妹版首页 / 10 家庭账本 / 11 花园 / 12 设置 /
  13 周计划 / 14 通知；身份门那屏没留）
- **对比度与日期重叠修复后的复拍**（`docs/shots/diag/`，浅色+深色各页）：
  妈妈版首页 x 轴只画 5 个标签（`10/4 10/7 10/10 10/13 10/16`，不再糊成一片）、
  三级文字明显变深、深色主题未读通知卡上的副文案可读、悬浮底栏在 5 个页面都正常浮起
- **动效中间态抓到实拍**：`docs/shots/21-page-transition-b.png` 一帧里同时有
  「路由 shared axis 转场中 + 错峰进场未完成 + 数字滚动到一半 + 导航指示器正在滑动」。
  抓法见 [docs/motion-kit.md](docs/motion-kit.md) 第六节（`--dart-define=SLOW_MO=N` 放慢时间轴）。
- 后端写路径实测：`POST /api/ledger` 回 201 `{id, status:"pending"}`；同 id 重发回 200 + `duplicate:true`；
  `PATCH` 通过后余额才 +10；`DELETE` 后余额复原

## 部署

Flutter Web 产物是纯静态文件，丢给任意静态托管即可。它默认连线上后端
（`https://sekainook.pages.dev`，属跨域调用，后端已加 CORS 中间件）：

```bash
# Cloudflare Pages（首次会创建新项目）
npx wrangler pages deploy build/web --project-name sekainook-app
```

> 应用用的是 hash 路由（`#/home`），所以**不需要** SPA 的 `_redirects` 兜底规则。
> 想指向别的后端，构建时加 `--dart-define=API_BASE=https://你的域名`。

Android 装包：

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

> 当前 release 包用的是 Flutter 模板自带的 debug 签名（`android/app/build.gradle.kts` 里留了 TODO）。
> 要上架应用商店得先配自己的 keystore。

## 目录结构

```
lib/
  main.dart              入口：建 SharedPreferences → 建各 store → runApp
  app.dart               MaterialApp.router + Provider 注入 + 启动加载
  router.dart            go_router 路由表（对应 Web 版 src/App.tsx）
  config/                业务规则常量（family_rules / garden_config / app_constants）
  core/                  api_client(dio) / api_exception / pin_guard / task_rules / week / image_compress / ledger_ids
  data/api/              接口层：ledger / plans / notifications / settings / admin / upload / maintenance
  data/models/           数据模型
  state/                 全局状态（ChangeNotifier）：family / theme / settings / notification / customTasks / garden
  theme/                 tokens（间距圆角字号）+ app_theme（7 套主题色板）+ motion（动效令牌）
  ui/shell/              底部导航骨架 MainShell（含 15 秒通知轮询）
  ui/pages/              页面：home(妹妹版/妈妈版/通知) / family(工作台/周计划) / garden / settings / role_gate
  ui/widgets/            通用卡片、状态视图、全局背景图层、motion/（动效组件）
docs/                    接口契约与移植说明（见下）
```

## 动效与视觉

设计语言参考 [FlClash](https://github.com/chen08209/FlClash) 的 Material 3 做法：
圆角更大、层级靠底色与描边而非阴影、动效统一由一套令牌驱动。
调研记录（含真实源码片段与参数）见 [docs/design-ref-flclash.md](docs/design-ref-flclash.md)，
页面改造的 API 契约见 [docs/motion-kit.md](docs/motion-kit.md)。

- **令牌**：`lib/theme/motion.dart` 的 `AppMotion` —— 时长 90/160/240/360/520/900ms 六档、
  四条曲线（standard / decelerate / accelerate / emphasized）、三档弹簧（`SpringCurve`，
  把物理弹簧塞进只吃 `Curve` 的 API）、列表错峰 42ms 步长（第 10 项封顶）。
- **动效组件**：`lib/ui/widgets/motion/` —— `EnterBox`（入场/错峰）、
  `PressInkWell`/`PressScale`（按压反馈）、`AnimatedCount`（数字滚动）、
  `AnimatedProgressBar`/`PulseDot`、`SkeletonBox/Line/Card/List`（骨架屏，壁钟对齐相位）、
  `SlideFadeSwitcher`/`SlidingHighlight`（内容与选项切换）、`SuccessBurst`/`showBurst`（成功那一下）、
  `SpringDriver`（保留速度的物理弹簧，`AnimationController` 做不到连点不打断手感）。
- **文字对比度**：色板新增 `palette.onColor(底色)` / `onColorSoft(底色)` ——
  **凡是字/图标落在有色底（主色、`primarySoft`、渐变、`colorScheme.*Container`）上都必须用它**，
  不能直接取 `text`。原因：`original` 主题的主色 `#1A1A2E` 与正文色是同一个值，
  `midnight` 的亮蓝主色同理，深底放深字会直接糊掉；`ColorScheme.fromSeed` 也只会按种子色
  自己推一套容器色。`AppTheme.build` 已把 Chip / SegmentedButton / NavigationBar /
  BottomSheet / Button / ListTile 等组件主题按 palette 显式收口，页面里剩下的用 `onColor`。
  取色不是拍脑袋：先按底色亮度判亮字还是暗字，再挑最柔但对比度仍达标的那个
  （`onColor` ≥ 4.5:1、`onColorSoft` ≥ 3.5:1），七套主题逐组由
  `flutter test --no-pub test/palette_contrast_test.dart`（42 条）自动守着。
  同理 **`textTertiary` 也校准过**：出厂值在白卡上只有 2.54:1（用户反馈「字和底看不清」
  的主因），现在七套主题都压在卡片底 ≥ 4.5:1、页面底 ≥ 4.0:1。
- **底部导航**：`lib/ui/shell/app_nav_bar.dart` —— FlClash 的弹簧透镜底栏移植版：
  栏级 `Listener` 统一处理按下/拖动/松手，三枚 `SpringDriver` 分别驱动「透镜位置 / 按压膨胀 /
  果冻拉伸」，透镜按速度拉长压扁（`_rubberBand` 橡皮筋），松手落位并 `HapticFeedback`。
  与 FlClash 的差异：不做 hover 磁吸、不做透镜放大镜与 gapless shader（Web 上 blur 太贵、
  Android 没有 hover），也不自持导航状态（只回吐 index，由 go_router 决定去向）。
- **页面转场**：全平台统一 **shared axis（水平）**（`AppMotion.pageTransitionsTheme`
  + `SharedAxisPageTransitionsBuilder`，用官方 `animations` 包的 `SharedAxisTransition`，
  `fillColor: Colors.transparent` 防过渡期铺底闪一下）。与 FlClash 同一选择。
- **主题切换**：MaterialApp 内置 `AnimatedTheme`，色板与玻璃底一起 lerp 过去（520ms emphasized）。
- **全局背景图**：`AppBackgroundLayer` 铺在所有页面之下（照片 + 一层薄纱 `palette.bgVeil`）；
  设了背景图时各页 Scaffold 背景透明、卡片转半透明玻璃底。
- **启动动画**：Flutter Web 首帧前是一块空白 canvas，`web/index.html` 先铺一层纯 HTML/CSS
  启动动画（🌱 呼吸 + 进度条扫光 + 「正在打开你的小世界…」，`prefers-reduced-motion` 时静止），
  首帧画好后由 `lib/core/boot_splash.dart` → `window.__sekainookBootDone()` 淡出撤除；
  HTML 侧另有 8 秒兜底（首帧前就崩了也不会一直挡着）。非 Web 平台走空实现 stub。
- **无障碍**：所有动效组件都读 `MediaQuery.disableAnimations`，系统关掉动画时直接落终点态。
- **怎么验收动效**：静态截图证明不了动画 —— 组件回归跑
  `flutter test --no-pub test/motion_widgets_test.dart`（12 个用例）与
  `flutter test --no-pub test/app_nav_bar_test.dart`（底栏 5 个用例）；
  要看/要抓中间态就加 `--dart-define=SLOW_MO=60` 构建（把 `timeDilation` 放慢 60 倍，
  默认 1 倍完全不生效），实拍见 `docs/shots/`。

## 契约文档（写代码前先查这里）

| 文件 | 内容 |
| --- | --- |
| [docs/api-contract.md](docs/api-contract.md) | 全部 19 个接口的字段级契约、任务规则总表、防刷闸门、日结算、数据表结构、80 条 Dart 易踩的坑、81 项验收清单 |
| [docs/contract-garden-store.md](docs/contract-garden-store.md) | 花园 store（阳光/勋章/商城/古诗/语文）的持久化格式、日切规则、逐函数逻辑、33 条坑 |
| [docs/contract-other-stores.md](docs/contract-other-stores.md) | 通知 / 主题 / 设置 / 自定义任务四个 store 的行为契约与持久化键 |
| [docs/parity-audit.md](docs/parity-audit.md) | 与 Web 版的功能对齐审计：逐页核对表、缺失项 M1–M9、行为不一致 I1–I10、交互形态差异 |
| [docs/parity-fixes.md](docs/parity-fixes.md) | 上述审计问题的处置记录：14 项已修复、3 项刻意保留的差异及理由、验证方式 |
| [docs/design-ref-flclash.md](docs/design-ref-flclash.md) | FlClash 设计/动效源码调研：圆角与层级体系、时长与弹簧参数、最值得移植的 5 条手法、明确不移植的部分 |
| [docs/motion-kit.md](docs/motion-kit.md) | 动效工具包契约：`AppMotion` 令牌表、全部动效组件的用法、页面改造清单、硬约束 |

## 与 Web 版的差异（有意为之）

1. **本地存储**：Web 版用 `localStorage`，Flutter 用 `shared_preferences`。
   键名保持一致，便于对照；Web 版与 Flutter Web 在同一浏览器里并不共享存储区，互不影响。
2. **家长口令**：Web 版在非安全上下文（http 打开）会把口令降级为明文存储；
   Dart 的 `crypto` 任何环境都能算摘要，所以 Flutter 侧**一律存摘要**，
   但**读取**仍兼容 Web 版留下的 `plain:` 前缀与无前缀裸明文。
3. **上传**：Web 版 `fetch` 直接发 `arrayBuffer`；Flutter 侧对应 `ApiClient.postBytes`，
   同样发裸二进制（**不是 multipart**）。
4. **图表**：Web 版用 echarts，Flutter 用 `fl_chart`。
5. **通知轮询**：间隔与 Web 版一致（15 秒），且在应用退到后台时跳过。
   页面级轮询（首页 20s / 账本页 10s·15s）同样在后台跳过，回到前台立刻补一次
   —— 对应 Web 版轮询里的 `document.hidden` 判断。
6. **导出流水**：Web 版靠浏览器下载 CSV 文件；Flutter 侧（Android 没有下载目录概念，
   又不引 `share_plus` / `path_provider`）改为**复制到剪贴板**并提示已复制。
   导出的内容本身与 Web 版同构（同样的表头与行序）。
7. **22:00 判定口径**：与 Web 版一致用**设备本地时间**（`DateTime.now().hour`），
   不是东八区；东八区那套只服务 `/api/ledger/settle` 的日结算
   （`FamilyState.expectedSettleDay`）。App 内首页与账本页现在是同一口径。
8. **不加全局顶栏**：Web 版 `MainLayout` 有一条顶栏（页面名胶囊 + 余额胶囊 + 通知铃铛 +
   深浅开关），Flutter 版不复制 —— 目标是 375px 手机宽度，各页自带头部，
   余额/通知/深浅在首页与设置页都已各有入口。未读角标按 Web 版挂法挂在「首页」Tab。
9. **不做「chunk 加载失败自动刷新」**：Web 版命中旧 chunk 404 会先自动刷新一次
   （`sessionStorage: sekainook_chunk_autoreload`）；Flutter Web 是 AOT 单包，
   没有这种失败模式。错误兜底改为 `ErrorWidget.builder` 的中文卡片 + 手动「重新加载」
   （见 `lib/core/app_error.dart`）。
