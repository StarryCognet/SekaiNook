# SekaiNook UI 全量替换为 FlClash 0.9.1 自研 UI · 迁移计划

> 目标：把 SekaiNook-App 的**全部界面**换成 FlClash v0.9.1 的 `lib/ui` 组件库（90 文件 / 29,521 行 / 300 个公开声明）与它的设计系统（超椭圆形状、四层表面色、液态玻璃、Glyph 图标）。
> 本文是**计划**，不是执行记录。§6 的 5 项决策已定稿（2026-10-21），按此执行。

---

## 0. 结论先行：可行性已实测

**关键实验（已跑）**：把 FlClash v0.9.1 的整个 `lib/ui` 只做一件事——`package:material_ui/material_ui.dart` → `package:flutter/material.dart`——然后在本机 Flutter 3.47.7 上 `flutter analyze`：

- **0 error / 0 warning**，只剩 71 条原库自带的 info（`prefer_initializing_formals` 之类）。
- 说明 `lib/ui` 对 `material_ui` 的依赖**只在 import 层**，用到的 API 全是 `flutter/material` 也有的东西；`RoundedSuperellipseBorder` 来自 `material_new_shapes`（基于 `flutter/painting`，与 `flutter/material` 天然兼容）。

**因此路线确定**：

> 把 `lib/ui` 原样搬进 SekaiNook，改 import + 改包名；**不动** SekaiNook 的 `MaterialApp` / `go_router` / `provider` / `fl_chart` / 发版链路。**不要**反向把全仓迁到 `material_ui`——`go_router`、`fl_chart`、`provider` 内部都 import `flutter/material.dart`，两套 `ColorScheme`/`Page`/`ThemeData` 类型会全面冲突，不可行。

**真实工作量不在"库适配"，而在：**

1. 19,444 行业务 UI 的逐页重写（6 个 1500+ 行的页面占 13,283 行）；
2. 主题系统改建（7 套自研色板 → FlClash 的 seed + 4 档 ColorStyle，含老用户设置迁移）；
3. 图标系统全量切换（100 个不同 Material 图标 → Glyph，约 60–70 枚需新绘）；
4. 液态玻璃的真机性能验证（AGENTS.md 有明确的"卡过、已回滚"前车之鉴）；
5. 每批次的发版链路（changelog → 版本号 → APK → latest.json）。

**估算：12–14 个工作日**，分 5 批发布，每批可独立回滚。

---

## 1. 现状盘点（2026-10-21）

### 1.1 代码规模

| 层 | 文件数 | 行数 |
|---|---|---|
| 全部 dart | 85 | 29,366 |
| UI（页面+壳+组件+主题） | — | 19,444 |

页面行数 Top：`family_dashboard_page` 2785、`settings_page` 2537、`kid_home_page` 2368、`garden_page` 2310、`selftest_panel` 1923、`parent_home_page` 1570、`weekly_plan_page` 766、`notifications_page` 630、`push_section` 596、`reminder_editor_sheet` 459、`role_gate_page` 366、`reminder_list` 251；壳：`app_nav_bar` 470、`main_shell` 241、`back_intent` 77；组件：`update_dialog` 336、`task_row` 277、`app_card` 221、`state_views` 194；主题：`app_theme` 688、`motion` 246、`tokens` 51。

### 1.2 现有 Material 用量（决定替换成本）

`Card(` 155、`TextButton(` 40、`FilledButton(` 33、`SnackBar(` 33、`CircularProgressIndicator(` 22、`OutlinedButton(` 17、`TextField(` 16、`Scaffold(` 7、`IconButton(` 4、`TabBar(` 1；0 处 AppBar / ListTile / BottomNavigationBar / NavigationBar / Drawer / showDialog / showModalBottomSheet（这些早已自绘）。

> 含义：现有 UI 是"自研外壳 + Material 零件"的混合体，不是纯 Material 应用。替换不是换主题，是把零件逐个换成 `lib/ui` 的同位组件。

### 1.3 已有的 FlClash 研究资产

`docs/design-ref-flclash.md`（1257 行）是**旧版调研**：对象是 FlClash `main` 分支 0.9.0 的 `lib/widgets`（旧结构），不是 0.9.1 的 `lib/ui`。可复用的结论：

