# SekaiNook 功能对齐审计报告（Flutter 客户端 vs Web 版）

> ⚠️ **本报告写于两个仓库合并之前**（那时 Flutter 端还在 `E:\Git\SekaiNook-App`），
> 里面的行号与部分结论**已经过时** —— 例如它记的「无全局错误边界」「底部导航少『学习计划』」
> 「未读角标挂设置 Tab」，在逐项核验时发现都早已修好。
> **每条问题的最终处置以 [parity-fixes.md](parity-fixes.md) 为准**，本文件只当那份差异清单的出处。

- 被审对象：`E:\Git\SekaiNook-App`（Flutter）与 `E:\Git\SekaiNook`（React + antd + zustand，同一套 Cloudflare Pages Functions 后端）
- 审计方式：只读逐文件对照，结论全部附 `文件:行号`；已按要求排除 6 条有意差异（`shared_preferences` 代替 `localStorage`、口令摘要存储、裸二进制上传、`fl_chart` 代替 `echarts`、通知轮询 15 秒且退后台跳过、中文文案措辞微调）
- 审计范围：孩子端首页 / 家长端首页 / 通知页 / 家庭账本 / 周计划 / 设置页 / 身份门 / 花园 8 个菜单，以及 `state/`、`data/`、`core/`、`config/`、`ui/widgets/`、`ui/shell/`、路由层

---

## 1. 结论摘要

1. **没有整页缺失**：Web 版 7 个主页面 + 花园 8 个菜单在 Flutter 侧全部落地，核心链路（账本读写、审批/驳回/撤回/重提、日结算、花园 store、任务规则表、HTTP 客户端、家长口令节流、管理员面板、闲置照片清理）逐条对齐，多处连文案都一字不差。
2. **对齐度最高的部分**：`lib/config/garden_config.dart` 与 `src/config/garden.ts`、`lib/config/family_rules.dart` 与 `src/config/familyRules.ts`、`lib/core/api_client.dart` 与 `src/api/http.ts`（12s 超时 / GET 重试 2 次 / 可重试状态码 / 重试间隔 400ms、1200ms / 错误文案）、花园装饰「上限 3 件、挂满淘汰最早挂上的」淘汰逻辑，均为逐条同口径实现。
3. **有 1 个系统性缺陷**：Web 用 view state（`family.activeTab` / `garden.activeMenu` / `home.noticeFilter`）+ 地址栏 query 承载「进哪一页、哪个 Tab、哪个菜单」，Flutter 侧**全部退化为纯内存 state 且路由层不读任何参数**，导致首页与头像的跨页入口落点丢失（10 处），是本轮审计最严重的问题。
4. **有 4 处被明显简化**：导出流水不是文件（只 toast 或复制剪贴板）、学习记录页缺「今日已完成」任务清单、没有全局错误边界、底部导航少「学习计划」且无全局顶栏。
5. **其余差异集中在交互形态与文案**（弹窗 vs Dialog、底部导航 4 项 vs 5 项、通知时间格式、单位「积分」/「阳光」），用户能感知但不影响功能闭环。

逐页核对统计（详见 §5）：**✓ 对齐 10 项 / ⚠ 有差异 5 项 / ✗ 缺失 0 项**。

---

## 2. 缺失的功能点

> 判定标准：Web 版有、Flutter 版没有或明显简化。

### M1 跨页定点跳转 + 视图状态记忆 🔴 高

| 项 | 内容 |
| --- | --- |
| Web 版位置 | `src/views/home/KidHome.tsx:305-315`（`goGarden(menu)` = `setViewState('garden.activeMenu', menu)` + `navigate('/garden')`；`goLedger(tab)` = `setViewState('family.activeTab', tab)` + `navigate('/family')`）；宫格入口 `KidHome.tsx:317-332`；头像按钮 `KidHome.tsx:347-350`（`goGarden('rewards')`）；待审批卡底部 `KidHome.tsx:429`（`goLedger('pending')`）；家长端同机制 `src/views/home/ParentHome.tsx:127-130` + 宫格 `:201-236`；消费端 `src/layouts/GardenLayout.tsx:56-70`、`src/views/family/FamilyDashboard.tsx:70`（`useViewState('family.activeTab','tasks')`） |
| Flutter 版现状 | **没有**。`lib/ui/pages/home/kid_home_page.dart:1575-1587` 全部是无参 `context.go`：`去打卡 → context.go('/family')`、`背古诗 → context.go('/garden')`、`我的花园 → context.go('/garden')`、`我的账本 → context.go('/family')`、`我的勋章 → context.go('/garden')`；头像 `:735 → context.go('/garden')`、`:1042 → context.go('/family')`、`:613 → context.go('/garden')`、`:1165 → context.go('/garden')`、`:1298 → context.go('/family')`。家长端 `lib/ui/pages/home/parent_home_page.dart:1016`（去审批）、`:1019`（家庭账本）都是 `context.go('/family')`。承接侧也不接受外部初值：`lib/ui/pages/family/family_dashboard_page.dart:66`（`String _activeTab = 'tasks'`，纯 state）、`lib/ui/pages/garden/garden_page.dart:75-77`（`String _menu = GardenConfig.defaultMenu`，纯 state）、`lib/router.dart:49-52`（`/garden` 不读 query）。 |
| 影响面 | **用户直接可感知**：点「背古诗」「我的花园」「我的勋章」都落在花园的「今日任务」；点「我的账本」落到账本的「任务区」；家长点「去审批」也落到「任务区」而不是待审批列表 —— 等于白点。 |
| 建议优先级 | **高** |

