# 性能审查核对与优化计划（2026-10-24）

> 对象：上一轮纯静态审查给出的 32 条「性能优化点」（Flutter 18 / 后端 8 / React 6）。
> 本文只做两件事：**核对每条在现仓库代码里是否成立**，以及**给出可执行的分阶段计划**。
> 本轮没有改任何代码，也没有发版。

---

## 0. 一句话结论

方向可行，大部分条目成立，但**优先级不能照抄原报告**：

- 原报告把「代码里有浪费」和「用户能感知」混在一起了。按收益排序，真正省流量/省电的是 **合并轮询与请求（P0）**；真正解决卡顿的是 **时钟隔离 + 按需构建（P1）**；**图片处理（P1）** 收益取决于用户是否真传大图；后端那批（P2）要等数据量长起来才值得动。
- 原报告有 **3 处判断有误或夸大**（见 §3），有 **4 类只能实测**（见 §7），不要当成结论。
- 报告里的量化例子（家长停在首页 21 次请求/分钟）**算得对**，已复核。

---

## 1. 核对方法与边界

- 全部为**静态核对**：读源码 + 读已有构建产物（`dist/assets/antd-vendor-*.js` 实测字节数）。没有跑真机、没有做性能采样。
- 报告里的行号来自上一轮 sandbox 副本（`/workspace/scratch/.../SekaiNook`），本仓库文件与之一致，行号可直接对。
- 结论分四档：**成立** / **部分成立** / **不成立** / **需实测**。
- 核对基准：`git branch --show-current` = `main`，工作区仅有一个未跟踪图片 `docs/web-2.5.0-home.png`。

---

## 2. 逐条核对

### 2.1 Flutter 端（18 条）

