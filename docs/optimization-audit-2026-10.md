# SekaiNook 全量优化点检测（2026-10-24）

> 本文只列问题与建议，**不改任何代码**。上一轮性能专项（32 条 → P0–P3 已修）见 `docs/perf-audit-2026-10.md`；
> 本文是它的续篇：范围从「性能」扩到**正确性、数据一致性、错误处理、可维护性、打包体积、工程化**。
>
> 检测方式：4 个只读审查（页面层 / 状态数据层 / 后端 / React + 构建配置）+ Lead 自查（可达性、依赖、测试、APK 构成）。
> 标「已核实」的是我逐行看过代码的；「待实测」的是静态推断、需要复现一次再动手的。

## 0. 一句话结论

没有「必须立刻停机修」的问题，但有三组值得在下个版本处理 —— 其中**最危险的不是安全漏洞，是发版脚本**：
**发版脚本 2 条不可逆风险（R-1/R-2）**：忘了给 versionCode +1 → 全家人静默收不到更新；换 keystore 发布 → 老用户永远装不上。两者都不报错、都不可逆；
**状态层 8 条正确性/数据风险（S 组）**，其中 4 条的触发条件是「启动时存档或接口有一处异常」——一旦发生就是**半残启动或丢阳光**；
**后端 7 条严重问题（B-1~B-7）**，本质都是「公网可达 + 无鉴权 + 读改写不原子」，其中 B-2/B-3/B-4 是**知道域名就能触发群发通知、清空照片、无限上传**的破坏性接口。
其余是体验与维护性债务，可按季度排。

## 1. 范围

| 层 | 文件数 | 行数 |
|---|---|---|
| Flutter `app/lib` | 196 | 62629 |
| 后端 `functions/` + `workers/reminder/src/` | 38 | 5927 |
| React（退役中）`src/` | 66 | 14516 |
| 测试 `app/test` | 18 | 2666 |

---

## 2. 严重（正确性 / 数据风险，建议下版修）

### S-1 主题重建会造出第二套 store，路由却还握着第一套（已核实）
- 位置：`app/lib/main.dart:59-79` 的 `DynamicColorBuilder.builder` 里构造全部 8 个 store；
  `app/lib/app.dart:67` 的 `late final GoRouter _router = createRouter(widget.family);`。
- 问题：Android 12+ 且用户开了「跟随壁纸」时，系统壁纸色变化 → `builder` 重建 → `SekaiNookApp.widget.family` 变成新实例，
  但 `_router` 是 `late final`，只在第一次拿的是旧 `FamilyState`；而 `app.dart:132-142` 的 `MultiProvider` 用的是**新**实例。
- 影响：路由 redirect 读旧 role、页面读新 role，状态分裂；`initState` 挂的 listener 也还挂在旧实例上。
  触发概率低（换壁纸/系统主题色变化），但一旦触发就是灵异 bug，难复现。
- 建议：store 只在 `main()` 里构造一次（或放进 `SekaiNookApp` 的 `State.initState`），`DynamicColorBuilder` 里只把
  `lightDynamic?.primary` 传下去；`SekaiNookApp` 加 `didUpdateWidget` 或干脆不依赖 `widget.family` 而是构造时注入的 final 字段。

### S-2 补发定时器的闸是 `static`，但状态是实例态，且全类没有 dispose（已核实）
- 位置：`app/lib/state/garden_state.dart:391` `static bool _syncLoopReady = false;`，`:668-674` 用它挡启动；
  `Timer.periodic` 起在 `_ensureSyncLoop`，全类无 `dispose()`。
- 问题：实例一旦重建（见 S-1，或热重载/测试里重复 `init()`），新实例看到闸已 true → **永不启动补发**；
  旧实例定时器继续跑，用旧内存态写同一个 prefs 键。
- 影响：离线操作补发卡死 + 双写（配合 S-3 会丢阳光）。
- 建议：闸改实例字段；`dispose()` 里 `_timer?.cancel()`；或把 `GardenState` 收敛成进程级单例（与 S-1 一起解决）。

### S-3 `_saveState()` 与 `_savePending()` 两次写、无原子性（已核实）
- 位置：`app/lib/state/garden_state.dart:549-550`（`_commit` 里先 `_saveState()`，含 `patch.pending` 时再 `_savePending()`）；
  两个方法分别写两个 prefs 键。
- 问题：两次写之间进程被杀/崩溃，会出现「余额已更新但离线队列丢了」（未同步的阳光永久消失）
  或「队列还在但余额回滚」（重复记账）。
- 建议：把 `pending` 并进同一份 payload 一次 `setString` 写完（prefs 单键写入是原子的）；
  如果嫌 JSON 大，至少先写队列、再写余额，并在读档时用版本号/时间戳校验一致性。

### S-4 启动链对 `garden.init()` 无保护，一处坏 JSON 全链停摆（已核实到调用点）
- 位置：`app/lib/app.dart:110-128` `_bootstrap` 里 `widget.garden.init();` 是同步调用、无 try/catch；
  `garden_state.dart:713`、`:745` 裸调 `GardenTask.fromJson` / `Badge.fromJson`，
  而 `app/lib/data/models/garden.dart:57-62`、`:103` 是 `(json['id'] ?? '') as String` 这类硬转。
- 问题：存档里一条字段类型不对（比如 `id` 变成数字）→ `TypeError` 直接冒泡出 `_bootstrap` →
  其后的 `localNotify.init()` / `update.autoCheck()` / `loadLedger()` / `notifications.load()` **全部不执行**。
- 影响：应用「能打开但半残」：没有提醒、不查更新、流水不加载，而且 release 下只 `debugPrint`（见 L-11）。
- 建议：`_bootstrap` 每一步各自 `try/catch`（注释本来就写着「都是尽力而为」，实现没做到）；
  `GardenTask/Badge.fromJson` 换成逐字段安全取值（`garden_state` 里已有 `_toSafe*` 那套，抽出来复用）。

### S-5 `GardenState.refreshLedger` 没有请求序号守卫，两个入口会并发（已核实到调用点）
- 位置：`app/lib/state/garden_state.dart:644-662`；调用方 `:792` `init()` 里 `unawaited(refreshLedger())`，
  `:621` `flushPending()` 末尾又 `await refreshLedger()`。
- 问题：慢响应后到会把新的 `summarySun` / `ownedItems` 覆盖回旧值（`FamilyState` 有 `_ledgerSeq`，这里没有）。
- 影响：已购物品闪回、阳光跳变、兑换按钮可重复点。
- 建议：照抄 `FamilyState._ledgerSeq` 的模式：自增 → 回包比对 → 过期丢弃。

### S-6 `LocalNotifyState.rescheduleAll` 无互斥，并发会漏排提醒（已核实）
- 位置：`app/lib/state/local_notify_state.dart:349-404`：先 `await _sink.cancelAll()` 再逐条 `await` 排程；
  `enable()` / `updateReminder()` / `disable()` / `syncFromRecords()`（`:343`）都会进它。
- 问题：两次调用交错，后一次的 `cancelAll` 会把前一次刚排好的清掉，而它自己还没排完 → 当天/明天提醒静默丢失。
- 影响：真机上「提醒不响」这类最难排查的用户投诉。
- 建议：串行队列（`_busy` 链式 await）或 epoch 校验：`cancelAll` 之后如果 epoch 变了立即中止本轮。

### S-7 `_parseRecords` 单条坏就整次失败（已核实）
- 位置：`app/lib/data/api/ledger_api.dart:233-240` 与 `app/lib/data/models/ledger_record.dart:65-73`；
  `fromJson` 里多处 `as String` / `as num` 硬转。
- 问题：服务端某条记录字段类型漂移 → 整次 `fetchRecords` 抛错，而不是跳过这一条。
- 影响：流水页 + 余额一起失效（而 `fetchSnapshot` 是同一批数据，也会全挂）。
- 建议：单条解析包 `try/catch`，坏条跳过并记数上报；`fromJson` 改容错取值。

### S-8 回退路径三个并发的 Future 只 await 了一个（已核实）
- 位置：`app/lib/state/family_state.dart:159-176`。
- 问题：`recordsFuture` 先抛时，`pendingFuture` / `summaryFuture` 的错误变成 unhandled async error
  （会打到 `PlatformDispatcher.onError`，见 L-11；也可能中断后续 await 链）。
- 建议：`Future.wait([...], eagerError: false)` 或每个 future 先 `catchError` 再 await。

---

## 3. 中等（体验 / 稳定性 / 可维护性）

状态与数据层（M 组）：

| # | 位置 | 问题 | 建议 |
|---|---|---|---|
| M-1 | `app/lib/state/update_state.dart:171-210` | `downloadAndInstall` 有 `_downloading` 标志但入口不校验，连点两次并发两个 60MB 包、进度互相覆盖、`_clear` 抢删临时目录 | 入口先 `if (_downloading) return;` |
| M-2 | `app/lib/state/family_state.dart:266-280` | `approveMany` 逐条 `.catchError((_) => false)` 吞错，最后只报「有 N 条没通过」，家长看不出哪条、为什么 | 收集失败 id + `ApiException.message` 一并回报 |
| M-3 | `app/lib/core/pin_guard.dart:163-175` | `verify` 是「读 fails → await 比对 → 递增」，快速连点读到同一份计数，锁定阈值可绕过 | verify 串行化（`_verifying` 闸）或计数放内存 |
| M-4 | `app/lib/core/pin_guard.dart:85`（`lockRemaining`） | 用 `DateTime.now()` 与存储时间戳比，改系统时间可立刻解除锁定 | 冷却改「上次失败时刻 + 时长」并夹住时钟回拨 |
| M-5 | `app/lib/core/api_client.dart:216-218` | 兜底 `catch (_)` 把任何非 Dio 异常都伪装成「网络连接失败」，真实 bug 被当网络抖动 | 只对 `DioException` 转网络错误，其余带原文重抛 |
| M-6 | `app/lib/core/api_client.dart:204-213` | 重试不区分 `cancel` / `badCertificate` / `connectionError`，证书错误也发 3 次、白等 36s | 只对超时/连接类重试；取消与证书错误直接抛 |
| M-7 | `app/lib/state/family_state.dart:57,72` | `records` / `pendingRecords` getter 直接暴露内部 List（`garden_state` 都包了 `unmodifiable`） | 统一 `List.unmodifiable` |
| M-8 | `app/lib/state/notification_state.dart:86-100` | `refresh()` 无序号/在途去重，10s 轮询与手动下拉并发时会用旧响应覆盖新数据（未读数回退、红点复现） | 加 `_seq` 比对 |
| M-9 | `app/lib/state/local_notify_state.dart:287-293` | `_nextSlot()` 是 `(max+1).clamp(1,99)`，顶到 99 后两条提醒同 slot → 同一个 notificationId，后者覆盖前者 | 槽位满时回收空闲 slot，或 id 改 hash(reminder.id) |
| M-10 | `app/lib/state/garden_state.dart:79-84` | `_nextStreak(today)` 收了 `today` 却不用，内部用 `DateTime.now()` 求昨天 → 跨零点口径不一致、不可测 | 用传入的 `today` 反推 |
| M-11 | `app/lib/state/theme_state.dart:226-235` | `_syncBackgroundCache()` 只写不读（全仓 grep 无读取方），注释承诺的「首帧先上缓存背景」没实现，白写一份字节进 prefs | 要么在 `loadBackground` 开头读，要么删 |
| M-12 | `app/lib/core/task_rules.dart:100-108` | `todayProgress` 对每个任务调 `isTaskDone`，每次全表扫 → O(任务数×流水数)；同文件 `countTodaySubmissionsByTask` 已能一次聚合 | 先聚合再查表（与上一轮同一类优化） |

## 4. 轻微（体验细节 / 防御性）