- 超椭圆圆角是"贵"的来源；`AppCorner` 六档一次性对齐 15 个组件；
- `SpringCurve` + 100/200/300ms 三级时长体系；
- 页面转场用 shared-axis 450ms；骨架屏壁钟对齐呼吸；
- Web 上大面积 `ImageFilter.blur` 开销高。

### 1.4 不可破坏的不变量

1. `AGENTS.md` 全部条款（发版流程、不用 `dart format`、不用 `--split-per-abi`、`context.go`、`BackIntentHandler`、不叠 `BackdropFilter`、更新链路别动、签名库别删、图标别手改）。
2. 业务逻辑、数据层（`lib/data`、`lib/state`、`lib/core`、`lib/config`）**一行不改**（主题状态字段的迁移除外，见 §2.2）。
3. **主题系统按已决策改建**：7 套自研主题 → seed 色 + 4 档 ColorStyle；必须处理老用户本地存储的 `themeId` 迁移，对比度门槛不变。
4. 发版链路：`changelog.ts` → `changelog:fallback` → `changelog:sync` → `publish_apk.ps1` → `latest.json` 核对。
5. 自定义背景图功能（`AppBackgroundLayer` + `surfaceGlass` 半透明卡片）保留。

---

## 2. 技术方案

### 2.1 移植 `lib/ui` → `lib/fl_ui/`

**目录**：新建 `lib/fl_ui/`（独立于现有 `lib/ui/` 业务目录，避免命名冲突；业务页面按批次原地重写，不搬目录）。

改动清单（可脚本化，见 §7）：

1. `package:material_ui/material_ui.dart` → `package:flutter/material.dart`（约 70 处）。
2. `package:fl_clash/` → `package:sekainook_app/fl_ui/`（跨文件引用；推荐包名替换，便于以后对比上游）。
3. 保留 3 处 Web 兼容 patch（SekaiNook 同时构建 Flutter Web）：
   - `keyboard.dart` / `scroll_behavior.dart`：`dart:io Platform` → `defaultTargetPlatform`；
   - `liquid_glass.dart`：`pushClipRSuperellipse(..., clipBehavior: ui.Clip.antiAlias)`（flutter_web_sdk 把该参数设为 required）。
4. **不要**带 `material_ui` 依赖进 pubspec。

**新增依赖**（都是 FlClash 已在用、体积小的官方/半官方包）：

```yaml
material_new_shapes: ^1.0.0      # RoundedSuperellipseBorder（超椭圆）
material_color_utilities: ^0.13.0 # Hct / seededColorScheme
collection: ^1.19.1
emoji_regex: ^0.0.5
freezed_annotation: ^3.1.0
path_parsing: ^1.1.0
super_sliver_list: ^0.4.1
# animations ^3.0.0、intl ^0.20.3 已有
```

**新增资源**：

- `shaders/liquid_glass.frag` + pubspec `shaders:` 段（液态玻璃唯一硬依赖）；
- `assets/fonts/JetBrainsMono-Regular.ttf`（273 KB）；
- **不引入** `Twemoji.Mozilla.ttf`（1.45 MB，emoji 走系统字体）。

**本地化**：`lib/ui` 的 `UiLocalizations` 是抽象类（14 个 getter：back/cancel/clearSearch/close/hidePassword/more/noSearchResults/reset/search/showLess/showMore/showPassword/sort/submit）。在 `lib/fl_ui_zh.dart` 实现中文 delegate，注册进 `MaterialApp.localizationsDelegates`。

**验收**：`flutter analyze --no-pub lib/fl_ui` 0 error；空壳页渲染 `CommonCard` + `TonalButton` + `ListItem` + `CommonCircleLoading` 无异常。

### 2.2 主题链改造（已决策：换成 FlClash 的 seed + 4 档 ColorStyle）

目标形态：

```dart
// ThemeState 的持久化字段（替代原 themeId）
String seedColor;          // 主色 seed，如 #1A1A2E
ColorStyle colorStyle;     // vivid / tinted / soft / monochrome
bool pureBlack;            // 纯黑（仅深色）

ThemeData build() => ThemeData(
  useMaterial3: true,
  colorScheme: seededColorScheme(
    seedColor: parseHex(seedColor),
    brightness: bright ? Brightness.dark : Brightness.light,
    style: colorStyle,
  ),
  pageTransitionsTheme: _pageTransitions(),   // FlClash shared-axis 曲线
  actionIconTheme: _actionIconTheme,          // GlyphIcon(back/close)
  extensions: [AppPalette.businessOnly()],    // 只留 success/danger/warning 等语义色
).withAppShapes.withAppSurfaces.withAppTypography;
```