| # | 原报告 | 结论 | 关键证据（文件:行号） |
|---|---|---|---|
| F1 | 多处重复轮询 | **成立** | 全项目共 **9 处**定时器：`app/lib/ui/shell/main_shell.dart:95`（10s `notifications.refresh` + 家长 `refreshPending`，全局不分 tab）、`app/lib/ui/pages/home/parent_home_page.dart:196`（20s 整账）、`kid_home_page.dart:244`（20s 整账）、`family_dashboard_page.dart:226`（家长 10s 待审批 / 孩子 15s 整账）、`weekly_plan_page.dart:72`（60s）、`garden_state.dart:663`（30s flushPending）、`family_dashboard_page.dart:162` 与 `parent_home_page.dart:191`（1s 时钟）、`settings_page.dart:156` + `role_gate_page.dart:244`（1s 锁倒计时）。`dashboard._pollOnce` 与 `main_shell._tick` **都没有 `_refreshing` 阀**（只有页面级 `_refresh` 有），所以上一轮没回来下一轮照发 |
| F2 | 请求序号只丢结果、不减少请求 | **成立（弱网会叠加）** | `family_state.dart:134,148,172-174` 只有 seq 丢弃；`api_client.dart:136` 的 `_send` 无在途合并。`api_client.dart:16-19` 超时 12s、GET 重试 2 次（400ms/1200ms 延迟，共 3 次尝试）——**单轮最坏耗时超过 10s 轮询间隔**，多源轮询叠加时在途请求数**没有上界** |
| F3 | 启动重复初始化/重复拉 settings | **成立** | `garden.init()` 有 **3 个**调用点：`app/lib/app.dart:114`、`kid_home_page.dart:239`、`garden_page.dart:117`，且 `init()` **无幂等 guard**；`theme_state.dart:191` 与 `settings_state.dart:93` 各自 `fetchSettings()`，两者是**独立实例**（`main.dart:66-67`），启动时两次 GET `/api/settings` |
| F4 | 每次刷新都通知，即使数据没变 | **成立** | `family_state.dart:151-160`：每次都 `where(...).toList()` 造新 List 再 `notifyListeners()` |
| F5 | 靠列表对象相同判断账本变化 → 反复全量重排提醒 | **成立**（机制是间接的） | `app/lib/app.dart:95` 用 `identical(records, _syncedRecords)`；但 F4 保证每次都是新 List ⇒ 永远不 identical ⇒ `local_notify_state.dart:349-397` 每轮都 `cancelAll()` + 逐条 `schedule()` + `_persist()` |
| F6 | 每秒时钟用页面级 setState | **成立（4 处）** | `family_dashboard_page.dart:162`、`parent_home_page.dart:191`、`settings_page.dart:156`、`role_gate_page.dart:244`：都是 `Timer.periodic(1s, () => setState(...))`。锁倒计时那两处只影响局部文案，但同样整页 rebuild |
| F7 | 图片压缩在主线程同步执行 | **成立** | `app/lib/core/image_compress.dart:14-25`，26 行纯 Dart 同步实现（`img.decodeImage` → `copyResize` → `encodeJpg`）；`:3` 无条件 `import package:image`，无 isolate/条件导入 |
| F8 | 先整图读取解码再缩；孩子端双重编码 | **成立（三个入口都不限尺寸）** | `kid_home_page.dart:2012` `pickImage(source: ..., imageQuality: 90)`（无 maxWidth/maxHeight）→ `:2015 compressImage(raw)`（再 JPEG 80）；`family_dashboard_page.dart:2261` **完全无参数**选图 → `:2265 readAsBytes()` 整图进内存 → `compressImage`；`settings_page.dart:350` 背景图同样无限制 |
| F9 | 48×48 缩略图用完整图 | **成立** | `family_dashboard_page.dart:2680-2687` `Image.network(width: 48, height: 48)`，无 `cacheWidth/cacheHeight`；全 `app/lib` 下 `cacheWidth` 出现 **0 次** |
| F10 | 历史/待审批外层 ListView、内部 Column 全量构建 | **成立（有 20 条/页上限，不是无限）** | `family_dashboard_page.dart:643`（外层 ListView）、`:1891` `filtered.take(_visibleCount)` 在 Column 里全量构建；「加载更多」在 `:1943` 只是 `_visibleCount += 20`（`_recordsPageSize = 20`）。注意：上限只是「一次多 20 条」，**已加载的仍一次性全建**，且外层 ListView 不懒 |
| F11 | `_buildTabs()` 先构建三个分区 | **成立** | `family_dashboard_page.dart:1068-1080`：`areas` 列表先构造三个 `_build*Area`，`:1136` 才 `areas[index]` 取用，未选中的也执行 |
| F12 | 统计反复扫描流水 | **成立** | `family_dashboard_page.dart:926-941` 14 天 × 全部流水双层循环；`app/lib/core/task_rules.dart:27-32` `countTodaySubmissions` 每个任务都全量扫一遍 records |
| F13 | Provider 订阅范围大；路由监听整个 FamilyState | **成立（两条都成立）** | 路由监听整个对象：`app/lib/router.dart:24` `refreshListenable: family` —— 每次 `notifyListeners` 都会重跑 `redirect` 并重建路由表（`router.dart:78` 的 `context.select` 是 `HomeSwitcher` 内部订 role，与前者并存）；页面级 watch：`parent_home_page.dart:365-368` watch 4 个、`kid_home_page.dart:519-523` watch 5 个，且 `kid_home_page.dart:519-559` **build 顶部就有 `DateTime.now()` + 约 6 次全量扫账本** |
| F14 | 花园 `refreshLedger()` 串行且与注释不符 | **成立（且是注释/实现不一致）** | `garden_state.dart:634` 注释写「两个请求并行」，`:642-643` 实际 `await _safeSummary(); await _safeRecords();` 串行 |
| F15 | 花园每次提交完整序列化存档 | **成立** | `garden_state.dart:497-556` `_commit()` 每次 `_saveState()`；`_saveState()` 里 `jsonEncode` 整份 payload（含 `cachedRecords`，最多约 200 条）；`:560-580` 补发队列每完成一笔就 `_settleOp` → `_commit` |
| F16 | 设置交互写入过密 | **成立** | `settings_page.dart:1269` Slider `onChanged: theme.setNavBarOpacity` → `theme_state.dart:76-79` 每次 `await _prefs.setDouble`；`settings_page.dart:178-182` 每次字符 `setState` + `_writeNameDraft()` |
| F17 | 骨架各自持控制器；禁用动画仍启动 | **成立** | `app/lib/ui/widgets/motion/skeleton.dart:24-27` 构造时就 `..repeat()`，`build` 里才判断 `disableAnimations`（`:35`） |
| F18 | `postBytes()` 重复复制字节 | **成立** | `api_client.dart:122` `Uint8List.fromList(bytes)` 无条件复制 |