### M2 「导出流水」不是真正的文件导出 🟡 中

| 项 | 内容 |
| --- | --- |
| Web 版位置 | `src/views/home/ParentHome.tsx:165-171`（`handleExport` → `exportLedgerCsv(records)` 真下载 CSV，空账本提示「还没有流水可以导出」）；`src/views/family/FamilyDashboard.tsx:488-490`（`exportLedgerCsv(filteredRecords)`）；实现 `src/utils/exportLedger.ts` |
| Flutter 版现状 | **简化**。家长端 `lib/ui/pages/home/parent_home_page.dart:302-313` 只弹一句提示（注释写明「Flutter 侧没有 CSV 依赖，只给一句如实反馈」）；账本页 `lib/ui/pages/family/family_dashboard_page.dart:456-490` 把同一份 CSV 内容放进剪贴板，`:486` `_csvRow`，提示「已导出 N 条记录（CSV 已复制到剪贴板）」。 |
| 影响面 | 能感知：家长拿不到 `.csv` 文件，得自己去找剪贴板再粘进表格软件（家长端首页那个入口则一无所获）。 |
| 建议优先级 | 中 |

### M3 学习记录页缺「今日已完成」任务清单 🟡 中

| 项 | 内容 |
| --- | --- |
| Web 版位置 | `src/views/garden/RecordsPage.tsx:8-17`（`doneTasks = tasks.filter(t => t.done)`、`earnedToday` 口径注释）`：(42-69)` `<Card title="今日已完成">` 列表 —— 每条任务名 + 完成时刻（`toLocaleTimeString('zh-CN',{hour:'2-digit',minute:'2-digit'})`）+ `+{task.reward}` 标签，空态「今天还没有完成任务，快去加油吧！」 |
| Flutter 版现状 | **没有**。`lib/ui/pages/garden/garden_page.dart:1610-1657` 只有「今日完成 x/y」+「获得阳光」两格统计，下面接的是自创的「阳光流水」列表（`:1642` `SectionHeader(title:'阳光流水', subtitle:'最近的花园流水（含待同步）')`、`:1653` `_recordRow`）；全仓库 grep `今日已完成` 在 `lib/` 下 0 命中。 |
| 影响面 | 能感知：孩子看不到「今天做了哪几件事、几点做的、各拿到多少阳光」，只剩一个总数和流水。 |
| 建议优先级 | 中 |

### M4 没有全局错误边界 🟡 中

| 项 | 内容 |
| --- | --- |
| Web 版位置 | `src/components/ErrorBoundary.tsx`（219 行，含「这一块坏了，点一下重来」样式化兜底）+ `src/layouts/MainLayout.tsx:656-662`（`<ErrorBoundary variant="section" resetKey={location.pathname}>` 二级边界，路由变化即重置） |
| Flutter 版现状 | **没有**。`lib/main.dart` 只做 `SharedPreferences` 初始化与 Provider 装配；`lib/` 下 grep `ErrorWidget.builder|FlutterError.onError|runZonedGuarded` 0 命中。 |
| 影响面 | 单个卡片渲染异常会按 Flutter 默认行为整屏报错（release 下白屏/灰屏），没有「这一块坏了，重试一下」的局部兜底。 |
| 建议优先级 | 中 |

### M5 底部导航缺「学习计划」，无桌面端壳层 🟡 中

| 项 | 内容 |
| --- | --- |
| Web 版位置 | `src/layouts/MainLayout.tsx:63-101`（`NAV_ITEMS` 共 5 项：`/home` 首页、`/family` 家庭账本、`/family/plan` 学习计划、`/garden` 阳光花园、`/settings` 设置）；PC 侧 `src/layouts/MainLayout.tsx:565-577`（可折叠 `Sider`）+ `:39-46`（面包屑）+ `src/utils/tabMemory.ts`（每个 Tab 记忆自己的路径与滚动位置） |
| Flutter 版现状 | **简化**。`lib/ui/shell/main_shell.dart:71-78` 只有 4 个 Tab（`/home`、`/family`、`/garden`、`/settings`），学习计划只能从首页宫格或账本页进入；无桌面/宽屏布局，无面包屑，无每 Tab 路径与滚动记忆。 |
| 影响面 | 能感知（导航少一条路）；宽屏/桌面体验差距明显但对当前手机端使用影响有限。 |
| 建议优先级 | 中 |

### M6 无全局顶栏（余额胶囊 / 通知铃铛 / 深浅开关） 🟡 中低

| 项 | 内容 |
| --- | --- |
| Web 版位置 | `src/layouts/MainLayout.tsx:579-654`：移动端 pageChip（图标 + 当前页名）/ PC 面包屑；右上角余额胶囊（点→`/family`）、通知铃铛（点→`/home/notifications`，带未读角标）、太阳/月亮一键深浅开关（`toggleBrightness`） |
| Flutter 版现状 | **没有全局顶栏**。深浅切换只在设置页（`lib/ui/pages/settings/settings_page.dart:185 _toggleBrightness`）；通知入口只有首页宫格与底部「设置」Tab 角标。 |
| 影响面 | 能感知：任何页面想切深浅或看通知都得回首页/设置。 |
| 建议优先级 | 中低 |