具体改造点：

1. **`app_theme.dart`（688 行）整体重写**：删除 7 套 `AppPalette` 色板常量，改由 `seededColorScheme` 生成；`AppPalette` 收缩为业务语义色扩展（success/danger/warning + `onColor()` 对比度选色 + `bgVeil`）。页面继续读 `context.palette`，不感知底层变化。
2. **`ThemeState` 字段迁移**：`themeId` → `seedColor + colorStyle + pureBlack`。SharedPreferences 旧键迁移：首次启动读到旧 `themeId` 时按映射表转换（original→#1A1A2E、midnight→#10131C、sakura→#E8749A、forest→#2E7D5B、sunset→#F2994A、crimson→#C0392B、graphite→#4A5568），转换后写回新键并清旧键。
3. **设置页主题选择器重写**：7 宫格主题缩略图 → 「主色色板（12 色预设 + 自定义）+ 色彩风格 4 档 + 亮暗 + 纯黑开关」，交互复用 FlClash 的 `SegmentedControl` / `ListItem` / `ColorStyle` 预览卡。
4. **`palette_contrast_test.dart` 重写**：从"7 套固定色板"改为"seed × 4 档 style × 2 brightness 全组合，卡片底 ≥4.5:1 / 页面底 ≥4.0:1"。
5. **背景图功能保留**：`hasBackground` 时卡片用 `surfaceGlass` 半透明；与纯黑、液态玻璃互斥关系明确写进设置页提示。

### 2.3 壳与导航（已决策：直接换 NavigationDock）

- `MainShell`（轮询 / 返回栈 / 更新检查）**逻辑一行不改**，只换视觉：
  - 手机：`AppNavBar`（470 行）整体替换为 `NavigationDock` + `FloatingNavigationBar` + `ElasticButton`（1836 行浮动 dock：弹性按压、透镜、拖拽选择、水波纹）。注意触屏/鼠标差异，Android 与 Web 都要点检。
  - 宽屏 / Web：`NavigationSidebar`（展开 240 / 收起 72）+ `navigator_resizable`。
- 二级页（设置分区、提醒编辑、自检面板）→ `sheet` / `snap_sheet` / `side_sheet` 替换现有自绘弹层。
- 页面转场：FlClash `page_transition.dart` 的 shared-axis 曲线（450ms），保留 `BackIntentHandler` 语义（别自己套 `PopScope`）。
- 注意：`NavigationDock` 的 5 个 tab 数量与现有路由（/home、/family、/garden、/settings + 通知）需对齐；若 tab 数不完全匹配，按 FlClash 的 dock 配置裁剪。

### 2.4 组件映射表

| SekaiNook 现状 | 替换为（FlClash lib/ui） | 备注 |
|---|---|---|
| `AppCard`（221 行自绘） | `CommonCard` | 水波纹→ElasticPress；选中态用 `isSelected` |
| `SectionHeader` | `ListHeader`（带 `IconButtonData` actions）或 `CommonCard` 的 header | 视觉再微调 |
| `StatBlock` + `AnimatedCount` | **保留业务组件**，数字样式换 `AppTextStyle.title1` + `kTabularNumbers` | 业务专用，不硬套 |
| `task_row`（277 行） | `ListItem` + `.toggle` / `.checkbox` / `.options` / `.open` | 最划算的一处 |
| `state_views`（加载/空/错） | `CommonCircleLoading` / `NullStatus`（20 种插图）/ `NullStatusSwitcher` | 空态立刻高级一档 |
| `update_dialog`（336 行） | `CommonDialog` / `snap_sheet` | 更新链路逻辑别动 |
| `SnackBar` ×33 | **新建 `AppToast`**（Overlay + FlClash Surface 风格） | `lib/ui` 没有 SnackBar 对应物 |
| `FilledButton`/`TextButton`/`OutlinedButton` ×90 | `TonalButton` / `TonalButtonGroup` / `MoreActionButton` | 胶囊 + 三档尺寸（bar/section/compact） |
| `TextField` ×16 | `FilledInputTheme` + `SecretTextFormField` / `SearchField` / `InputDialog` | 输入框超椭圆 |
| `Card(` ×155 | `CommonCard` | 部分可 sed 批量 |
| `CircularProgressIndicator` ×22 | `CommonCircleLoading` | 或 `.page` |
| `Icon(Icons.xxx)` ×100 种 | `GlyphIcon(AppGlyphs.xxx)` **全部替换**；业务图标补绘（见 §2.6） | |
| `TabBar` ×1 | `SegmentedControl` | |
| `Scaffold(` ×7 | 独立页用 `CommonScaffold`；ShellRoute 内页面**不要**套（会双层 toolbar） | 见 §5 风险 3 |
| `motion/` 8 组件 | `ElasticPress` / `FadeBox` / `FadeScaleEnterBox` / `AnimatedEntries` / `Skeleton` | 旧 `AppMotion` 曲线可保留 |
| `fl_chart` | **保留** | FlClash `LineChart` 只适合速率曲线，不通用 |
| `AppBackgroundLayer` | **保留** | 与液态玻璃互斥（见 §2.5） |

