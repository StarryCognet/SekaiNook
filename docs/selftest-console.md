# 全站自检控制台（设置 → 管理员 → 自检）契约

> 这份文档是**两端共用的唯一契约**：Web（`src/views/settings/SettingsPage.tsx`）与 Flutter
> （`E:\Git\SekaiNook-App\lib\ui\pages\settings\settings_page.dart`）都只按本文档渲染与调用，
> 检查项的**清单与执行都在服务端**，客户端只负责「把清单画出来 + 跑自己的本地检查 + 合并展示」。

## 0. 为什么这样设计

- **清单只有一份**：检查项定义在服务端（`functions/_lib/selftest/`），客户端 `GET` 下来动态渲染。
  加一条检查只改后端，两端同时出现 —— 否则两端各维护一份清单，迟早写歪。
- **执行也尽可能在服务端**：绝大多数检查是「打接口 + 断言响应 + 对账口径」，在 Pages Function 里
  跑有 D1/R2 绑定、能拿到真实数据，客户端不用重复实现业务口径。
- **客户端只跑跑不了的**：路由是否可达、主题能不能切、Service Worker 注册没、本地通知排不排得上、
  SharedPreferences 读写 —— 这些必须在客户端跑，跑完把结果**回传**给服务端合并。
- **危险动作一律可预演**：会写库/删数据的检查带 `mutates: true`，默认 `dryRun`，且**自己清理自己**
  （测试完把产生的流水/订阅/图片删掉）。控制台里危险项要二次确认。

## 1. 接口

### `GET /api/admin/selftest`

返回**清单**，不需要密码（管理员区本身在客户端已口令门禁；清单不含任何数据）。

```jsonc
{
  "version": 2,
  "generatedAt": "2026-10-17T10:00:00.000Z",
  "groups": [
    {
      "id": "ledger",
      "name": "账本",
      "desc": "记账、审批、余额、结算",
      "items": [
        {
          "id": "ledger.summary.reconcile",
          "name": "余额对账（summary vs 流水累加）",
          "desc": "GET /api/ledger/summary 的两个数字，必须等于按同口径重算的流水合计",
          "side": "server",          // server | client
          "client": null,            // null | "web" | "flutter"（side=client 时是哪个端）
          "mutates": false,          // 会不会写库/删数据
          "danger": "safe",          // safe | write | destructive
          "params": ["dryRun"],      // 这一项认哪些参数（名字对应下面顶层 params 的 name）
          "estMs": 40                // 预估耗时，用于进度条
        }
      ]
    }
  ],
  "params": [
    { "name": "dryRun", "label": "预演（不写库）", "type": "bool", "desc": "…", "default": true },
    { "name": "channel", "label": "推送通道", "type": "enum", "options": ["webpush", "ntfy", "bark", "webhook"] }
  ],
  "presets": [
    { "id": "readonly", "name": "只读体检", "desc": "…", "skipMutating": true },
    { "id": "notify.short3", "name": "还差 3 个任务", "desc": "…", "params": { "simulateDone": 2 } },
    { "id": "push.chain", "name": "推送全链路", "desc": "…", "itemIds": ["push.key", "push.list"] }
  ],
  "clientChecks": {
    "web": ["web.routes", "web.theme", "web.sw", "web.push", "web.storage", "web.export"],
    "flutter": ["flutter.routes", "flutter.theme", "flutter.notify.permission",
                "flutter.notify.schedule", "flutter.notify.cancel", "flutter.storage", "flutter.image"]
  }
}
```

- 预设三种形态：`skipMutating: true`（跳过所有写库项）、`itemIds: [...]`（只跑这些项）、`params: {...}`（套一组参数）。
- `side: "client"` 的项**不会**被服务端执行，服务端只在结果里标记 `skip` + `detail: "client-side"`，由客户端跑完回传覆盖。

### `POST /api/admin/selftest`

需要管理员密码（与 `POST /api/admin` 同一套密码与节流）。

```jsonc
{
  "password": "…",
  "items": ["ledger.list", "ledger.summary.reconcile"],  // 省略 = 跑全部 server 项
  "groups": ["ledger", "push"],                          // 与 items 取并集；都省略 = 全部
  "params": { "simulateDone": 2, "now": "2026-10-20T13:30:00Z", "dryRun": true },
  "clientResults": [ { "id": "web.routes", "status": "pass", "ms": 120, "detail": "7/7 路由" } ],
  "includeClient": false      // true 时结果里保留 client 项（默认保留并标记 skip）
}
```

响应：