| # | 位置 | 问题 | 建议 |
|---|---|---|---|
| L-1 | `app/lib/state/theme_state.dart:165-193` | `setFollowWallpaper` / `setPureBlack` / `setTextScale` 无「值未变则 return」，拖动文字缩放滑杆整树重建 | 三个 setter 加等值早退（`setThemeId` 已有） |
| L-2 | `app/lib/core/image_compress.dart:61-73` | 解码后未 `bakeOrientation` 就 `copyResize`，竖拍照片可能方向被压平（**待实测**） | 解码后补 `bakeOrientation` |
| L-3 | `app/lib/core/image_compress.dart:44-46` | `readAsBytes()` 整份读进内存再压，12MP 图峰值内存≈原字节+解码位图，低端机/Web 有 OOM 风险 | 降采样解码，或先估尺寸再决定是否 `compute` |
| L-4 | `app/lib/data/models/garden.dart:57-62,103` | `GardenTask.fromJson` / `Badge.fromJson` 硬转，字段类型不对就 TypeError（S-4 的根因之一） | 复用 `_toSafe*` |
| L-5 | `app/lib/data/models/task_config.dart:85-95` | `json['window'] is Map<String,dynamic>` 判断过窄，`Map<dynamic,dynamic>` 会被当成「没有时间窗」，任务时间限制静默失效 | `is Map` + 显式转换 |
| L-6 | `app/lib/data/models/ledger_record.dart:70` | `createdAt: parseTime(...) ?? DateTime.now()`，服务端漏 `created_at` 时记录被当成「刚刚」，当日统计虚高、日结算可能误触发 | 回退 `updatedAt`，或标记未知并排除出今日统计 |
| L-7 | `app/lib/data/api/upload_api.dart:42-45` | `(raw?['url'] ?? '') as String` 且空串不校验 → 200 但无 url 时返回「上传成功 + 空地址」，裂图无提示 | 空 url 抛 `ApiException` |
| L-8 | `app/lib/data/api/admin_api.dart:52-58` | `AdminAdjustment.fromJson` 多处硬转，后端改字段类型会整页白屏 | 容错取值 helper |
| L-9 | `app/lib/core/custom_tasks_state.dart:284-303` vs `:263-276` | `isRecordedToday` 按设备本地天、`countDoneToday` 按东八区天（注释自认「照抄现状」），非东八区设备上两者矛盾 | 统一口径（与后端一致用东八区） |
| L-10 | `app/lib/core/app_error.dart:24-27` | `ErrorWidget.builder` 把 `exceptionAsString()` 原文显示给用户，内部路径/类名/堆栈可能被截图外传 | 只显示通用文案 + 短码 |
| L-11 | `app/lib/main.dart:40-47` | `PlatformDispatcher.onError` 返回 `true` 吞掉所有未捕获异步异常，release 下只剩 `debugPrint`（真机看不到），线上不可观测 | 本地环形日志 + 自测页展示「未捕获异常次数」 |
| L-12 | `app/lib/state/family_state.dart:257-298` | `approve/reject/resubmit/removeRecord` 无在途保护（approve 服务端幂等，reject/删除不是），快速双击会发两次 | 按 id 记 in-flight 集合 |

> 说明：S/M/L 编号按「状态与数据层」审查结果编号；页面层、后端、工程化三组见后续章节。

---

## 5. 死代码与依赖（自查）

### 5.1 `app/lib/fl_ui` 有三分之一是死代码
从 `app/lib/main.dart` 做 import 图 BFS：
- `fl_ui` 共 92 文件 / 29667 行，**不可达 39 个文件 / 9726 行（约 33%）**；全库不可达 43 个文件。
- 最大的几个：`fl_ui/liquid_glass_capture.dart`（967 行）、`fl_ui/generated/models.freezed.dart`（887 行）、
  `fl_ui/null_status.dart`（753 行）、`fl_ui/open_container.dart`（693 行）、`fl_ui/list.dart`（601 行）、
  `fl_ui/sidebar.dart`（574 行）、`fl_ui/navigator_resizable.dart`（523 行）、`fl_ui/snap_sheet.dart`、
  `fl_ui/keyed_animated_list.dart`、`fl_ui/list_row_separator.dart`、`fl_ui/collapsible_section.dart`、
  `fl_ui/animated_entries.dart`、`fl_ui/table_layout.dart`、`fl_ui/focus_traversal.dart`、`fl_ui/paged_sheet.dart`、
  `fl_ui/theme_cross_fade.dart`、`fl_ui/line_chart.dart`、`fl_ui/context_menu.dart`；另有 `fl_ui/ui.dart` barrel（73 行，无人 import）。
- 影响：不影响运行产物（tree-shaking 会裁掉），但**拖慢分析/编译、误导阅读**（`fl_ui` 是从 FlClash 移植的整套 UI，只用了一部分）。
- 建议：先确认没有动态引用（barrel / 反射/字符串化类名），再按「不可达 = 删除」清一轮；保留 `docs/ui-migration-flclash.md` 里说还会用的少数几个。

### 5.2 5 个依赖只为死代码存在
用 `grep package:<name>/` 统计的直接引用方，全部落在上面的不可达文件里：

| 依赖 | 唯一引用方 | 结论 |
|---|---|---|
| `collection` ^1.19.1 | `fl_ui/list.dart` | 死文件删了就能删依赖 |
| `emoji_regex` ^0.0.5 | `fl_ui/text.dart` | 同上 |
| `freezed_annotation` ^3.1.0 | `fl_ui/models.dart` | 且仓库无 `build_runner`/freezed 生成流程，`.freezed.dart` 是手工留的产物 |
| `material_new_shapes` ^1.0.0 | `fl_ui/null_status.dart` | 同上 |
| `super_sliver_list` ^0.4.1 | `fl_ui/super_reorderable_list.dart` | 同上（上一轮评估过「将来懒加载可能用到」，真要用时再加回） |

另：`intl` **0 处直接 import**（只被 `flutter_localizations` 间接需要，不能删）；`cupertino_icons` **0 处引用**（可删，tree-shaking 后 APK 里仅 848 字节，收益小）。

### 5.3 其它自查结论（正面）
- **无 TODO/FIXME/HACK 遗留**（全仓 1 条，属注释说明）；`.env`、`.dev.vars`、`*.log`、`.tmp-*`、`dist/` 均未被 git 跟踪，`.gitignore` 覆盖良好。
- **前后端路由一一对应**：前端调用的 14 个 `/api/*` 在 `functions/api/` 下都有落点，无缺失/多余。
- 后端 POST `/api/ledger` 的幂等设计（客户端 `providedId` + `INSERT OR IGNORE` + 撞主键返回 `duplicate:true`）是健全的，网络重试不会重复入账。
- 时区统一硬编码东八区（`app/lib/core/week.dart:36-37`、`app/lib/core/day_completion.dart:55-56`），对国内家庭是刻意设计，不属于缺陷 —— 但它是 L-9 口径矛盾的背景。

---

## 6. 测试与工程化

| 项 | 现状 | 建议 |
|---|---|---|
| 单元测试覆盖 | 18 个测试文件，覆盖 `api_client`、models、changelog、week、theme、widgets 等 | 给**改过的核心逻辑**补单测：`FamilyState`（内容指纹 `_sameRecordList` / `_applyLedger`）、`GardenState`（离线队列、`_commit`）、`task_rules` 聚合、`image_compress` 尺寸上限、`api_client` 的 GET 单飞 |
| 集成测试 | `e2e_flow_test.dart` / `garden_flow_test.dart` **打生产后端** | 全量跑时会互相干扰 + 30s 超时偶发，还会往线上留 `e2e-` 数据（需手工清理）。建议：要么给测试专用 D1（或 `--dart-define` 指向 staging），要么把这两个标 `@Tags(['live'])` 默认不跑 |
| CI | **没有**（无 `.github/`，push 不触发任何检查） | 加一个最小 workflow：`flutter analyze --no-pub` + `flutter test --no-pub`（排除 live tag）+ `npx tsc --noEmit`。发版脚本前也值得跑一遍 |
| Lint | `analysis_options.yaml` 只有 `include: package:flutter_lints/flutter.yaml`，101 issues 全是 info | 逐步打开 `prefer_const_constructors`、`avoid_print`、`use_build_context_synchronously` 等；`flutter_lints` 默认集已够，不必上 very_good |
| 文档 | `docs/` 有性能审查、UI 迁移、安卓更新等 | 与代码同步良好；本次报告即续篇 |

---

## 7. 打包与体积（APK 24.96 MB）

`unzip -l app-release.apk` 的构成：

| 项 | 大小 | 说明 |
|---|---|---|
| `lib/arm64-v8a/libflutter.so` | 11.7 MB | Flutter 引擎，不可压 |
| `lib/arm64-v8a/libapp.so` | 10.5 MB | Dart AOT 产物；死代码经 tree-shaking 后影响有限，删 fl_ui 死文件主要收益在这 |
| `classes.dex` | 1.15 MB | Android 侧 |
| `assets/fonts/JetBrainsMono-Regular.ttf` | 274 KB | 只在少数代码字体位置用，可考虑子集化（只保留 ASCII + 常用符号） |
| `shaders/liquid_glass.frag` | 144 KB | 玻璃效果着色器 |
| `lib/x86_64/libdartjni.so` + `lib/armeabi-v7a/libdartjni.so` | 116 KB + 81 KB | **单 ABI（arm64）包里混进了另外两种 ABI 的 .so**，约 330 KB 可裁 |

建议：发版脚本固定 arm64 后，检查 `image_picker`/`dartjni` 是否把多 ABI 的 .so 带进来（`android { packagingOptions { jniLibs { excludes += ["**/x86_64/**", "**/armeabi-v7a/**"] } } }` 或检查依赖版本），一次性省几百 KB。

---

## 8. 后端（functions/ 33 + workers/reminder/src/ 5，实际 5927 行）

> 威胁模型：这是个部署在公网域名上的家庭应用，没有登录态。「家里人」以外的人只要知道域名就能直接打接口。
> 下面 B 组按这个前提排的序 —— 家里用不等于可以让人顺着接口把阳光扣光。

### 8.1 严重

| # | 位置 | 问题 | 建议 |
|---|---|---|---|
| B-1 | `functions/api/ledger/settle.ts:155-167` | **结算接口无鉴权，且 `date` 允许任意过去日期**（只挡未来、只挡开户日之前）—— 外部人可循环触发历史补结算：家人几天没开 App 时，本该下次打开才结算的罚款会被立即执行；响应里的 `applied` 数组还会暴露每天的罚款记录 id。罚款本身幂等、且基于「当日确实没完成」的真实事实（**不会凭空多扣**），但「公网无登录的写接口」不该存在 | 可结算日期限制为「昨天/今天」；若要保留补结算，加一道令牌 |
| B-2 | `functions/api/push/test.ts:108-146` | **公开接口可触发真实群发**，唯一门槛是 15 秒冷却，而冷却标记在 `fetch` 之后才写 —— 任何人可反复调用给全家手机刷通知、烧推送配额，并发还能同时穿过后写 | 加口令门禁；冷却改成发送前原子占位 |
| B-3 | `functions/api/maintenance/orphans.ts:177-197` | **破坏性清理只校验 `body.confirm === true`** —— 任何知道域名的人可 POST 清空所有未被引用的照片，不可恢复 | 先过 `gateAdminPassword` 或 `REMIND_TOKEN` 再允许 confirm |
| B-4 | `functions/api/upload.ts:45-72` | 文件头注释称「受 `/api/_middleware.ts` 鉴权保护」，**该文件不存在**，全站无鉴权也无上传配额 —— 任何人可无限写 5MB 图片撑爆 R2；未被引用的图要等 6h 宽限期，而清理接口本身也公开 | 加日计数配额或来源校验；删掉那条不存在的鉴权注释 |
| B-5 | `functions/_lib/settings.ts:274-286` | 管理员失败计数是「读 → +1 → 写回」的读改写，**非原子** —— 并发请求读到同一旧值，5 次锁定形同虚设，口令可被并发爆破；攻破后能改余额/改密码/跑自检 | 改 `UPDATE settings SET value = CAST(value AS INTEGER) + 1 …` 单语句原子自增 |
| B-6 | `functions/api/ledger/index.ts:166-236` | `dailyLimit` 与自定义任务日封顶都是「先 COUNT 再 INSERT」—— 并发或连点可同时通过检查，突破 `dailyLimit` 与 `CUSTOM_TASK_DAILY_CAP` 刷分 | 单条 `INSERT … SELECT … WHERE (SELECT COUNT(…)) < ?` 原子写 + 唯一约束兜底 |
| B-7 | `functions/api/plans/index.ts:44-59` | 用随机 UUID + `INSERT OR IGNORE`，但幂等实际落在唯一索引 `(week_label, task_name)` 上（不含 subject）—— 同一周两个科目下的同名任务（如都叫「预习」）被**静默丢弃**，接口仍回 201 且无提示 | 迁移重建唯一索引为 `(week_label, subject, task_name)`，用 `meta.changes` 回报实际写入数 |

### 8.2 中等