### 2.5 液态玻璃策略（已决策：默认关）

- 原理：`FragmentShader` + 场景背景捕获（`liquid_glass_capture.dart` 895 行），比 `BackdropFilter` 省，但仍是每帧 GPU 成本。
- AGENTS.md 有前车之鉴：1.31.6 真机 `BackdropFilter` 太卡 → 1.31.8 全量回滚。**FlClash 的 shader 版不等于 BackdropFilter，但同样必须真机实测后才能默认开。**
- 策略：
  1. 默认 `LiquidGlassScope(enabled: false)`；设置页加"液态玻璃"开关 + 质量档（standard / ultra）；
  2. 仅导航栏、浮层、少量关键按钮启用，**长列表项一律不用**；
  3. shader 加载 `try/catch`，失败降级为无玻璃（低端 GPU / 部分 WebGL）；
  4. 关闭时零 shader 开销（`LiquidGlassHost(enabled:false)` 直接透传）；
  5. 背景图模式（`hasBackground`）继续用现有 `surfaceGlass` 半透明，不叠玻璃 shader——二者选一。

### 2.6 图标（已决策：全部换 Glyph）

- 现状扫描：全仓用到 **100 个不同**的 Material 图标。可映射现有 `AppGlyphs`（121 枚）的通用操作约 30–35 个（back/close/search/settings/add/remove/delete/edit/check/star/calendar/clock/lock/cloud/wifi/refresh/export/import/copy/filter/sort/pin/history…）。
- 其余约 65 个业务图标需**新绘**：`local_florist`（花）、`eco`（叶/种）、`emoji_events`（奖杯）、`savings`/`account_balance_wallet`（储蓄/钱包）、`monetization_on`（积分币）、`fact_check`/`task_alt`/`checklist`（打卡/核对）、`menu_book`/`chrome_reader_mode`/`auto_stories`（书）、`local_fire_department`（连续火焰）、`calendar_today`/`event`/`schedule`（日历/提醒）、`storefront`/`card_giftcard`（商店/礼物）、`family_restroom`（家庭）、`bedtime`/`wb_sunny`/`light_mode`/`dark_mode`（昼夜）、`local_dining`/`local_laundry_service`/`cleaning_services`（家务）、`park`、`bolt`、`trending_up/down`、`receipt_long`、`dashboard`、`inbox`、`photo_camera`、`palette`、`tune` 等。
- 绘制规格：沿用 `lib/ui/icons/` 的 Glyph 原语（`GlyphBox` / `GlyphCircle` / `GlyphPolyline`），24×24 网格、按 detail 角色区分描边粗细，每枚约 10–30 行；新图标追加到独立文件 `lib/fl_ui/icons/app_business_glyphs.dart`，**不改上游 `app_glyphs.dart`**，便于以后对照 FlClash 上游。
- **不手改** `android/app/src/main/res/mipmap-*` 与 `web/icons/*`（AGENTS.md 规定由 `.icon-work/` 管线生成）。

---

## 3. 分批计划（每批可独立发版、独立回滚）