### 2.2 后端 / 提醒 Worker（8 条）

| # | 原报告 | 结论 | 关键证据 |
|---|---|---|---|
| B1 | 余额接口每次全表 SUM | **成立** | `functions/api/ledger/summary.ts:24-28` `FROM family_ledger WHERE status IS NULL OR status='approved'`，无窗口/无时间范围 |
| B2 | 轮询返回数据偏重、缺数量接口 | **部分成立** | 待审批确实整份返回（`functions/api/ledger/index.ts:70` `SELECT *`）；**通知「缺数量」不成立** —— `functions/api/notifications/index.ts:44-55` 同 batch 已带 `COUNT(*) AS unread` |
| B3 | 缺历史游标分页 | **成立** | `functions/api/ledger/index.ts:33` `DEFAULT_LIMIT = 200`、`:70` `ORDER BY created_at DESC LIMIT`，全文件只有 `since` 无 offset/cursor；Flutter 端「加载更多」纯本地展开（见 F10） |
| B4 | 删图片前扫描全部图片引用 | **不成立** | `functions/api/ledger/[id].ts:115-126` 只 `SELECT image_url ... WHERE id = ?` 取被删记录自己那一条 |
| B5 | 闲置清理全量入内存 + 串行删除 | **成立** | `functions/api/maintenance/orphans.ts:90-120` 全桶对象 + 全表引用各自装进数组/Set；`:143-144` list 与 DB 查询先后 await；`:198-206` 逐张串行 delete |
| B6 | Web Push 逐台串行、单台 15s | **成立** | `workers/reminder/src/webpush.ts:69` `for (const row of rows)`、`:88` `AbortSignal.timeout(15000)`；其它通道 `channels.ts:162-166` 无超时 |
| B7 | 版本日志每次整份读取 | **成立** | `functions/_lib/changelog.ts:67-74` 每次查库 + `JSON.parse`；`functions/api/changelog/index.ts:24-31` 无 Cache-Control/ETag |
| B8 | 上传超 5MB 判断在读完请求体之后 | **成立** | `functions/api/upload.ts:31` 先 `arrayBuffer()`，`:35` 才判长度；无 Content-Length 前置检查 |

### 2.3 React 端（6 条）

React 版主域名已停用（`src/`+`public/` 仅作回滚退路），以下仅记录，不进计划主线。

| # | 原报告 | 结论 | 关键证据 |
|---|---|---|---|
| R1 | 订阅整个 store、秒级页面更新、轮询重复 | **成立** | `src/layouts/MainLayout.tsx:106-108`、`src/views/family/FamilyDashboard.tsx:327`（1s setInterval）、`MainLayout.tsx:147`(15s) 与 `FamilyDashboard.tsx:345`(10s) 双刷同一接口 |
| R2 | 导航拖动频繁 setState | **成立** | `MainLayout.tsx:334-337` 每个 pointermove 三次 setState（`setTrailX` 每次新值） |
| R3 | 滚动记忆每帧读/解析/序列化 | **成立** | `MainLayout.tsx:395-398` + `src/utils/tabMemory.ts:77-83` |
| R4 | 图片固定 1600 宽、竖图缩两次、取消不释放 bitmap | **成立** | `src/utils/image.ts:65-69,70,77-80` |
| R5 | antd 厂商块 912 kB / gzip 290 kB | **成立（有实测）** | `dist/assets/antd-vendor-DEZJF0xj.js` = 912,830 字节，gzip 后 289,078 字节 |
| R6 | HTTP 超时在响应头后即清除 | **成立** | `src/api/http.ts:85-87` `finally { clearTimeout(timer) }`，`:106` 的 `res.json()` 不受超时约束 |

---

## 3. 原报告里要纠正的两处（外加我自己的一处误判）