### M7 通知筛选不记忆 + 孩子端首页无实时时钟 🟢 低

| 项 | 内容 |
| --- | --- |
| Web 版位置 | `src/views/home/NotificationsPage.tsx:54`（`useViewState<NoticeFilter>('home.noticeFilter','all')` 筛选持久化）；`src/views/home/KidHome.tsx:92`（`const now = useNow();`）+ `src/views/home/homeUtils.ts:10`（`useNow(intervalMs = 60000)` 每分钟 tick，驱动问候语/日期/22 点判断/相对时间） |
| Flutter 版现状 | 通知筛选是纯 state（`lib/ui/pages/home/notifications_page.dart:31 _NotifyFilter _filter = _NotifyFilter.all`），退出页面即重置；孩子端首页只在 build 时取一次时间（`lib/ui/pages/home/kid_home_page.dart:515 final DateTime now = DateTime.now();`），没有分钟级 tick —— 跨过 22:00 或跨天时，页面要等到下一次 provider 通知/轮询才刷新文案。家长端反而是每秒计时器（`lib/ui/pages/home/parent_home_page.dart:144-174`）。 |
| 影响面 | 轻微（孩子端问候语/22 点提醒延迟刷新；通知筛选每次要重选）。 |
| 建议优先级 | 低 |

### M8 家庭称呼草稿不落盘 🟢 低

| 项 | 内容 |
| --- | --- |
| Web 版位置 | `src/views/settings/SettingsPage.tsx:83`（`NAME_DRAFT_KEY = 'sekainook_name_draft'`）+ `:87-115`（`readNameDraft`/`writeNameDraft`/`clearNameDraft`，按 `${NAME_DRAFT_KEY}:${target}` 存 localStorage） |
| Flutter 版现状 | **简化**：只有内存态 `lib/ui/pages/settings/settings_page.dart:62-65`（`_namesInitialized`/`_namesTouched`/`_syncingNames`/`_savingNames`），`_onNameInputChanged :118` 只 setState。离开页面或杀进程后未保存的称呼改动会丢。 |
| 影响面 | 轻微。 |
| 建议优先级 | 低 |

### M9 花园菜单没写进地址栏，返回键不沿菜单回退 🟢 低

| 项 | 内容 |
| --- | --- |
| Web 版位置 | `src/layouts/GardenLayout.tsx:50-53`（菜单唯一真相是 `/garden?tab=`）、`:56-70`（消费一次性深链意图）、`:73-79`（`selectMenu` push 新历史，点当前项不制造历史） |
| Flutter 版现状 | **没有**：`lib/ui/pages/garden/garden_page.dart:162-166`（`_switchMenu` 只 `setState`），`lib/config/garden_config.dart:90-92` 的 `menuParam = 'tab'` 定义了但全仓库无引用（grep 仅命中定义与注释）。另有**文案与实现不符**：`lib/config/changelog.dart:122` 宣称「花园那 8 个菜单能按返回键往回退了：菜单改成写进地址栏（/garden?tab=…），系统返回键沿点过的菜单回退」—— 这是从 Web 版抄来的说明。 |
| 影响面 | 轻微（手机端无地址栏，可感知的是「返回键直接退出花园」+ 更新日志说了没做的事）。 |
| 建议优先级 | 低 |

---

## 3. 行为不一致点

> 判定标准：两版都有该功能，但逻辑/口径不同。

### I1 「22:00 提醒」的时间口径不同（且 Flutter 内部两页不一致） 🟢 低

- 场景：晚上判断「已经 22:00 啦，还有 N 个学习任务没完成」这条提醒。
- Web 版行为：`src/views/home/KidHome.tsx:214` `const showLateAlert = now.getHours() >= 22 && learningLeft > 0;` —— 用**设备本地时区**的小时；渲染 `:438-444`，点击 `goGarden('tasks')`。账本页同样用本地小时：`src/views/family/FamilyDashboard.tsx:231-233`（`isLate = hour >= 22`）。
- Flutter 版行为：孩子端 `lib/ui/pages/home/kid_home_page.dart:541 final bool showLateAlert = WeekUtil.beijingHour(now) >= 22 && learningLeft > 0;`（`:612` 渲染、`:613` `onTap: () => context.go('/garden')`），睡觉任务提醒同口径 `:647 if (WeekUtil.beijingHour(now) >= 22) return null;`；但**账本页用的是本地小时** `lib/ui/pages/family/family_dashboard_page.dart:700-702`（`_now.hour`，对应 Web 同处）。
- 差异后果：非东八区设备上，「22 点提醒」在首页与账本页会在不同时刻出现/消失（两页各自给出的「已过 22:00」判断可能互相矛盾）。

### I2 通知列表的时间显示格式不同 🟢 低