| 批次 | 版本 | 内容 | 验收 | 估算 |
|---|---|---|---|---|
| **批 1** | v1.32.0 | 移植 `lib/fl_ui` + 主题链重写 + 主题设置页重写 + 老设置迁移 + 中文本地化 + 壳（NavigationDock/Sidebar）+ `AppCard`/`task_row`/`state_views`/`CommonCircleLoading` 映射 | analyze/test 绿；`/role`、`/home`、`/settings` 首屏真机点检；seed×style 全组合对比度测试过；老用户升级后主题设置不崩 | 3 天 |
| **批 2** | v1.32.1 | 按钮（90 处）/ 输入（16）/ 对话框 / 弹层（sheet/snap_sheet）/ `AppToast`（33 处 SnackBar）/ 进度环（22）/ 通用图标（约 35 枚映射） | 全仓 `grep FilledButton\|TextButton\|SnackBar` 归零；交互回归（更新弹窗、提醒编辑、自检面板） | 2 天 |
| **批 3** | v1.33.0 | 页面 A：`role_gate`、`kid_home`、`parent_home`、`garden`（fl_chart 保留）+ 业务图标第一批（约 30 枚） | 4 页真机点检；家庭/积分/花园流程 e2e | 3 天 |
| **批 4** | v1.34.0 | 页面 B：`family_dashboard`、`weekly_plan`、`notifications`、`settings` 系列（settings/push/reminder×2/selftest）+ 业务图标收尾 | 家长端全流程；设置全分区；自检面板 | 3.5 天 |
| **批 5** | v1.35.0 | 动效统一、骨架屏、LiquidGlass 真机调优与默认值决策、测试补齐、`AGENTS.md` 规则更新、文档 | 中低端真机帧时间对比；全量 test；文档 | 2 天 |

**总计 ≈ 13.5 个工作日**（不含真机返工与审核等待）。每批结束都必须走 AGENTS.md 的发版链路。

---

## 4. 测试与验收

**保留不动**：`api_smoke_test`、`e2e_flow_test`、`back_intent_test`、`local_notify_test`、`reminder_parity_test`、`week_label_test`、`garden_flow_test`、`app_update_test`。

**需重写**：`palette_contrast_test`（改为 seed×style 全组合）、`app_nav_bar_test`（换成 dock 后）、`motion_widgets_test`、`update_dialog_test`、`nav_opacity_test`。

**新增**：

- `lib/fl_ui` 冒烟 test：pump `CommonCard` / `TonalButton` / `ListItem` / `NullStatus` / `CommonScaffold` / `NavigationDock`；
- 主题迁移 test：7 个旧 `themeId` → seed 映射正确、读写 SharedPreferences 兼容；
- 液态玻璃开关 test：`enabled:false` 时零 `LiquidGlass` 实例。

**真机**：用户自有中低端 Android + Web；每批点检关键页；批 5 用 DevTools timeline 对比玻璃开/关的帧时间。

---

## 5. 风险与对策

| # | 风险 | 对策 |
|---|---|---|
| 1 | 19k 行页面重写回归 | 分批；逐页替换、旧文件替换完成前不删；每批真机点检 |
| 2 | LiquidGlass 真机卡顿（有历史教训） | 默认关 + 开关 + 质量档 + 真机 A/B；关闭时零 shader 成本 |
| 3 | `CommonScaffold` 与 `MainShell`/GoRouter 双层脚手架 | ShellRoute 内页面**不套** `CommonScaffold`；只在独立页（`/role`）用 |
| 4 | GoRouter 页面转场不生效 | 全局 `PageTransitionsTheme` 只对 `MaterialPage` 生效；需要时给 `pageBuilder` 换 `CustomTransitionPage` |
| 5 | 液态玻璃与背景图功能重叠 | 二者互斥：有背景图走 `surfaceGlass`，无背景图才允许开玻璃 |
| 6 | **主题改建让老用户视觉突变** | 迁移映射表 + changelog 明确说明 + 设置页保留纯黑/亮暗直达；`palette_contrast_test` 扩到全组合 |
| 7 | **65 枚业务图标补绘量大** | 分批画；先映射 35 枚通用图标保底，业务图标按页面批次补齐；宁可少画也不留 Material 图标混用（已决策全换） |
| 8 | `NavigationDock` 在触屏/鼠标行为差异 | 手机与 Web 分别点检；必要时裁掉 hover/lens 相关逻辑 |
| 9 | 体积增加（shader + 字体 + 新依赖） | 不带 Twemoji（省 1.45MB）；依赖均轻量；APK 体积每批对比 |
| 10 | `AGENTS.md` 规则与新库冲突 | 批 5 更新：卡片改"一律 `CommonCard`"；澄清"不叠 BackdropFilter"不禁止 FlClash shader 玻璃（但默认关）；主题条款改为 seed+ColorStyle |
| 11 | 发版审核/真机更新链路只能设备验证 | 每批照旧发版并在真机走一次更新流程；说清楚哪步没实跑 |

