# 功能对齐：审计问题的处理记录

对应审计报告 [parity-audit.md](parity-audit.md)。
本文记录**每条问题的最终处置**，以及刻意保留的差异及理由。

> ⚠️ 审计报告写于两个仓库合并之前，里面的行号与部分结论**已经过时**：它记的「无全局错误边界」
> 「底部导航少『学习计划』」「未读角标挂设置 Tab」在逐项核验时发现早已修好。**以本文为准。**

## 一、已修复

| # | 审计项 | 处置 | 落点 |
| --- | --- | --- | --- |
| M1 | 首页宫格/头像/入口的跨页定点跳转全部失效（10 处落点丢失） | 17 处跳转全部带上落点参数（孩子端 10、家长端 7），参数名走 `GardenConfig.menuParam` 常量 | `ui/pages/home/kid_home_page.dart`、`ui/pages/home/parent_home_page.dart` |
| M2 | 「导出流水」不是文件（只复制到剪贴板） | **真导出文件**：三平台分支（Web 直接下载 / Android 走系统分享面板 / 其余抛 `UnsupportedError`），文件名 `sekainook-流水-YYYY-MM-DD.csv`（取**本地**日期），内容带 UTF-8 BOM 好让 Excel 认中文 | `core/ledger_export*.dart`（5 个新文件）、`core/ledger_csv.dart`、`ui/pages/home/parent_home_page.dart`、`ui/pages/family/family_dashboard_page.dart` |
| M3 | 学习记录页缺「今日已完成」清单 | 补上任务名 + 完成时刻 + 奖励标签，空态文案与 Web 一字不差 | `ui/pages/garden/garden_page.dart` |
| M4 | 无全局错误边界 | `ErrorWidget.builder` 装中文兜底卡片（🌱 + 页面出了点问题 + 重新加载），`PlatformDispatcher.onError` / `FlutterError.onError` 留痕 | `core/app_error.dart`、`main.dart`、`app.dart` |
| M5 | 底部导航少「学习计划」Tab | 补第 5 格；并把周计划页、通知页一并收进 `ShellRoute` | `ui/shell/main_shell.dart`、`router.dart` |
| M6 | 无全局顶栏 | **补上全局顶栏**：左侧页面名胶囊、右侧通知铃铛（带未读角标）与太阳/月亮深浅开关；**真悬浮**——不占 `Scaffold.appBar` 槽，挂在 body 的 `Stack` 顶层（`Positioned(left: 0, right: 0)`，须 `StackFit.expand`），内容从屏顶铺下来、能从胶囊后穿过；各页用 `AppTopBar.contentInset(context)` 顶部让位（13 处滚动容器） | `ui/shell/app_top_bar.dart`（新建 + `contentInset`）、`ui/shell/main_shell.dart`、8 个页面文件各加一行 import |
| M7 | 通知筛选不记忆 + 孩子端首页无实时时钟 | 筛选落 `SharedPreferences`（键 `sekainook_notice_filter`）且地址栏仍可深链；首页 20 秒轮询每轮重取 `DateTime.now()`，跨 22:00 / 跨天最迟 20 秒刷新 | `ui/pages/home/notifications_page.dart`、`ui/pages/home/kid_home_page.dart` |
| M8 | 家庭称呼草稿不落盘（切页即丢） | 草稿按身份落 `SharedPreferences`（`sekainook_name_draft:kid\|mom`），保存成功即清 | `ui/pages/settings/settings_page.dart`、`config/app_constants.dart` |
| M9 | 花园菜单没写进地址栏 | 菜单改由 `/garden?tab=` 承载（唯一真相是地址栏） | `ui/pages/garden/garden_page.dart` |
| I1 | 22 点判定用北京时区、且页内两套口径 | 统一为**设备本地时间**（与 Web 版 `now.getHours()` 同口径），东八区那套只留给 `/api/ledger/settle` 的日结算 | `ui/pages/home/kid_home_page.dart`、`ui/pages/family/family_dashboard_page.dart` |
| I2 | 通知时间格式与 Web 版不同（「N 分钟前 / N 天前」） | 抽 `core/time_text.dart`（`relativeDayTime` / `clockText`），统一成「今天 HH:mm / 昨天 HH:mm / M月D日 HH:mm」，三处私有实现全删 | `core/time_text.dart`（新建）、`ui/pages/home/*` |
| I3 | 打卡审批失败不刷新账本 | 四处 `LedgerApprovalException` 分支都先 `loadLedger()` 再提示 | `ui/pages/home/kid_home_page.dart`、`ui/pages/home/parent_home_page.dart`、`ui/pages/family/family_dashboard_page.dart` |
| I4 | 页面级轮询不退后台 | 抽 `core/app_foreground.dart`；四个轮询点（首页 20s、家长首页、账本 10s·15s、周计划 1min）都在 `lifecycleState != resumed` 时跳过，回前台立刻补一次 | `core/app_foreground.dart`（新建）、四个页面 |
| I5 | 未读通知角标挂在「设置」Tab | 移到「首页」，与 Web 版 `NAV_ITEMS` 一致 | `ui/shell/main_shell.dart` |
| I6 | 选图即上传 | 改成提交那一刻才传：选图只留本地文件，`_uploadPhoto()` 在 `_submit()` 里调，失败提示重试 | `ui/pages/home/kid_home_page.dart` |
| I7 | 打卡弹窗标题不区分身份 | 「打卡：X」/「申请打卡：X」按身份切 | `ui/pages/home/kid_home_page.dart` |
| I8 | 积分卡副标题多算今日任务 | 副标题改成「攒够可以跟妈妈兑现 · 今天打卡 N 次」，与 Web 版一致（`progressDone` / `progressTotal` 整条链一并删掉） | `ui/pages/home/kid_home_page.dart` |
| I10 | 21 点后睡觉任务提醒 | 保留（Flutter 独有，不是问题） | — |