- 场景：通知列表每条右下角的时间。
- Web 版行为：`src/views/home/NotificationsPage.tsx:22`（`import { relativeTime, useNow } from './homeUtils'`）+ `:169` `relativeTime(notice.created_at, now)` —— 口径是 `src/views/home/homeUtils.ts:90-100` 的「今天 HH:mm / 昨天 HH:mm / M月D日 HH:mm」。
- Flutter 版行为：`lib/ui/pages/home/notifications_page.dart:479-491 _relativeTime()` —— 「刚刚 / N 分钟前 / N 小时前 / N 天前 / MM-DD HH:mm」（`:419` 调用）。注意这与 Flutter 自家首页的口径也不同（`lib/ui/pages/home/kid_home_page.dart:144-151` 是「今天 HH:mm」，对齐 Web）。
- 差异后果：同一批通知，两版读法不同；Flutter 内部两个页面也有两套相对时间。

### I3 打卡弹窗在「审批失败」时没有刷新账本 🟢 低

- 场景：孩子提交打卡，后端记账成功但审批环节抛错（`LedgerApprovalError`）。
- Web 版行为：`src/components/CheckInModal.tsx:126-131` —— 提示「已记账，但审批没成功…去待审批点一下」**并 `await loadLedger()`**，让那条 pending 立刻出现在「等妈妈看」里。
- Flutter 版行为：`lib/ui/pages/home/kid_home_page.dart:453-476 _openCheckInSheet` 只在 `submitted == true` 时 `loadLedger()`；`_CheckInSheet._submit`（`:1964-1971`）捕获异常后仅弹提示，不刷新。
- 差异后果：这种情况下孩子看不到自己刚交的申请，要等 20 秒轮询才出现，容易以为没交上而重复提交。

### I4 页面级轮询没有「退到后台就跳过」 🟡 中低

- 场景：App 切到后台时的定时刷新。
- Web 版行为：三处都有 `if (document.hidden) return;` + `visibilitychange`/`focus` 立即补拉：`src/views/home/KidHome.tsx:172-185`、`src/views/home/ParentHome.tsx:81-94`、`src/views/family/FamilyDashboard.tsx:194-229`（家长 10s 待审批、孩子 15s 账本）、`src/layouts/MainLayout.tsx:139-158`（通知 15s）。
- Flutter 版行为：只有壳层做了判断 —— `lib/ui/shell/main_shell.dart:55-61`（`Timer.periodic(AppConstants.notificationPollInterval)` + `if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;`，`:44-53` `didChangeAppLifecycleState`）；页面级定时器**没有等价判断**：`lib/ui/pages/home/kid_home_page.dart:216-219`（20s）、`lib/ui/pages/home/parent_home_page.dart:172`（20s，另 `:150-170` 周计划 60s）、`lib/ui/pages/family/family_dashboard_page.dart:137-152`（家长 10s / 孩子 15s）。
- 差异后果：退到后台仍持续打后端（耗电、流量、服务端压力）；回到前台时也不会立刻补一次刷新。

### I5 未读通知角标挂在「设置」Tab 🟡 中

- 场景：底部导航上的红点/角标。
- Web 版行为：`src/layouts/MainLayout.tsx:63-71` —— `NAV_ITEMS` 里 `/home` 首页带 `badge: 'unread'`（未读通知），`/family` 带 `badge: 'pending'`（且 `:519-523` 仅家长可见）。
- Flutter 版行为：`lib/ui/shell/main_shell.dart:113-125` 家庭 Tab 挂 `isParent ? pending : 0`；`:131-135` **未读通知角标挂在「设置」Tab**。
- 差异后果：孩子看到「设置」有红点会点进设置页，而不是通知页；与 Web 的习惯相反。

### I6 打卡照片「选完即上传」而不是「提交时才上传」 🟢 低

- 场景：打卡弹窗里选照片。
- Web 版行为：`src/components/CheckInModal.tsx` —— 选择后仅本地压缩（`src/utils/image.ts`，长边 1600），提交时才 `uploadImage`。
- Flutter 版行为：`lib/ui/pages/home/kid_home_page.dart:1901-1947` —— `_pick()` 里选完压缩（`compressImage(raw) ?? raw`）**立刻 `await _uploadPhoto()`**。
- 差异后果：用户选了照片又取消提交，会在图床留下永远不会被引用的图片（正好要靠设置里的「打卡照片清理」回收）。

### I7 打卡弹窗标题不区分「打卡 / 申请打卡」 🟢 低

- Web 版行为：`src/components/CheckInModal.tsx:143` 按 `isParent` 区分标题（家长=打卡，孩子=申请打卡）。
- Flutter 版行为：`lib/ui/pages/home/kid_home_page.dart:2012` 固定 `'打卡/申请打卡：${task.name}'`（两种身份同一串文案）；提交按钮已正确区分（`:2148-2150`）。
- 差异后果：仅文案，孩子看到家长口径的标题，不影响功能。

### I8 积分卡副标题多算了「今日任务 x/y」 🟢 低

- Web 版行为：`src/views/home/KidHome.tsx:501-544`（副标题 `攒够可以跟{momName}兑现 · 今天打卡 {todayCount} 次`）。
- Flutter 版行为：`lib/ui/pages/home/kid_home_page.dart:1211-1212`（`'攒够可以跟$momName兑现 · 今日任务 $progressDone/$progressTotal · 今天打卡 $todayCount 次'`，`:534` 用 `todayProgress(...)` 额外算了一组进度）。
- 差异后果：信息更多（不是缺失），但与 Web 文案不一致，且「今日任务」进度在这一卡与「今日学习任务」卡重复。

### I9 单位与页面标题的用词不同 🟢 低