1. **F13 成立 —— 我上一版误判了，这里更正。** 路由**确实**监听整个 FamilyState：`app/lib/router.dart:24` `refreshListenable: family`，FamilyState 每次 `notifyListeners()` 都会让 GoRouter 重跑 `redirect` 并重建路由表。报告说对了。我上一版只看 `router.dart:78` 的 `context.select<FamilyState, FamilyRole?>`（那是 `HomeSwitcher` 内部只订 role，与 `refreshListenable` 并存，不矛盾），就误判为「不成立」。
   - 这条与 F4/F5 是**同一个根因**：因为每轮刷新都 `notifyListeners`，`refreshListenable` 每轮都会被拉起来重算。所以 P1 的「无变化不通知」会一并省掉路由重算，收益比原估算更大。
   - 页面级 watch 完整对象同样成立（`parent_home_page.dart:365-368` watch 4 个、`kid_home_page.dart:519-523` watch 5 个）。
2. **B4「删除图片前扫描全部引用」不成立。** `functions/api/ledger/[id].ts:115` 只查被删记录自己那一行。把这条和 B5（`orphans` 全量扫描）混了。
3. **B2「通知缺数量接口」不成立。** `notifications/index.ts` 在同一次 batch 里已经算了 `unreadCount`，不用额外请求。只有**待审批**是整份列表返回。

另：「报告漏掉的问题」里那条 `orphans` 前端先 GET 再 POST 会扫两遍 —— 前端现在是 POST 一次（`orphans.ts:191` 内部扫一次），不构成双扫，**不成立**。

---

## 4. 收益怎么排序（用可量化的三个维度）

### 4.1 请求数：现状复核

原报告的例子算对了。再补两个场景（静态推算，`loadLedger` = 3 个请求：records + pending + summary）：

| 场景 | 现状估算 | 构成 |
|---|---|---|
| 家长停在 `/home` | **21 次/分钟** | 主壳 10s ×2（通知+待审批）=12；首页 20s ×3 =9 |
| 孩子停在 `/family` | **27 次/分钟** | 家庭页 15s ×3 =12；孩子首页 20s ×3 =9；主壳 10s ×1 =6 |
| 家长停在 `/family` | **30 次/分钟** | 家庭页 10s ×1（待审批）+ 主壳 10s ×1 =12；首页已卸载；主壳通知 6 → 实际 18；若首页常驻则更高 |

关键浪费不是「轮询存在」，而是**同一接口被两路同时轮询**：`refreshPending` 被 `main_shell:103` 和 `family_dashboard:236` 各以 10s 打一遍；`loadLedger` 被 `parent_home:196` 和 `kid_home:244`（20s）与家庭页（孩子态 15s）重复打。

### 4.2 重建次数：每秒一次的全页重算

`family_dashboard_page.dart:162` 与 `parent_home_page.dart:191` 的秒级 `setState` 会让整个页面 `build`，连带：

- 趋势图 14 天 × 全部流水（≤200 条）= **最多 2800 次日期比较/秒**
- 每个任务 × 全部流水（`task_rules.dart:27-32`）
- 历史区 `Column` 里全部已加载条目（`take(_visibleCount)`）
- `_buildTabs()` 三个分区全都构造一遍

孩子首页更重：`kid_home_page.dart:519-559` 的 `build` 顶部就有 `DateTime.now()` 和约 6 次全量扫账本（`_recentSummary` / `_todayRecords` / `_latestRejected` / `_sleepTask` …），只要**任何一个** watch 的状态对象变化就重跑一遍。

这不是「卡」的主因（单次计算廉价），但它让任何一处数据变化都无法局部化，属于**结构性浪费**；叠加 F4 的「每轮无条件 notify」和 F13 的 `refreshListenable`，同一次刷新会依次触发：页面 rebuild → 路由重算 → 提醒全量重排。

### 4.3 主线程阻塞：图片

- Android：`img.decodeImage` 纯 Dart 解码 5MB JPEG，主线程可达数百毫秒（需实测）。
- **Web 上不能靠 isolate 解决**：dart2js 不支持 isolate，Flutter 的 `compute()` 在 Web 是**同步执行**的。所以报告说「Web 采用适合浏览器的方式」是对的，但具体只能是：**限制输入尺寸 + 减少一次编码**，不能指望后台线程。

---

## 5. 分阶段计划

原则：**每阶段独立可发版、可回滚**；先做「不改 UI、收益确定」的，再做「改结构、需要真机验收」的。每阶段结束都走一次完整发版（`npm run web:deploy` + APK），不留半成品。

### P0 — 请求合并（预计 1 天，收益最确定）