| # | 位置 | 问题 | 建议 |
|---|---|---|---|
| B-8 | `functions/_lib/settings.ts:194-206` | 管理员密码**明文**存 settings；读取失败回退 `DEFAULT_ADMIN_PASSWORD`（硬编码 `'3398377037'`）—— 这个值恰好就是 **Cloudflare 账号 ID**（也出现在 `wrangler.jsonc` 的 `REMINDER_URL` = `sekainook-reminder.3398377037.workers.dev` 里），可猜性极高；库短暂异常时等于退回这个公开口令 | 存哈希（SHA-256 + 盐）；读失败拒绝而非回退 |
| B-9 | `functions/_lib/settings.ts:124-130` | `sanitizeBackground` 只判断字符串「包含」`/api/images/` —— `https://evil.example.com/api/images/x` 也能存成全局背景图，每个客户端打开都向第三方发请求（泄露 IP/UA） | `new URL` 解析后断言 origin 一致且 path 前缀正确 |
| B-10 | `functions/api/ledger/[id].ts:62-65` | UPDATE 后不检查 `meta.changes` 就按「状态变了」发通知 —— 与并发 DELETE 竞争时仍回 `ok:true`，并推一条指向已删记录的通知 | `if (result.meta.changes === 0) return 404` |
| B-11 | `functions/api/ledger/snapshot.ts:61-83` | `pendingCount` 取 `pending.length` 而 pending 查询带 LIMIT；两个 `SELECT *` 各回最多 500 整行且 records/pending 高度重叠 —— pending 超 limit 时红点偏小，轮询响应体可达数百 KB | pending 用独立 COUNT；列表只选必要列 |
| B-12 | `functions/api/ledger/index.ts:166-236` | 一次打卡串行 4–6 次 D1 往返（日限 COUNT、两条自定义 COUNT、INSERT，pending 时再加 `readFamilyNames` + 通知 batch） | 三条 COUNT 合成一次 batch，或先 INSERT 再校验 |
| B-13 | `functions/api/ledger/settle.ts:180-198` | `MIN(created_at)` 与两条子查询 COUNT 都是全表扫，`family_ledger` 无 `(task_id, created_at)` 复合索引 | 加复合索引；`accountFirstDay` 缓存进 settings |
| B-14 | `functions/api/maintenance/orphans.ts:90-127` | R2 全量分页列举 + 一次 `all()` 把所有 `image_url` 载入内存 —— 图片上万时慢且费内存 | 分页即比对，或加增量游标 |
| B-15 | `functions/api/notifications/index.ts:44-55` | notifications **只增不删**（全仓无 `DELETE FROM notifications`），每次 GET 还要 COUNT 未读 —— 表无限增长 | 保留策略（30 天 / 每 audience 500 条），由维护接口顺带清理 |
| B-16 | `workers/reminder/src/reminder.ts:197-219` | 每天成功发送后往 settings 写一行 `reminder_sent_<day>`，只在失败时删 —— settings 随天数无限增长（一年 365 行），自检还整表读出 | 定时清 N 天前标记，或改单行「最后发送日」 |
| B-17 | `workers/reminder/src/channels.ts:162-173` | `request()` 没有超时（webpush.ts:89 有 15s）—— ntfy/bark/webhook 上游挂住会把 cron 或 `/trigger` 拖到 Worker 超时 | 加 `AbortSignal.timeout(10_000)` |
| B-18 | `functions/_lib/selftest/checks-core.ts:220-247` | `checkSummaryReconcile` 把 `GET /api/ledger`（默认 200、最大 500）当全量重算余额 —— 流水超 200 条后该自检**恒定误报**，掩盖真故障 | 直接跑 SUM SQL 复核 |
| B-19 | `functions/api/admin/index.ts:184-227` | 调整余额是「读 summary → 算差额 → 写流水」，非原子 —— 两个并发 adjust 各按同一旧值算差额，余额被推过头 | 固定目标值 + 幂等 task_id；写前复查 summary 做乐观校验 |

### 8.3 轻微

| # | 位置 | 问题 |
|---|---|---|
| B-20 | `functions/api/ledger/[id].ts:32-33` | `String(params.id)` 无长度/字符校验（`ledger/index.ts:36` 有 `ID_PATTERN` 却没用在这） |
| B-21 | `functions/api/plans/index.ts:36-41` | `target` 无取值范围、`items` 无条数上限（可拼出上百条 batch） |
| B-22 | `functions/api/push/subscribe.ts:32-46` | `endpoint`/`p256dh`/`auth` 无长度上限 |
| B-23 | `functions/api/images/[[key]].ts:13-15` | key 未强制 `tasks/` 前缀，bucket 内任意对象可被公开读 |
| B-24 | `functions/api/ledger/index.ts:233` | `image_url` 不校验来源/协议，可存任意外链（客户端渲染时外发请求） |
| B-25 | `workers/reminder/src/index.ts:133-141` | 令牌允许 `?token=` 查询串 + `===` 普通比较（进日志/历史、非常量时间） |
| B-26 | `workers/reminder/src/index.ts:32-46` | `/health` 匿名返回 server/appUrl/hasTriggerToken 等部署细节，且每次调用读一次 D1 |
| B-27 | `functions/_lib/settings.ts:181-190` | `sanitizeAdminPassword` 会 `trim`，用户设的首尾空格被静默吞掉 |
| B-28 | `functions/api/admin/index.ts:135` | 未知 action 静默降级为 verify，打错字看不出来 |
| B-29 | `functions/api/ledger/settle.ts:273-275` | catch 空手回 500，不打日志 |
| B-30 | `functions/api/maintenance/orphans.ts:160-166,192-197` | 两处 catch 不打日志 |
| B-31 | `functions/api/admin/selftest.ts:73-76` | 500 把 `error.message` 原文回客户端，泄漏表名/绑定名 |

> 另两条因上限未列入正文的：`plans/index.ts:66-72` 回读 `SELECT *` 后直接回 201，无法区分「真写入」与「被唯一索引丢掉」（是 B-7 的放大器）；
> `selftest/checks-rules.ts:263-294` 的 `checkPlanCreateIdempotent` 验不出同名不同科目被丢弃，反而给绿灯。

---

## 9. 页面层（`app/lib/ui/`）

### 9.1 严重

| # | 位置 | 问题 | 建议 |
|---|---|---|---|
| P-1 | `app/lib/ui/pages/settings/selftest_panel.dart:681-688` | `_checkImage` 在主 isolate 里同步造 1800×1200 噪点图（216 万次 `setPixelRgb`）再 `encodePng`、`compressImage`、`decodeImage`；`_runClientChecks`(:426) 的 16ms 让帧只够画出「正在跑哪一项」——点「运行」时面板冻结数百毫秒到数秒，低端机可 ANR | 整段丢进 `compute`/`Isolate.run` |
| P-2 | `app/lib/ui/pages/family/weekly_plan_page.dart:170-194` | `_persistPlan` 入口不判 `_pending.contains(plan.id)`，而 `_handleAdd`(:198)/`_handleCommit`(:202) 都是 `unawaited`，输入框 `onTapOutside` 也会 commit → 同一行可并发两个 PATCH；先发的成功后写 `_inputs`，后发的失败又回滚成旧值(:190) | 入口加 `if (_pending.contains(plan.id)) return;` |
| P-3 | `app/lib/ui/pages/settings/reminder_editor_sheet.dart:146-175` | `_busy = true` 后 `await addReminder/updateReminder` 无 try/finally、无复位——抛错时面板不关、按钮**永久置灰**；`:127-135` 的 `_test` 同样裸 await | try/finally 复位 + 失败 toast |
| P-4 | `app/lib/ui/pages/settings/settings_page.dart:617-622` | 拉「最近调整」失败时把 `_adjustments` 清空 → UI 显示「没有调整记录」，管理员把网络/密码过期当成「没人改过积分」 | 保留旧数据 + 独立错误态 |
| P-5 | `app/lib/ui/pages/home/kid_home_page.dart:360` | `settleLedgerOncePerDay()` 无 catch（外层 `:349-372` 只有 try/finally），三个调用点全是 `unawaited(_refresh())` —— 日结算失败变成未捕获异步异常，页面无提示 | 这一支也包 catch |

### 9.2 中等

| # | 位置 | 问题 | 建议 |
|---|---|---|---|
| P-6 | `family_dashboard_page.dart:1961-2013` | 历史记录 `filtered.take(_visibleCount)` 后在 `Column` 里 for 全量建 widget，「加载更多」只 `_visibleCount += 20` 且永不回收 | 与上一轮 P2-4 同一结论：等他日上 `SuperSliverList`；短期至少设上限 |
| P-7 | `family_dashboard_page.dart:490,521,533,543,553` | 一律 `catch (_)` + 「操作失败，请重试」，吞掉 `ApiException.message`（积分不够/已审批/超今日上限）；`:506` 的 `approveMany` 又只认 `StateError` | 统一走 `_handleWriteError` 的文案 |
| P-8 | `settings_page.dart:1255` + `theme_state.dart:188-193` | 字号 Slider 的 `onChanged` 直接 `setTextScale`，后者每次 `await _prefs.setDouble` + notify —— 拖动每一帧都写盘并重建整个 App | 照 `previewNavBarOpacity` 的做法：onChanged 只改内存、onChangeEnd 落盘 |
| P-9 | `kid_home_page.dart:519-523`、`parent_home_page.dart:365-368` | 一次 `context.watch` 四到五个状态，每次 build 重跑 `_recentSummary`/`_todayRecords`（含 `_latestRejected` 排序，`kid_home:484-489`） | `context.select` 收窄 + 缓存派生数据 |
| P-10 | `garden_page.dart:45-67` vs `kid_home_page.dart:46-68`；`kid_home_page.dart:99-149` vs `parent_home_page.dart:54-74` | `_gardenIcon` 逐字重复；`_greetingText/_dateText/_dayKey/_todayRecords` 也是两份 —— 改一处漏一处，首页口径会漂 | 抽到 `ui/widgets` 或 `core/` |
| P-11 | `settings_page.dart:48,56`、`garden_page.dart:2058,2084`、`selftest_panel.dart:1847`、`theme/app_theme.dart:135` | 对比度/前景色工具**四份实现**（WCAG 口径各自维护），自检面板判的 4.5:1 与 UI 实际算法可能不一致 | 合并成 `theme/contrast.dart` |
| P-12 | `parent_home_page.dart:1460`、`kid_home_page.dart:2052,2252` | 文案写死「女儿」/「让女儿知道为什么扣分」，而设置里可改称呼（momName/kidName）—— 改了称呼文案仍写死 | 用 `SettingsState` 的称呼拼 |
| P-13 | `settings/reminder_list.dart:220-224`（另 `:135` 「恢复内置提醒」） | 删除提醒、覆盖内置提醒都**无二次确认、无撤销** | 复用设置页的确认弹窗 |
| P-14 | `role_gate_page.dart:175-176` | 角色卡 `SizedBox(width: 320)` 硬编码，窄屏/大字号下超出可用宽度 | `ConstrainedBox(maxWidth: 360)` 或自适应 padding |
| P-15 | `settings_page.dart:2085`、`selftest_panel.dart:760` | 这两个确认框用原生 `showDialog`+`AlertDialog`，别的页统一 `showFloatingDialog` —— 两套弹窗视觉/交互 | 收敛到 `showFloatingDialog` |

### 9.3 轻微

| # | 位置 | 问题 |
|---|---|---|
| P-16 | `notifications_page.dart:334-335`、`weekly_plan_page.dart:598`、`settings_page.dart:1003-1004`、`selftest_panel.dart:1035/1095/1169` | `minimumSize: Size.zero` + `tapTargetSize: shrinkWrap`，点击区低于 48dp，老人机难点中 |
| P-17 | `family_dashboard_page.dart:1811` | 「再想想」与同文件 `:1748/:2173/:2196` 的「取消」混用，同类按钮两种叫法 |
| P-18 | `family_dashboard_page.dart:2294` | `setDialogState(() {})` 空更新，每次白重建一次弹窗 |
| P-19 | `family_dashboard_page.dart:618-625` | `_formatTime` 用 20 秒 tick 的 `_now` 判「今天」，跨零点后最多 20 秒内昨天的记录仍显示「今天 HH:mm」 |
| P-20 | `garden_page.dart:136-144` | `_timeLabel` 内部直接 `DateTime.now()`，与家庭页注入 `_now` 的口径不一致 |
| P-21 | `garden_page.dart:1866-1935` | 记录与徽章用普通 `Column` + for 全量铺，记录一多白建 widget |
| P-22 | `kid_home_page.dart:663,666` | 两处 `EnterBox(index: 10)` 同帧同相位，入场动效错峰失效 |
| P-23 | `push_section.dart:77`、`reminder_list.dart:41` | 用户**自己关掉**提醒也显示成错误红字（判定是 `!enabled && !permissionGranted`） |
| P-24 | `push_section.dart:415-417` | 把 `AppConstants.apiBase` 常量 URL 拼进给用户读的文案 |
| P-25 | `weekly_plan_page.dart:471-632` | `_buildRow` 每行都重算 `_cardBase`/`doneChipFill`（`:460,477`） |
| P-26 | `selftest_panel.dart:992-998` | `_controllers[param.name]` 为 null 时现场 new `TextEditingController`，没 dispose 且每次 build 换新（是否可达待验证） |
| P-27 | `reminder_editor_sheet.dart:189`（另 `:76-93`） | `insetPadding` 底部 `AppSpacing.xl * 3` 硬编码只为躲高 74 的底栏胶囊；`slot: 99` 是魔法值 |

另（Lead 自查，页面层 subagent 之外）：`family_dashboard_page.dart:2495` 在**每次上传时**都 `UploadApi(ApiClient())` —— 新建 Dio、绕过全局 client 的超时/重试/单飞；同类还有 `weekly_plan_page.dart:52`、`settings_page.dart:88`、`update_state.dart:59`。
建议这些统一从 `main.dart` 注入（`kid_home_page.dart:230` 的 static 单例是正确做法）。

---

## 10. 发版链路与构建配置（第 4 路审查）

> 这一章来自「React + 构建配置」那一路审查，关键行 Lead 已复核。**它翻出了本轮最危险的两条** —— 不是外部攻击，是「自己一次疏忽就静默生效、且不可逆」。

### 10.1 严重（3）