- 单位：Web 处处写「积分」（`src/views/garden/RecordsPage.tsx:33 '获得积分'`、`TasksPage.tsx:35 '+${reward} 积分！${name}完成啦'`、`:103 '积分'`）；Flutter 花园页写「阳光」（`lib/ui/pages/garden/garden_page.dart:1631 '获得阳光'`、`:1633 unit: '阳光'`、`:176-189 _completeTask` 提示 `+N 阳光！X 完成啦`）。注：Web 首页 hero 也把花园币叫「阳光」（`KidHome.tsx:360-366`），所以这是 Web 自身「积分/阳光」混用被 Flutter 统一成了「阳光」。
- 标题：Web 花园页内标题 `src/views/garden/ChinesePage.tsx:27 '语文练习'`，而菜单项在两个版本里都叫「语文预习」（`src/config/garden.ts:131-140` / `lib/config/garden_config.dart:79-88`）—— Flutter 统一用「语文预习」，属于顺带修掉了 Web 的不一致。
- 差异后果：无功能影响，只影响孩子对同一数字的叫法。

### I10 21 点后「睡觉任务提醒」是 Flutter 额外功能（记录备查） 🟢 低

- Flutter 独有：`lib/ui/pages/home/kid_home_page.dart:644-653 _sleepTask()`（`if (WeekUtil.beijingHour(now) >= 22) return null;` 且 `checkTask` 通过时返回带时间窗的任务）+ `:615-623` 渲染成可点击直接打卡的提醒条「「按时睡觉」19:00-22:00，别忘啦」。
- Web 版：没有这条提醒；`sleep_on_time` 只作为「我的积分卡」里的快捷打卡按钮出现（`src/views/home/KidHome.tsx:48-55` 的 `QUICK_TASK_IDS` 含 `sleep_on_time`）。
- 结论：Flutter 功能**更全**，不是缺失；已按要求核对，确认「22 点睡觉提醒」在 Flutter 侧存在（且比 Web 更强）。

---

## 4. 交互形态差异（不算 bug，记录备查）

| 主题 | Web 版 | Flutter 版 |
| --- | --- | --- |
| 确认类交互 | antd `Modal` / `Popconfirm`（`src/views/family/FamilyDashboard.tsx:1085-1110` 驳回弹窗、`src/views/settings/SettingsPage.tsx:709-811` 背景图卡） | `showDialog` + `AlertDialog`（`lib/ui/pages/family/family_dashboard_page.dart:1584 _confirmWithdraw`、`:1607 _confirmDelete`、`:1657 _startReject`、`lib/ui/pages/settings/settings_page.dart:248-270`） |
| 可撤销提示 | `message.open({duration:5})` + 「撤销」链接（`src/views/family/FamilyDashboard.tsx:250-267`） | `SnackBar` + `SnackBarAction(label:'撤销')`（`lib/ui/pages/family/family_dashboard_page.dart:212-225`）—— 等价 |
| 底部导航 | 5 项（含学习计划）+ 玻璃胶囊高光、长按拖动换序、水痕动画、`prefers-reduced-motion` 降级（`src/layouts/MainLayout.tsx:202-368`、`:665-763`） | 4 项 Material `NavigationBar`，无动画（`lib/ui/shell/main_shell.dart:92-139`） |
| 顶栏 | 有：页面名/面包屑 + 余额胶囊 + 通知铃铛 + 深浅开关（`src/layouts/MainLayout.tsx:579-654`） | 无全局顶栏；深浅开关在设置页（`lib/ui/pages/settings/settings_page.dart:185`） |
| 勋章庆祝 | 压暗整屏 + CSS 弹跳（`badgePop`/`badgeFade`，`src/views/home/KidHome.tsx:646-658`，含 reduced-motion 降级） | 系统 `Dialog`（`lib/ui/pages/home/kid_home_page.dart:1684-1747`，默认淡入缩放，无弹跳；「好耶，收下啦」文案一致） |
| 列表加载 | 「加载更多（还有 N 条）」按钮（`src/views/family/FamilyDashboard.tsx:686-816` 区段） | 同样是「加载更多」（`lib/ui/pages/family/family_dashboard_page.dart:1437`）—— 口径一致，非无限滚动 |
| 下拉刷新 | 无（浏览器窗口滚动） | 处处 `RefreshIndicator`（`lib/ui/pages/home/notifications_page.dart:339-362` 等）—— Flutter 额外能力 |
| 图片大图 | antd `Image` 预览 | `Dialog` + `InteractiveViewer`，可捏合缩放（`lib/ui/pages/family/family_dashboard_page.dart:2007-2053`）—— 等价或更好 |
| 数值输入 | antd `InputNumber` 带 min/max 硬限制 | `TextField` + `int.tryParse(...) ?? 5` + `clamp(1, 200)` 静默纠正（`lib/ui/pages/home/kid_home_page.dart:1798`） |
| 花园布局 | 顶部 8 个 tab + 顶栏 5 个信息块（`src/layouts/GardenLayout.tsx:137-176`） | 横向滚动胶囊菜单 + 3 个信息块（`lib/ui/pages/garden/garden_page.dart:294-348`、`:351 _buildMenuBar`） |
| 花园离线态 | 无 | 有「待同步」横幅（`lib/ui/pages/garden/garden_page.dart:247 _buildPendingBanner`）+ 记录页「含待同步」说明 —— Flutter 额外能力 |
| 平板/桌面 | PC 侧边栏、面包屑、每 Tab 路径与滚动记忆（`src/layouts/MainLayout.tsx:565-577`、`src/utils/tabMemory.ts`） | 无桌面布局 |