```jsonc
{
  "ranAt": "2026-10-17T10:00:01.000Z",
  "durationMs": 1830,
  "env": { "db": "sekainook", "origin": "https://sn.starrymiku.com", "now": "…", "worker": "https://sekainook-reminder.3398377037.workers.dev" },
  "params": { "dryRun": true, "simulateDone": 2, "now": "…", "…": "…" },   // 本轮实际生效的参数（回显）
  "summary": { "total": 71, "passed": 52, "failed": 0, "skipped": 19, "warned": 0 },
  "results": [
    {
      "id": "ledger.summary.reconcile",
      "group": "ledger",
      "name": "余额对账（summary vs 流水累加）",
      "side": "server",
      "mutates": false,
      "status": "pass",              // pass | fail | warn | skip
      "ms": 37,
      "detail": "family 135 = 135，sun 175 = 175",
      "data": { "summary": { "family": 135, "sun": 175 } }   // 可选，给前端展开看原始响应
    }
  ],
  "clientMissing": ["web.push"],   // 这轮选了、但前端没回传结果的客户端项 id
  "notes": ["写库类检查已自清理：新增 1 条流水已删除"]
}
```

- `status: "warn"` = 没失败但值得看一眼（例如「今天已经提醒过了（幂等标记还在）」）。
- 单项执行失败**不影响**其余项；每项独立 try/catch，异常变成 `fail` + `detail: String(err)`。
- 单项超时 `10s` 判 `fail: "超时"`；整轮超过 `45s` 会停止剩余项并在 `notes` 里说明。

## 2. 检查项清单（服务端）

分组 id / 名称 / 覆盖内容。**加检查项时改这里 + `functions/_lib/selftest/` 注册表**。

| 分组 | id | 覆盖 |
| --- | --- | --- |
| 环境与部署 | `env` | 绑定可查、关键表存在（含 `changelog`）、迁移版本、CORS 预检、404 形态、`/sw.js` 有 push 监听、`/manifest.webmanifest` 可读、**版本日志已上云**（`GET /api/changelog` 的条数/顺序/最新版本） |
| 账本 | `ledger` | 列表结构、待审批过滤、**余额对账**、写入幂等、未知任务 403、日限拦截、审批/驳回/重新提交/删除全链路、结算幂等 |
| 任务规则 | `rules` | 12 条任务规则与服务端逐条对账、睡觉卡时间窗、完成数口径（helper vs 独立 SQL）、客户端上报的表/周标签/罚款常量对账 |
| 每周学习计划 | `plans` | 列表结构、非法周标签、进度夹取值并还原、幂等初始化 |
| 通知 | `notify` | 两格信箱、未读数、缺 audience 400、单条已读、整格已读、客户端文案对账 |
| 设置 | `settings` | GET 结构、称呼读写并还原、背景图白名单守卫 |
| 图片 | `images` | 上传并自清理、匿名读取、孤儿扫描、缺 confirm 守卫 |
| 手机提醒（推送） | `push` | VAPID 公钥、订阅登记/校验/退订/列表、幂等标记、Worker health、发送预演、真发（自定义文案/通道/目标） |
| 管理员 | `admin` | 错误密码 401 + 剩余次数（跑完清计数）、节流锁状态、按当前值调整不写流水、最近调整、一键清零预演 |
| 维护 | `maintenance` | settings 键体检、流水时间戳与东八区日界自洽 |
| 客户端 | `client` | 13 项必须在客户端跑的检查（`side: "client"`），服务端只回传合并 |

## 3. 可覆盖参数（`params`）

服务端每项在清单里声明自己认哪些参数（`item.params`），顶层 `params` 给出**渲染所需的元数据**
（`name` / `label` / `type: bool|string|int|enum` / `desc` / `default?` / `options?`）。
**控制台按清单动态渲染表单，不要硬编码参数表**（加一个参数只改后端）。

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `dryRun` | bool | 默认 `true`。写库类检查在 `true` 时只预演不落库 |
| `now` | string(ISO) | **时间旅行**：替代真实时间参与口径计算（日界、22 点、周标签） |
| `simulateDone` | int | 模拟「今天已完成 N 个任务」，用于通知文案与罚款预演 |
| `dayKey` | string | 直接指定东八区日期 `YYYY-MM-DD` |
| `taskId` | string | 指定任务（默认 `clean_room`） |
| `amount` / `note` | int/string | 指定写入的金额与备注 |
| `weekLabel` | string | 指定周标签，默认当前周 |
| `audience` | enum | `parent` / `child` / `all`（通知与订阅目标） |
| `endpoint` | string | 指定推送目标设备（`push_subscriptions.endpoint`），留空 = 全部 |
| `channel` | enum | `webpush` / `ntfy` / `bark` / `webhook` |
| `title` / `message` / `click` | string | 自定义通知标题/正文/点击链接 |
| `priority` | int | 1–5 |
| `force` | bool | 推送：跳过当天幂等标记 |
| `keep` | bool | 写库类检查：`true` 时**不清理**产生的数据（默认清理） |