| # | 位置 | 问题 | 建议 |
|---|---|---|---|
| R-1 | `app/tool/publish_apk.ps1:133` | 上传前**从不读线上 `latest.json`**（全脚本无一处 GET），没有「versionCode 必须变大」的闸 —— 忘 bump `+N`、或用 `-SkipBuild/-ApkPath` 传旧包，照样发出去：`app/lib/data/models/app_update.dart:70` 的 `versionCode > currentVersionCode` 恒 false，**全家人静默收不到更新**，线上清单还可能被降级（线上现值 2.6.0/34，已核对与 pubspec 一致） | 上传前 GET 一次 latest.json，`versionCode <= 线上` 直接 throw |
| R-2 | `app/tool/publish_apk.ps1:115` | 证书 SHA-256 算出来只用于**文件名**（`:126-127`）和打印（`:116`），`:112` 只拦 `Android Debug`，**从不比对是否还是同一把 release 证书** —— 换机器/丢 jks 后用新 keystore 发布，老用户覆盖安装报「安装失败(-7)」，只能全家卸载重装（AGENTS.md 自己标注这是不可逆事故） | 把发布证书 SHA-256 固定进仓库，与 `:115` 比对，不一致即中止 |
| R-3 | `app/web/` 缺 `_routes.json`（对照 `public/_routes.json:1`） | Flutter 产物里没有 `_routes.json` → `functions/_middleware.ts:19` 对**所有**路径生效：实测线上 `/main.dart.js`、`/flutter.js`、`/icons/Icon-192.png` 都带 `Access-Control-Allow-Origin: *` —— 每个静态资源多一次 Pages Function 调用；且每次 `npm run web:deploy` 都会把 React 时期的 `_routes.json` 从线上删掉（回滚才恢复），`functions/_middleware.ts:9` 注释「生效范围由 public/_routes.json 决定」已失真 | 在 `app/web/` 放 `{"version":1,"include":["/api/*"],"exclude":[]}`，随产物一起部署 |

### 10.2 中等（10）

| # | 位置 | 问题 | 建议 |
|---|---|---|---|
| R-4 | `app/web/_headers:15`（另 `:12`、`:24`） | 实测线上 `/main.dart.js`、`/flutter_bootstrap.js`、`/sw.js`、`/favicon.png` 仍是 `Cache-Control: max-age=14400`，只有 `/version.json`、`/manifest.json` 的 no-cache 真生效 —— 该文件自述要根治的「发版后 4 小时旧 JS」并未解决（现在靠 `app/web/flutter_bootstrap.js:16-22` 给 main.dart.js 加 `?v=` 兜住；bootstrap 自身与 sw.js 仍被 4h 缓存） | 入口缓存别依赖 `_headers`，改构建期注入版本参数/hash；并查清 Pages 忽略这几条的原因（**待验证**） |
| R-5 | `package.json`（无 `engines`）+ `scripts/changelog-sync.mjs:45` | 脚本直接 `import('src/config/changelog.ts')`，依赖 Node ≥22.6 的类型擦除，仓库却没声明 engines（本机 v24.20.0 可用） | 换机器/CI（Node 20）发版第一步就 `ERR_UNKNOWN_FILE_EXTENSION` → 加 `"engines": {"node": ">=22.6"}` + 启动断言 |
| R-6 | `app/tool/publish_apk.ps1:98` | key.properties 前置检查写在 `:78` 的 `flutter build` **之后** —— 签名配置缺了也要先白等几分钟构建才抛错 | 检查挪到构建前 |
| R-7 | `scripts/changelog-sync.mjs:69` | date 只做正则形状校验，`2026-02-30 10:00:00` 能过并写进 D1，两端显示不存在的日期 | 加 `new Date()` 有效性校验 |
| R-8 | `scripts/changelog-sync.mjs:84` | 只校验 `APP_VERSION` ↔ `entries[0].version`，从不读 `app/pubspec.yaml:19` —— 三方（APK versionName / 网页版本号 / 版本日志）漂移无拦截 | 读 pubspec 的 `version:` 做三方比对 |
| R-9 | `functions/api/changelog/index.ts:29` | ETag 只由 `snapshot.version` 派生 —— 同版本号下改 changes 文案（修错别字）后浏览器永远 304，到下次升版本才更新（**这条是上一轮 P3 我自己引入的**） | ETag 带内容摘要或 `updated_at` |
| R-10 | `.trae/rules/project_rules.md:131` | 关键约束「`public/_routes.json` 必须保持 `include: ["/api/*"]`」在 Flutter 主域名下已不成立（产物里没这个文件），后人按文档排查会误判接口被吞成 HTML | 注明这是 React 产物约束；Flutter 需在 `app/web/` 补等价文件（同 R-3） |
| R-11 | `README.md:144` | 仍写「线上部署后（`npm run deploy`）用手机浏览器打开站点」—— 照做会把 Flutter 产物覆盖回 React（同文件 `:81` 已写对） | 改成 `npm run web:deploy` |
| R-12 | `.trae/rules/project_rules.md:10` | 前端栈写「antd / antd-mobile」，antd-mobile 既不在 package.json 依赖也无任何 import | 删掉 antd-mobile |
| R-13 | `.trae/rules/project_rules.md:19` | 目录约定只列 ledger/plans/upload/images，实际 `functions/api/` 下还有 admin、changelog、maintenance、notifications、push、settings 等 | 补齐，或写「以 functions/api 实际目录为准」 |

### 10.3 轻微（10）

| # | 位置 | 问题 | 建议 |
|---|---|---|---|
| R-14 | `app/pubspec.yaml:56` | `dynamic_color: 1.9.0` 是全表唯一精确锁版（其余皆 caret），小版本无法跟进，别的包要不同版本时直接解析失败 | 改 caret 或注明锁版原因 |
| R-15 | `app/pubspec.yaml:59` | `material_color_utilities: ^0.13.0` 是 Flutter SDK 自带依赖的显式覆盖，SDK 升级时最易先冲突（当前能构建） | 非直接 import 就删 |
| R-16 | `app/lib/fl_ui/models.dart:5` | 用了 `part 'generated/models.freezed.dart'` + `@freezed`，但 dev_dependencies 里没有 freezed / build_runner（生成文件已提交）—— 改模型时无法再生成。**该文件当前不可达（见 §5）**，暂不影响 | 补 dev_dependencies 或改手写不可变类；若按 §5 删死代码则一并消失 |
| R-17 | `vite.config.ts:64` | `manualChunks` 匹配列表里有 `echarts-for-react`，该包未安装（`src/components/BalanceTrend.tsx:15` 注释正好解释为何不用它） | 删掉该分支 |
| R-18 | `app/tool/publish_apk.ps1:140` | `-Changelog` 不传时清单无 changelog 字段 → 更新弹窗文案空白（AGENTS.md 示例每次都传，所以漏传没人发现） | 回落默认文案或直接报错 |
| R-19 | `app/tool/publish_apk.ps1:97` | key.properties 这道闸被 `if (-not $SkipBuild)` 包着 —— `-SkipBuild/-ApkPath` 发手工包时少一道前置检查 | 挪出条件外 |
| R-20 | `app/tool/publish_apk.ps1:104` | `$env:ANDROID_HOME` 未设时 build-tools 拼成相对路径，apksigner 找不到只 `Write-Warning`（`:118`）静默跳过签名校验 | 未设时明确报错 |
| R-21 | `notification-options.html:1` | 根目录一个 124KB 演示页被 git 跟踪，与主站无关 | `git rm --cached` 或挪进 `docs/` |
| R-22 | `src/utils/swUpdate.ts:54` | 有新版时 `window.confirm` —— iOS 主屏幕独立窗口里体验差，还打断正在填的表单 | 换页内提示条 |
| R-23 | `scripts/changelog-sync.mjs:268` 与 `app/tool/publish_apk.ps1:57` | 直接跑 wrangler，而 AGENTS.md 要求先手动清 `HTTP_PROXY` —— 忘清时 `changelog:sync` / R2 上传在中段失败，脚本自己不检测 | 启动时检测代理并提示/临时置空 |

### 10.4 React 退役与回滚（结论：回滚可用，但有护栏缺口）

| # | 位置 | 问题 | 建议 |
|---|---|---|---|
| R-24 | `package.json` 的 `"deploy"` | `npm run build && wrangler pages deploy` 会把 **React 产物**推到同一 Pages 项目，**直接盖掉线上 Flutter 版** | 改名 `deploy:legacy-react` 并加提示；AGENTS.md 有口头警告但脚本无护栏 |
| R-25 | `wrangler.jsonc` 的 `pages_build_output_dir: "./dist"` | 指向 React 的 `dist`，日常部署却用 `app/build/web` —— 谁直接敲 `wrangler pages deploy` 就传错目录 | 注释说明「仅 React 回滚用」或拆 `wrangler.react.jsonc` |
| R-26 | 依赖树 | `antd` + `echarts` + `@ant-design/icons` 等 8 个运行时依赖只服务回滚，`npm install` 重、`npm audit` 长期有噪音 | 打 `git tag react-legacy-2026-10` 后从主干删 `src/` + 依赖（回滚走 Cloudflare 部署历史 Rollback） |
| R-27 | `public/sw.js` + `BUILD_ID` | 这是解决 React 版「上线要刷好几次」的 SW 机制，Flutter 走自己的 sw，已无意义 | 与 R-26 一起归档 |
| R-28 | React 侧 | 无 eslint / prettier | 已退役，不值得补 |

**回滚可用性（正面结论，未发现问题）**：`src/` 66 个 ts/tsx 的相对 import 全部可解析、裸包 import 全在 deps 内、`/api` 路径全有对应 Functions、`ErrorBoundary` 与 localStorage 读写处处 try/catch（`src/App.tsx:101-108`、`src/store/useGardenStore.ts:366-418`）、`src/api/http.ts` 的超时/重试合理。`npm run deploy` 本身能跑（`dist` 会带上 `public/_routes.json`，回滚后 Functions 收窄回 `/api/*`）。

### 10.5 配置层健康的部分（不用动）

- `tsconfig.json`：`strict` + `noUnusedLocals` + `noUnusedParameters` + `noFallthroughCasesInSwitch` 全开，`include` 覆盖 `src`、`functions`、`worker-configuration.d.ts`（`npx tsc --noEmit` 一次校验前后端）。
- `vite.config.ts`：dev 代理显式 `target: 'http://127.0.0.1:8788'` 并注释了 IPv6 坑；`watch.ignored` 挡编辑器 `.tmpdir`；`BUILD_ID` 方案本身正确（只是 React 专属）。
- `workers/reminder/wrangler.jsonc`：cron `30 13 * * *`（UTC）= 北京 21:30，注释写清了；`observability` 已开；VAPID 公钥与 Pages 项目一致。
- `package.json` 的 `web:deploy` 一条命令走完 `flutter build web` + `wrangler pages deploy app/build/web`，参数齐全。

---

## 11. 优先级建议

### 第一批：下个版本（P0，风险最高、改动最小）

| 项 | 为什么先修 | 大概改法 |
|---|---|---|
| **R-1 发版前不校验 versionCode 递增** | 一次忘 bump `+N` 就**全家人静默收不到更新**，且线上清单可能被降级 —— 无任何报错 | 上传前 GET 一次 `latest.json`，`versionCode <= 线上` 直接 throw。20 行 |
| **R-2 发版不比对证书指纹** | 换机器/丢 jks 后一次发布 → 老用户覆盖安装「安装失败(-7)」，**只能全家卸载重装，不可逆** | 把 release 证书 SHA-256 写死进脚本比对，不一致中止。10 行 |
| **B-2 / B-3 / B-4** 公开接口可群发通知、清空照片、无限上传 | 破坏性 + 攻击门槛最低（知道域名即可） | 三个接口共用一道 `gateAdminPassword`/令牌；上传加日配额。半天 |
| **S-1 + S-2** 主题重建造第二套 store / 补发闸 static | 灵异 bug 的根，且两者同源 | store 构造移到 `main()`；`_syncLoopReady` 改实例字段 + `dispose()` |
| **S-4 + L-4** 启动链无保护、模型硬转 | 一条坏存档 → 半残启动 | `_bootstrap` 每步 try/catch；`fromJson` 复用 `_toSafe*` |
| **S-3** 两个 prefs 键非原子写 | 真会丢阳光 | `pending` 并进同一 payload |
| **B-7** 计划同名任务静默丢弃 | 用户可感知的数据丢失 | 迁移唯一索引加 `subject` |
| **S-5 / S-6 / S-7 / S-8** 并发覆盖、提醒漏排、坏条全挂、unhandled error | 都是「偶发但难查」 | seq 守卫 / 串行队列 / 单条 try-catch / `Future.wait` |
| **P-3 / P-4 / P-5** 面板永久置灰、假「没有记录」、未捕获结算异常 | 用户直接卡死或误判 | try/finally + 保留旧数据 + catch |

### 第二批：下个版本之后（P1）

- 后端：B-1（settle 日期收窄）、B-5（失败计数原子自增）、B-6（日限原子写）、B-8（密码哈希）、B-9（背景图 URL 校验）、B-10（`meta.changes` 检查），以及 B-12/B-13 的查询合并与索引。
- 发版与构建（R 组中等项）：R-3（`app/web/_routes.json`）、R-4（入口缓存别再依赖 `_headers`）、R-5（`engines` + Node ≥22.6 断言）、R-6~R-8（发版脚本前置检查与版本/日期校验）、R-9（ETag 带内容摘要）、R-10~R-13（三份文档与代码对齐）。
- 状态层：M-1~M-12（重入守卫、错误信息、getter 不可变、`_nextSlot`、`_nextStreak`、死代码 `_syncBackgroundCache`、`todayProgress` 聚合）。
- 页面层：P-1（自检面板丢 isolate）、P-2（并发 PATCH）、P-6（记录列表）、P-7（错误文案）、P-8（字号落盘节流）、P-9（select 收窄）。
- 工程化：把 `e2e_flow_test` / `garden_flow_test` 从默认测试里摘出去（`@Tags(['live'])`）+ 加最小 CI。