---

## 5. 逐页面核对表

| # | 页面 / 菜单 | 结论 | 一句话说明（证据） |
| --- | --- | --- | --- |
| 1 | 孩子端首页 `KidHome.tsx` ↔ `kid_home_page.dart` | ⚠ 有差异 | 卡片全齐（被驳回重提、等妈妈看、花园任务、积分+快捷打卡、我的任务含自加、妈妈的话、宫格、勋章庆祝、加载失败条）；差异＝宫格/头像落点丢失（§2-M1）、22 点口径（§3-I1）、无分钟 tick（§2-M7）、额外多一条睡觉提醒（§3-I10）。`KidHome.tsx:378-433` ↔ `kid_home_page.dart:888-1053` |
| 2 | 家长端首页 `ParentHome.tsx` ↔ `parent_home_page.dart` | ⚠ 有差异 | 「需要我处理」「最近 7 天概览＋14 天趋势」「女儿今天（先看这 5 条）」「一键全兑换（Popconfirm + 100 积分=10 元）」全在；差异＝去审批/家庭账本落点丢失、导出流水不是文件（`parent_home_page.dart:302-313`）、时钟 1s vs Web 30s（`parent_home_page.dart:144-174` vs `ParentHome.tsx:53`） |
| 3 | 通知页 `NotificationsPage.tsx` ↔ `notifications_page.dart` | ⚠ 有差异 | 类型图标 6 种、未读/全部筛选、全部已读（含失败文案）、「通知功能还没就绪」提示、失败保留旧列表 + RefreshFailedBar、空态文案全部对齐（`notifications_page.dart:443-460`、`:131-136`、`:178-262`）；差异＝时间格式（§3-I2）、筛选不记忆（§2-M7） |
| 4 | 家庭账本 `FamilyDashboard.tsx` ↔ `family_dashboard_page.dart` | ⚠ 有差异 | 任务区/待审批/历史记录三 Tab、逐条通过+驳回（含驳回理由）、全部通过、撤回、重新提交、删除（关联图片）、筛选四档、加载更多、兑换、日结算提示、近 14 天趋势、22 点作息卡全在（`family_dashboard_page.dart:989-1076`、`:1230-1282`、`:1384-1458`、`:420-452`）；差异＝Tab 记忆与深链（§2-M1）、CSV 走剪贴板（§2-M2）、轮询不跳后台（§3-I4） |
| 5 | 周计划 `WeeklyPlan.tsx` ↔ `weekly_plan_page.dart` | ✓ 对齐 | 周标签+总体完成度（`weekly_plan_page.dart:209-240`）、按模板科目分组、`已完成` 标记（`:473`）、`未初始化`（`:448`）、`增加`（`:506`）、落库文案 `进度已更新 / 已记到上限 $applied`（`:154`）、每分钟 ticker 跨周自动更新（`:49-59`）、空态「本周暂无学习计划」（`:196-197`）—— 与 `WeeklyPlan.tsx:31/58-77/80-96/99-110` 一一对应 |
| 6 | 设置页 `SettingsPage.tsx` ↔ `settings_page.dart` | ✓ 对齐 | 两级结构（外观/家庭/家长管理/管理员/关于）、主题+深浅记忆、背景图上传/取消/移除、身份切换（家长需口令）、家庭称呼、家长口令 4-8 位、打卡照片清理（扫描+清理闲置）、管理员四件套（改积分数/一键清零/最近改动+撤销/改密码）、版本日志收起展开、关于（`家庭财务与行为管理`+`当前版本`）全部存在（`settings_page.dart:619-728`、`:860-990`、`:1057-1270`、`:1269-1470`、`:699/709`）。仅两处次要：称呼草稿不落盘（§2-M8）、Flutter 多一个「退出当前身份」（`:591-604`，Web 设置页没有该动作） |
| 7 | 身份门 `RoleGate.tsx` ↔ `role_gate_page.dart` | ✓ 对齐 | 两张身份卡（`role_gate_page.dart:52-63`，副标题「打卡赚积分、看花园、背古诗」/「审批打卡、看账本、管设置」）+ 家长口令弹窗 + 锁定中按钮禁用（`:273`）；Web 同构（`RoleGate.tsx:31-60` 锁定倒计时 + 剩余次数提示）。两版都坚持「绝不缺省为家长」（`lib/router.dart:26-30`、`RoleGate.tsx:7-12` 注释） |
| 8 | 花园·学习总览 ↔ `garden_page.dart:403 _buildOverview` | ✓ 对齐 | 三格统计 + 今日进度 + 「花园里多了什么」装饰展示（`garden_page.dart:406-408`、`:474-493` ↔ `OverviewPage.tsx:15/24-25/73-81`） |
| 9 | 花园·今日任务 ↔ `:580 _buildTasks` | ✓ 对齐 | 今日完成/完成率/连续学习三格 + 8 个任务卡（图标/时长/奖励）+ 重复打卡保护提示（`garden_page.dart:583-607`、`:174-189` ↔ `TasksPage.tsx:24-36/41-74/82-104`） |
| 10 | 花园·古诗背诵 ↔ `:714 _buildPoems` | ✓ 对齐 | 小诗人进度（累计背会 N 首 / 还差 N 首解锁「小诗人」/ 已解锁）+ 12 首诗卡 + 重复背诵提示（`garden_page.dart:718-749`、`:191-198` ↔ `PoemPage.tsx:16-26/31-37/39-72`） |
| 11 | 花园·语文预习 ↔ `:828 _buildChinese` | ✓ 对齐（文案微差） | 每项次数进度 `current/timesPerDay` + 「今天已完成」/打卡按钮（`:200 _practice`）；仅页面标题用词不同（I9） |
| 12 | 花园·阳光花园 ↔ `:920 _buildGarden` | ✓ 对齐 | 3 株植物 + 照顾花园进度（`植物战士` 7 天目标，`garden_page.dart:1006`）+ 浇水/今日已照顾文案（`:213 _care` ↔ `GardenPage.tsx:24-25/73-81`） |
| 13 | 花园·阳光商城 ↔ `:1106 _buildShop` | ✓ 对齐 | 3 类商品（头像框/称号/装饰）、「戴上」vs「挂上」文案、正在用/已拥有/积分不足/已获得 状态、顶部「正挂在花园里」、装饰上限 3 件挂满淘汰最早（`garden_page.dart:1109`、`:1374-1390`、`:1394`、`:1414` ↔ `ShopPage.tsx:14/20/66/74/88/131-132`；淘汰逻辑 `garden_state.dart:987-991` ↔ `useGardenStore.ts:952-956`） |
| 14 | 花园·我的奖励 ↔ `:1441 _buildRewards` | ✓ 对齐 | 「花园小达人」成就面板 + 成就进度%（`:1467-1501`）+ 勋章墙 7 枚（已获得/未获得 `:1565`）+ poet/plant_warrior 进度文字（`:1594-1595` ↔ `RewardsPage.tsx:21-37/42-58/74-99`） |
| 15 | 花园·学习记录 ↔ `:1610 _buildRecords` | ⚠ 有差异 | 今日完成/获得阳光两格对齐，`_recordRow` 状态图标（待审批/已驳回/已入账）齐备（`:1661-1676`）；差异＝缺「今日已完成」任务清单（§2-M3）、单位用「阳光」（I9）、并把 Web 没有的「阳光流水」加了进来（`:1642-1657`） |