---

## 6. 决策记录（2026-10-21 已定稿）

| # | 议题 | 决定 |
|---|---|---|
| 1 | 液态玻璃默认状态 | **默认关**；设置里可开，质量档 standard/ultra；真机验证后再考虑改默认 |
| 2 | 主题系统 | **换成 FlClash 的 seed + 4 档 ColorStyle**（vivid/tinted/soft/monochrome），7 套旧主题映射为 7 个 seed 供迁移 |
| 3 | 底部导航 | **直接换 NavigationDock**（+ FloatingNavigationBar + ElasticButton） |
| 4 | 图标 | **全部换 Glyph**：约 35 枚映射现有图标，约 65 枚新绘 |
| 5 | 交付节奏 | **分 5 批，每批发一版**，可独立回滚 |

---

## 7. 现在就能开始、不需要再决策的第 0 步

1. 建 `lib/fl_ui/`，把 `lib/ui` 90 个文件搬进来；
2. 写一次性脚本（`tool/port_fl_ui.sh` 或 PowerShell）做 import/包名替换 + 校验，**可重复运行**；
3. 跑 `flutter analyze --no-pub lib/fl_ui` 出《移植差异报告》；
4. 把 `shaders/liquid_glass.frag`、`JetBrainsMono-Regular.ttf` 加进资源，pubspec 补依赖，`flutter pub get`；
5. 这一步不改任何业务代码，随时可 `git checkout` 撤销。

**上游对照**：FlClash v0.9.1 源码镜像 `E:\Git\FlClash-0.9.1`；可交互组件展示站 `E:\Git\FlClash-UI-Lab`（覆盖 90 文件/36 个 demo，含 3 处 Web patch 说明）。

---

## §8 执行记录（批 1 · 库 + 主题链 + 壳）

### 已完成

| 项 | 文件 | 说明 |
|---|---|---|
| 移植库 | `lib/fl_ui/`（92 文件 / 29,610 行） | 从 FlClash v0.9.1 `lib/ui` 复制；`material_ui` → `flutter/material`；3 处 Web patch 保留 |
| 中文文案 | `lib/fl_ui_zh.dart` | `FlUiZhLocalizations`（14 个 getter）+ `FlUiZhDelegate` |
| 主题链 | `lib/theme/flclash_theme.dart` | `FlThemeId` 7 套迁移预设；`FlThemeSpec`（seed/brightness/style）；`buildFlClashTheme()` = seededColorScheme + withAppShapes/Surfaces/Typography + 4.5:1 对比度兜底 |
| 旧色板适配 | `lib/theme/flclash_palette.dart` | `appPaletteFromScheme()` 把新 ColorScheme 映射回 `AppPalette`，迁移期旧页面继续读 `context.palette` |
| 主题接线 | `lib/app.dart` | `_buildTheme()`；MaterialApp.builder 挂 `MeasureScope`/`ViewScope`/`LiquidGlassScope`/`LiquidGlassHost` |
| 主题设置数据 | `lib/state/theme_state.dart` + `app_constants.dart` | `colorStyle`（null=跟随预设）、`liquidGlass`（默认关）、`glassQuality` |
| 壳 | `lib/ui/shell/main_shell.dart` | `Scaffold + AppNavBar` → `NavigationDock`（Glyph 图标 + badge） |
| 底栏几何兼容 | `lib/ui/shell/app_nav_bar.dart` | 旧文件收敛为 `AppNavBar.contentInset()` 兼容层（页面暂不用改） |
| Dock 角标扩展 | `lib/fl_ui/navigation_dock.dart` | `NavigationDockDestination.badge` + `_DockBadge`（FlClash 原件没有，SekaiNook 扩展） |
| 测试 | `test/flclash_theme_test.dart`（14）、`test/fl_ui_smoke_test.dart`、`test/navigation_dock_test.dart`（2） | 全绿 |
| 工具 | `tool/port_fl_ui.sh`、`tool/apply_pubspec.py`、`tool/screenshot.mjs`、`tool/interact.mjs`、`tool/login.mjs` | 可重复执行 |