### 第三批：择机（P2）

- **死代码**：`fl_ui` 不可达 39 文件 / 9726 行 + 5 个只服务它们的依赖（见 §5）。删之前先确认没有动态引用。
- **测试**：给 `FamilyState`/`GardenState`/`task_rules`/`image_compress`/`api_client` 单飞补单测。
- **体积**：多 ABI `.so` 清理（约 330KB）、JetBrainsMono 子集化。
- **页面打磨**：P-10~P-27 里的重复实现（`_gardenIcon`/对比度工具四份/称呼写死）、点击区 48dp、弹窗统一、文案统一。
- **依赖治理**：`cupertino_icons` 删、`intl` 留着（被 `flutter_localizations` 需要）。

### 不建议动（写进来是为了以后别再提）

- `intl` 0 处直接 import 是正常的 —— `flutter_localizations` 依赖它。
- 后端的「无鉴权」整体改成登录体系不在本期范围：**用口令/令牌堵住破坏性接口**即可，别上完整 auth。
- `task_rules` 的全表扫描在家庭规模（几百条/年）不成问题，除非流水上千。
- `fl_ui` 的玻璃/动效组件是刻意移植的视觉基线，不要为了「统一」重写。

### 待实测（静态推断，动手前先复现一次）

1. **L-2** EXIF 方向：`image_picker` 的 `maxWidth/maxHeight` 预缩放是否已把方向烘平 —— 拿一张竖拍照片走一遍上传，看结果。
2. **P-26** `selftest_panel` 的 controller 兜底分支是否可达。
3. **B-18** `checkSummaryReconcile`：流水超 200 条后自检是否真的恒定报错（用本地 `wrangler pages dev` + 造 300 条验）。
4. **S-1** 的触发路径：Android 12+ 开「跟随壁纸」后换壁纸，store 是否真的重建（加一行 `debugPrint` 验）。
5. **P-1** 自检面板冻结时长：低端机上跑一次「客户端自检」计时。
6. **R-4** `_headers` 为何没生效：部署后 `curl -I /main.dart.js` 看 `Cache-Control`，同时核对 `app/build/web/_headers` 是否被 `flutter build web` 原样拷进产物（怀疑是 Pages 只读部署根目录的 `_headers`，或 pattern 写法问题）。
7. **R-3** 补完 `_routes.json` 后复查：`curl -I /main.dart.js` 不应再带 `Access-Control-Allow-Origin`，且 Functions 调用量应下降。

---

## 12. 附：本轮没有改任何代码

- 工作区保持干净（`git status` 只有未跟踪的 `docs/web-2.5.0-home.png` 与本文档）。

---

## 13. 第二轮补扫（2026-10-24 深夜）

上一轮的 4 路审查偏「性能与正确性」，这一轮换四个角度：数据模型边界、资源生命周期与内存、
迁移/schema/R2/隐私、Web 与 Android 行为差异。**仍然只读，不改代码。**

### 13.1 迁移与 schema（A 组）

- **M-A-1（中）`migrations/0002_ledger_member.sql:13` 不可重入** —— 裸 `ALTER TABLE family_ledger ADD COLUMN member TEXT;`，SQLite 没有 `ADD COLUMN IF NOT EXISTS`，而 `README.md:173` 写着「编号递增，必须幂等」，0003–0006 都用了 `IF NOT EXISTS`，只有它破例。重复执行（新环境 / `d1_migrations` 记录丢失 / 有人先手工建过表）会在写迁移记录前中断，`0003`–`0006` 全部不执行，之后每次 `db:migrate:remote` 都死在同一行。建议加 `scripts/db-migrate.mjs` 先查 `PRAGMA table_info` 再决定是否跑 0002。
- **M-A-2（低）`migrations/.changelog-sync.sql`（86KB / 81 条 INSERT）躺在 migration 目录里** —— 只因为 wrangler 的 `getD1MigrationFiles` 用 `Minimatch(pattern, { dot: false })` 才没被 `d1 migrations apply` 当成迁移。任何 `migrations/*.sql` 通配批量执行都会误跑。建议挪到 `scripts/sql/changelog-sync.sql`。
- **M-A-3（中）管理员加分被算进「今日完成数」—— 已核实成立** —— `functions/api/admin/index.ts:40-41` 写入 `task_id='admin_adjust'` 与 `garden:admin_adjust`，但 `functions/_lib/rules.ts:202-206` 的 `COMPLETION_EXCLUDED_IDS` 只有 `seed_welcome_bonus / daily_min_tasks_penalty / sleep_penalty`；`DAY_COMPLETION_SQL`（`rules.ts:251-258`）`COUNT(DISTINCT task_id)` 会把管理员加分算成 1 个完成任务 → 抵消当天的 `daily_min_tasks_penalty` 罚款，也让提醒 Worker 少报「还差 N 个任务」。修法：把两个 ADMIN_* id 加进 `COMPLETION_EXCLUDED_IDS`（该数组是唯一真源）。
- **M-A-4（中低）`migrations/0001_init.sql:34` 唯一索引 `(week_label, task_name)` 不含 subject** —— 配 `functions/api/plans/index.ts:49` 的 `INSERT OR IGNORE`：同一周两个科目下都有同名任务（如「读书」）时第二条被静默丢弃、接口仍回成功，前端周计划缺项且无提示（与 §8 B-7 同源，这里补充「无任何错误提示」）。修法：唯一键改 `(week_label, subject, task_name)` 或换 `ON CONFLICT DO UPDATE`。
- **M-A-5（低）`functions/api/ledger/summary.ts:24-28` 的 `status IS NULL` 是死分支** —— `migrations/0001_init.sql:14` 是 `status TEXT NOT NULL DEFAULT 'approved'`。要么线上老库真可空（那这类脏行会静默计入余额），要么只是噪音。建议核对线上 `PRAGMA table_info` 后二选一。
- **M-A-6（低）`push_subscriptions.audience` 无 CHECK 约束** —— `migrations/0005_push_subscriptions.sql` 只是 `TEXT NOT NULL DEFAULT 'child'`，`functions/api/push/subscribe.ts:33-46` 只校验 keys 不校验取值；写错大小写（`Parent`）的订阅永远匹配不到，前端仍显示「订阅成功」。
- 正面：迁移建的表/列/索引与 `functions/` 实际读写**逐项对得上**（member、weekly_plans.subject、ua、read_at/dedupe_key、sort_order 都有真实读写），除 0002 外无 DROP/RENAME 类破坏性变更。

### 13.2 R2 图片对象（B 组）

- **M-B-1（中）`functions/api/images/[[key]].ts:13-15` 无 key 前缀白名单** —— `bucket.get(key)` 不看前缀，`/api/images/*` 等于整个桶的公开只读网关；以后任何往这个桶写东西的路径（`wrangler r2 object put`、别的 Worker、备份脚本）都会在 `sn.starrymiku.com` 同源可读。
- **M-B-2（中）`images/[[key]].ts:20-27` Content-Type 由对象元数据决定且无 `nosniff`** —— `writeHttpMetadata` 原样回显上传时的 contentType，响应里没有 `X-Content-Type-Options: nosniff`。能写桶的路径写入 `text/html` 就等于在本站同源执行脚本；该源 localStorage 里有家长口令摘要、角色、余额，API 又全部无鉴权。建议 Content-Type 白名单 + nosniff + `Content-Disposition: inline`。
- **M-B-3（中高）`functions/api/upload.ts:71-75` 无任何配额** —— key 是 `tasks/${Date.now()}-${uuid8}.${ext}`，猜不到，但没有频率/总量/单账号限制：任何人可无限 POST 5MB 图片，R2 存储与出网流量直接进账单，也能把桶塞到孤儿清理处理不过来的规模。建议 WAF rate limit + 按日上传计数。
- **M-B-4（高）`functions/api/ledger/index.ts:233` `image_url` 零校验 —— 可删任意 R2 对象** —— `typeof image_url === 'string' ? image_url : null`，长度都不限。危害两层：(a) 可存任意外链，前端 `<img>` 直载 → 第三方追踪像素；(b) `functions/api/ledger/[id].ts` 删除时用 `image_url` 反推 R2 key，只要把 `image_url` 写成 `https://<本站>/api/images/tasks/<别人的照片>` 再删掉这条流水，就能删掉那个对象——包括 `settings.background` 指向的全局背景（`[id].ts` 对 background 没有任何保护）。建议入库前校验 `new URL()` 成功 + `pathname` 前缀 `/api/images/tasks/` + 长度 ≤ 400。
- **M-B-5（中低）`ledger/[id].ts:122-132` 先删图再删库且吞 R2 错误** —— D1 删除失败时图片已不可恢复、流水留 404 图；R2 删除失败只留孤儿，现场无日志。建议先删 D1（或先把 `image_url` 置 NULL）再删对象，`catch` 至少 `console.warn`。
- **M-B-6（中）`maintenance/orphans.ts:111-127` 引用判定只认两个字段** —— 只收集 `family_ledger.image_url` + `readBackground`；`extractImageKey` 在 `orphans.ts:51-61` 与 `ledger/[id].ts:19-29` 各写一份。新增图片字段忘了登记 → 6h 后被当孤儿真删；两份实现漂移则「删除流水删得掉、清理删不掉」。建议收敛 `REFERENCE_SOURCES` 常量 + `_lib/` 只留一份。
- **M-B-7（中）`maintenance/orphans.ts:168-173` GET 无闸门吐 200 个 key** —— 只读扫描接口公开返回 `keys`，而 6h grace 内的孤儿多是自己刚上传、流水还没写进去的照片；配合 `/api/images/:key` 可逐张查看。

### 13.3 数据安全与隐私（C 组）

- **M-C-1（高）`functions/_lib/settings.ts:174` `DEFAULT_ADMIN_PASSWORD = '3398377037'` 是最终回退值** —— `readAdminPassword` 在 settings 表没有 `admin_password` 时回退到它，`admin/index.ts:154` 明文比较。线上若从没改过（很可能，因为默认值能用），任何人读公开仓库就知道口令，可改余额、审批、跑自检（自检能写库、发真通知）。这 10 位数字还与 `wrangler.jsonc` 里 `REMINDER_URL` 的子域一致。建议删回退值（无口令一律 503）+ 口令走 `ADMIN_PASSWORD` secret。
- **M-C-2（中）`settings.ts:171` 管理员口令明文存在与「公开称呼」同一张表** —— `admin_password` 与 `mom_call` / `background` 同居 `settings`，无可见性分区；一次 `d1 export` 或备份就把口令带走。建议单独表或存 hash+salt。
- **M-C-3（中）`workers/reminder/src/index.ts:139` `/trigger` 接受 `?token=`** —— 令牌会进 Cloudflare 访问日志、浏览器历史、Referer。建议只收 `Authorization: Bearer`。
- **M-C-4（中）`workers/reminder/src/index.ts:23-25` cron 把整个 `RunResult` 打进 console.log** —— 含 `sendDetail`（上游推送服务响应原文），而 ntfy 的 topic 本身就是访问凭证，上游错误体常回显它。建议只打 `sent/skipped/sendStatus/sendChannel`。
- **M-C-5（低）`functions/api/push/test.ts:135`、`workers/reminder/src/channels.ts:166` 上游响应体 300 字回客户端** —— 内部地址 / token 可能被前端拿到（自检面板还会展示并可复制）。建议只回状态码 + 归类原因。
- **M-C-6（中）`app/lib/core/pin_guard.dart` 4 位数字 + 固定 salt（`sekainook-pin:`）+ 纯客户端门禁** —— 1 万次哈希即可反查；改 localStorage 里的 `sha256:...` 或 `sekainook_role` 就能直接进家长模式；Web 侧在非安全上下文还会降级写 `plain:<明文>`。注：这是纯本地防误触设计，不算漏洞，但「家长模式」被当成隐私边界时它不成立。
- **M-C-7（低）Web localStorage 缓存了比展示必需更多的东西** —— `sekainook_bg_cache_v1`、`sekainook_garden_state`（余额/兑换/待同步 ops）、`sekainook_family_names`；不含口令，但含家庭消费与作息，同源脚本可一把读走，设备借用/丢弃时也不会随「登出」清掉。
- **M-C-8（高）图片 URL 即公开相册** —— `GET /api/ledger` 无鉴权返回全部 `image_url`（含孩子照片），`GET /api/maintenance/orphans` 再补 200 个 key，`/api/images/*` 无签名、`ACAO: *`、`Cache-Control: public, max-age=31536000, immutable`。等于「知道 URL 就能看」这层保护不存在；`ACAO: *` 让任意网站跨站 fetch 走流水 JSON；长期公开缓存意味着删了记录也删不掉 CDN/浏览器副本。建议图片改私有 + 短期签名，缓存降 `private, max-age=0, must-revalidate`，ACAO 收成站点白名单。
- **M-C-9（低）`workers/reminder/src/reminder.ts:147,213` 通知正文进日志** ——「今天还差 N 个任务」落到 Cloudflare 日志（保留期不可控、不可删）。
- 正面：错误响应体一律中文短句、**不含 SQL / 堆栈 / D1 错误原文**；`functions/` 内无 `console.log`；`workers/reminder/.dev.vars` 已被 `.gitignore:14` 忽略；`GET /api/settings` 只返回 `names/background`，没有泄 `admin_password`。