## 二、刻意保留的差异（1 项）

| 项 | Web 版做法 | Flutter 版做法 | 为什么 |
| --- | --- | --- | --- |
| 错误恢复 | 命中 chunk 加载失败先自动刷新一次（`sessionStorage: sekainook_chunk_autoreload`） | 不自动刷新，直接停在卡片上等用户点「重新加载」 | Flutter Web 是 AOT 单包，不存在「旧 chunk 404」这种失败模式，自动刷新没有对应场景 |

## 三、明确不做（都有理由）

| 项 | 说明 |
| --- | --- |
| I9 用词：「阳光」vs「积分」、「语文预习」vs「语文练习」 | 两本账两个名字是**有意设计** —— `lib/config/changelog.dart:406`：「孩子的首页把两种钱分清楚了：花园的阳光只能在花园里花，家庭积分才是攒够能跟妈妈兑现的」。Flutter 内部 105 处「阳光」自洽；且我们的目标是**用 Flutter 取代 Web**，取代之后「与 Web 逐字对齐」不再是目标 |
| 顶栏的桌面端形态 | 不做 PC 面包屑、不做余额胶囊 —— 手机优先；余额在首页与账本本来就有更大的卡 |
| 卡片毛玻璃 | 不引入 `BackdropFilter`（1.31.6 试过液体玻璃，真机实测太卡，1.31.8 已整体回滚） |

## 四、验证方式

静态：

```
flutter analyze --no-pub          # 18 issues，全部 info（0 error / 0 warning）
```

测试：

```
flutter test --no-pub <13 个纯单元测试文件>   # 147 passed
```

其中 `test/ledger_export_test.dart` 用 mock method channel（`plugins.flutter.io/path_provider`、
`dev.fluttercommunity.plus/share`）跑完整条导出链路，包含「分享期间临时文件必须还在」的竞态断言；
`test/app_top_bar_test.dart` 11 条钉住顶栏（location→页面名含先例顺序、角标、深浅两档、窄屏不溢出、接线层真切主题）。

构建：

```
flutter build web --release --dart-define=API_BASE=https://sn.starrymiku.com   # ✓ build/web
```

运行（Flutter Web，指向线上数据）：

| 验证项 | 结果 |
| --- | --- |
| 身份选择门 → 孩子端首页（545 积分、云端背景图、中文无豆腐块） | ✓ 截图（合并前的预览站） |
| 底部导航 5 格、未读角标在「首页」 | ✓ 截图 |
| 深链 `#/garden?tab=poem` / `#/family?tab=history` | ✓ 落在「古诗背诵」/「历史记录」 |
| 花园「学习记录」的今日已完成清单 + 日期文案 | ✓ 截图 |
| `test/api_smoke_test.dart` / `e2e_flow_test.dart` / `garden_flow_test.dart` | ✓ 全过（打生产后端） |

**尚未在真机/真浏览器里验证过的**（如实交底）：
- ~~顶栏挂上之后的实际渲染，特别是「顶栏 + 页内大标题」是否显重复~~：**已在真浏览器看过**（Edge，495×909 手机视口与 1874 宽屏各一次）—— 不显重复（顶栏那条是导航指示、页内是内容头，React 版 `MainLayout` 同结构）；真悬浮下内容能正常从顶栏后滚过。**注意**：合成指针事件在这个 Flutter 版本里对 canvas 不生效（连底栏 Tab 都点不动），所以顶栏右侧按钮的「真点击」没能在浏览器里复现，改由 `test/app_top_bar_test.dart` 的 11 条兜住。
- Android 上点「导出流水」：系统分享面板会不会弹、`XFile` 的 mime 类型被微信/文件管理器认不认、临时文件删除与「保存到文件」的竞态。
- Web 下载分支的运行时行为（只过了 `flutter build web` 的编译）：Blob 真造得出来、`<a download>` 真触发下载、中文文件名没问题。

## 五、新增依赖

`share_plus: ^13.3.1`（连同 `share_plus_platform_interface`、`url_launcher_*`、`uuid` 共 8 个）。

加它的原因：安卓上 `path_provider` 的 `getDownloadsDirectory()` 给的是**应用专属**外部目录
（`Android/data/<包名>/files/Download`，见 `path_provider_android_real.dart:103` → `getExternalFilesDirs`），
系统文件管理器默认不展示 —— 提示用户「已导出到 下载/」会让人去公共下载夹白找。
分享面板把「存到哪 / 发给谁」交给用户，这才是家里人真正拿到 CSV 的路径。