**目标**：家长首页 21 → ≤10 请求/分钟，孩子家庭页 27 → ≤12。

1. **`ApiClient` 加 GET 在途合并（single-flight）**
   - `app/lib/core/api_client.dart`：`Map<String, Future<dynamic>> _inflight`，key = `method|path|query`；完成后 `remove`。只对 GET 生效，写请求不合并。
   - 风险：调用方拿到同一个 Future 实例，不能各自 `catch` 后当作独立结果用；需确认 `_summaryOrNull()` 这类「失败即 null」的包装不受影响。
2. **消掉重复轮询（关键）**
   - `main_shell.dart:103` 的 `family.refreshPending()` 改成「仅当当前路由不自己刷待审批时」才发（`/home` `/family` 由页面自己刷；`/garden` `/settings` `/family/plan` 由主壳兜底）。
   - `family_dashboard_page.dart` 家长态的 10s 轮询与主壳重复，保留页面侧、主壳让路。
3. **轮询专用轻量接口（后端）**
   - 新增 `GET /api/ledger/snapshot?since=<cursor>`：一次返回 `{ family, sun, pendingCount, pendingRecords, records }`，`records` 用现有的 `since` 增量（`functions/api/ledger/index.ts:62-66` 已支持）。
   - 前端 `loadLedger()` 改为先打 snapshot；`/api/ledger/summary` 与 `/api/ledger` 保留给首屏/深链。
   - ⚠️ 边界：现有 `since` 只按 `created_at > ?`，同秒多条记录会漏/重；游标要用 `(created_at, id)` 复合，或让客户端按 id 去重后合并。
   - 效果：`loadLedger` 的 3 个请求 → 1 个。
4. **顺手修**：`garden_state.dart:642-643` 改成 `Future.wait`（注释早就写了并行）。
5. **顺手修**：`api_client.dart:122` 仅在 `bytes is! Uint8List` 时复制。

**验证**：`flutter analyze --no-pub` + `flutter test --no-pub`；用 `wrangler tail` 或浏览器 Network 面板数 60 秒请求数，对比上表。
**风险**：合并后写操作必须能强制刷新 —— `approve/reject/removeRecord` 原本紧跟 `loadLedger()`，保留不变；snapshot 的 `since` 游标要处理好「同一秒多写」的边界。

### P1 — 停止无效重建（预计 1–2 天，需要真机看）

**目标**：秒级 tick 只重建时钟本身；数据没变就不通知。

1. **时钟隔离**
   - 4 处 1s `setState`：`family_dashboard_page.dart:162`、`parent_home_page.dart:191`、`settings_page.dart:156`、`role_gate_page.dart:244`。把 `_now` 下沉到独立 `ClockText` 组件（内部自持 `Timer` + `ValueListenableBuilder`），页面不再每秒 `setState`。
   - 锁倒计时那两处（settings / role_gate）最好先改：它们只影响局部文案，改动小、见效立竿见影。
   - 注意：页面里用 `_now` 的地方不少（趋势图、任务状态、倒计时），要逐个改成「组件内取时间」。趋势图/任务区对 `_now` 的依赖是**日粒度**，可以改成只在跨天时重建（比秒级更容易）。
2. **状态层无变化不通知（P1 里收益最大的一项）**
   - `family_state.dart:136-137,160-161` 每轮无条件两次 `notifyListeners`；`:151-153` 每次新建 `_records` List。改成比较记录指纹（`id + status + amount` 或长度+首尾 id）与 `_pendingCount`，相同则跳过赋值与通知。
   - 同时把 `app.dart:96` 的 `identical` 判断改成「内容指纹相同则跳过重排」。
   - 效果：**一条改动同时消掉三处浪费** —— F5 的「每轮取消全部提醒 → 重排 → 写盘」、F13 的 `refreshListenable` 路由重算、以及页面因 notify 触发的重建。
3. **按需构建分区**
   - `family_dashboard_page.dart:1068-1080`：`areas` 只 `build` 当前 index 对应的那个（其余给 `SizedBox.shrink()` 或懒加载）。