### 13.4 数据模型与序列化边界（D 组）

整体判断：**这是仓库里做得最用心的一层** —— `_toSnapshot`/`_toSummary`/`_toSettleResult` 都有整体形状校验，
`app_update`/`changelog` 是「字段不全就当没读到」的正确姿势，camelCase 契约与后端逐一对过**没有漂移**。
问题集中在「**记录级解析没有隔离**」+「三类兜底在掩盖故障」：缺失→0、坏时间→现在、未知枚举→默认值。
下面 10 条中等全出自这一族。

- **D-1（中）`app/lib/data/api/ledger_api.dart:237` `_parseRecords` 没有逐条 try/catch** —— 只挡了 `item is Map<String, dynamic>` 就直接 `LedgerRecord.fromJson`，而 `app/lib/data/models/ledger_record.dart:65,69,71,72` 有 4 处 unchecked cast（id/task_name 的 `as String`、amount 的 `as num?`、note/image_url 的 `as String?`）。一条字段类型不对的记录抛 TypeError → 整批解析失败 → `app/lib/state/family_state.dart:182-188` catch rethrow → 账本页停在旧数据并持续报错。SQLite 的 INTEGER 列可能存进文本（脏数据/手改库），不是纯理论。建议逐条 try/catch 跳过并计数 + `_asString/_asNum` 宽松 helper。
- **D-2（中）`ledger_record.dart:70`（同型 `notification_record.dart:71`）`createdAt: parseTime(...) ?? DateTime.now()`** —— 解析失败静默变成「现在」，于是 `app/lib/core/task_rules.dart:31,47` 的当日提交计数把脏记录算进今天 → 该任务当天直接置灰；`app/lib/core/day_completion.dart:65-66` 当日完成数虚高。建议保留 null 或纪元时间并显式标记，**绝不用 `DateTime.now()` 兜**。
- **D-3（中）`ledger_record.dart:14-20,89` 未知状态被当成已入账** —— `LedgerStatusX.parse` 对未知非空值返回 null，而 `isCredited => status == null || approved` 把 null 当已入账。后端将来加 `expired/void/cancelled` 时，前端会把它计入 `calcApprovedBalance` 和 CSV，与服务端 `functions/api/ledger/summary.ts:28` 的口径相反且无任何信号。建议区分「字段缺失」与「未知非空值」。
- **D-4（中）`app/lib/data/models/task_config.dart:11-12` `TaskType.parse` 未知值一律 earning** —— `value == 'spending' ? spending : earning`。未知 type 的流水进「赚钱」分支（`task_rules.dart:18` 要求拍照、`day_completion.dart:62` 计入完成数），而 `signedAmount`（`ledger_record.dart:101`）按 amount 符号显示，可能相反（显示 -50 但计入完成数）。建议加 `TaskType.unknown`。
- **D-5（中）客户端有两套时区口径** —— `ledger_record.dart:78-86` + `task_rules.dart:55-56` 用**设备本地日历日**判「今天已打卡」，而服务端日限/罚款全部硬编码东八区（`functions/_lib/rules.ts:337-353`），同一客户端里 `day_completion.dart:51-57` 又按东八区算。设备/浏览器不在 UTC+8 时，东八区 00:00–08:00 区间的记录会被算到前一天 → 「客户端说还能打、服务端说超限」。中国境内不触发，属跨时区/旅行才暴露的潜伏 bug。建议客户端统一 `WeekUtil.beijingDayKey`。
- **D-6（中）`app/lib/state/custom_tasks_state.dart:122` + `custom_task.dart:105,107` 坏存档能崩启动** —— `_restore()` 里 `map(CustomTask.fromStored).whereType<...>()` 无 try/catch，而 `fromStored` 的 `raw['createdBy'] as String?` / `raw['kind'] as String?` 是 unchecked cast（同函数其余字段都用 `is` 检查）。一条 `createdBy: 1` 就让整个自定义任务列表加载失败，而 `_restore` 在构造期调用。建议 `is String` 检查 + 整批 try/catch（`local_notify_state.dart:475-493` 已有正确范式）。
- **D-7（中）`ledger_record.dart:69` `amount` 缺失静默 0** —— `(json['amount'] as num?)?.toInt() ?? 0`，坏字段显示 `+0` 且仍算已入账 → 余额静默偏差。建议缺失即丢弃该条或整体报错。
- **D-8（中）花园 id 两套清单已漂移** —— 前端 `app/lib/core/ledger_ids.dart:19-24` 用精确相等比 `gardenLegacyTaskId`，后端 `functions/_lib/rules.ts:305,312-314` 的 `GARDEN_LIKE_CLAUSE` 是 `LIKE 'garden_legacy%'` 前缀匹配。任何 `garden_legacy*` 变体会被服务端算进阳光、被前端算进家庭积分 → 两个余额对不上。建议两侧统一 + 加跨语言一致性断言。
- **D-9（中）`app/lib/data/api/notification_api.dart:28` + `notification_record.dart:110` 形状不检查就窄化** —— `fromJson` 形参是 `Map<String,dynamic>`，调用处传的是 `getJson<dynamic>` 的 dynamic。服务端返回数组（老版本 `/api/notifications` 直接回 `[]`）时抛 TypeError 而不是 ApiException，`notification_state.dart:77-82` 只能兜成「通知加载失败」、`ready` 语义丢失。建议形参改 dynamic。
- **D-10（中）`app/lib/data/api/upload_api.dart:43-44` 空 url 能穿过 null 检查** —— `url: (raw?['url'] ?? '') as String`，上传接口「200 但缺 url」被当成功 → `kid_home_page.dart:2064` 只判 `imageUrl == null`，空串一路写进账本 `image_url: ''`（服务端 `typeof === 'string'` 照收），「要拍照」的打卡以一张破图通过。建议空串/非字符串抛 ApiException。
- D-11（轻微）`task_config.dart:84-95/123-132`：`requirePhoto`（L82）既不在 fromJson 也不在 toJson，JSON 往返一次就丢「不需要拍照」设置。当前全仓无调用点（休眠缺陷），建议补齐或删方法。
- D-12（轻微）`ledger_api.dart:76-83,243-258`：`fetchSnapshot` 把 500/超时/字段漂移全吞成 null 静默回退三请求 → 后端一改字段就永久走 3 倍请求旧路径且零日志。建议区分 404（老部署，静默）与格式不对（记日志）。
- D-13（轻微）`ledger_api.dart:152,180`：`LedgerWriteResult.fromJson(raw ?? const {})` 兜底空 id，`autoApprove && result.id.isNotEmpty` 才审批 → 记账返回空体时跳过审批仍当成功。建议空 id 抛错。
- D-14（轻微）`ledger_record.dart:121-131`：`toJson` 不含 `member` 却带服务端忽略的 id/status/created_at（当前无调用点）。
- D-15（轻微）时间解析重复三份（`ledger_record.dart:78-86`、`notification_record.dart:75-79`、`admin_api.dart:57`，另 `weekly_plan.dart:36`）且数字分支硬编码毫秒（秒级时间戳会被当成 1970）。建议抽 `parseWireTime`。
- D-16（轻微）`notification_record.dart:9-10`：`NotifyAudience.parse` 未知值一律 parent → 后端新增 audience 时通知静默落进家长信箱。
- D-17（轻微）`weekly_plan.dart:34` vs `functions/api/plans/index.ts:55`：前端 `.round()`、后端 `Number(item.target)` 允许小数，两个客户端可能看到不同分母；`created_at` 是全批唯一硬 cast。
- D-18（轻微）`app_update.dart:57,76` + `apk_installer_io.dart:32`：sha256 只校验 `length == 64` 不验字符集；`fileName => 'SekaiNook-$versionName.apk'` 不做字符清洗，`versionName` 含 `/` 或 `..` 会写出缓存目录（清单在 R2，能写桶就能构造文件名）。**待验证**。
- D-19（轻微）`local_reminder.dart:309-310,324,328-329`：slot clamp 1..99 + 时间越界静默默认 21:30；两条同 slot 提醒映射到同一 notificationId（`2100 + slot*10`）→ 后注册覆盖前一条。
- D-20（轻微）`maintenance_api.dart:70,80`：空响应体返回 `{total:0, orphans:0, keys:[]}` 把「接口没返回内容」伪装成「没有问题」。

**最该先做的两件**：给 `_parseRecords` 加逐条 try/catch；禁止用 `DateTime.now()` 兜时间戳。

### 13.5 资源生命周期与内存（L 组）

单个页面的资源纪律**相当好**：定时器、控制器、Observer、键盘处理器几乎都成对，`mounted` 守卫写得比一般项目密
（逐处核对清单见本节末）。真正的问题全在**跨组件的所有权边界**上。

- **L-1（高）8 个 store 在 `DynamicColorBuilder.builder` 里构造，而 builder 会二次执行 —— 这是 §2 S-1 的完整机制** —— `app/lib/main.dart:58-80` 的 8 个 store 全在 builder 闭包内；`dynamic_color` 1.8.1 的 `DynamicColorBuilderState.initPlatformState()` 拿到 palette/accent 后会 `setState`（`dynamic_color_builder.dart:70-73 / 92-101`）→ builder 再跑一遍 → 造出**第二套 store**，`SekaiNookApp` 因同类型同位置被原地更新 → `app.dart:67` 的 `late final _router`、`:77-82` 的 `addListener`、`:110-128` 的 `_bootstrap` 仍绑第一套，Provider（`app.dart:134-141`）却用 `.value` 暴露第二套。后果：① 第一套被 router 里的 listener 永久钉住 → 泄漏整套 store（含 GardenState 全量存档）；② 第二套永不 bootstrap → `loadBackground()`（全仓唯一调用点 `app.dart:111`）不跑，settings、本地提醒、更新检查全部不跑；③ `_onFamilyChanged` 挂在第一套上，其 `records` 恒空 → `localNotify.syncFromRecords(...)` 永不触发 → **本地提醒不再随账本重排**。**Android 12+ 且系统下发 palette/accent 时，每次冷启动必现**（真机待验证：在 `_bootstrap` 打印 `identityHashCode(widget.family)`，看是否有一段 store 从未被 bootstrap）。修法：把 8 个 store 提到 `main()` 里、`runApp` 之前构造，`DynamicColorBuilder` 只负责把 seed 传给 `SekaiNookApp`。
- **L-2（高）全屏背景图按原图分辨率常驻** —— `app/lib/ui/widgets/app_background.dart:30-51` 的 `Image.network` 没有 `cacheWidth/cacheHeight`；它挂在 `app.dart:199-203` 的 `MaterialApp.builder` 上，**所有页面常驻**，且 `AnimatedSwitcher` + `key: ValueKey(url)`（`:27`/`:58-63`）在换背景的淡出期新旧两张同时驻留。上传路径已压到长边 1600（≈7.7MB 可接受），但 `app/lib/ui/pages/settings/settings_page.dart:1383-1388` 的「图片地址」输入框允许手填任意 URL，贴一张 4000×3000 就是 ≈48MB 常驻 + 切换瞬间翻倍 → 低端机 OOM。修法：`cacheWidth: (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round()`。
- **L-3（中高）每进一次设置页/周计划页泄漏一个 Dio 与连接池** —— `settings_page.dart:89` 与 `weekly_plan_page.dart:52` 把 `final ApiClient _client = ApiClient()` 写在 `State` 字段里；而 `app/lib/core/api_client.dart` 只有 `final Dio _dio`，**整类没有 `close()`/`dispose()`**（`main.dart:52` 明明已有共享 client）。修法：Provider 注入共享 client + 给 `ApiClient` 补 `close()`。
- **L-4（中）`router.dart:26-29` 的 `ValueNotifier role` 永不 dispose**，且 `createRouter` 每次调用都在 `FamilyState` 上再加一个 listener（注释说「与 router 同生命周期」，但 router 被换掉时没有拆）。
- **L-5（中）`local_notify_state.dart:103` 的 `bindTapHandler` 只有 setter、没有 unbind** —— 全局 store 永久持有 App 层闭包（捕获 `_router`，进而钉住整个 Provider 图）；store 换代后点通知会跳到已废弃 router。
- **L-6（中）`garden_state.dart:391` / `:667-674` 的 static 闸与丢弃的 Timer 句柄** —— `static bool _syncLoopReady` + `Timer.periodic(...)` 句柄不保存、全仓无 cancel；`_appVisible` 却是实例字段，闭包绑的是第一个调 `_ensureSyncLoop()` 的实例 → 换代后 30 秒兜底补发驱动的是被弃用的实例。好在下限有保证：每次变更都立即 `flushPending()`，所以**不会丢待发操作**，只是断了定时兜底。
- **L-7（中）`fl_ui/context_menu.dart:145` 全局按键处理器只在 KeyUp 时摘** —— `_handleHold()` 里 `FocusManager.instance.addEarlyKeyEventHandler(swallow)`，`swallow` 只在收到 `KeyUpEvent` 时移除；`dispose()`（`:55-60`）与 `_closeUnlessEnabled()`（`:64-71`）都不摘。长按触发菜单后不按键、直接点别处关掉 → **全局 handler 永久残留，吞掉该键后续事件**；反复长按可累积多个。
- L-8（低）`app/lib/core/app_error.dart:10-12`：顶层 `VoidCallback? _reloadHandler` 存的是 `_SekaiNookAppState._handleReload`，全仓唯一「全局变量持有 State」，换代后旧 State 不回收。
- L-9（低）`kid_home_page.dart:2209-2214`、`family_dashboard_page.dart:2414-2419`：`Image.memory` 预览显示高只有 160，却按原图解码（≈7.7MB / 张）；同文件 `:2744-2751` 的缩略图已经做了 `cacheWidth: 144`，这两处是遗漏。
- L-10（低）`family_dashboard_page.dart:2730-2738`：点缩略图放大的 `Image.network` 全尺寸解码且关闭后不 `evict`（全仓 `evict()` 0 处），连看十几张就把 100MB 的 `ImageCache` 顶满，把常驻背景图挤出去重下。
- L-11（低）`kid_home_page.dart:227-231`：`static final UploadApi _uploadApi = UploadApi(ApiClient())` 把 Dio/HttpClient 钉到 isolate 结束、热重载也不换，且与 `main.dart` 的共享 client 重复。
- L-12（低）`app/lib/ui/widgets/motion/skeleton.dart:24-27`：`AnimationController..repeat()` 无条件启动，而 `build` 在「减少动态效果」开启时直接 `return widget.child`（`:37`）→ 控制器仍每帧空转（不是泄漏，是能耗/掉帧源）。
- L-13（低，待验证）`selftest_panel.dart:992-998`：`controller: controller ?? TextEditingController(text: …)` 在 `build` 里兜底新建控制器且从不 dispose（正确路径 `:74` / `:100-101` / `:142-149` 都成对）；是否可达取决于 manifest 参数类型是否都在 `_seed` 里预建。
- L-14（极低）`fl_ui/list_row_separator.dart:370-381`：`addPersistentFrameCallback(_check)` 注册后永不移除（`_rows` 空时立即 return，成本 ≈0）。

