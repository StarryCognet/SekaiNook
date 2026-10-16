# 功能对齐：审计问题的处理记录

对应审计报告 [parity-audit.md](parity-audit.md)（262 行，✓ 对齐 10 / ⚠ 差异 5 / ✗ 缺失 0）。
本文记录**每条问题的最终处置**，以及刻意保留的差异及理由。

## 一、已修复（14 项）

| # | 审计项 | 处置 | 落点 |
| --- | --- | --- | --- |
| 1 | 首页宫格/头像/入口的跨页定点跳转全部失效（10 处落点丢失） | 17 处跳转全部带上落点参数（孩子端 10、家长端 7），参数名走 `GardenConfig.menuParam` 常量 | `ui/pages/home/kid_home_page.dart`、`ui/pages/home/parent_home_page.dart` |
| 2 | Tab/菜单视图状态无任何持久化 | 账本分区改由 `/family?tab=tasks\|pending\|history` 承载、通知筛选由 `/home/notifications?filter=all\|unread` 承载，非法值统一回落默认 | `ui/pages/family/family_dashboard_page.dart`、`ui/pages/home/notifications_page.dart` |
| 3 | 花园菜单不可深链 | 菜单改由 `/garden?tab=` 承载（唯一真相是地址栏），`menuParam` 死常量被消费 | `ui/pages/garden/garden_page.dart` |
| 4 | 「导出流水」不是文件（家长端只 toast） | 抽到 `core/ledger_csv.dart` 共用；两个入口都真把 CSV 放进剪贴板 | `core/ledger_csv.dart`、`ui/pages/family/family_dashboard_page.dart`、`ui/pages/home/parent_home_page.dart` |
| 5 | 学习记录页缺「今日已完成」清单 | 补上任务名 + 完成时刻 + 奖励标签，空态文案与 Web 一字不差 | `ui/pages/garden/garden_page.dart` |
| 6 | 无全局错误边界 | `ErrorWidget.builder` 装中文兜底卡片（🌱 + 页面出了点问题 + 重新加载），`PlatformDispatcher.onError` / `FlutterError.onError` 留痕 | `core/app_error.dart`、`main.dart`、`app.dart` |
| 7 | 页面级轮询不跳后台 | 三处轮询（首页 20s、账本 10s·15s）在 `lifecycleState != resumed` 时跳过，回前台立刻补一次 | `ui/pages/home/kid_home_page.dart`、`ui/pages/home/parent_home_page.dart`、`ui/pages/family/family_dashboard_page.dart` |
| 8 | 未读通知角标挂在「设置」Tab | 移到「首页」，与 Web 版 `NAV_ITEMS` 一致 | `ui/shell/main_shell.dart` |
| 9 | 底部导航少「学习计划」Tab | 补第 5 格；并把周计划页、通知页一并收进 `ShellRoute`（对应 Web 版 `MainLayout` 包住全部 6 页） | `ui/shell/main_shell.dart`、`router.dart` |
| 10 | 22 点判定用北京时区、且页内两套口径 | 统一为**设备本地时间**（与 Web 版 `now.getHours()` 同口径），东八区那套只留给 `/api/ledger/settle` 的日结算 | `ui/pages/home/kid_home_page.dart` |
| 11 | Tab 高亮与内容可能不同源 | 两处都吃同一个 URL 派生值，`TabController` 降级为纯动画执行器 | `ui/pages/family/family_dashboard_page.dart` |
| 12 | 孩子端深链 `?tab=pending` 的回落 | 收敛在派生阶段一处（只回落显示、不回写地址栏） | 同上 |
| 13 | 花园阳光流水的时刻只有 `HH:mm` | 补上日期：今天「今天 HH:mm」、更早「M/d HH:mm」（与账本页同口径） | `ui/pages/garden/garden_page.dart` |
| 14 | 打卡弹窗审批失败不刷新账本 | 四处 `LedgerApprovalException` 分支都已 `loadLedger()` 后再提示 | 三个页面 |

## 二、刻意保留的差异（3 项）

| 项 | Web 版做法 | Flutter 版做法 | 为什么 |
| --- | --- | --- | --- |
| 导出流水 | 浏览器下载 CSV 文件 | 复制到剪贴板 + 提示 | Android 没有「下载目录」概念；不为此引入 `share_plus` / `path_provider`。导出内容本身同构 |
| 全局顶栏 | `MainLayout` 顶栏：页面名胶囊 + 余额胶囊（**仅桌面端**）+ 通知铃铛 + 深浅开关 | 不加全局顶栏，各页自带头部 | 目标是手机端（375px）；余额、通知入口、深浅开关在首页与设置页都已各有入口，再叠一条顶栏会把内容区挤矮。通知角标已按审计要求挂到「首页」Tab |
| 错误恢复 | 命中 chunk 加载失败先自动刷新一次（`sessionStorage: sekainook_chunk_autoreload`） | 不自动刷新，直接停在卡片上等用户点「重新加载」 | Flutter Web 是 AOT 单包，不存在「旧 chunk 404」这种失败模式，自动刷新没有对应场景 |

## 三、验证方式

静态：

```
flutter analyze --no-pub          # 15 issues，全部 info（无 error）
```

运行（Flutter Web，指向本地 8788 后端 + 线上数据副本）：

| 验证项 | 结果 |
| --- | --- |
| 底部导航 5 格、未读角标在「首页」 | ✓ 截图 |
| 深链 `#/garden?tab=poem` | ✓ 落在「古诗背诵」 |
| 深链 `#/family?tab=history` | ✓ 落在「历史记录」 |
| 花园「学习记录」的今日已完成清单 + 日期文案 | ✓ 截图 |
| 妈妈版首页（时钟 / 待审批 / 余额 / 7 天概览 / 14 天趋势） | ✓ 截图 |
| `test/api_smoke_test.dart`（只读冒烟，7 个 test） | ✓ 全过 |
| `test/e2e_flow_test.dart`（写路径闭环：打卡→幂等→审批→删除） | ✓ 全过 |
| `test/garden_flow_test.dart`（花园阳光闭环） | ✓ 全过 |

产物：

```
flutter build web --release --dart-define=API_BASE=...   # build/web
flutter build apk --release                               # 57.8MB，含 arm64-v8a / armeabi-v7a / x86_64
```