## 4. 客户端本地检查项（两端各自实现，id 固定）

### Web（`clientChecks.web`）

| id | 断言 |
| --- | --- |
| `web.routes` | 7 条路由（`/home`、`/home/notifications`、`/family`、`/family/plan`、`/garden`、`/settings`、`/role`）都能渲染出根节点内容 |
| `web.theme` | 7 套主题 × 浅/深 切换后 `data-theme` 与 CSS 变量生效、无异常 |
| `web.sw` | `navigator.serviceWorker` 可用、`/sw.js` 已注册、`'push' in registration` |
| `web.push` | 通知权限状态、`PushManager` 可用性、当前是否已订阅（含 iOS 未加主屏的提示） |
| `web.storage` | `localStorage` 读写删、`sekainook_*` 键清单 |
| `web.export` | 导出 CSV/JSON 的数据源可生成（不触发下载） |

### Flutter（`clientChecks.flutter`）

| id | 断言 |
| --- | --- |
| `flutter.routes` | 7 条路由 `go` 之后对应页面构建成功（无异常） |
| `flutter.theme` | 7 套主题构建 + `AppPalette` 对比度不低于 4.5:1（复用 `test/palette_contrast_test.dart` 的口径） |
| `flutter.notify.permission` | 通知权限状态查询 + 请求（Android 13+） |
| `flutter.notify.schedule` | 排一条 **5 秒后**的本地通知并断言「已排程」 |
| `flutter.notify.cancel` | 取消上面那条并断言「已取消」 |
| `flutter.storage` | `SharedPreferences` 读写删 + 键清单 |
| `flutter.image` | 压缩：1 张测试图 → 长边 ≤ 1600、体积变小 |

> `flutter.notify.permission` / `flutter.notify.schedule` / `flutter.notify.cancel` 依赖本地通知插件
> （`flutter_local_notifications`），**目前 App 还没接入**：这三项如实返回 `skip`，
> detail 写「本地通知尚未接入（需 flutter_local_notifications）」。不要为了自检去加依赖。

## 5. 结果导出

两端都提供「导出 JSON」（浏览器下载 `sekainook-selftest-<时间>.json` / App 复制到剪贴板）与
「复制 Markdown」（两端都进剪贴板）：Markdown 格式固定为

```md
# SekaiNook 自检报告
- 时间：2026-10-17 18:00:01 (+08:00)
- 环境：https://sn.starrymiku.com · Worker sekainook-reminder
- 参数：simulateDone=2, dryRun=true
- 结果：44 项 · 通过 41 · 失败 2 · 跳过 1

| 结果 | 分组 | 检查项 | 耗时 | 详情 |
| --- | --- | --- | --- | --- |
| ✅ | 账本 | 余额对账 | 37ms | family 135 = 135 |
```

## 6. 两端 UI 要求

- 位置：设置 → **管理员** 区里新增一个入口「全站自检」（Web 是 `superadmin` 分区里的内容，
  Flutter 是管理员子页里的一块），点开就是面板；不新开顶层入口。
- 顶部：环境信息（origin / Worker / DB）、参数区（预设按钮 + 动态表单）、
  「全部跑一遍」「只跑失败项」「只跑写库项」三个动作。
- 列表：按分组折叠，每项显示状态点、名称、耗时；失败项展开显示 `detail` + `data`（JSON）。
- 客户端项：运行前先跑 `clientChecks.web` / `clientChecks.flutter` 里的本地检查，
  把结果作为 `clientResults` 一起提交；响应里的 `clientMissing` 要提示出来（还有几项没跑）。
- 危险项（`mutates`）：默认不跑，勾选后才跑，且必须二次确认；`keep` 默认关（跑完自清理）。
- 底部：汇总条 + 「复制 JSON」「导出 Markdown」。
- 运行中：逐项进度（已完成/总数），可中途停止。
- 权限：进管理员区时已校验过密码，运行请求带上同一个密码；密码错误/锁定按现有 401/429 文案展示。

## 7. 不做什么

- 不新增鉴权中间件（沿用「管理员密码在 POST 里校验」这一套）。
- 不改任何业务语义：自检只**观察**业务，写库类检查必须自清理。
- 不在客户端复制业务口径：口径对账由客户端**上报本地实现的结果**、服务端比对，客户端不重新实现。