4. **启动只取一次 settings / 初始化只跑一次**
   - `ThemeState.loadBackground()` 改为从 `SettingsState` 拿（或由 `app.dart` 先 `settings.load()` 再把 background 喂给 theme），消掉重复的 `fetchSettings()`（`theme_state.dart:191` + `settings_state.dart:93`）。
   - 给 `garden.init()` 加幂等 guard：现在 `app.dart:114`、`kid_home_page.dart:239`、`garden_page.dart:117` 三处调用，重复执行。
5. **设置写入降频**：`setNavBarOpacity` / 名字草稿改成「内存即时生效 + 停止滑动/输入 300ms 后落盘」。

**验证**：真机 Android Profile 看 `build` 次数（`flutter run --profile` + DevTools Performance）；确认提醒不再每轮重排（可在 `rescheduleAll` 加临时日志）。
**风险**：`_now` 下沉改动面较大（页面有十余处引用），建议先只做 `parent_home_page`（结构简单）验证效果，再动 `family_dashboard_page`。

### P2 — 图片与列表（预计 2 天，收益取决于用户行为）

1. **选图阶段就限制尺寸**（收益最大，改一行）
   - `kid_home_page.dart:2012`：`pickImage(..., maxWidth: 1600, maxHeight: 1600, imageQuality: 85)`，并**去掉** `imageQuality: 90` 与后续 JPEG80 的双重编码（保留 `compressImage` 做兜底，但它不再需要 resize）。
   - 说明：`image_picker` 的 maxWidth/quality 在 Android 是原生解码阶段生效，能避免整图进内存；Web 端也会缩小。
2. **Android 后台化**：`compressImage` 用 `compute()` 包一层（仅 Android/iOS；Web 上 `compute` 是同步的，不要指望）。
3. **缩略图解码尺寸**：`family_dashboard_page.dart:2680-2687` 加 `cacheWidth: 96, cacheHeight: 96`（2x 屏）。
4. **列表懒加载**
   - 记录区/待审批区从 `Column` 改成懒加载列表，保留现有入场动画（`EnterBox` 支持 index）。
   - 项目已依赖 `super_sliver_list: ^0.4.1`（`app/lib/fl_ui/super_reorderable_list.dart:2` 已在用），可直接用 `SliverList` / `SuperSliverList` 改造，不必引入新依赖。
   - 「加载更多」保持本地展开语义不变，只是不再一次性构建全部。
5. **统计索引**：流水变化时建一次 `Map<dayKey, sum>` 与 `Map<taskId, count>`，趋势图/任务完成度复用（`family_dashboard_page.dart:929`、`task_rules.dart:63`）。

**验证**：Android 真机选一张 4000×3000 照片，测从点击到出现预览的耗时（改前/改后各一次）；`flutter test --no-pub` 的 golden 若受影响要更新。
**风险**：`maxWidth` 会改变输出分辨率，要确认画质验收（当前统一长边 1600，与 picker 限制一致即可）。

### P3 — 后端与数据量（等观测，不着急）

按「数据量长起来才有感」排序：

1. `summary.ts` 全表 SUM：先**减少调用**（P0 已做）；若 D1 单表 > 1 万行再考虑「事务维护汇总值 + 对账脚本」，不要现在动。
2. `orphans.ts`：分页处理 + list/DB 并行 + 有限并发删除（`Promise.all` 分片）。
3. `webpush.ts`：限并发（如 5）发送。
4. `changelog`：加 `Cache-Control` / ETag。
5. `upload.ts`：先看 `Content-Length` 再读 body（顺带做魔数校验，见 §8）。
6. 历史游标分页：等真出现「200 条不够用」再上。

### P4 — React 端

主域名已切 Flutter Web，React 仅回滚退路。**除非要回滚，否则不动**。若动，按 R1→R6 顺序，一次一版。

---

## 6. 不建议做 / 保留

- **骨架控制器共享**（F17）：收益是「每个骨架少一个 ticker」，但骨架只在加载态出现，用户感知为零；改共享驱动器反而引入生命周期 bug。**不做**。
- **花园定时器句柄**（F17 后半）：`garden_state.dart:663` 的 `Timer.periodic` 是单例、生命周期等于 App，不构成泄漏。**不做**。
- **已有的正确设计要保留**：图片长缓存、React 路由懒加载、ECharts 按需引入、导航动画局部构建 —— 原报告说得对。
- **`garden_state` 的 `_commit` 全量序列化**：P1 之后（每笔不再触发 notify 链）可以先观察；真要做是拆键，但会破坏「整份存档原子性」，风险大于收益。