### 验证

- `flutter analyze --no-pub`：**0 error / 0 warning**（109 info，71 条来自 lib/fl_ui 上游、其余为既有风格提示）。
- `flutter test --no-pub`：146 通过 / 1 失败（`garden_flow_test` 需真实后端，**基线即失败**，已用 stash 验证）。
- `flutter build web --debug` 成功（≈100s）；headless Chrome 截图确认：登录页、家长口令弹窗、新底栏（5 tab + 选中胶囊 + Glyph 图标）均正常。
- 中文字体在 headless 环境显示为方块，原因是 `fonts.gstatic.com` 不可达（Flutter Web CanvasKit 的 Noto fallback 走网络），**非代码问题**；第二次加载（有缓存）中文/emoji 正常。

### 已知缺口 / 延后项

1. **设置页主题选择仍用旧 `AppTheme.all`**：7 套名字与描述还在，点击切到的是映射后的新 seed，色板 swatch 还是旧颜色 → 批 4 换成 `FlThemePreset.migrated` 并加 ColorStyle 四档选择。
2. **ColorStyle / LiquidGlass 开关没有 UI 入口**（数据层已就绪）→ 批 4 设置页。
3. **「底栏不透明度」设置失效**：新 `NavigationDock` 没有 opacity 参数（玻璃底由 LiquidGlass 决定）→ 批 4 决定保留（给 Dock 加 tint 扩展）还是移除该设置。
4. 各页面仍用 Material 组件与旧 `AppNavBar.contentInset` → 批 2/3/4 逐页替换。

### 下一步

批 2（v1.32.1）：按钮/输入/弹层/AppToast/进度环 —— `FilledButton→TonalButton`、`TextButton→MoreActionButton`、`SnackBar→AppToast`、`CircularProgressIndicator→CommonCircleLoading`、`TextField→FilledInputTheme+SecretTextFormField`。

---

## §9 执行记录（真实仓库 · 批 1 · 2.2.0）

> **基线修正（2026-10-21）**：本计划的基准仓库是 `E:\Git\SekaiNook`（monorepo：网页 + `app/` Flutter 子目录），当前版本 **2.1.5+28**。早前的 `E:\Git\SekaiNook-App` 是 2026-10-19 的过期快照（1.31.18+20、无 git remote），§0–§8 只作设计与验证参考，**代码以 monorepo 的 `app/` 为准**。

真实基线已有（2.1.x 已吸收的部分，批 1 不需要重做）：

- `lib/theme/app_shape.dart`：超椭圆 `AppShape.all/top/bottom/pill/card/dialog/sheet/input/of` + `AppInputBorder`
- `lib/theme/app_theme.dart`：7 个种子色（rose/brown/blue/yellow/grayblue/green/purple）、`AppPalette.fromSeed`、`AppTheme.build(dark/pureBlack/textScale/dynamicSeed)`、`NoSplash`、`AppMotion.pageTransitionsTheme`
- `lib/ui/shell/app_nav_bar.dart`：自研弹簧透镜底栏（751 行，参考 FlClash 但未用其代码）
- `lib/ui/widgets/motion/*`：elastic_press / press_scale / spring_driver / skeleton / empty_illustration 等

批 1（2.2.0，2026-10-21）实际改动：

| 内容 | 文件 |
|---|---|
| 移植 FlClash v0.9.1 lib/ui（92 文件 29,610 行，import 改写为 `flutter/material` + 包名 `sekainook_app`） | `app/lib/fl_ui/` |
| 中文本地化（14 个文案） | `app/lib/fl_ui_zh.dart` |
| 7 个依赖 + 资源（JetBrainsMono 字体、liquid_glass.frag） | `app/pubspec.yaml`、`app/assets/fonts/`、`app/shaders/` |
| 作用域链（MeasureScope / ViewScope / LiquidGlassScope / LiquidGlassHost，玻璃默认关） | `app/lib/app.dart` |
| 底栏换 `NavigationDock`（Glyph 图标 + badge 扩展） | `app/lib/ui/shell/main_shell.dart`、`app/lib/fl_ui/navigation_dock.dart` |
| `AppNavBar.contentInset` 委托 `NavigationDock.insetOf` | `app/lib/ui/shell/app_nav_bar.dart` |