**已逐处核对、确认无问题**：Timer 全部有 cancel 且回调有 `mounted` 守卫（`live_clock`、`parent_home_page`、`weekly_plan_page`、`main_shell`、`family_dashboard_page`、`kid_home_page`、`settings_page`、`fl_ui/scroll`、`fl_ui/popup`、`fl_ui/context_menu`、`elastic_press`）；控制器成对释放（`settings_page` 16 个字段、dashboard 三个弹窗、`reminder_editor_sheet`、`role_gate_page`、`parent_home_page`、`kid_home_page`、`garden_page`、`fl_ui/scaffold`、`fl_ui/popup`、`animated_entries`、`keyed_animated_list`、`snap_sheet`）；5 处 `WidgetsBindingObserver` 均成对；全仓 `StreamSubscription` / `Stream.listen` 0 处、`precacheImage` / `imageCache.*` / `evict()` 0 处。

**整体判断**：单页资源纪律好，风险全在跨组件所有权边界。修掉 L-1（store 提到 `runApp` 之前）与 L-4/L-5（给 router / localNotify 补 dispose 路径）即可消掉本轮绝大多数实质问题。





### 13.6 Web 构建产物与部署（Lead 实测）

- **`flutter build web --release` 产物 43MB**：`canvaskit/` 占 37MB（`canvaskit.wasm` 7.0MB、`chromium/` 6.5MB、`skwasm_heavy.wasm` 5.0MB、`webparagraph/` 4.6MB、`skwasm.wasm` 3.5MB、`wimp.wasm` 3.5MB，外加各自的 `.js`/`.symbols`），`main.dart.js` 5.06MB（**gzip 后 1.46MB**）。这是 Flutter Web 引擎的多渲染器目录，不是应用代码可裁的；用户实际只会按引擎选择下载其中一套。结论：**不建议为此做拆包/延迟加载改造**（收益 < 破坏风险），但要知道「网页版首屏约 2MB 下载、首次访问 43MB 部署体」这个量级。
- **`app/web/_headers` 的文件本身没问题**：7 条规则（`/index.html`、`/flutter_bootstrap.js`、`/main.dart.js`、`/version.json`、`/manifest.json`、`/sw.js` 全部 `no-cache`，`/favicon.png` 一小时），且 `app/web/_headers` 与 `app/build/web/_headers` **逐字节相同** → 部署时确实传上去了。所以 §R-4 的「为什么没生效」不是「文件没拷进产物」，而是 Pages 的 `_headers` 匹配/缓存行为，需要按 §11 待实测第 6 条实测确认。
- **确认无 `_routes.json`**（§R-3 成立）：`app/web/` 下没有该文件，`app/build/web/` 也没有。Cloudflare Pages 在缺省时所有请求都会经过 Functions，静态资源也跑一次函数调用。
- `version.json` 由构建生成（当前是 `{"version":"2.7.0","build_number":"35"}`），`flutter_bootstrap.js` 拿它拼 `main.dart.js?v=<version>-<build>`，绕过 4 小时缓存 —— 机制本身是对的，前提是 `version.json` 的 `no-cache` 真的生效。

### 13.7 跨端差异、无障碍、崩溃可见性、国际化（W 组）

**真正会被家里人撞上的四处**：Web 推送是一条自指死路、客户端与服务端两套时区口径、字号滑杆对 394 处硬编码字号无效、线上崩溃只有 `debugPrint` 不落盘也不上报。

**A. Web 与 Android 的行为差异**

- **W-1（高）Web 端「手机提醒」卡片是自指死路** —— `app/lib/ui/pages/settings/push_section.dart:328-335` 让人「在手机上打开 `${AppConstants.apiBase}`，进设置 → 手机提醒」，可 `apiBase` 就是 Flutter 版自己，而 Web 上那一页只有一句说明（`push_section.dart:203-213`），没有任何开关；`app/web/sw.js` 是退役脚本（activate 里 `unregister()` + 清缓存），lib 里也没有 `pushManager.subscribe` / `Notification.requestPermission`。结果：Web 端无法新建订阅，旧 React 版留下的订阅随 SW 注销一起失效，用户被指进死路。建议：要么真实现订阅，要么明写「网页版暂不支持推送，请在 App 里开」+ App 下载入口。
- **W-2（高）打卡时间窗用设备本地钟，服务端用北京钟** —— `app/lib/core/task_rules.dart:61-67` / `app/lib/data/models/task_config.dart:44-47` 用 `DateTime.now().hour*60+minute`，服务端 `functions/_lib/rules.ts:356-366` 用 `beijingClock(now)` 复核 → 非东八区用户（出国/出差/改时区）客户端放行、服务端拒绝（或反之），报错还说「不在打卡时间」。建议客户端统一 `WeekUtil.beijingNow()`（`app/lib/core/week.dart:35-38` 已有）。
- **W-3（高）日限按设备本地日重置，结算按北京日** —— `task_rules.dart:53-56` 与 `app/lib/core/day_completion.dart:49-57` 两套日界 → 跨时区用户在本地午夜 0:00 后日限重置，服务端仍是同一天，可重复打卡。
- **W-4（中）`app/lib/core/week.dart:8-26` 的 `isoWeekLabel` 用本地时区推 ISO 周**，而注释 `:4-5` 要求与后端北京时间一致 → 非东八区用户周日晚/周一凌晨看到隔壁一周的计划。
- **W-5（中）深链在 role 未就绪时被丢弃** —— `app/lib/router.dart:31,33-42` 首次 redirect 时 `family.role` 很可能还是 null，直接返回 `/role` 且**丢掉原目标路径** → Web 上把 `/#/garden` 收藏/分享出去，打开落首页（中间闪一帧角色页）。时序待验证；修法：`state.matchedLocation` 记下目标，role 到位后跳回。
- **W-6（中）裸路径 404** —— `app/web/` 无 `_redirects`，且全仓无 `usePathUrlStrategy`（默认 hash 路由）→ `sn.starrymiku.com/family` 直接 404，只有 `/#/family` 可用；家里人互发链接很容易发出 404 的裸路径。
- **W-7（中）Web 上「检查更新」整块消失且无说明** —— `app/lib/state/update_state.dart:76`、`update_dialog.dart:252,305`、`settings_page.dart:948-950` 在 `supported == false` 时都 `return SizedBox.shrink()`，设置页仍显示「当前版本 vX.Y.Z」却没有任何更新语义。建议换成「网页版每次刷新自动取最新；发现新版本点这里刷新」+ `version.json` 轮询。
- **W-8（中，待验证）`main_shell.dart:150-160,171-178` 的自定义 `_backStack` 与浏览器后退两套账** —— `PopScope(canPop:false)` 拦系统返回，Web 上浏览器后退走 popstate→popRoute，栈空时的 `SystemNavigator.pop()` 在 Web 是 no-op。
- **W-9（中）`app/web/index.html:2` 没有 `<meta name="viewport">`**（线上已 `curl` 核对，与仓库一致）—— 手机浏览器可能按 980px 布局视口排版再整体缩小。建议补 `width=device-width, initial-scale=1.0`（别加 `user-scalable=no`）。
- **W-10（低）`app/web/manifest.json` 的 `"orientation": "portrait-primary"`** 把主屏应用锁死竖屏。
- **W-11（低）`app/lib/fl_ui/drag_back.dart:252` 用 `defaultTargetPlatform` 判桌面**，Web 上它返回宿主 OS 而非「Web」→ 桌面浏览器里手势走 pan-slop 分支。

**B. 无障碍与键盘可达性**

- **W-12（高）字号滑杆基本无效** —— `app/lib/theme/app_theme.dart:514-522` 只做 `textTheme.apply(fontSizeFactor:)`，而 `lib/ui` 里 `fontSize:` 字面量 **394 处**、`textTheme.`/`AppTextStyle.` 只有 13 处 → 用户拖到 140% 看到的还是 12/14/16 的硬编码字。建议把 `AppFontSize.*` 改成走主题派生；短期至少说明「仅影响部分文字」。
- **W-13（中）`app/lib/ui/widgets/app_toast.dart:87-91` 的「撤销」按钮**是 `GestureDetector` 包 19dp 文本，无 Semantics、不可 Tab 聚焦 → 键鼠/读屏用户点不到，误删救不回来。
- **W-14（中）`app/lib/core/app_error.dart:100-114` 崩溃页的「重新加载」**同样是 `GestureDetector`（约 38dp、无 Semantics/不可聚焦）—— 恰恰在最需要自救的页面上。
- **W-15（中）`settings_page.dart:1442-1512` 主题/色板 tile** 由 `PressScale`/`GestureDetector` 承接点击，无 `Semantics(selected:)`、无 Focus 节点 → Tab 走不到、读屏不报「已选中」。
- **W-16（中）无语言声明** —— `index.html` 缺 `<html lang="zh-CN">`、`manifest.json` 缺 `"lang"`，`app/lib/app.dart:181` 又固定 `Locale('zh','CN')`（只影响 Flutter 内部文案）→ 英文系统下读屏会乱读。
- **W-17（中）页面转场不尊重「减少动态效果」** —— `app/lib/theme/motion.dart:164-197` 与 `app/lib/ui/widgets/motion/switcher.dart` 没查 `MediaQuery.disableAnimations`（其余动效组件 `celebrate`/`enter_box`/`animated_count`/`animated_progress`/`skeleton`/`press_scale` 都查了）。
- W-18（中低）`app/lib/ui/widgets/task_row.dart:110-120`：整行可点但无 `Semantics(label/hint)` 说明「点一下打卡」。
- W-19（低）`app/lib/ui/shell/app_top_bar.dart:314`：图标按钮 32dp 低于 48dp 建议（语义齐全，外扩透明热区即可）。
- W-20（低）`settings_page.dart:1266-1271,1297`：两个 Slider 缺 `semanticFormatterCallback`，读屏把字号念成「1.0」。
- W-21（低）`app/lib/theme/app_theme.dart:61-64`：textTertiary 在页面底只到 4.0:1，而 `AppFontSize.xs = 12` 大量直接用它 → 12px 小字不达 AA 的 4.5:1。

**C. 错误上报与崩溃可见性**