---

## 7. 只能实测、不能静态断言的四类

原报告已标注，这里明确列成待办（需要 Android 真机 + Flutter Web 各一份）：

1. 导航阴影/半透明底栏的 GPU 开销（1.31.6 的毛玻璃已因真机卡顿回滚过，这类只能实测）。
2. 持续呼吸/骨架动画的耗电。
3. Flutter Web 首屏下载组成与首屏时间。
4. APK 下载进度通知是否过密。

做法：Android 用 `flutter run --profile` + DevTools Performance/Memory；Web 用 Chrome Performance + Network。**没有这两份数据之前，不要为这四项改代码。**

---

## 8. 顺带发现（原报告没写，也不混进本次优化主线）

**非性能 / 安全问题：**

1. `functions/api/upload.ts:25-28` 只信 `Content-Type` 判断图片类型，不校验魔数。
2. `functions/api/ledger/[id].ts:124-129` R2 删除失败被 `catch {}` 吞掉，流水删除后图片成永久孤儿。
3. `functions/_lib/notifications.ts:53-72` notifications 表无 TTL/上限/清理任务，随使用无限增长。
4. `src/api/http.ts:105-106` `res.json()` 解析失败抛原生 `SyntaxError`，绕过 `ApiError` 归一化。
5. `functions/api/ledger/index.ts:70` `SELECT *` 把 note/image_url 等全字段塞进 200 条列表（与 B2 同源，P2 一起考虑）。

**性能细节（已并入上面的表，这里单列便于查）：**

6. `family_dashboard_page.dart:1150` 任务区内部又 `watch<CustomTasksState>()`，与 `:607` 叠加，同一状态变了触发两层重建。
7. `family_dashboard_page.dart:2683` 每个 48×48 缩略图的 `errorBuilder` 里各自 `select<ThemeState>` —— N 个缩略图就 N 个订阅，网络图错误时开销放大。
8. `settings_page.dart:156` 与 `role_gate_page.dart:244` 的 1s 锁倒计时同样整页 `setState`（原报告只提了 home/family）。
9. `garden_state.dart:660-667` 的 `Timer.periodic` 没存句柄、无 `cancel()` —— 因为 GardenState 是 app 级单例，当前不构成泄漏，但如果有天要销毁它会漏。
10. `api_client.dart:47` GET 重试 × 多源轮询（F1）⇒ **在途请求数没有上界**，P0 的 single-flight 应同时解决这一点（同 URL 只留一个在途）。

---

## 9. 执行顺序小结

```
P0 请求合并（含 snapshot 接口）  ← 改后端 + api_client + 轮询调度
P1 时钟隔离 + 无变化不通知      ← 改 UI 结构，真机验收
P2 图片尺寸 + 懒加载 + 统计索引  ← 改 UI + 选图
P3 后端数据量优化                ← 等观测
P4 React                         ← 除非回滚
```

每阶段完成即发版；发版前 `flutter analyze --no-pub` + `flutter test --no-pub`，发版后核对 `latest.json`。

---

## 10. 实施记录（2026-10-24）

### 已完成

**P0 — 请求合并**
- `app/lib/core/api_client.dart`：GET 在途合并（`_inflightGet` + `_getKey` 排序查询串）；`postBytes` 不再无条件复制 `Uint8List`。
- 新增 `functions/api/ledger/snapshot.ts`：`GET /api/ledger/snapshot?limit=` 一次 batch 返回 `{family, sun, pendingCount, pending, records}`。
- `app/lib/data/api/ledger_api.dart`：`LedgerSnapshot` + `fetchSnapshot()`（异常/老部署 404 回退 null）。
- `app/lib/state/family_state.dart`：`loadLedger()` 优先 snapshot，失败回退原三请求；抽出 `_applyLedger` 共用。
- `app/lib/ui/shell/main_shell.dart`：`/home`、`/family` 上不再重复 `refreshPending()`（页面自己刷）。
- `app/lib/state/garden_state.dart`：`refreshLedger()` 的 summary/records 真正并行（修 F14）。