---

## 附：按优先级排序的问题清单（全量）

| 优先级 | 问题 | 证据位置 |
| --- | --- | --- |
| 高 | 首页宫格/头像/账本入口的跨页定点跳转全部失效（10 处落点丢失） | `kid_home_page.dart:1575-1587`、`:735`、`:1042`、`:613`、`:1165`、`:1298`；`parent_home_page.dart:1016-1021` ← `KidHome.tsx:305-332`、`ParentHome.tsx:127-130` |
| 高 | Tab/菜单视图状态无任何持久化（无法跨页记忆或指定） | `family_dashboard_page.dart:66`、`garden_page.dart:75-77`、`notifications_page.dart:31` ← `FamilyDashboard.tsx:70`、`GardenLayout.tsx:56-70`、`NotificationsPage.tsx:54` |
| 高 | 花园菜单不可深链/返回键不沿菜单回退，且 changelog 宣称已实现 | `garden_page.dart:162-166`、`garden_config.dart:90-92`、`router.dart:49-52`、`changelog.dart:122` |
| 中 | 「导出流水」不是文件（家长端只提示、账本页复制剪贴板） | `parent_home_page.dart:302-313`、`family_dashboard_page.dart:456-490` ← `ParentHome.tsx:165-171`、`FamilyDashboard.tsx:488-490` |
| 中 | 学习记录页缺「今日已完成」任务清单 | `garden_page.dart:1642-1657` ← `RecordsPage.tsx:42-69` |
| 中 | 无全局错误边界 | 无 Flutter 对应 ← `MainLayout.tsx:656-662` + `ErrorBoundary.tsx` |
| 中 | 页面级 10/20s 轮询不跳后台 | `kid_home_page.dart:216-219`、`parent_home_page.dart:172`、`family_dashboard_page.dart:137-152` ← `KidHome.tsx:172-185`、`ParentHome.tsx:81-94`、`FamilyDashboard.tsx:194-229` |
| 中 | 未读通知角标挂在「设置」Tab（Web 挂首页） | `main_shell.dart:131-135` ← `MainLayout.tsx:63-71` |
| 中 | 底部导航少「学习计划」，无全局顶栏（余额胶囊/通知铃铛/深浅开关） | `main_shell.dart:71-78` ← `MainLayout.tsx:63-101`、`:579-654` |
| 低 | 22 点判定用北京时区（Web 用设备本地），且 App 内两页口径不一致 | `kid_home_page.dart:541/647`、`family_dashboard_page.dart:700` ← `KidHome.tsx:214`、`FamilyDashboard.tsx:231-233` |
| 低 | 通知页时间格式两版不同 | `notifications_page.dart:479-491` ← `NotificationsPage.tsx:22/169` |
| 低 | 打卡弹窗审批失败不刷新账本 | `kid_home_page.dart:453-476`、`:1964-1971` ← `CheckInModal.tsx:126-131` |
| 低 | 选图即上传，取消提交会留下孤儿图片 | `kid_home_page.dart:1901-1947` ← `CheckInModal.tsx`（提交时上传） |
| 低 | 称呼草稿只在内存，不落盘 | `settings_page.dart:62-65` ← `SettingsPage.tsx:83/87-115` |
| 低 | 孩子端首页无分钟级 tick（问候语/22 点提醒延迟刷新） | `kid_home_page.dart:515` ← `KidHome.tsx:92` + `homeUtils.ts:10` |
| 低 | 单位「阳光」/「积分」、页面标题「语文预习」/「语文练习」用词不同 | `garden_page.dart:1631-1633` ← `RecordsPage.tsx:33`、`TasksPage.tsx:35`；`ChinesePage.tsx:27` |
| 低 | 打卡弹窗标题不区分「打卡/申请打卡」；积分卡副标题多算今日任务进度 | `kid_home_page.dart:2012`、`:1211-1212` ← `CheckInModal.tsx:143`、`KidHome.tsx:501-544` |