- **W-22（高）线上异步异常被彻底吞掉** —— `app/lib/main.dart:40,44`：`PlatformDispatcher.instance.onError` 只 `debugPrint` 然后 `return true`，`FlutterError.onError` 只 `presentError + debugPrint`，**没有 `runZonedGuarded`**。
- **W-23（高）没有任何崩溃上报与本地落盘** —— 全仓无 Sentry/Crashlytics，无 lastError/crashLog，`debugPrint(` 只有 3 处；唯一诊断出口是自检面板手点复制 JSON/Markdown（`selftest_panel.dart:360-374`）→ 家人报「打不开了」时开发者手上零信息。建议极简本地崩溃记录（prefs/文件环形 20 条：时间 + 异常 + 栈 + 版本 + 平台）+ 设置页「导出诊断」。
- **W-24（中）`app/lib/core/app_error.dart:24-27` 把异常原文铺在用户可见卡片**（`:117-125`，xs + textTertiary）—— 既泄露实现细节又吓人，而开发者拿不到这份文本。建议只显示「出了点问题」，原文折进「复制错误详情」。
- **W-25（中）兜底页只有「重新加载」一个动作**（`app_error.dart:100-114`，重载 = 整树重建重走初始化）→ 崩在初始化路径时进入「崩→重载→崩」循环。建议加「清缓存并重启」+ 连续崩溃计数降级。

**D. 国际化与文案**

- **W-26（中）`app.dart:181` 写死 `Locale('zh','CN')` + 无 l10n 基建**（无 arb / l10n 目录），但 `supportedLocales` 里有 `en`、没有任何英文文案 → `en` 是假承诺。
- **W-27（中）`app/lib/core/day_completion.dart:87-96` 的 `ReminderText.allDone` 写死「5 个任务」「22:00」「扣 10 分」**，而同文件 `:100-109` 的 `reminderTextFor` 用 `FamilyRules` 动态拼 → 改了 `app/lib/config/family_rules.dart:86-92` 后一半提醒文案对不上（「规则改了但通知还在说旧规则」）。
- **W-28（中）`push_section.dart:376` 的 `_localStatusText` 末支写死「已开启 · 每天 21:30」**（卡片描述 `:175-177` 同病）→ 用户把提醒改成别的时刻后状态行不变，会以为没生效。
- W-29（低）`settings_page.dart:952-960`：正式设置页挂着「FlClash 试样间 / UI 组件预览（开发者用）」，建议 `kDebugMode` 或连点版本号隐藏。
- W-30（低）金额无千分位（`parent_home_page.dart:130` 的 `toStringAsFixed(2)`）、日期三套口径混写（`time_text.dart:26-36` vs `push_section.dart:380-386`），全仓 `DateFormat`/`NumberFormat` 0 命中。建议统一走 `time_text.dart` 一个入口 + 金额加千分位。

**整体**：工程质量不差（对比度有校准测试、条件导入干净、动效大多尊重减动画），缺的是「跨端一致」与「出事可追」两块 —— 前者是设计问题，后者是基建缺失。

- 本文档本身是新增的未跟踪文件，等你看完再决定是否提交。
- 上一轮修完的性能项（P0–P3）在 `docs/perf-audit-2026-10.md` 的 §10 有完整记录。

---

## 14. 实施记录：本轮「全修」做了什么（2026-10-25）

> 用户看完本文档后说「全修」。下面按四批记录实际落地情况，**未做的逐条说明原因**，
> 不留「看起来修了其实没修」的模糊地带。

### 14.1 批 1：安全与不可逆（后端 + 发版脚本）

| 项 | 落地内容 |
|---|---|
| M-C-1 / B-8 默认管理员口令 = 账号 ID | `functions/_lib/settings.ts` 删掉 `DEFAULT_ADMIN_PASSWORD`，口令改存 `sha256:salt+password`；旧明文键首次读取自动迁移；`verifyAdminPassword` 三态（未配置 503 / 错 401 / 锁 429）。env `ADMIN_PASSWORD` 只在**首次初始化**时使用 |
| B-5 失败计数读改写非原子 | `registerAdminFailure` 改单条 `ON CONFLICT DO UPDATE SET value = CAST(value AS INTEGER)+1` |
| M-B-4 `image_url` 可删任意 R2 对象 | 写入前用 `sanitizeBackground(image_url, request origin)`：只认 `/api/images/` 且 origin 一致；`[id].ts` 的 `extractImageKey` 强制 `tasks/` 前缀 + 无 `..`；删除前查引用（其他流水 + 全局背景图）；删除顺序改为**先删 D1 再删 R2** |
| B-3 orphans 破坏性接口无闸 | GET 不再返回 key 列表（只回数量）；POST 先 `gateAdminPassword(body.password)` 再校验 `confirm === true` |
| B-2 push/test 可群发 | 冷却改条件 upsert 原子占位（先占后再发），加 `HOURLY_LIMIT=10` 小时配额 |
| B-4 upload 无保护无配额 | 保留「无鉴权但有限制」：类型白名单 + 魔数 + 5MB + `DAILY_UPLOAD_LIMIT=200`（按天原子自增） |
| B-1 settle 可结算任意过去日期 | 收紧为「今天或昨天」，其余 400 |
| B-7 plans 同名任务静默丢弃 | POST 重写为先查已有 `(subject, task_name)` 去重、只插新条目、全重复返回 200；新增 `migrations/0007_plans_unique_subject.sql`（唯一索引含 subject，可重入） |
| M-A-3 管理员加分算进「今日完成数」 | `COMPLETION_EXCLUDED_IDS` 加 `admin_adjust` / `garden:admin_adjust` |
| R-1 忘 bump versionCode 静默发布 | `publish_apk.ps1` 上传前 GET 线上 `latest.json`，`versionCode <= 线上` 直接 throw |
| R-2 不比对证书指纹 | 固定 release 证书 SHA-256 写入脚本，`apksigner` 输出不一致即中止 |
| R-6 / R-19 / R-20 前置检查 | key.properties / jks 检查挪到 build 前且不受 `-SkipBuild` 影响；`ANDROID_HOME` 未设明确报错；`-Changelog` 缺省兜底文案 |
| M-B-1 / M-B-2 R2 越权与 MIME 注入 | `images/[[key]].ts` key 必须 `tasks/` 前缀、白名单 Content-Type、`X-Content-Type-Options: nosniff` |

### 14.2 批 2：启动链与状态层

- **S-1 / L-1（最灵异的一条）**：8 个 store 从 `DynamicColorBuilder.builder` 提到 `main()`、`runApp` 之前 —— 修「Android 12+ 换壁纸后造出第二套 store，router/启动链还绑着第一套」。
- **S-2**：`garden_state` 的 `static _syncLoopReady` 改实例字段 + `Timer? _syncTimer` + `dispose()`。
- **S-3**：`pending` 队列并入 `_saveState()` 同一 payload，删掉 `_savePending()`（读旧键自动迁移），两键非原子写消失。
- **S-4**：`_bootstrap()` 里 `customTasks.ensurePresets()` 与 `garden.init()` 各包 try/catch。
- **S-5**：`GardenState.refreshLedger` 加 `_refreshSeq` 守卫。**S-6**：`LocalNotifyState.rescheduleAll` 改串行队列（并发只跑最新一次）。
- **S-7 / D-1**：`LedgerApi._parseRecords` 逐条 try/catch + 跳过坏 id；**D-2**：`createdAt` 解析失败用 epoch 而不是 `DateTime.now()`（不再把坏时间算进今天）。
- **M 组 12 条**：update 下载重入守卫、approveMany 不再吞错（带失败 id）、pin verify 并发闸、api_client 只对超时/连接类重试 + 非网络异常透传、records getter 改 unmodifiable、notification refresh seq、`_nextSlot` 找空闲槽、`_nextStreak` 用传入日期、首帧读背景缓存、`todayProgress` 改一次聚合。
- **L 组 12 条**：主题 setter 等值早退、图片按 EXIF 摆正（`bakeOrientation`）、模型宽松解析（garden/task_config/admin/upload）、`ErrorWidget` 换成通用文案、家庭写操作 `_guardWrite` 在途去重、`custom_tasks` 日界改东八区。
- **F13 收尾**：`GoRouter` 的 `refreshListenable` 从整个 `FamilyState` 换成 `ValueNotifier<FamilyRole?>`（只在身份变化时重算路由），由 `app.dart` 持有并 dispose。

### 14.3 批 3：页面层与跨端

- **P-1**：自检面板造图 + PNG 编码丢进 `compute`，尺寸 1800×1200 → 900×600（Web 上 compute 退化为同步，所以尺寸也降）。
- **P-2**：周计划加减改按计划 id 串行队列，连点不再后到的旧值覆盖先到的新值。
- **P-3 / P-4 / P-5**：提醒测试/保存 `try/finally` 复位 `_busy`；「最近调整」失败保留旧列表并显示错误行；`settleLedgerOncePerDay` 调用点加 catch。
- **Dio 复用**：`ApiClient.shared` 全局实例，`main.dart` 与 4 处页面 `ApiClient()` 全部改共享（原来每页新建 Dio/连接池）。
- **P-8**：字号滑杆改 `previewTextScale`（只改内存）+ `onChangeEnd` 落盘，拖动期间零写盘。
- **W-1**：推送卡片文案改成实话（React 下线后浏览器推送暂不可用，本机提醒才是现役通道）。
- **P-11**：驳回/扣分等面向家长的文案把写死的「女儿」改成中性「孩子」。
- **C-1**：`AndroidManifest.xml` 加 `android:allowBackup="false"` + `fullBackupContent="false"`（PIN 摘要、称呼、花园状态不再进 Android Auto Backup）。

### 14.4 批 4：工程化与文档

- **死代码**：从 `main.dart` + `test/` 做 import BFS，删掉 27 个不可达 `fl_ui/*.dart`（约 6 千行），顺带删掉只为死代码存在的 `super_sliver_list` 依赖。
- **测试标签**：`app/dart_test.yaml` 定义 `live` 标签并默认 skip；`api_smoke_test` / `e2e_flow_test` / `garden_flow_test` 加 `@Tags(['live'])` —— 默认 `flutter test` 不再打生产后端（之前「偶发失败」的根因）。
- **CI**：新增 `.github/workflows/ci.yml`（`npm ci` → `npm run build` → `flutter analyze --no-pub` → `flutter test --no-pub`）。
- **R-3**：新增 `app/web/_routes.json`（`include: ["/api/*"]`），随 Flutter 产物部署，静态资源不再走一遍 Functions。
- **R-9**：changelog 的 ETag 改成「版本 + 内容哈希」，同版本改文案不再永远 304。
- **R-7 / R-8**：`changelog-sync.mjs` 校验日期真实存在（2026-02-30 过不了）+ 与 `app/pubspec.yaml` 的 version 三方比对。
- **R-5 / R-24**：`package.json` 加 `engines: node >=22.6`；`npm run deploy`（会盖掉 Flutter 产物）改成直接报错的护栏，回滚专用命令改名 `deploy:legacy-react`。
- **R-10~R-13 / R-17 / R-14 / R-21**：`project_rules.md`（技术栈、目录、`_routes.json` 约束）、`README.md`（`npm run web:deploy`）对齐；vite 删 `echarts-for-react`；`dynamic_color` 改 caret；`notification-options.html` 挪进 `docs/`。

### 14.5 明确没做的（及原因）

| 项 | 为什么不做 |
|---|---|
| **W-12 字号滑杆对 395 处 `fontSize:` 字面量无效** | 真修要统一改成 `AppTextStyle`/`textTheme` 派生，等于重排全库字号体系，风险和收益不成比例。改为在文档记成「已知限制」 |
| **W-22 / W-23 崩溃上报** | 需要第三方服务或本地环形日志 + 导出 UI；本轮只做了 `ErrorWidget` 文案中性化。建议下一步单独做「本地崩溃环形日志 + 设置页导出」 |
| **W-26 国际化** | 无 arb/l10n 基建，`supportedLocales` 里的 `en` 应该先删掉而不是补翻译 |
| **R-26 / R-27 React 归档删除** | 保留回滚价值。建议：打 `react-legacy-2026-10` tag 后再从主干删 `src/` 与 8 个运行时依赖 |
| **R-4 `_headers` 缓存未生效** | 已补 `_routes.json`，需**部署后实测** `curl -I /main.dart.js` 再决定是否改用构建期 hash |
| **P-6 历史记录全量建 widget** | 要整页改 `CustomScrollView + SliverList`，会破坏 `AppCard` 视觉与转场；已加载量是 20×N，触发条件未到 |
| **M-4 时钟回拨绕过锁** | 威胁模型是家里孩子，能改系统时间的场景可以直接清数据，收益低于成本 |
| **R-16 freezed dev_dependencies** | `fl_ui/models.dart` 当前可达且用 `@freezed`，但补 `build_runner` 要拉一批依赖；生成文件已提交，暂不动 |
| **批 3 剩余轻微项**（P-10 四份图标工具、P-12 删除提醒确认、P-13 硬编码宽度、P-14 两套弹窗、W-24/25/27/28/29/30） | 单点收益小，且 P-10/P-14 属于重构，留作后续维护时顺手做 |

### 14.6 本轮验证

- `flutter analyze --no-pub`：**96 issues**（删死代码后从 101 降下来），全部 info，唯一 warning 是既有 `lib/ui/icons/app_icons.dart:3:8 unused_import`，**无 error**。
- `flutter test --no-pub`：**192 通过、3 跳过**（跳过的就是打生产后端的 3 个 live 用例）。
- `npx tsc --noEmit`：EXIT 0。
- 后端行为变更需部署后才生效；本轮发版为 **2.8.0+36**。