**P1 — 无变化不通知 / 时钟隔离 / 启动合并**
- `family_state.dart`：`_sameRecordList` 内容指纹 + `_loadedOnce`（轮询静默）；内容不变保留旧 List 实例，`app.dart` 的 `identical` 判断恢复有效。`refreshPending` 相同不通知。
- `app/lib/router.dart`：`refreshListenable` 从 FamilyState 换成 role 的 `ValueNotifier`，只有身份变化才重算路由（修 F13）。
- 新增 `app/lib/ui/widgets/live_clock.dart`（`AppLiveClock`）；dashboard 时钟 1s→20s（仅跨分钟/天 `setState`）、parent_home 1s→30s（仅跨小时/天）。
- `family_dashboard_page.dart` `_buildTabs`：只构建当前分区。
- `settings_api.dart`：`fetchSettings` 在途合并，theme/settings 启动只打一次。
- `garden_state.dart` `init()` 幂等 guard。
- settings 称呼草稿 400ms 防抖；底栏不透明度用 `previewNavBarOpacity`（拖动只改内存）+ `onChangeEnd` 落盘。

**P2 — 图片与统计**
- `app/lib/core/image_compress.dart`：`pickCompressedImage()`（picker 层 maxWidth/maxHeight 1600 + quality 85）、`compressImageAsync()`（Android/iOS 走 `compute`，Web 同步）、`ImageUnreadableException`。三个选图入口（孩子首页打卡、家庭页打卡、设置背景）全部改走它。
- 缩略图 `cacheWidth/cacheHeight: 144`（家庭页记录 48×48）；设置背景预览 `cacheWidth: 800`。
- 统计缓存：`task_rules.countTodaySubmissionsByTask`（一次扫账本）、家庭页 `_todayCountsFor` / `_trendFor` / `_filteredRecords` 三处按「List 实例 + 日期/口径」缓存。

**P3 — 后端**
- `functions/api/changelog/index.ts`：ETag + `Cache-Control: public, max-age=300, stale-while-revalidate=86400`，`If-None-Match` 命中 304。
- `functions/api/upload.ts`：先看 `Content-Length` 挡超大请求；新增魔数校验（jpg/png/gif/webp），伪造 Content-Type 返回 415。
- `workers/reminder/src/webpush.ts`：8 台并发发送（原来逐台串行，最坏 N×15s）。
- `functions/api/maintenance/orphans.ts`：R2 列举与 DB 引用查询并行；删除改 100 个/批的 `bucket.delete(string[])`，批量失败退化逐张。

### 评估后不做（附触发条件）

| 项 | 结论 | 理由 / 什么时候再做 |
|---|---|---|
| P2-4 列表懒加载 | 不做 | 要整页改 `CustomScrollView`，破坏 AppCard 卡片视觉与 SlideFadeSwitcher/EnterBox 动效；已加载量是 20×N（用户点「加载更多」才增长）。流水到几百条再上 `SuperSliverList`。 |
| 孩子首页 build 内多次扫账本 | 不做 | `_recentSummary/_todayRecords/_latestRejected/_sleepTask` 合计约 500 条比较，微秒级；P1 后 rebuild 频率已大降。 |
| settings/role_gate 的 1s 锁倒计时 | 不改 | 只在锁定期间 `setState`，未锁定空转极低。 |
| B1 summary 全表 SUM | 不做 | 已有 `idx_family_ledger_status` / `idx_family_ledger_created_at`；单表 > 1 万行再考虑维护汇总值。 |
| B2 `SELECT *` 改显式字段 | 不做 | 表窄、收益小、有漏字段风险。 |
| B3 历史游标分页 | 不做 | 等真出现「200 条不够用」。 |
| P4 React | 不动 | 主域名已切 Flutter Web，React 仅回滚退路。 |

### 本轮验证

- 后端：根 `npx tsc --noEmit`、`workers/reminder` 的 `tsc --noEmit -p tsconfig.json` 均通过。
- 本地 `wrangler pages dev` 验证 snapshot 结构与 summary 数值一致。
- `flutter analyze --no-pub`：101 issues（基线，无 error）。
- `flutter test --no-pub`：199 pass / 2 个打生产后端的 e2e（`e2e_flow_test`、`garden_flow_test`）并发跑时 30s 超时，**单跑均通过**（已知偶发，非回归）。