## 附：已核查确认「不是问题」的重点项（按需求方点名）

| 点名项 | 结论 | 证据 |
| --- | --- | --- |
| 家长端「一键清零」 | ✅ 有 | `settings_page.dart:497-530 _clearLedger({required bool sun})`（`:505` 确认文案「把$label从 X 清零？」）← `SettingsPage.tsx:506-526` |
| 家长端「撤销调整」 | ✅ 有 | `settings_page.dart:532-554 _revokeAdjustment`（`:536` 确认「撤销这条调整？」）← `SettingsPage.tsx:529-542` |
| 家长端「密码试错节流」 | ✅ 有 | `settings_page.dart:89 _pinLockSeconds`、`:1535` 段（把服务端锁定/剩余次数写进报错文案）、`:273-303 _changeRole`；`lib/core/pin_guard.dart`（201 行）与 `lib/core/api_client.dart` 同源 ← `SettingsPage.tsx:306-329`、`RoleGate.tsx:23-60`、`useFamilyStore` 的 `pinAttemptsLeft` |
| 家长端「闲置照片清理」 | ✅ 有 | `settings_page.dart:351-397 _scanOrphans/_cleanOrphans`（`:373` 确认「确认清理这 $_orphanCount 张闲置照片？」）← `SettingsPage.tsx:640-674` |
| 孩子端「被驳回记录重提」 | ✅ 有 | `kid_home_page.dart:888-969`（知道了 / 重新交一次，`_dismissReject :379-385`）← `KidHome.tsx:227-233/378-408` |
| 孩子端「勋章庆祝」 | ✅ 有（形态不同） | `kid_home_page.dart:1684-1747`、本机去重键 `AppConstants.keyBadgesCelebrated` ← `KidHome.tsx:62/646-658` |
| 孩子端「22 点睡觉提醒」 | ✅ 有，且比 Web 多一条 | `kid_home_page.dart:541/612-623/644-653` ← Web 只有 `KidHome.tsx:214/438-444` |
| 花园「装饰淘汰 / 装备槽位」 | ✅ 完全对齐 | `garden_config.dart:70 maxDecor = 3`、`garden_state.dart:987-991`（挂满淘汰最早）、`:1011`（取下）← `config/garden.ts:113`、`useGardenStore.ts:742/952-956/972` |
| 花园「记录页」 | ⚠ 部分差异（见 §2-M3） | `garden_page.dart:1610-1657` ← `RecordsPage.tsx:42-69` |
| 设置「主题记忆浅深」 | ✅ 有 | `settings_page.dart:172-195 _pickTheme/_toggleBrightness` + `lib/state/theme_state.dart` ← `SettingsPage.tsx:545-554`、`useThemeStore` |
| 设置「背景图」 | ✅ 有 | `settings_page.dart:196-270 _uploadBackground/_saveBackgroundUrl/_removeBackground`（`:251` 确认移除）← `SettingsPage.tsx:557-600/755-810` |
| 设置「家庭称呼」 | ✅ 有 | `settings_page.dart:304-348 _saveNames`（`:317` 「称呼和昵称至少要填一个」）、`:1103-1170` ← `SettingsPage.tsx:603-637/852-925` |
| 设置「退出身份」 | ✅ 有（Flutter 独有） | `settings_page.dart:591-604 _signOut`（`:594` 确认「退出当前身份？」）、`:728` 入口 ← Web 设置页无该动作 |
| 首页「实时时钟」 | ⚠ 家长端有（1s），孩子端无 tick | `parent_home_page.dart:56-60/144-174`；`kid_home_page.dart:515` ← `ParentHome.tsx:53`、`KidHome.tsx:92` |
| 首页「待审批角标」 | ✅ 有（位置不同，见 §3-I5） | `main_shell.dart:113-125`、`parent_home_page.dart:1017` ← `MainLayout.tsx:63-71` |
| 首页「14 天趋势」 | ✅ 有 | `parent_home_page.dart:20-21 _trendDays = 14`、`:1199-1317 _BalanceTrend`；`family_dashboard_page.dart:795-925 _buildTrendCard` ← `ParentHome.tsx:318-343`、`FamilyDashboard.tsx:1079-1081`、`BalanceTrend.tsx`（`TREND_DAYS = 14`、按天净额单柱） |