验证：

- `flutter analyze --no-pub`：**0 error / 0 warning**（99 info：71 条来自 lib/fl_ui 上游、28 条既有风格提示）
- `flutter test --no-pub`：**198 全绿**
- `flutter build web --debug` 成功（≈113s）
- headless Chrome 截图确认：首页 / 设置 / 家庭三页渲染正常，新底栏 5 个 Tab 切换正常（家庭 Tab 角标正确显示）

已知缺口（承接 §8，另加）：

1. 主题仍用 `AppPalette.fromSeed`，尚未叠加 FlClash 的 `withAppShapes/withAppSurfaces/withAppTypography` 与 `ColorStyle` 四档 → 批 2
2. 页面仍用 Material 组件与旧色板 → 批 2/3/4 逐页替换
3. 底栏不透明度设置随旧 `AppNavBar` 一起失效（NavigationDock 无 opacity 参数）→ 批 4 决定保留（给 Dock 加 tint）还是移除
4. 液态玻璃设置入口未接（库已就绪、默认关）→ 批 4

---

## §10 执行记录（真实仓库 · 批 2 · 2.2.1）

批 2 的主题是「横切交互语言」：先把**全站的提示条**与**等待转圈**收敛成 FlClash 的两件套。按钮/输入/弹层的结构替换被有意推迟（见文末原因）。

新增与替换：

| 内容 | 文件 |
|---|---|
| `AppToast`：超椭圆浮动卡片提示（neutral/success/warning/error 四档语义色淡底 + Glyph 图标 + 可选撤销动作） | `app/lib/ui/widgets/app_toast.dart`（新） |
| `AppLoading`：FlClash 彗星环包装（替代 `CircularProgressIndicator`） | `app/lib/ui/widgets/app_loading.dart`（新） |
| 9 个页面的 `_toast()` helper 内部换成 `AppToast.show()`，**调用点一行未动** | family_dashboard / weekly_plan / garden / kid_home ×2 / parent_home / notifications / selftest_panel / settings_page / update_dialog |
| 12 处 `CircularProgressIndicator` → `AppLoading`（6 个文件） | kid_home / notifications / parent_home / role_gate / selftest_panel / settings_page / family_dashboard / weekly_plan |
| 保留 2 处**确定性进度环**（带 `value` 的兑换进度、周计划完成环） | family_dashboard_page:1324、weekly_plan_page:367 |
| 单测：`test/app_toast_test.dart`（2 例，Toast 渲染 + Loading 渲染） | `app/test/app_toast_test.dart`（新） |

验证：

- `flutter analyze --no-pub`：**0 error / 0 warning**
- `flutter test --no-pub`：**197 通过 / 3 失败**，3 个失败均为真实后端集成测试（`api_smoke_test` / `e2e_flow_test` / `garden_flow_test`，基线即失败）
- `flutter build web --debug --no-pub`：成功（122s）
- 全站 `SnackBar(` 只剩 `app_toast.dart` 内部一处（其他页面全部收敛）

有意留下的（为什么不在批 2 做）：

1. **按钮换 `TonalButton`**：FlClash 的 `TonalButton` 只接受 `Glyph` + `String label`，而 SekaiNook 现有按钮带 `IconData` 图标（约 100 个 Material 图标），要先有 Glyph 映射/新绘——放到批 3 和图标系统一起做，避免二次返工。
2. **输入框**：`inputDecorationTheme` 在 2.1.5 已经是 `AppInputBorder`（超椭圆 + filled），TextField 视觉已对齐，不需要逐个改。
3. **弹层（showDialog 21 处 → CommonDialog）**：每处弹窗内容结构不同，跟页面重写一起做更稳（批 3/4）。

进程记录：`changelog:sync`（推 D1）在发版时两次 `fetch failed`（网络波动），但 APK 内置的 `changelog.dart` fallback 已生成 2.2.1（76 条），App 内日志不受影响；D1 同步已在发版后补跑成功（`npm run changelog:sync` → 同步完成，自检 env.changelog=ok）。
