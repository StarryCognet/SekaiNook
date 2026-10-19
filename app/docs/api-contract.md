# SekaiNook REST API 契约（Flutter 客户端唯一接口事实来源）

本文档从 Web 版后端源码逐行提炼，**只描述后端真实行为**，不描述期望行为。
凡源码无法确定的行为一律标注 **【未确认】**，不要去猜。

- 后端源码：`E:\Git\SekaiNook`（React + Cloudflare Pages Functions + D1 + R2）
- 本次读码基准（这些文件是本文档的唯一依据）：
  - `functions/api/ledger/index.ts`、`functions/api/ledger/[id].ts`、`functions/api/ledger/summary.ts`、`functions/api/ledger/settle.ts`
  - `functions/api/plans/index.ts`、`functions/api/plans/[id].ts`
  - `functions/api/upload.ts`、`functions/api/images/[[key]].ts`
  - `functions/api/notifications/index.ts`、`functions/api/notifications/[id].ts`、`functions/api/notifications/read-all.ts`
  - `functions/api/settings/index.ts`、`functions/api/admin/index.ts`、`functions/api/maintenance/orphans.ts`、`functions/api/changelog/index.ts`
  - `functions/_lib/rules.ts`、`functions/_lib/settings.ts`、`functions/_lib/notifications.ts`、`functions/_lib/changelog.ts`
  - `migrations/0001_init.sql` ~ `migrations/0006_changelog.sql`
  - Web 客户端调用方式参考：`src/api/*.ts`、`src/config/familyRules.ts`、`src/config/garden.ts`、`src/utils/week.ts`、`src/types/*.ts`

---

## 1. 如何使用本文档

1. **Flutter 客户端复用 Web 版后端，不改后端。** 本文档是接口的**唯一事实来源**；当本文档与任何其它文档（包括 Web 仓库里的 `docs/v1.30-实现契约.md`）冲突时，以本文档为准，因为它直接来自后端源码。
2. **全站 `/api/*` 没有任何鉴权。** 没有 Token、没有 Cookie、没有 Session、没有签名头。唯一的一处凭据校验是 `POST /api/admin` 请求体里的 `password` 字段（用于改余额/改密码/列调整记录）。
   - 仓库里**不存在** `functions/_middleware.ts`（已核实：`functions/` 下只有 `_lib/` 与 `api/`）。
   - `public/_routes.json` 只声明 `include: ["/api/*"]`，不含任何鉴权逻辑。
   - `functions/api/upload.ts` 顶部注释「受 /api/_middleware.ts 鉴权保护」是**过期注释**，不要据此加鉴权头。
   - 结论：除 `POST /api/admin` 外，所有请求都不需要任何 header 凭据；也**不要**在客户端实现"登录"，没有可登录的东西。请把「孩子端/家长端」当作本地 UI 视角切换，而不是两种权限。
3. **字段命名不统一是事实，不是笔误。** 数据行（账本/计划/通知）一律 `snake_case`（`task_id`、`task_name`、`image_url`、`created_at`、`week_label`、`read_at`）；而 settings / 通知列表 / admin 的外层字段是 `camelCase`（`unreadCount`、`ready`、`attemptsLeft`、`lockRemainingMs`、`passwordChanged`、`createdAt`、`momCall`）。照抄本文档，不要"顺手统一"。
4. **时间一律按东八区（Asia/Shanghai，固定 UTC+8，不含夏令时）判断**日限、时间窗、结算日；但存储的时间戳都是 UTC ISO（`new Date().toISOString()`，形如 `2026-08-20T04:12:33.123Z`）。Flutter 端不要用设备本地时区去算"今天"。
5. **错误响应统一形态**：`{"error": "<中文原文>"}` + 非 2xx 状态码。但有两种例外必须容忍：① `GET /api/images/:key` 的 404 是**纯文本** `Not Found`；② 少数接口路径没有 try/catch，底层异常会冒出平台级 500（**不是** JSON）。
6. 本文档中的所有中文错误文案都是**原文**，可用于 `expect` 断言或用作用户提示（占位符用 `${}` 标注）。

### 1.1 端点总览（20 个路由）

| # | 方法 | 路径 | 成功状态 | 返回形态 | Web 端调用点 |
|---|---|---|---|---|---|
| 1 | GET | `/api/ledger` | 200 | 裸数组 `LedgerRecord[]` | `src/api/familyLedger.ts:55` |
| 2 | POST | `/api/ledger` | 201 / 200 | `{id,status}` 或 `{id,status,duplicate}` | `src/api/familyLedger.ts:211` |
| 3 | PATCH | `/api/ledger/:id` | 200 | `{ok:true}` | `src/api/familyLedger.ts:298` |
| 4 | DELETE | `/api/ledger/:id` | 200 | `{ok:true}` | `src/api/familyLedger.ts:322` |
| 5 | GET | `/api/ledger/summary` | 200 | `{family,sun}` | `src/api/familyLedger.ts:78` |
| 6 | POST | `/api/ledger/settle` | 200 | `{family,sun,applied,day}` | `src/api/familyLedger.ts:122` |
| 7 | GET | `/api/plans?week=` | 200 | 裸数组 `WeeklyPlan[]` | `src/api/familyTasks.ts:7` |
| 8 | POST | `/api/plans` | 201 | 裸数组 `WeeklyPlan[]` | `src/api/familyTasks.ts:15` |
| 9 | PATCH | `/api/plans/:id` | 200 | `{ok:true,current}` | `src/api/familyTasks.ts:29` |
| 10 | POST | `/api/upload` | 201 | `{url,key}` | `src/api/upload.ts:25` |
| 11 | GET | `/api/images/:key` | 200 | 图片二进制 | 由 `<img src>` 直接引用 |
| 12 | GET | `/api/notifications?audience=` | 200 | `{items,unreadCount,ready}` | `src/api/notifications.ts:16` |
| 13 | PATCH | `/api/notifications/:id` | 200 | `{ok:true}` | `src/api/notifications.ts:23` |
| 14 | POST | `/api/notifications/read-all` | 200 | `{ok:true,updated}` | `src/api/notifications.ts:32` |
| 15 | GET | `/api/settings` | 200 | `{names,background,ready}` | `src/api/settings.ts:26` |
| 16 | PATCH | `/api/settings` | 200 | `{names,background,ready}` | `src/api/settings.ts:31` |
| 17 | POST | `/api/admin` | 200 | `{family,sun,...}` | `src/api/admin.ts:27,36,44,66` |
| 18 | GET | `/api/maintenance/orphans` | 200 | `{total,referenced,orphans,keys}` | `src/api/maintenance.ts:35` |
| 19 | POST | `/api/maintenance/orphans` | 200 | `{deleted,failed,keys}` | `src/api/maintenance.ts:40` |
| 20 | GET | `/api/changelog` | 200 | `{version,entries,ready}` | `src/api/changelog.ts:27` |

### 1.2 分层结构图（用于理解相对路径的解析）

```
/api/ledger                → ledger/index.ts        (GET, POST)
/api/ledger/summary        → ledger/summary.ts      (GET)        ← 字面量段，优先于 [id]
/api/ledger/settle         → ledger/settle.ts       (POST only)  ← 只导出 onRequestPost
/api/ledger/<任意字符串>    → ledger/[id].ts          (PATCH, DELETE)
/api/plans, /api/plans/<id>, /api/upload, /api/images/<任意/多级路径>,
/api/notifications, /api/notifications/read-all, /api/notifications/<id>,
/api/settings, /api/changelog, /api/admin, /api/maintenance/orphans
```

- `settle`、`summary`、`read-all` 都是**字面量段**，Cloudflare Pages 的最具体路由优先，不会被 `[id]` 抢走。
- `GET /api/ledger/settle`：settle.ts 没有 `onRequestGet`，`[id].ts` 也没有 GET handler ⇒ 一定不是 200；预期 405 Method Not Allowed，**具体状态码与响应体【未确认】**。
- `GET /api/ledger/summary` 返回 `{family,sun}`，**不要**误当成一条流水记录。

---

## 2. 通用约定

### 2.1 HTTP 层

| 项目 | 约定 |
|---|---|
| 请求体编码 | `application/json`（**唯一例外**：`POST /api/upload` 是原始二进制，Content-Type 必须是图片 MIME） |
| 成功判定 | `200 <= status < 300`。注意同一个接口可能用 201（新建）和 200（幂等命中）两种成功码 |
| 错误体 | `{"error":"<中文原文>"}`（见 1.5 的两处例外） |
| Web 端重试策略（供 Flutter 参考，非后端行为） | GET 自动重试 2 次；写请求默认不重试，仅 `POST /api/ledger` 显式开 1 次重试；可重试状态码 `[429,500,502,503,504]`；退避 `[400ms,1200ms]`；超时 12s（`src/api/http.ts:20-28`） |
| 4xx 判定 | `status >= 400 && status < 500 && status !== 429` 视为"服务端明确拒绝，重试无用"（`src/api/familyLedger.ts:231`） |

### 2.2 客户端生成 id 的通用约束（写流水用）

- 正则：`/^[A-Za-z0-9][A-Za-z0-9_:.-]*$/`（`functions/api/ledger/index.ts:36`）
- 长度上限：64（`ID_MAX_LENGTH`）
- **正则先对完整字符串校验，然后才 `slice(0,64)`**（`index.ts:151-152`）—— 见第 16 节坑 #20。
- 非法 id 序号：不报错，**静默替换成服务端 `crypto.randomUUID()`**（`index.ts:153`）—— 幂等性随之消失。

---

## 3. `GET /api/ledger` —— 流水列表（专项）

**返回：裸 JSON 数组（不是 `{items:[…]}`），按 `created_at DESC` 排序。**

### 3.1 查询参数

| 参数 | 类型 | 默认 | 边界与语义 |
|---|---|---|---|
| `status` | string | 无（不过滤） | `if (status)` 真值判断：**空串 `?status=` 等于不过滤**。非空时拼 `status = ?` 精确匹配，**不校验合法性**：`?status=nonsense` 不报错，返回 `[]`。`?status=null` 会按**字符串 `"null"`** 过滤（历史数据 status 为 SQL NULL，匹配不到）⇒ 也返回 `[]` |
| `member` | string | 无（不过滤） | 历史遗留字段（多成员功能已下线，前端不再传）。空串 = 不过滤。非空拼 `member = ?` 精确匹配 |
| `limit` | number | 200（`DEFAULT_LIMIT`） | 上限 500（`MAX_LIMIT`）。解析：`Number(raw)`；`Number.isFinite(raw) && raw > 0` 才用它，否则回退 200。合法值再 `Math.min(Math.floor(raw), 500)`。⇒ `limit=abc`/`-1`/`0`/`Infinity` → 200；`limit=1000` → 500；**`limit=0.5` → `Math.floor` 得 0 → `LIMIT 0` → 返回 `[]`**（真实坑，见第 16 节 #6） |
| `since` | string（ISO 时间） | 无 | 增量拉取：拼 `created_at > ?`（**严格大于**，字符串比较）。⚠️ 同一毫秒的多条记录会被漏掉 |
| 未知参数 | — | — | 静默忽略 |

### 3.2 返回记录字段（`SELECT *`，列名随迁移状态变化）

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | string | 主键。客户端自带 id 时就是客户端那个值 |
| `task_id` | string | 任务 id，见第 6 节任务规则总表 |
| `task_name` | string | 任务显示名（服务端规范化后的值） |
| `type` | `'earning' \| 'spending'` | 收入/支出，决定 UI 的正负号与颜色 |
| `amount` | number | 整数。earning 为正、spending 为负（不变量，`user_task_exec` 负数也遵守） |
| `note` | string \| null | 备注，接口层不截断 |
| `image_url` | string \| null | 形如 `<origin>/api/images/tasks/1712…-1a2b3c4d.jpg` |
| `status` | `'pending' \| 'approved' \| 'rejected'` \| **null** | **可能为 null**（0001 之前/裸 SQL 写入的历史数据）⇒ 视为已入账。DB 默认值是 `'approved'`，但 API 写入时总是显式赋值 |
| `created_at` | string | UTC ISO，如 `2026-08-20T04:12:33.123Z`。**UTC，不是东八区**，UI 显示要转换 |
| `member` | string \| null | **0002 迁移未执行时这个键根本不存在**。Dart 模型必须容忍字段缺失（用 `json['member'] as String?` 而不是强转） |

### 3.3 失败

| 状态码 | 触发条件 | error 原文 |
|---|---|---|
| 500（**非 JSON**）【未确认】 | D1 查询异常（如 `member` 列不存在却带了 `?member=`、库不可用） | 无 `{error}` 体；平台级错误页 |

> 该方法**没有** try/catch，是本文档里少数可能返回非 JSON 500 的路径之一。

---

## 4. `POST /api/ledger` —— 写一条流水

服务端是唯一可信源：`task_name` / `type` / `amount` / `status` 默认全部由服务端规则决定，客户端传的一律忽略（例外见 4.2）。

### 4.1 请求体字段

| 字段 | 类型 | 必填 | 含义 |
|---|---|---|---|
| `task_id` | string | **是** | 必须是第 6 节表里的已知 id。非 string / 空串 / 长度 > 64 → 400 |
| `id` | string | 否 | 客户端幂等键。必须匹配 2.2 的正则；否则静默丢弃改用 UUID |
| `amount` | number | 视规则 | 只有当规则声明了 `clientAmount` 时才会被读取；否则完全忽略。规则声明了 `clientAmount` 却没传/不是有限数 → 400 |
| `task_name` | string | 否 | 只有当规则声明了 `clientName: true`（仅 `user_task_exec`）时才采纳。处理：`trim()` → 连续空白折叠为单空格 → 截断 30 字符；空结果回退规则名 `自定义任务` |
| `type` | string | 否 | **永远忽略** |
| `status` | string | 否 | **永远忽略** |
| `note` | string | 否 | 非 string 存 null。**接口层不截断、无长度上限**（客户端自己截） |
| `image_url` | string | 否 | 非 string 存 null。**无长度上限** |
| `member` | string | 否 | 历史遗留。`trim()` 后截断 20 字符；空串存 NULL。⚠️ 传了它但库没跑 0002 迁移时会打到不存在的列 |

### 4.2 服务端取值规则（精确）

```
未知 task_id                                   → 403
rule.serverOnly                                → 403
rule.clientAmount 存在且 amount 非有限数        → 400
clientAmount = clamp(round(amount), min, max)   仅当规则有 clientAmount 且未标 clientAmountValidateOnly
             = null                             当规则标了 clientAmountValidateOnly（只校验不采纳）
finalAmount = clientAmount ?? rule.value
finalType   = (clientAmount !== null && clientAmount < 0) ? 'spending' : rule.type
finalName   = clientName 规则且 task_name 是 string 且 trim 后非空 ? 规范化名(≤30) : rule.name
finalStatus = rule.autoApprove ? 'approved' : 'pending'
```

- **超范围是夹取（clamp），不是报错**：`user_task_exec` 传 `amount: 9999` 会记成 `+200`；`garden_legacy` 传 `-50` 会记成 `0`。
- `clientAmountValidateOnly` 的两条预置任务（`custom:english_words10` / `custom:poem2`）：**必须传 amount**（否则 400），但金额固定按服务端 `+10` 记账，传 100 也只加 10。
- 状态判定只认 `rule.autoApprove`：花园奖励/商城/兑现直接 `approved`，其余（含 `user_task_exec`）一律 `pending`，必须由 `PATCH /api/ledger/:id` 改成 `approved`。

### 4.3 成功响应

| 状态码 | Body | 说明 |
|---|---|---|
| **201** | `{"id":"<实际写入的id>","status":"pending"\|"approved"}` | 新建成功。`id` 可能是服务端 UUID（当客户端 id 非法时） |
| **200** | `{"id":"…","status":"…","duplicate":true}` | 幂等命中：该 id 之前已入账，本次**没有**新增。**必须按成功处理** |

### 4.4 失败（全部原文）

| 状态码 | 触发条件 | error 原文 |
|---|---|---|
| 400 | body 不是合法 JSON | `请求体不是合法 JSON` |
| 400 | `task_id` 非 string / 空 / 长度 > 64 | `task_id 非法` |
| 403 | `task_id` 不在规则表里 | `未知任务，不能记账` |
| 403 | `rule.serverOnly === true` | `「${rule.name}」由服务端自动记账，不能直接提交` |
| 400 | 规则有 `clientAmount`，`amount` 非 number 或非有限 | `amount 非法` |
| 409 | 非 autoApprove 规则且不在时间窗内（在日限检查**之前**判定） | `「${rule.name}」只能在 ${start}-${end} 之间打卡` |
| 409 | 日限闸门（详见第 7 节） | 见第 7 节 5 条文案 |
| 500 | `INSERT OR IGNORE` 后 `changes === 0` 但按 id 又查不到记录 | `写入失败，请重试` |

**时间窗规则唯一条**：`sleep_on_time`，`window = {start:'19:00', end:'22:00'}`，**闭区间**（`minutes < start || minutes > end` 才拒绝），按东八区墙上时钟比较，不支持跨零点。

### 4.5 副作用

- 记账成功后，**仅当 `finalStatus === 'pending'`** 才写一条家长通知：
  - `audience: 'parent'`、`type: 'checkin_pending'`、`title: '${kid的显示名}提交了打卡'`、`body: '${finalName} ${amountText(type,amount)}'`、`link: '/family'`、`dedupeKey: 'ledger:${id}:pending'`
  - `amountText(type, amount) = (type === 'spending' ? '-' : '+') + abs(amount)`（`src/api/familyLedger.ts` 侧同款函数）
  - 写通知失败**不影响**记账（`_lib/notifications.ts` 内部吞异常）
- 通知文案里的称呼来自 settings 表（昵称优先，见第 12 节）。

---

## 5. `PATCH /api/ledger/:id` 与 `DELETE /api/ledger/:id`

### 5.1 PATCH —— 改审批状态

请求体：

| 字段 | 类型 | 必填 | 含义 |
|---|---|---|---|
| `status` | string | **是** | 只接受 `'pending'` / `'approved'` / `'rejected'` 三个字面量 |
| `reason` | string | 否 | 驳回理由。`trim()` 后截断 **60** 字符；只在 `status === 'rejected'` 时进入通知文案 |

成功：**200** `{"ok":true}`。

| 状态码 | 触发条件 | error 原文 |
|---|---|---|
| 400 | body 不是合法 JSON | `请求体不是合法 JSON` |
| 400 | `status` 非 string 或不在三值内 | `status 非法` |
| 404 | id 查不到 | `记录不存在` |

副作用（仅当状态**确实变化**时，同值重复 PATCH 不重复通知）：

| 新状态（且与旧值不同） | 通知 |
|---|---|
| `approved` | `audience:'child'`、`type:'approved'`、`title:'${mom}通过了「${task_name}」'`、`body:'${amountText} 积分已入账'`、`link:'/family'`、`dedupeKey:'ledger:${id}:approved:${旧状态}'` |
| `rejected` | `audience:'child'`、`type:'rejected'`、`title:'${mom}驳回了「${task_name}」'`、`body: reason ? '${mom}说：${reason}' : '看看哪里不对，改好可以再提交一次'`、`dedupeKey:'ledger:${id}:rejected:${旧状态}'` |
| `pending` | `audience:'parent'`、`type:'resubmitted'`、`title:'${kid}重新提交了打卡'`、`body:'${task_name} ${amountText}'`、`dedupeKey:'ledger:${id}:resubmit:${旧状态}'` |

- `mom = displayName(names,'mom')`，`kid = displayName(names,'kid')`。
- 注意 `dedupeKey` 里带的是**旧状态**，所以 `rejected → pending → approved` 这类流转不会被 dedupe 吃掉。

### 5.2 DELETE —— 删流水（并清理图片）

无请求体。成功：**200** `{"ok":true}`；404 `记录不存在`。

副作用：若 `image_url` 的 pathname 以 `/api/images/` 开头，则取出 R2 key 并 `bucket.delete(key)`；**R2 删除失败被吞掉，不阻断流水删除**。

---

## 6. 任务规则总表（最重要 —— Flutter 端要照它做 UI）

来源：`functions/_lib/rules.ts`，三个 map 合并成 `LEDGER_TASK_RULES`：`FAMILY_TASK_RULES`（16 条）+ `GARDEN_TASK_RULES`（18 条）+ `SYSTEM_TASK_RULES`（2 条）= **36 条，全部列出，无省略**。

列含义：
- `value`：服务端确定的金额（除非该行标了 `clientAmount`）。
- `dailyLimit`：每日提交次数上限；**空 = 无任何日限**（可无限提交）。
- `window`：东八区 `HH:MM` 闭区间。
- `autoApprove`：写入即 `approved`（否则 `pending`）。
- `serverOnly`：客户端 POST 一律 403，只能由服务端结算接口写入。
- `clientAmount`：`{min,max}` 表示采纳客户端金额并夹取；后缀 `(仅校验)` 表示**只校验不采纳**（金额仍按 `value`）。
- `clientName`：`true` 表示采纳客户端任务名。

### 6.1 family 组（16 条）

| # | `task_id` | 名称 | `type` | `value` | `dailyLimit` | `window` | `autoApprove` | `serverOnly` | `clientAmount` | `clientName` |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `clean_room` | 整理房间 | earning | 10 | 2 | — | — | — | — | — |
| 2 | `wash_dishes` | 洗碗 | earning | 5 | 2 | — | — | — | — | — |
| 3 | `do_laundry` | 洗衣服 | earning | 15 | 1 | — | — | — | — | — |
| 4 | `take_out_trash` | 倒垃圾 | earning | 5 | 1 | — | — | — | — | — |
| 5 | `finish_homework` | 按时完成作业 | earning | 20 | 1 | — | — | — | — | — |
| 6 | `read_book` | 课外阅读30分钟 | earning | 10 | 2 | — | — | — | — | — |
| 7 | `sleep_on_time` | 按时睡觉 | earning | 10 | 1 | 19:00–22:00 | — | — | — | — |
| 8 | `ipad_time` | 看iPad 30分钟 | spending | −10 | 4 | — | — | — | — | — |
| 9 | `phone_time` | 玩手机 30分钟 | spending | −10 | 4 | — | — | — | — | — |
| 10 | `eye_penalty` | 视力下降1度 | spending | −100 | **无** | — | — | — | — | — |
| 11 | `sleep_penalty` | 未按时作息(晚于22:00) | spending | −20 | 1 | — | — | — | — | — |
| 12 | `homework_incomplete` | 作业未完成 | spending | −50 | 1 | — | — | — | — | — |
| 13 | `custom:english_words10` | 十个英语单词 | earning | 10 | 1 | — | ✔ | — | `{1,100}`（仅校验） | — |
| 14 | `custom:poem2` | 两首古诗 | earning | 10 | 1 | — | ✔ | — | `{1,100}`（仅校验） | — |
| 15 | `user_task_exec` | 自定义任务 | earning | 0 | 20 | — | — | — | `{-200,200}` | ✔ |
| 16 | `payout` | 现金兑现 | spending | 0 | **无** | — | ✔ | — | `{-100000,0}` | — |

要点：
- `eye_penalty`、`payout` **没有 dailyLimit** ⇒ 服务端不做任何次数限制（`payout` 还是 autoApprove ⇒ 无限次兑现流水，UI 必须自己防连点）。
- `sleep_penalty` 的 `serverOnly` 是 **false**（家长可以手工记），但它与日结算共用同一个 `task_id`，所以两边的日限一起生效、不会重复扣。它同时被 `COMPLETION_EXCLUDED_IDS` 排除在"今日完成数"之外。
- `user_task_exec` 的 `value: 0` 只是占位；实际金额必须由客户端传（不传 → 400）。
- `payout` 是 v1.30 回归补登记的老任务，前端点"结算兑现"走它。

### 6.2 garden 组（18 条）

| # | `task_id` | 名称 | `type` | `value` | `dailyLimit` | `window` | `autoApprove` | `serverOnly` | `clientAmount` | `clientName` |
|---|---|---|---|---|---|---|---|---|---|---|
| 17 | `garden:poem` | 背一首古诗 | earning | 10 | **无** | — | ✔ | — | — | — |
| 18 | `garden:chinese` | 语文预习 15 分钟 | earning | 15 | 1 | — | ✔ | — | — | — |
| 19 | `garden:math` | 数学预习 15 分钟 | earning | 15 | 1 | — | ✔ | — | — | — |
| 20 | `garden:reading` | 课外阅读 20 分钟 | earning | 20 | 1 | — | ✔ | — | — | — |
| 21 | `garden:writing` | 练字 10 分钟 | earning | 10 | 1 | — | ✔ | — | — | — |
| 22 | `garden:eyes` | 休息眼睛 5 分钟 | earning | 5 | 1 | — | ✔ | — | — | — |
| 23 | `garden:sport` | 运动 20 分钟 | earning | 20 | 1 | — | ✔ | — | — | — |
| 24 | `garden:chore` | 做一件家务 | earning | 15 | 1 | — | ✔ | — | — | — |
| 25 | `garden:read_aloud` | 课文朗读 | earning | 5 | 3 | — | ✔ | — | — | — |
| 26 | `garden:new_words` | 生字认读 | earning | 5 | 2 | — | ✔ | — | — | — |
| 27 | `garden:write_words` | 生字书写 | earning | 10 | 1 | — | ✔ | — | — | — |
| 28 | `garden_legacy` | 花园阳光迁移 | earning | 0 | 1 | — | ✔ | — | `{0,2000}` | — |
| 29 | `garden_shop:avatar_sun` | 阳光头像框 | spending | −60 | **无** | — | ✔ | — | — | — |
| 30 | `garden_shop:avatar_star` | 星星头像框 | spending | −80 | **无** | — | ✔ | — | — | — |
| 31 | `garden_shop:title_poet` | 称号・小诗人 | spending | −100 | **无** | — | ✔ | — | — | — |
| 32 | `garden_shop:title_gardener` | 称号・小园丁 | spending | −120 | **无** | — | ✔ | — | — | — |
| 33 | `garden_shop:decor_rainbow` | 装饰・彩虹花架 | spending | −150 | **无** | — | ✔ | — | — | — |
| 34 | `garden_shop:decor_lantern` | 装饰・星星灯串 | spending | −200 | **无** | — | ✔ | — | — | — |

- 六个商城商品**没有** dailyLimit ⇒ 服务端不阻止重复购买（"一次性拥有"是前端 store 的约束，不是后端约束）。
- `garden:poem` 无日限（"一天可以背好几首"），但"今日完成数"按 `task_id` 去重 ⇒ 背 3 首只算 1 个完成任务。
- 商品名里的 `・` 是 U+30FB（KATAKANA MIDDLE DOT），不是 `·`。

### 6.3 system 组（2 条）

| # | `task_id` | 名称 | `type` | `value` | `dailyLimit` | `window` | `autoApprove` | `serverOnly` | `clientAmount` | `clientName` |
|---|---|---|---|---|---|---|---|---|---|---|
| 35 | `seed_welcome_bonus` | 开户礼金 | earning | 100 | 1 | — | ✔ | **✔** | — | — |
| 36 | `daily_min_tasks_penalty` | 今日完成不足 5 个任务 | spending | −10 | 1 | — | ✔ | **✔** | — | — |

> 注意第 36 行的 `value` 是 **`-10`**（源码里写成 `-DAILY_MIN_TASKS_PENALTY`，`DAILY_MIN_TASKS_PENALTY = 10`）。
> `sleep_penalty`（第 11 行，−20）也属于系统结算会写的记录，但它在 family 组且**不是** serverOnly。

### 6.4 相关常量

| 常量 | 值 | 出处 |
|---|---|---|
| `EXEC_TASK_ID` | `'user_task_exec'` | `rules.ts:179` |
| `DAILY_MIN_TASKS` | `5` | `rules.ts:182` |
| `DAILY_MIN_TASKS_PENALTY` | `10` | `rules.ts:185` |
| `CUSTOM_TASK_DAILY_CAP` | `50` | `rules.ts:196` |
| `SLEEP_DEADLINE` | `'22:00'`（派生自 `sleep_on_time.window.end`） | `rules.ts:246` |
| `GARDEN_LEGACY_MAX` | `2000` | `rules.ts:135` |
| `PAYOUT_MAX_POINTS` | `100000` | `rules.ts:52` |
| `COMPLETION_EXCLUDED_IDS` | `['seed_welcome_bonus','daily_min_tasks_penalty','sleep_penalty']` | `rules.ts:202-206` |
| `COMPLETION_EXCLUDED_SQL_LIST` | `'seed_welcome_bonus', 'daily_min_tasks_penalty', 'sleep_penalty'` | `rules.ts:209` |
| `DEFAULT_LIMIT` / `MAX_LIMIT`（ledger） | `200` / `500` | `ledger/index.ts:33-34` |
| `DEFAULT_LIMIT` / `MAX_LIMIT`（notifications） | `50` / `200` | `notifications/index.ts:26-27` |
| `MEMBER_MAX_LENGTH` | `20` | `ledger/index.ts:31` |
| `CLIENT_NAME_MAX_LENGTH` | `30` | `ledger/index.ts:38` |
| `ID_MAX_LENGTH` / `ID_PATTERN` | `64` / `/^[A-Za-z0-9][A-Za-z0-9_:.-]*$/` | `ledger/index.ts:35-36` |
| `REASON_MAX_LENGTH` | `60` | `ledger/[id].ts:16` |
| `MAX_NAME_LENGTH`（称呼） | `12` | `_lib/settings.ts:39` |
| `MAX_BACKGROUND_LENGTH` | `400` | `_lib/settings.ts:121` |
| `MIN/MAX_ADMIN_PASSWORD_LENGTH` | `4` / `32` | `_lib/settings.ts:177-178` |
| `DEFAULT_ADMIN_PASSWORD` | `'3398377037'` | `_lib/settings.ts:174` |
| `ADMIN_MAX_ATTEMPTS` / `ADMIN_LOCK_MS` | `5` / `300000`（5 分钟） | `_lib/settings.ts:233-236` |
| `MAX_ADJUST_ABS` | `1000000` | `admin/index.ts:47` |
| `ADMIN_ADJUSTMENT_LIMIT` | `20` | `admin/index.ts:50` |
| `MAX_SIZE`（上传） | `5242880`（5MB） | `upload.ts:20` |
| `ORPHAN_GRACE_MS` | `21600000`（6 小时） | `maintenance/orphans.ts:32` |
| `MAX_KEYS`（闲置照片返回上限） | `200` | `maintenance/orphans.ts:29` |
| `LIST_LIMIT`（R2 单页） | `500` | `maintenance/orphans.ts:26` |

### 6.5 Web 端每周计划模板（POST /api/plans 的 items 用这份）

来源 `src/config/familyRules.ts` 的 `WEEKLY_PLAN_TEMPLATE`（8 条）：

| subject | task_name | target |
|---|---|---|
| 英语 | 单词背诵 | 50 |
| 英语 | 小作文 | 1 |
| 语文 | 课文预习 | 2 |
| 语文 | 课外阅读 | 3 |
| 数学 | 口算练习 | 5 |
| 数学 | 错题订正 | 10 |
| 日常 | 22:00前睡觉 | 7 |
| 日常 | 7:00起床 | 7 |

### 6.6 积分兑现汇率（纯前端约定，后端不参与）

`POINTS_PER_YUAN = 10`（100 积分 = 10 元），`pointsToYuan(p) = round(p / 10 * 100) / 100`，文案 `100 积分 = 10 元`。`payout` 的 `amount` 是**积分**（负数），不是元。花园阳光**不可兑现**。

---

## 7. 写流水的防刷闸门（`POST /api/ledger`）

### 7.1 闸门总顺序（严格按代码顺序，后面的不会覆盖前面的）

1. body 必须是 JSON 对象 → 400 `请求体不是合法 JSON`
2. `task_id` 合法性（string / 非空 / ≤64） → 400 `task_id 非法`
3. `rule = LEDGER_TASK_RULES[task_id]` 存在？ → 403 `未知任务，不能记账`
4. `rule.serverOnly`？ → 403 `` 「${rule.name}」由服务端自动记账，不能直接提交 ``
5. 若 `rule.clientAmount`：`amount` 必须是有限 number → 400 `amount 非法`
6. 若 `rule.autoApprove !== true`：`checkLedgerRule`（**只看 window**）→ 409 窗口文案
7. 若 `rule.dailyLimit !== undefined`：**幂等预检 → 日限闸门** → 409 或 200(duplicate)
8. `INSERT OR IGNORE`；`changes === 0` → 查同 id，返回 200 duplicate，否则 500 `写入失败，请重试`

### 7.2 `dailyLimit` 分支的触发条件（关键，别理解错）

- 进入闸门的唯一条件是 **`rule.dailyLimit !== undefined`**。
- ✅ **`autoApprove` 不会绕过 `dailyLimit`。** 日限判断在 `index.ts:156-223`，完全不看 `autoApprove`；`garden:chinese` 这类既有 `autoApprove` 又有 `dailyLimit: 1` 的规则，第二次提交照样 409。
- ✅ `autoApprove` 唯一绕过的是 `checkLedgerRule`（**它只检查 `window`**，见 `rules.ts:356-365`）。而当前 36 条规则里**没有任何 autoApprove 规则带 window**，所以这条豁免目前是空转 —— 但契约上要按"autoApprove ⇒ 跳过 window 校验"来实现。
- ⚠️ **真正没有日限的是 `dailyLimit === undefined` 的规则**（共 9 条）：`eye_penalty`、`payout`、`garden:poem`、6 个 `garden_shop:*`。它们可以无限次提交，服务端不做次数校验。

### 7.3 日限计数口径

- 时间窗口：东八区 **`[当天 00:00, 次日 00:00)`**，SQL 为 `created_at >= startIso AND created_at < endIso`（`startIso`/`endIso` 是 UTC ISO）。
- 计数口径：`status != 'rejected'` ⇒ **pending 与 approved 都占额度，被驳回的不占**。
- 其余规则（非 `clientName`）：`WHERE task_id = ? AND status != 'rejected' AND created_at >= ? AND created_at < ?`，`COUNT(*) >= dailyLimit` 即拦截。

### 7.4 `user_task_exec` 的三层闸门（全部 409）

判定顺序（`perTaskName = rule.clientName === true`）：

| 层 | 条件（原文口径） | 409 文案 |
|---|---|---|
| ① 同名判重 | `task_id = 'user_task_exec' AND task_name = <即将写入的 finalName> AND status != 'rejected'` 当日 `c >= 1` | `` 「${finalName}」今天已经打过卡啦 `` |
| ② 条数粗闸门 | 当日 `user_task_exec` 条数（`status != 'rejected'`）`>= dailyLimit(20)` | `今天添加的自定义任务已经够多啦（每天最多 20 个）` |
| ③ 正分总额闸门 | 当日 `task_id = 'user_task_exec' AND status != 'rejected' AND amount > 0` 的 `SUM(amount) >= CUSTOM_TASK_DAILY_CAP(50)` | `今天的自定义任务积分已经拿满啦（每天最多 50 分）` |

- ⑦ 用的是**规范化后的 `finalName`**（trim + 折叠空白 + 截 30）⇒ `"  倒垃圾  "` 再发也 409。
- 先判 ①；① 未命中才查 ②/③（② 优先于 ③）。
- ③ **只统计 `amount > 0`**，负分自定义任务不占额度；`pending` 也占额度（否则连点可绕过）。
- 预置任务 `custom:english_words10` / `custom:poem2` 是**各自独立 task_id、各自日限 1**，同一天两条都能打卡、各 +10，**不占**那 50 分额度。

### 7.5 其余规则的日限文案

```
dailyLimit === 1  →  「${rule.name}」今天已经打过卡啦
dailyLimit >  1  →  「${rule.name}」每天最多 ${rule.dailyLimit} 次，今天用完啦
```

### 7.6 日限命中时的幂等优先

日限命中**不是立刻 409**：先看客户端有没有带**合法** `id`，若库里已存在该 id，则返回 **200** `{"id":…,"status":…,"duplicate":true}`（不报错）。

设计动机（原文注释）：网络重试/离线补发可能晚于本次上限检查 —— 第一次其实已写进库、只是响应丢了；若直接 409，客户端会回滚已经到账的阳光。

⇒ **Flutter 端重试同一 `id` 时，日限路径上拿到的是 200 duplicate，而不是 409。**

### 7.7 幂等 id 规则

| 项 | 规则 |
|---|---|
| 正则 | `/^[A-Za-z0-9][A-Za-z0-9_:.-]*$/`（首字符必须是字母或数字；后续可含 `_ : . -`） |
| 长度 | 先对**完整字符串**跑正则，通过后再 `slice(0,64)` |
| 非法 id 的后果 | **静默丢弃**，改用 `crypto.randomUUID()`；响应里的 `id` 是 UUID。客户端若拿自己那个非法 id 重试 ⇒ **重复入账**（幂等失效） |
| 合法但超长 id 的后果 | 截断到 64；两个前 64 字符相同的不同长 id 会**撞成同一条**，第二个请求返回 `duplicate: true`（静默吞掉一笔） |
| 主键冲突 | `INSERT OR IGNORE`，绝不重复入账 |
| 建议 | 客户端用 `crypto.randomUUID()` 等价物（UUID v4 小写，符合正则），并**以响应里的 `id` 为准**做后续 PATCH/DELETE |

### 7.8 `serverOnly` 与未知 `task_id`

- 未知 `task_id` 一律 **403 `未知任务，不能记账`** —— 客户端**绝不能**自造 `custom_<ts>` / `wish_<ts>` 之类的 id 直写账本；自定义任务统一用 `user_task_exec` + `task_name`。
- `serverOnly`（`seed_welcome_bonus`、`daily_min_tasks_penalty`）客户端提交一律 **403**。少了这道，`seed_welcome_bonus` 就是"每天白拿 100"（它 autoApprove + 日限 1）。

---

## 8. 花园前缀规则（家庭积分 vs 花园阳光）

### 8.1 精确前缀值（`rules.ts:305`）

```ts
GARDEN_ID_PREFIXES = ['garden:', 'garden_shop:', 'garden_legacy']
```

派生出的 SQL 条件（`GARDEN_LIKE_CLAUSE`，供 `GET /api/ledger/summary` 用）：

```sql
task_id LIKE 'garden:%' OR task_id LIKE 'garden_shop:%' OR task_id LIKE 'garden_legacy%'
```

- ⚠️ **第三项是 `'garden_legacy%'`，没有冒号**（前两项有）。`task_id LIKE 'garden_legacy%'` 会连 `garden_legacy_xxx` 一起匹配进"阳光"。
- 前缀清单**只此一处**（`rules.ts`），summary 与 admin 都从它派生，客户端必须与之逐字一致。
- 判定函数：`isGardenTaskId(taskId) = GARDEN_ID_PREFIXES.some(p => taskId.startsWith(p))`。

### 8.2 两本账的口径

| 账 | 归属规则 | 说明 |
|---|---|---|
| **家庭积分**（`family`） | `task_id` 不匹配任何花园前缀 | 含 `admin_adjust`、`payout`、全部 family 组任务 |
| **花园阳光**（`sun`） | `task_id` 匹配任一花园前缀 | 花园奖励/练习/商城购买/老余额迁移/`garden:admin_adjust` |

同一套规则也用于前端 `src/api/familyLedger.ts` 的 `isGardenTaskId`（清单一致）。

### 8.3 花园任务 id 的拼装约定（Web 端）

| 用途 | 拼法 | 例 |
|---|---|---|
| 花园打卡 | `'garden:' + 任务/练习 id` | `garden:poem`、`garden:read_aloud` |
| 商城购买 | `'garden_shop:' + 商品 id` | `garden_shop:avatar_sun` |
| 老余额迁移 | 固定 `'garden_legacy'` | — |

### 8.4 admin 的花园调整 task_id

- 家庭积分调整：`task_id = 'admin_adjust'`
- 花园阳光调整：`` task_id = `${GARDEN_ID_PREFIXES[0]}admin_adjust` `` ⇒ 实际值 **`'garden:admin_adjust'`**（**必须带花园前缀才会被算进 `sun`**，源码注释显式说明）
- 两条的 `task_name` 都是 `'管理员调整'`。

---

## 9. `GET /api/ledger/summary` —— 全量余额（专项）

**返回：`{"family": <number>, "sun": <number>}`**（空表时归一为 `0`；`SUM` 为 NULL 已处理）。

### 9.1 为什么必须用它，而不能对 `/api/ledger` 的窗口求和

`GET /api/ledger` **默认只回最近 200 条**（`DEFAULT_LIMIT = 200`，最大 500）。流水一旦超过窗口，窗口外更早的记录就被漏掉：

- 若客户端用窗口数据求和算余额 ⇒ **余额越算越少**（这正是要修的旧毛病，`summary.ts` 顶部注释原文）。
- `summary` 在 SQL 里一次性聚合**整张表**，不设窗口、不分页、不受 limit 影响。

⇒ Flutter 端的余额（家庭积分 / 花园阳光）**唯一来源**是 `GET /api/ledger/summary`（或 `POST /api/ledger/settle` / `POST /api/admin` 顺带返回的 `family`/`sun`）。窗口流水只用于列表展示。

### 9.2 聚合 SQL（原文）

```sql
SELECT
  SUM(CASE WHEN (task_id LIKE 'garden:%' OR task_id LIKE 'garden_shop:%' OR task_id LIKE 'garden_legacy%') THEN 0 ELSE amount END) AS family,
  SUM(CASE WHEN (task_id LIKE 'garden:%' OR task_id LIKE 'garden_shop:%' OR task_id LIKE 'garden_legacy%') THEN amount ELSE 0 END) AS sun
FROM family_ledger
WHERE status IS NULL OR status = 'approved'
```

**WHERE 条件原文：`WHERE status IS NULL OR status = 'approved'`**

- **`status IS NULL` 必须算**（历史老数据没有 status 字段值）。
- `pending` / `rejected` **不计入**任一余额。
- 与前端 `calcApprovedBalance` 口径一致（`(!r.status || r.status === 'approved')`）。

### 9.3 失败

| 状态码 | 触发条件 | error 原文 |
|---|---|---|
| 500 | SQL 抛错 | `统计失败` |

---

## 10. `POST /api/ledger/settle` —— 日结算（专项）

**只导出 `onRequestPost`**（不要指望 GET/PATCH/DELETE）。请求体**可空**（`{}`、无 body、或 body 不是对象都按"没带"处理）。

### 10.1 请求体

| 字段 | 类型 | 必填 | 含义 |
|---|---|---|---|
| `date` | string `'YYYY-MM-DD'` | 否 | **测试用**覆盖项：显式指定"被结算的那一天"（东八区） |

### 10.2 成功响应

```json
{ "family": 120, "sun": 45, "applied": ["daily_penalty_2026-08-19"], "day": "2026-08-19" }
```

| 字段 | 类型 | 含义 |
|---|---|---|
| `family` | number | 结算后的家庭积分余额（与 `summary` 同一条 SQL） |
| `sun` | number | 结算后的花园阳光余额 |
| `applied` | string[] | 本次**真的插进去**的记录 id 列表；重复调用会是 `[]` |
| `day` | string `'YYYY-MM-DD'` | **本次被结算的那一天**（东八区），可能不是今天 |

### 10.3 结算日 `settleDay` 选取规则

```
显式传 date（合法且 ≤ 今天）          → 用 date
否则 东八区现在 ≥ 22:00(SLEEP_DEADLINE) → 今天
否则                                    → 昨天
```

- `date` 非法（非法格式 / 不存在的日期如 `2026-02-31`） → 400 `date 必须是合法的 YYYY-MM-DD`
- `date` > 今天 → 400 `不能结算未来的日期`
- `dayIsOver = (settleDay < todayKey) || 东八区现在 ≥ 22:00`；**只有 `dayIsOver` 为真才判罚款**。
  - 所以显式传 `date=今天` 但还没到 22:00 时：不判罚款（这一天孩子还有机会完成任务/打卡），但**开户礼金仍可能写入**。

### 10.4 三项写库副作用（真实副作用，全部 `INSERT OR IGNORE`）

| 顺序 | 记录 id | `task_id` | 金额（`rule.value`） | `type` | `created_at` | 写入条件 |
|---|---|---|---|---|---|---|
| ① 开户礼金 | 固定 `seed_welcome_bonus` | `seed_welcome_bonus` | **+100** | earning | `now.toISOString()`（**不回填**） | 表里 `seed_welcome_bonus` 计数 = 0 **且** 除三条系统记录外**没有任何其它行**（即全新账号）。两个条件都满足才写 |
| ② 睡觉罚款 | `` `sleep_penalty_${settleDay}` `` | `sleep_penalty` | **−20** | spending | `beijingDayBoundsOf(settleDay).noonIso`（**回填当天东八区正午**） | `dayIsOver && canPenalize` 且当日**没有** `sleep_on_time` 的已入账记录（`status IS NULL OR status='approved'`）且当日**没有** `sleep_penalty` 记录（`status IS NULL OR status != 'rejected'`） |
| ③ 任务数罚款 | `` `daily_penalty_${settleDay}` `` | `daily_min_tasks_penalty` | **−10** | spending | 同上（当天正午） | `dayIsOver && canPenalize` 且当日"去重完成数" `< DAILY_MIN_TASKS(5)` 且当日没有 `daily_min_tasks_penalty` 记录（`status IS NULL OR status != 'rejected'`） |

- ② 的 `note` = `` `结算日 ${settleDay}：当日没有按时睡觉打卡` ``；③ 的 `note` = `` `结算日 ${settleDay}：当日完成 ${done}/${DAILY_MIN_TASKS} 个任务` ``。
- 三条一律 `status = 'approved'`、`image_url = NULL`、金额/类型/名称全取服务端规则。
- `canPenalize`：`accountFirstDay !== null && settleDay >= accountFirstDay`，其中 `accountFirstDay` = `MIN(created_at)` 所在东八区日。**账本一条流水都没有时不判罚款**（不能给"账本还不存在"的日子开罚单）。⚠️ 这段查询必须在写 seed **之前**执行，否则 seed 一落库账本"第一天"就变成今天了。

### 10.5 "今日完成数"口径（与罚款判定、UI 进度条必须一致）

```sql
SELECT COUNT(DISTINCT task_id) AS c FROM family_ledger
WHERE (status IS NULL OR status = 'approved')
  AND type = 'earning' AND amount > 0
  AND task_id NOT IN ('seed_welcome_bonus', 'daily_min_tasks_penalty', 'sleep_penalty')
  AND created_at >= ? AND created_at < ?      -- 东八区 [00:00, 次日 00:00)
```

- 东八区当日、`status IS NULL OR 'approved'`、`type='earning'` 且 `amount > 0`，按 `task_id` **去重**计数，排除三条系统记录。
- ⇒ 一天背三首诗只算 1 个；花钱/罚款不算完成；自定义任务换名字也只算 1 个（同一个 `user_task_exec`）。
- 阈值 5，罚款 10。

### 10.6 `created_at` 回填的原因（必须理解）

罚款若按真实时间落库，隔天补记的记录会落在第二天，**污染按 `created_at` 过滤的"当日完成数"**（会让第二天莫名其妙多一笔支出、并可能误判第二天完成数）。所以 ② ③ 的 `created_at` 一律回填到**被结算那天的东八区正午**（`noonIso` = 当天 00:00 + 12h，UTC ISO）。

⇒ Flutter 端若按 `created_at` 的东八区日期分组展示，这两笔会自动落到正确的那一天（正午不会跨日）。

### 10.7 为什么返回的 `day` 要当节流键

- 客户端想"每天只调一次结算"省流量，但服务端结算的是 `settleDay`，**可能是昨天**（早上打开 App 时）。
- 若客户端存"本地调用日"，那么 22:00 前后会算出不同的 `settleDay` 却共用同一个键值，导致漏结算或重复结算。
- 正确做法：把响应里的 `day` 存成本地节流键，下次比较"本地推算的 expectedSettleDay"与已存的值（Web 端实现见 `src/api/familyLedger.ts:128-170`，`localStorage` 键 `sekainook_settle_day`）。Web 端的 `expectedSettleDay(now)` 规则与后端一致：东八区 `≥22:00` 记今天，否则记昨天。
- ⚠️ **节流只为省流量，绝不能当成防重复扣的手段** —— 正确性完全由服务端幂等 id 保证。节流记录丢了最多多发一次请求。

### 10.8 失败

| 状态码 | 触发条件 | error 原文 |
|---|---|---|
| 400 | `date` 非法格式/不存在的日期 | `date 必须是合法的 YYYY-MM-DD` |
| 400 | `date` 晚于今天 | `不能结算未来的日期` |
| 500 | 任意异常（整个 handler 包在 try/catch 里） | `结算失败` |

**建议**：Flutter 端照 Web 端做法 —— 结算失败**静默**（返回 null / 不提示），绝不阻塞页面。

---

## 11. 学习计划接口（`/api/plans`）

### 11.1 `GET /api/plans?week=<label>`

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `week` | string | **是** | ISO 周标签，见第 15 节 |

返回：**裸数组** `WeeklyPlan[]`，`WHERE week_label = ? ORDER BY rowid ASC`（插入顺序）。

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | string | UUID |
| `subject` | string | 学科，如 `英语` |
| `task_name` | string | 任务名 |
| `target` | number | 目标值 |
| `current` | number | 当前进度 |
| `week_label` | string | 周标签 |
| `created_at` | string | UTC ISO |

| 状态码 | 触发条件 | error 原文 |
|---|---|---|
| 400 | 缺 `week` 或空串 | `缺少 week 参数` |

### 11.2 `POST /api/plans` —— 幂等初始化某周

请求体：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `week_label` | string | **是** | ⚠️ 注意参数名与 GET 不同（GET 用 `week`） |
| `items` | array | **是** | 非空数组。每项 `{subject, task_name, target}` |

- 逐项过滤：**只有 `subject` 和 `task_name` 都是 string 的项才会被写入**；`target` 用 `Number(item.target)`，非有限数记 `0`；`current` 一律写 `0`；`id = crypto.randomUUID()`；`created_at = now`。
- 写入用 `INSERT OR IGNORE`，唯一约束是 `UNIQUE(week_label, task_name)` ⇒ 同一周重复初始化不会重复插入（"幂等初始化"就是靠这个）。
- **成功返回 201 + 该周完整计划数组**（即使所有 items 都被 IGNORE 掉也返回 201），调用方无需再 GET。

| 状态码 | 触发条件 | error 原文 |
|---|---|---|
| 400 | body 非法 JSON | `请求体不是合法 JSON` |
| 400 | `week_label` 非 string 或空 | `week_label 非法` |
| 400 | `items` 非数组或空数组 | `items 非法` |
| 400 | 过滤后没有任何有效条目 | `items 无有效条目` |

### 11.3 `PATCH /api/plans/:id` —— 更新进度

请求体：`{"current": <number>}`。

成功：**200** `{"ok":true,"current":<服务端夹取后的真实值>}`。

服务端夹取（`clampCurrent`）：`lower = max(0, floor(value))`；若 `target` 是有限正数再 `min(lower, floor(target))`；`target` 非正/非法时只保证下限 0。

| 状态码 | 触发条件 | error 原文 |
|---|---|---|
| 400 | body 非法 JSON | `请求体不是合法 JSON` |
| 404 | id 查不到 | `记录不存在` |
| **200** | `current` **不是有限数字**（含缺字段、null、字符串） | 不报错：`{"ok":true,"current":<原值>}`，**不写库** |
| 404 | UPDATE 影响 0 行 | `记录不存在` |

⇒ Flutter 端**必须用返回值回写本地 state**，否则会出现"界面 60 / 目标 50、库里其实是 50"的错位。

---

## 12. 图片链路

### 12.1 `POST /api/upload` —— 上传到 R2

- 请求体是**原始二进制**（`ArrayBuffer`），**不是** `multipart/form-data`，**不是** JSON。**不要**用 `http.post` 的 JSON 通道。
- `Content-Type` 处理：`(header ?? '').split(';')[0].trim()` ⇒ `image/png; charset=binary` 也算通过；但必须是下表精确值。

| Content-Type | 存储扩展名 |
|---|---|
| `image/jpeg` | `.jpg` |
| `image/png` | `.png` |
| `image/webp` | `.webp` |
| `image/gif` | `.gif` |

⚠️ `image/jpg` **不在白名单**（只有 `image/jpeg`）。

校验顺序与错误：

| 顺序 | 条件 | 状态码 | error 原文 |
|---|---|---|---|
| 1 | Content-Type 不在白名单 | **415** | `仅支持 jpg / png / webp / gif 图片` |
| 2 | 读出的 body 长度为 0 | **400** | `文件为空` |
| 3 | 长度 > `5 * 1024 * 1024` | **413** | `图片不能超过 5MB` |

（注意顺序：先 MIME，再空，再超限。空文件不会报 413。）

成功：**201** `{"url":"<origin>/api/images/tasks/<ts>-<8hex>.<ext>","key":"tasks/<ts>-<8hex>.<ext>"}`

- `origin` 取**本次请求 URL 的 origin**（`new URL(context.request.url).origin`）⇒ 用自定义域名请求就返回自定义域名的 URL。Dart 端存 URL 即可，不要自己拼 origin。
- key 生成：`` `tasks/${Date.now()}-${crypto.randomUUID().slice(0, 8)}.${ext}` `` ⇒ 形如 `tasks/1755661234567-1a2b3c4d.jpg`。时间戳是**毫秒**。
- R2 里存 `httpMetadata.contentType = <上传时的 MIME>`。

失败：415/400/413 都是 `{error}` JSON。⚠️ 该 handler 没有 try/catch，R2 写入异常会冒成平台级 500（**非 JSON**）【未确认具体响应体】。

### 12.2 `GET /api/images/:key` —— 读取图片

- 路由是 catch-all `[[key]]`，`params.key` 是**字符串数组**，服务端 `join('/')` ⇒ 整个剩余路径就是 R2 key：`/api/images/tasks/1755-1a2b3c4d.jpg` → key `tasks/1755-1a2b3c4d.jpg`。
- 命中 200：body 是对象流；响应头：
  - R2 的 `httpMetadata`（含 `content-type`）
  - `etag: <object.httpEtag>`
  - `Access-Control-Allow-Origin: *`
  - `Cache-Control: public, max-age=31536000, immutable`（1 年不可变缓存；因为 key 由上传接口生成且不可变）
- 未命中 404：**纯文本 `Not Found`，不是 JSON**（`new Response('Not Found', {status:404})`）。Dart 端不要对图片请求做 JSON 解析。
- 该方法没有 try/catch ⇒ R2 异常 → 平台级 500（非 JSON）【未确认】。
- URL 编码字符（如 `%2F`）的解码行为**【未确认】**；按"key 里只有 `[A-Za-z0-9/._-]`"来用即可（上传接口生成的 key 天然满足）。

---

## 13. 通知接口（`/api/notifications`）

**通知没有创建接口** —— 只能由服务端在记账/审批处写入（`_lib/notifications.ts`）。前端只读 + 标已读。

### 13.1 `GET /api/notifications?audience=&limit=`

| 参数 | 类型 | 必填 | 默认/边界 |
|---|---|---|---|
| `audience` | `'parent' \| 'child'` | **是** | 非法/缺失 → 400 |
| `limit` | number | 否 | 默认 50，上限 200；解析规则与 ledger 完全一样（非法 → 50；`limit=0.5` → `LIMIT 0` → `items: []`） |

成功（**200**，包括降级情况）：

```json
{ "items": [ …NotificationRow… ], "unreadCount": 3, "ready": true }
```

`items` 按 `created_at DESC, rowid DESC` 排序。**`items` 里不包含 `dedupe_key`**（SELECT 列表没有它）。

| 字段 | 类型 | 说明 |
|---|---|---|
| `items[].id` | string | UUID |
| `items[].audience` | string | `parent` / `child` |
| `items[].type` | string | 见 13.4 |
| `items[].title` | string | 标题（写入时截断 120） |
| `items[].body` | string \| null | 正文（截断 200） |
| `items[].link` | string \| null | 点击跳转路径，如 `/family`（截断 200） |
| `items[].status` | `'unread' \| 'read'` | |
| `items[].created_at` | string | UTC ISO |
| `items[].read_at` | string \| null | |
| `unreadCount` | number | 该格信箱 `status = 'unread'` 的总数（**不只是本页**） |
| `ready` | boolean | `false` = 通知表没迁移（0003 未执行），此时 `items: []`、`unreadCount: 0`，**HTTP 仍是 200** |

| 状态码 | 触发条件 | error 原文 |
|---|---|---|
| 400 | `audience` 缺失或不是 `parent`/`child` | `audience 非法（应为 parent 或 child）` |
| 200 + `ready:false` | 查询抛错（最常见：0003 未迁移） | 无 error 字段 |

⇒ **`ready:false` 是降级信号，不是错误**：UI 按"空信箱"渲染，不要弹错误。

### 13.2 `PATCH /api/notifications/:id`

请求体：`{"status":"read"|"unread"}`。

- `read` → `read_at = now()`；`unread` → `read_at = NULL`。
- 成功 **200** `{"ok":true}`。

| 状态码 | 触发条件 | error 原文 |
|---|---|---|
| 400 | body 非法 JSON | `请求体不是合法 JSON` |
| 400 | `status` 非 string 或不在 `read`/`unread` | `status 非法（应为 read 或 unread）` |
| 404 | UPDATE 影响 0 行（id 不存在） | `通知不存在` |
| 503 | 查询抛错（表未迁移） | `通知表尚未就绪，请先执行数据库迁移` |

### 13.3 `POST /api/notifications/read-all`

请求体：`{"audience":"parent"|"child"}`。把该格信箱所有 `unread` 改成 `read`。

成功 **200** `{"ok":true,"updated":<本次改为已读的条数>}`（无未读时 `updated: 0`，仍是 `ok:true`）。

| 状态码 | 触发条件 | error 原文 |
|---|---|---|
| 400 | body 非法 JSON | `请求体不是合法 JSON` |
| 400 | `audience` 非法/缺失 | `audience 非法（应为 parent 或 child）` |
| 503 | 查询抛错 | `通知表尚未就绪，请先执行数据库迁移` |

### 13.4 服务端实际会写入的通知类型（穷举）

| `type` | `audience` | 触发点 | `dedupe_key` |
|---|---|---|---|
| `checkin_pending` | `parent` | `POST /api/ledger` 写成 pending | `ledger:${id}:pending` |
| `approved` | `child` | `PATCH /api/ledger/:id` → approved（状态变化时） | `ledger:${id}:approved:${旧状态}` |
| `rejected` | `child` | `PATCH` → rejected（状态变化时） | `ledger:${id}:rejected:${旧状态}` |
| `resubmitted` | `parent` | `PATCH` → pending（状态变化时） | `ledger:${id}:resubmit:${旧状态}` |

- ⚠️ Web 端类型定义里还列了 `recorded` / `payout`，但**后端源码里没有任何地方写这两种**（已全仓核实）⇒ Flutter 端不需要为它们做特殊渲染，但解析时仍要能容忍未知 `type`。
- `dedupe_key` 有 **UNIQUE 索引**：同一个 key 只保留第一条（`INSERT OR IGNORE`）。`dedupe_key` 为 NULL 时 SQLite 不参与唯一性判断 ⇒ 每次都留一条。
- 写入时统一截断：`type` 40、`title` 120、`body` 200、`link` 200、`dedupeKey` 160；空字符串归一为 NULL（`type` 缺失时回退 `'unknown'`，`title` 缺失时回退 `''`）。
- 单次 `db.batch` 最多 20 条（`rows.slice(0, 20)`）。
- 写通知失败**绝不**影响主业务（内部 try/catch）。

---

## 14. 设置接口（`/api/settings`）

两类设置共用一张 `settings` 键值表：家庭称呼 + 全局背景图。

### 14.1 `GET /api/settings`

成功 **200**：

```json
{ "names": {"momCall":"妈妈","momNickname":"","kidCall":"女儿","kidNickname":""},
  "background": "", "ready": true }
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `names.momCall` | string | 女儿对妈妈的称呼，默认 `妈妈` |
| `names.momNickname` | string | 女儿给妈妈的昵称，默认空串（显示时**昵称优先**） |
| `names.kidCall` | string | 妈妈对女儿的称呼，默认 `女儿` |
| `names.kidNickname` | string | 妈妈给女儿的昵称，默认空串 |
| `background` | string | 全局背景图 URL，`''` = 没设 |
| `ready` | boolean | `false` = settings 表没迁移 |

⚠️ **`ready` 实际上恒为 `true`**：`readFamilyNames` / `readBackground` 各自内部吞掉异常并返回默认值，外层 catch 几乎不可能触发（除非 `Response.json` 本身抛错）。**【未确认】** 是否存在能让 `ready:false` 的真实路径 —— Flutter 端按"解析失败才降级"处理，不要依赖 `ready`。

### 14.2 `PATCH /api/settings` —— 真部分更新

请求体：`Partial<FamilyNames> & { background?: string }`。

- 只处理**出现在 `source` 里的键**（`if (!(key in source)) continue`）⇒ **必须只提交自己要改的字段**。Web 端有明确设计理由：女儿改妈妈的称呼、妈妈改女儿的称呼，各改各的那一半；全量回写会覆盖对方刚改的值。
- 返回 **200**，body 与 GET 同形（`{names, background, ready}`，`names` 是**保存后的完整对象**）。

| 状态码 | 触发条件 | error 原文 |
|---|---|---|
| 400 | body 非法 JSON | `请求体不是合法 JSON` |
| 400 | body 不是对象（含数组/`null`） | `请求体必须是对象` |
| 400 | 某个称呼键存在但值不是 string（含 `null`） | `称呼必须是文字` |
| 400 | 称呼 `trim().length > 12` | `称呼最多 12 个字` |
| 400 | `background` 存在但 `sanitizeBackground` 返回 null | `背景图地址不合法（只能是本站上传的图片，且不超过 400 个字符）` |
| 400 | 有效改动一个都没有（只带未知键，或空对象） | `没有要保存的设置` |
| 503 | 写库抛错（settings 表未迁移） | `设置表尚未就绪，请先执行数据库迁移` |

**称呼的清洗语义**（`sanitizeName`）：

| 输入 | 存库结果 |
|---|---|
| 非 string / 缺失 | 该键不写（缺失）或 400（显式传了非 string） |
| `trim().slice(0,12)` 后非空 | 存该值 |
| 空/纯空白，键是 `momCall`/`kidCall` | **存默认值** `妈妈` / `女儿`（空串 ≠ 清空） |
| 空/纯空白，键是 `momNickname`/`kidNickname` | **存空串 `''`**（= 真的清掉昵称） |

⇒ Flutter 端"清空称呼输入框"对 call 键等于恢复默认，对 nickname 键才是清除。

**背景图的清洗语义**（`sanitizeBackground`）：

| 输入 | 结果 |
|---|---|
| 非 string（含 null） | `null` → 400 |
| `trim().length > 400` | `null` → 400 |
| 非空但**不包含** `/api/images/` | `null` → 400（防外链） |
| 空串 / 纯空白 | `''` → **删除该键**（恢复纯色背景） |
| 合法站内 URL | 存值 |

### 14.3 通知文案里的称呼读取规则

- 读取 `WHERE key IN ('mom_call','mom_nickname','kid_call','kid_nickname')`；表不存在/查询失败 → 回退默认值（不影响记账）。
- 显示名：`displayName(names, who) = (nickname || call || 默认).trim() || 默认`；`who='mom'` 取 `momNickname → momCall → '妈妈'`；`who='kid'` 取 `kidNickname → kidCall → '女儿'`。

---

## 15. 管理员接口（`POST /api/admin`）—— 唯一密码校验点

**只有一个 POST 入口**，靠 `action` 分流。**没有 GET/PATCH/DELETE**。

### 15.1 请求体

| 字段 | 类型 | 必填 | 含义 |
|---|---|---|---|
| `password` | string | **是** | 服务端 `trim()` 后比较；空串直接算错。任何 action 都要带 |
| `action` | string | 否 | `'verify'`（**默认**，缺失/非 string 时使用）/ `'adjust'` / `'password'` / `'adjustments'` |
| `family` | number | 仅 `adjust` | 家庭积分**目标值**（整数，会 `Math.round`，±1000000 内） |
| `sun` | number | 仅 `adjust` | 花园阳光**目标值**（同上） |
| `newPassword` | string | 仅 `password` | 新密码，4–32 位 |

### 15.2 校验顺序（严格）

1. body 必须是 JSON 对象 → 400 `请求体不是合法 JSON` / `请求体必须是对象`
2. 读锁定状态；`lockRemainingMs > 0` → **429**（**连正确密码也拒绝**，根本不比较密码）
3. 读当前密码（失败时回退出厂密码，见 15.5）
4. `!password || password !== stored` → 记一次失败：
   - 本次失败后达到 5 次 → **429** `密码错误次数太多，请等 ${seconds} 秒后再试` + `lockRemainingMs`
   - 否则 → **401** `管理员密码不对，还可以试 ${attemptsLeft} 次` + `attemptsLeft`
5. 密码正确 → 清空失败计数与锁定 → 按 `action` 分流

### 15.3 成功响应（都带最新余额）

| action | 200 Body |
|---|---|
| `verify`（含**未知 action**） | `{"family":…, "sun":…}` |
| `password` | `{"family":…, "sun":…, "passwordChanged":true}` |
| `adjust` | `{"family":…, "sun":…, "changed":["家庭积分 20 → 500","花园阳光 0 → 30"]}` |
| `adjustments` | `{"family":…, "sun":…, "adjustments":[{"id":"…","ledger":"family"\|"sun","amount":-30,"note":"…","createdAt":"<ISO>"}]}`（最多 20 条，按 `created_at DESC, rowid DESC`） |

- `changed` 文案：`` `家庭积分 ${before} → ${target}` `` / `` `花园阳光 ${before} → ${target}` ``。
- `adjustments[].note`：DB 为 NULL 时归一为 `''`；`ledger` 由 `task_id === 'garden:admin_adjust'` 判定为 `'sun'`，否则 `'family'`。
- ⚠️ **未知 `action` 静默按 `verify` 处理并返回 200** —— Dart 端要自己枚举校验，不能靠服务端报错。
- `adjustments` 只查 `task_id IN ('admin_adjust','garden:admin_adjust')`。

### 15.4 失败响应（全部原文）

| 状态码 | 触发条件 | Body |
|---|---|---|
| 400 | body 非法 JSON | `{"error":"请求体不是合法 JSON"}` |
| 400 | body 非对象 | `{"error":"请求体必须是对象"}` |
| **429** | 还在锁定期（请求一开始就判） | `{"error":"密码错误次数太多，请等 ${seconds} 秒后再试","lockRemainingMs":<ms>}`（`seconds = max(1, ceil(ms/1000))`，**没有** `attemptsLeft`） |
| **429** | 本次失败刚好触发锁定 | 同上，`lockRemainingMs` 固定为 `300000` |
| **401** | 密码错且未触发锁定 | `{"error":"管理员密码不对，还可以试 ${n} 次","attemptsLeft":${n}}`，`n = 5 - 本次失败后的累计次数`（$n \in \{4,3,2,1\}$） |
| 400 | `action='password'` 且 `newPassword` 清洗后为 null | `{"error":"新密码需为 4-32 位"}` |
| 400 | `action='adjust'` 且有 `family` 键但值非法（非 number/非有限/`|round| > 1000000`） | `{"error":"家庭积分需要是 ±1000000 之间的整数"}` |
| 400 | 同上，`sun` 键 | `{"error":"花园阳光需要是 ±1000000 之间的整数"}` |
| 400 | `action='adjust'` 但 `family`/`sun` 两个键都没带 | `{"error":"没有要修改的积分"}` |
| 503 | 读密码抛错 | `{"error":"设置表尚未就绪，请先执行数据库迁移"}`（**实际不可达**，见 15.5） |
| 500 | action 处理过程中任意异常 | `{"error":"操作失败，请重试"}` |

⚠️ `adjust` 的键存在性用 `'family' in body`：**省略该键 = 不改这本账**；显式传 `null` / 非数字 = 400。传 `0` 是合法目标值（会把余额改成 0）。

### 15.5 出厂密码与锁定策略

| 项 | 值 / 行为 |
|---|---|
| 出厂密码 | `3398377037`（`DEFAULT_ADMIN_PASSWORD`），存在 `settings.admin_password` 里；没设过就用它 |
| 密码长度 | 4–32（自己改时）。出厂那串 10 位 |
| 试错节流 | 连续错 **5** 次 → 锁 **5 分钟**（`ADMIN_LOCK_MS = 300000`） |
| 锁定期内 | 任何请求（含正确密码）一律 429，不比较密码 |
| 锁定触发时 | `admin_fail_count` 归 **0**、`admin_lock_until = now + 300000` ⇒ 解锁后重新获得 5 次机会 |
| 成功一次 | 清空 `admin_fail_count` 与 `admin_lock_until` 两行 |
| 状态存放 | 同 `settings` 表，键 `admin_fail_count`（字符串十进制整数）/ `admin_lock_until`（毫秒时间戳字符串） |
| 表不可用 | `readAdminLock` / `readAdminPassword` 内部吞异常 ⇒ 当作"没锁 + 出厂密码"（不能因为库的问题把人锁在门外） |
| `503` 路径说明 | `readAdminPassword` 自带 try/catch 并回退出厂密码，所以外层那个 `503` 分支**实际上不可达**【未确认】；但 `action='password'` 时 `writeAdminPassword` 会抛 ⇒ 外层 catch → **500 `操作失败，请重试`** |

### 15.6 adjust 的差额记账语义（重要）

余额是流水聚合出来的（没有单独余额字段可改），所以"改成目标值"是**按差额补记一条流水**：

```
delta = target - 当前余额
delta === 0 → 什么都不写（⇒ 重复提交天然幂等，不会再写第二条）
delta !== 0 → INSERT 一条 approved 流水：
  id        = `${taskId}_${Date.now()}_${Math.random().toString(36).slice(2,8)}`
  task_id   = 'admin_adjust'（家庭）| 'garden:admin_adjust'（阳光）
  task_name = '管理员调整'
  type      = delta > 0 ? 'earning' : 'spending'
  amount    = delta
  note      = `管理员把家庭积分改成 ${target}（原来 ${before}）` | `管理员把花园阳光改成 ${target}（原来 ${before}）`
  status    = 'approved'
  created_at= now（UTC ISO）
```

- `family` 与 `sun` 都基于**同一次读到的 `before`** 计算（两本账互不影响，安全）。
- 不写通知（`admin/index.ts` 没有引用 `pushNotifications`）。
- 留痕可审计，可在账本页用 `DELETE /api/ledger/:id` 撤销（Web 端就是这么做的）。
- `MAX_ADJUST_ABS = 1000000` 是单次调整绝对值上限（防手滑多打几位）。

---

## 16. 闲置照片维护接口（`/api/maintenance/orphans`）

「闲置照片」定义：R2 中 `tasks/` 前缀下存在、但**没有任何 `family_ledger.image_url` 引用**它、且写入时间**早于 6 小时前**的对象。设置页的全局背景图也算"被引用"（从 `settings.background` 解析 key 并加入引用集合）。

### 16.1 `GET /api/maintenance/orphans`（只读 dry run，绝不删除）

成功 **200**：

| 字段 | 类型 | 说明 |
|---|---|---|
| `total` | number | R2 `tasks/` 前缀下的对象**总数**（全量，分页列举到 `truncated === false`，单页 500） |
| `referenced` | number | **`total - 可清理闲置数`**（⇒ 包含"6 小时保护期内的新图"，所以界面上"共 N / M 还在用 / K 闲置"三个数能对上） |
| `orphans` | number | 可清理的闲置照片数（全量计数） |
| `keys` | string[] | 闲置 key 列表，**最多前 200 个**（`MAX_KEYS = 200`），但 `orphans` 计数是全量 |

| 状态码 | 触发条件 | error 原文 |
|---|---|---|
| 500 | 存储列举或数据库查询异常 | `扫描闲置照片失败（存储列举或数据库查询异常）` |

其他细节：

- 只扫 `tasks/` 前缀，**其他前缀一律不碰**。
- 对象写入时间的来源优先级：R2 的 `uploaded`（存储侧事实）→ 兜底从 key 前缀解析 `/^(\d{10,16})-/`。
- **拿不到写入时间、或时间在未来（时钟异常）→ 一律不删**（保守）。
- 报出的数量就是点"清理"真会删掉的数量。

### 16.2 `POST /api/maintenance/orphans`（危险操作）

请求体：必须 `{"confirm": true}`（**严格布尔 `true`**；`"true"` / `1` 都不行）。

成功 **200**：`{"deleted":<成功删除数>,"failed":<失败数>,"keys":[<已删除 key，最多 200>]}`。逐对象删除，单个失败只计入 `failed`，不影响整体。

| 状态码 | 触发条件 | error 原文 |
|---|---|---|
| 400 | body 非法 JSON | `请求体不是合法 JSON` |
| 400 | `confirm !== true` | `危险操作：请在请求体中传入 {"confirm": true} 以确认清理闲置照片` |
| 500 | 扫描异常 | `扫描闲置照片失败（存储列举或数据库查询异常）` |

⚠️ 删除时**不受 200 上限影响**：扫描出的全部闲置 key 都会被尝试删除，`keys` 只是回显前 200 个。

---

## 17. 数据表结构（4 张表，含全部索引与唯一约束）

### 17.1 `family_ledger`（`0001_init.sql` + `0002_ledger_member.sql`）

| 列 | 类型 | 约束/默认 | 说明 |
|---|---|---|---|
| `id` | TEXT | **PRIMARY KEY** | 客户端幂等键或 UUID |
| `task_id` | TEXT | NOT NULL | 任务 id |
| `task_name` | TEXT | NOT NULL | 显示名 |
| `type` | TEXT | NOT NULL | `earning` / `spending` |
| `amount` | INTEGER | NOT NULL | 有符号整数 |
| `note` | TEXT | 可空 | 备注 |
| `image_url` | TEXT | 可空 | `/api/images/<key>` 形式 |
| `status` | TEXT | NOT NULL **DEFAULT `'approved'`** | `pending`/`approved`/`rejected`；API 写入时总是显式赋值 |
| `created_at` | TEXT | NOT NULL | UTC ISO |
| `member` | TEXT | 可空（**0002 新增**） | 历史遗留，多成员功能已下线 |

索引：`idx_family_ledger_status(status)`、`idx_family_ledger_created_at(created_at)`、`idx_family_ledger_member(member)`。无额外唯一约束（`id` 主键即幂等键）。

### 17.2 `weekly_plans`（`0001_init.sql`）

| 列 | 类型 | 约束/默认 |
|---|---|---|
| `id` | TEXT | **PRIMARY KEY** |
| `subject` | TEXT | NOT NULL |
| `task_name` | TEXT | NOT NULL |
| `target` | INTEGER | NOT NULL |
| `current` | INTEGER | NOT NULL DEFAULT `0` |
| `week_label` | TEXT | NOT NULL |
| `created_at` | TEXT | NOT NULL |

索引：`idx_weekly_plans_week(week_label)`；**UNIQUE** `idx_weekly_plans_week_task(week_label, task_name)`（"同一周内任务名唯一"，保证初始化幂等）。

### 17.3 `notifications`（`0003_notifications.sql`）

| 列 | 类型 | 约束/默认 |
|---|---|---|
| `id` | TEXT | **PRIMARY KEY** |
| `audience` | TEXT | NOT NULL（`parent`/`child`） |
| `type` | TEXT | NOT NULL |
| `title` | TEXT | NOT NULL |
| `body` | TEXT | 可空 |
| `link` | TEXT | 可空 |
| `dedupe_key` | TEXT | 可空；**UNIQUE**（NULL 不参与唯一性判断） |
| `status` | TEXT | NOT NULL DEFAULT `'unread'` |
| `created_at` | TEXT | NOT NULL |
| `read_at` | TEXT | 可空 |

索引：**UNIQUE** `idx_notifications_dedupe(dedupe_key)`、`idx_notifications_audience_created(audience, created_at DESC)`、`idx_notifications_audience_status(audience, status)`。

### 17.4 `settings`（`0004_settings.sql`）

| 列 | 类型 | 约束 |
|---|---|---|
| `key` | TEXT | **PRIMARY KEY** |
| `value` | TEXT | NOT NULL |
| `updated_at` | TEXT | NOT NULL |

无额外索引。

### 17.5 `settings` 表已用到的 key 全清单（8 个，穷举）

| key | 写入者 | 含义 |
|---|---|---|
| `mom_call` | `PATCH /api/settings`（`names.momCall`） | 女儿对妈妈的称呼 |
| `mom_nickname` | `PATCH /api/settings`（`names.momNickname`） | 妈妈昵称 |
| `kid_call` | `PATCH /api/settings`（`names.kidCall`） | 妈妈对女儿的称呼 |
| `kid_nickname` | `PATCH /api/settings`（`names.kidNickname`） | 女儿昵称 |
| `background` | `PATCH /api/settings`（`background`） | 全局背景图 URL；空串时该行被 **DELETE** |
| `admin_password` | `POST /api/admin`（`action:'password'`） | 管理员密码 |
| `admin_fail_count` | `POST /api/admin` 密码错误时 | 连续失败次数（十进制字符串） |
| `admin_lock_until` | `POST /api/admin` 密码错误时 | 解锁时间（毫秒时间戳字符串，空/0 = 没锁） |

写入方式一律 `INSERT … ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`。

---

## 18. 周标签规约（`week_label`）

- **格式**：`<ISO 周年>-W<两位周数>`，例 `2026-W34`（`src/utils/week.ts:10-15`）。
- **必须是客户端生成**：后端 `weekly_plans.week_label` 是纯 TEXT，**没有任何生成或校验逻辑** —— `GET /api/plans` 缺 `week` 直接 400，`POST /api/plans` 只校验非空字符串。服务端不会替你算。
- **必须是 ISO 周年（ISO week-year），不是日历年**：1 月 1 日常常落在上一年的第 52/53 周（例如 2027-01-01 可能是 `2026-W53`），12 月末也可能落进下一年的 `W01`。用日历年拼 `2027-W01` 会和 Web 端算出**不同的周**，导致同一周出现两份计划。
- **周数必须补零到 2 位**：`W01`、`W34`；补零规则来自 `String(week).padStart(2,'0')`。
- **参数名不一致（务必注意）**：
  | 接口 | 参数名 | 位置 |
  |---|---|---|
  | `GET /api/plans` | **`week`** | query |
  | `POST /api/plans` | **`week_label`** | body |
- Dart 实现提示：Dart 核心库**没有** ISO 周 API（`DateTime` 没有 `weekOfYear`）。需要自己按 ISO 8601 算：`isoWeekYear` 取"该周所属的星期四所在的年"，`isoWeek` 取该周序号。**不要**用 `date.difference(...).inDays ~/ 7` 这类近似算法。
- 时间基准：按**东八区**当天算周（与日限/结算同一时区口径）。

---

## 19. Dart 客户端易踩的坑（读码时发现的所有反直觉细节，编号清单）

1. **全站无鉴权**：除 `POST /api/admin` 的 `password` 字段外，任何请求都不要加凭据；`/api/upload` 也不受保护（那句 `_middleware` 注释是过期的，仓库里没有该文件）。
2. `GET /api/ledger` 返回**裸数组**，不是 `{items:[…]}`；`GET /api/plans` 同样返回裸数组。
3. **别拿 `/api/ledger` 的窗口数据求和算余额**，会越算越少；余额只认 `/api/ledger/summary`。
4. `?status=`（空串）等于**不过滤**；`?status=null` 会按字符串 `"null"` 过滤，返回 `[]`。
5. `status` 传非法值**不报错**，静默返回 `[]` —— 别指望 400 帮你发现拼写错误。
6. `?limit=0.5` → `Math.floor` = 0 → `LIMIT 0` → **返回空数组**；而 `?limit=0` → 回退默认 200。同一个"0 附近"的输入给出完全相反的结果。
7. `limit` 的非法值（NaN、负数、`Infinity`）**静默回退默认值**，不报错；客户端传 1000 会被静默截成 500，别用它做"全量拉取"。
8. `since` 是 `created_at > ?` 的**严格大于**，且是字符串比较 ⇒ 同一毫秒的多条记录会被增量拉取漏掉；要用 `>=` 语义需客户端自己去重。
9. `member` 列在**没跑 0002 迁移**的库上根本不存在；解析账本记录时 `member` 必须按"可能缺失"处理。
10. `status` 可能是 **null**（历史数据），必须当作"已入账"；不要只判 `== 'approved'`。
11. `POST /api/ledger` 新建返回 **201**，幂等命中返回 **200 + `duplicate:true`** —— 两者都是成功，客户端要一起处理。
12. 客户端传的 `status` 与 `type` **永远被忽略**（`type` 只在 `user_task_exec` 金额为负时由服务端推导为 `spending`）。
13. 客户端传的 `task_name` 默认被忽略；**只有 `user_task_exec` 采纳**（其余任务名一律由服务端规则覆盖）。
14. 客户端传的 `amount` 默认被忽略；只有声明了 `clientAmount` 的规则采纳，且**超范围是夹取不是报错**（传 9999 记 +200，传 -50 记 0）。
15. `user_task_exec` / `garden_legacy` / `payout` / 两条预置任务**必须传 `amount`**，否则 400 `amount 非法`（不能省字段）。
16. 两条预置任务（`custom:english_words10` / `custom:poem2`）的 `amount` **只校验不采纳**：传 100 也只加 10 分。
17. 未知 `task_id` 一律 **403**：绝不能自造 `custom_<ts>` / `wish_<ts>` 直写账本；自定义任务统一用 `user_task_exec`。
18. `serverOnly` 任务（`seed_welcome_bonus` / `daily_min_tasks_penalty`）客户端提交一律 403。
19. 幂等 id 的正则要求首字符是**字母或数字**：`-abc`、`_abc`、`:abc` 都非法，会被**静默替换成 UUID** ⇒ 重试就重复入账。
20. 幂等 id 的**正则先对完整字符串校验、再 `slice(0,64)`**：两个前 64 字符相同的长 id 会撞成同一条，第二个请求被当作 `duplicate` 静默吞掉。
21. 幂等 id 建议直接用 UUID v4（小写）生成，并**以响应里的 `id` 为准**做后续 PATCH/DELETE。
22. 日限判定发生在**写入之前**，`pending` 也占额度，只有 `rejected` 不占。
23. 日限的"当天"是**东八区 [00:00, 次日 00:00)**，不是 UTC 日；用设备本地时区算会错。
24. 日限命中路径上，如果客户端带了**已存在**的合法 id，返回的是 **200 duplicate 而不是 409** —— 重试逻辑要把这种 200 当成功。
25. `?status=pending` 只能看到**最近 200 条窗口内**的 pending，流水多了会漏 ⇒ 待审批列表不能只靠它（要配合 `limit` 或按时间翻页）。
26. **没有 `dailyLimit` 的规则完全没有日限**：`eye_penalty`、`payout`、`garden:poem`、6 个 `garden_shop:*` 都可以无限次提交；`payout` 还是 autoApprove ⇒ 无限兑现流水，UI 必须自己防连点。
27. **`autoApprove` 不绕过 `dailyLimit`**（常见误解）：日限判断完全不看 autoApprove。autoApprove 只跳过 `checkLedgerRule`，而它**只检查 window**，且当前没有任何 autoApprove 规则带 window ⇒ 该豁免目前是空转。真正决定"有没有日限"的是 `dailyLimit === undefined`。
28. 花园奖励/商城购买/兑现写库即 `approved`（`autoApprove`），**不给家长发通知**；只有写成 `pending` 才发 `checkin_pending`。
29. `note` 与 `image_url` 在服务端**不截断、无上限**，长度靠客户端自律。
30. `PATCH /api/ledger/:id` 的 `reason` 只在 `rejected` 且状态**确实变化**时进入通知；状态没变不会重复通知（但依旧 200 `ok`）；`reason` 截断 60 字符。
31. `DELETE /api/ledger/:id` 会**顺带删除 R2 图片**（前提是 `image_url` 的 pathname 以 `/api/images/` 开头），且 R2 删除失败不阻断删流水 ⇒ 别以为"只删了记录"。
32. 家庭积分 / 花园阳光的划分靠 `task_id` 前缀，**第三个前缀是 `garden_legacy`（无冒号）且 SQL 里是 `LIKE 'garden_legacy%'`** ⇒ `garden_legacy_xxx` 也会算作阳光；客户端 `startsWith` 判断语义要一致。
33. admin 的花园调整 task_id 是 **`garden:admin_adjust`**（带花园前缀），家庭的是 `admin_adjust`；写错就记错账本。
34. `GET /api/settings` 的 `ready` **几乎恒为 true**（两个读取 helper 内部都吞异常并回默认值），不要用它判断"表已迁移"。
35. 通知的 `ready:false` **是可达的**（HTTP 200 + 空数组）⇒ 按空信箱渲染，不要弹错误。
36. `PATCH /api/settings` 是**真部分更新**：只提交要改的键。把四个称呼一起回写会覆盖对方刚改的另一半。
37. 称呼的空串语义不对称：`momCall`/`kidCall` 传空串会被存成默认 `妈妈`/`女儿`（**不是清空**）；`momNickname`/`kidNickname` 传空串**真的清空**（存 `''`）。
38. 称呼键传 `null` 是 400 `称呼必须是文字`（不是"清空"）；只有空**字符串**才是合法输入。
39. `background` 必须是含 `/api/images/` 的站内地址或空串；外链、超过 400 字符、非 string 都是 400；**空串 = 删除背景图行**。
40. `PATCH /api/settings` 只带未知键（或空对象）→ 400 `没有要保存的设置`，不是"静默成功"。
41. 通知列表**不返回 `dedupe_key`**（SELECT 里没有它）；需要幂等键做本地去重的话拿不到。
42. 通知的 `limit` 与账本同款坑：`limit=0.5` → 0 条；默认 50、上限 200。
43. `PATCH /api/notifications/:id` 标已读会写 `read_at = now`，标回未读会把 `read_at` 清成 **null**。
44. `POST /api/notifications/read-all` 的 `updated` 是"本次改为已读的条数"，0 也返回 `ok:true`；表未迁移时是 **503**（而 GET 同情况下是 200 + `ready:false`）。
45. admin 的 `attemptsLeft` **只在 401 出现**，429 只有 `lockRemainingMs`；**锁定期内连正确密码也会 429**（服务端连密码都不比）。
46. admin 的**未知 `action` 静默按 `verify` 处理并返回 200** —— Dart 端必须自己枚举校验 action。
47. `action:'adjust'` 里 `family`/`sun` 的**省略 = 不改**，显式 `null` = 400；`0` 是合法目标值（余额会被改成 0）。
48. `adjust` 是"改成目标值 + 按差额记一条流水"：差额为 0 时**什么都不写** ⇒ 重复提交天然幂等。
49. admin 返回的调整记录字段是 **`createdAt`（camelCase）**，而账本记录里是 `created_at`（snake_case）—— 同一个人写的两个接口不统一。
50. admin 调整**不发通知**；撤销要走 `DELETE /api/ledger/:id`。
51. `POST /api/upload` 必须是**原始二进制** + 精确 `Content-Type`（`image/jpeg` 可以，`image/jpg` **不行**）；不要用 multipart，也不要走 JSON 通道。
52. 上传的校验顺序是 Content-Type(415) → 空文件(400) → 超 5MB(413)；空文件**不会**报 413。
53. `GET /api/images/:key` 的 404 是**纯文本 `Not Found`** ⇒ 图片请求路径上不要做 JSON 解析；成功响应带 `Cache-Control: public, max-age=31536000, immutable`（key 不可变，可以放心长缓存）。
54. 图片 key 是 `tasks/<13位毫秒>-<8位hex>.<ext>`；URL 里 `/api/images/` 之后的**整个剩余路径**（可含多级 `/`）都是 key。
55. 上传返回的 `url` origin 取**本次请求的 origin**，客户端不要自己拼域名。
56. 有若干接口**没有 try/catch**（`GET/POST /api/ledger`、`GET /api/images/:key`、`POST /api/upload`）⇒ 底层异常会返回**非 JSON** 的 500；Dart 的响应解析必须容忍非 JSON 错误体（先判 `Content-Type` 或 try/catch 解析）。
57. `POST /api/ledger/settle` 的 body **可空**（`{}` 甚至无 body 都能过）；但 `GET /api/ledger/settle` 一定不成功（预期 405）。
58. settle 返回的 `day` **可能是昨天**，节流键必须存 `day`（不是本地当天），否则 22:00 前后会漏结算/重复结算。
59. settle 的 `applied` 里是**记录 id**（`seed_welcome_bonus` / `sleep_penalty_<day>` / `daily_penalty_<day>`），重复调用是 `[]`；不要把它当 task_id 用。
60. 结算失败要**静默**（不要弹错误挡住页面）；正确性由服务端幂等 id 保证，本地节流只为省流量。
61. `day` 的日期字符串是**东八区**日期，而记录 `created_at` 是 UTC ISO —— 展示"罚款发生在哪天"时要用回填后的 `created_at` 换算东八区日。
62. `GET /api/plans` **必须带 `week`**，缺参数 400；返回裸数组。
63. 周标签参数名不一致：`GET` 用 **`week`**，`POST` 用 **`week_label`**。
64. `POST /api/plans` 只有在 `subject` 与 `task_name` **都是 string** 时才写入该项；`target` 非数字记 0；`current` 一律 0；全部项被 IGNORE 也返回 **201**。
65. `PATCH /api/plans/:id` 的 `current` 不是有限数字时返回 **200 + 原值**（不写库、不报错）⇒ 必须用返回值回写 UI。
66. `current` 会被夹到 `[0, target]`；`target <= 0` 时只有下限 0 ⇒ 本地乐观 +1 会和服务端不一致，必须以返回值为准。
67. 周标签必须用 **ISO 周年**：Dart 无原生 ISO week API，必须自己实现（`isoWeekYear` = 该周星期四所在年）；用日历年会在跨年周产生两份计划。
68. 时间窗 `sleep_on_time` 是 **19:00–22:00 闭区间**（`minutes > end` 才拒绝），按东八区；**不支持跨零点窗口**。
69. 任务的 `dailyLimit` 与 `window` 要在 UI 上先拦一道（服务端只做兜底），否则用户会看到一堆 409。
70. `CUSTOM_TASK_DAILY_CAP = 50` **只统计 `user_task_exec` 的正分**；两条预置任务独立日限 1、各 +10、**不占**这 50 分额度。
71. 自定义任务的同名判重用**规范化后的名字**（trim + 折叠连续空白 + 截 30）⇒ 用带空格的名字重发照样 409；本地判重要用同一个规范化函数。
72. 自定义任务金额为负时服务端会记成 `spending`（保持 `earning ⇒ amount>0`、`spending ⇒ amount<0` 的不变量）；本地按 `type` 判正负号时不能只看返回的 `type`，还要看 `amount`。
73. `payout` 的 `clientAmount` 是 `[-100000, 0]` ⇒ **金额必须是负数**，传正数会被夹成 `0`（记一笔 0 分的支出）。
74. `garden_legacy` 的金额夹在 `[0, 2000]`，且日限 1 ⇒ 老余额迁移必须**复用同一个 id** 才能幂等续传。
75. `GET /api/maintenance/orphans` 的 `keys` 只回前 200 个但 `orphans` 是全量计数；`POST` 删除的是**全部**闲置对象（不止 200 个），别用 `keys.length` 判断"会删多少"。
76. 维护接口 POST 的 `confirm` 必须是**严格布尔 `true`**，字符串 `"true"` 会被拒。
77. "闲置照片"有 **6 小时保护期**，刚上传还没落库的图不会被删；`referenced = total - 可清理数`（含保护期内的新图）。
78. 通知的 `unreadCount` 是**该格信箱未读总数**（不受 `limit` 影响），不要用 `items.where(unread).length` 代替。
79. `GET /api/notifications` 的 `items` 排序是 `created_at DESC, rowid DESC`（同毫秒也有稳定顺序）；账本是纯 `created_at DESC`（同毫秒顺序不保证）。
80. `POST /api/admin` 的 `password` 会被服务端 `trim()`，存库的密码也经过 `trim()` 与长度清洗 ⇒ 首尾空白不参与比较。

---

## 20. 验收清单（人工逐条核对接口行为）

> 用法：在真机/模拟器上按顺序跑，或直接用 curl 打后端。每条都要亲眼确认响应。
> 约定：`BASE` = 后端 origin（如 `https://sn.starrymiku.com`）。

### 20.1 基础与无鉴权

- [ ] `curl -i "$BASE/api/ledger"` 不带任何 header 凭据 → 200 + 裸数组。
- [ ] `curl -i "$BASE/api/settings"` 不带凭据 → 200 `{names,background,ready:true}`。
- [ ] 确认仓库里**没有** `functions/_middleware.ts`（`ls functions/`），即"全站无鉴权"成立。
- [ ] `POST /api/admin` 带错误密码 → 401 + `attemptsLeft`；连续 5 次 → 429 + `lockRemainingMs`；第 6 次（锁定期内）带**正确**密码 → 仍 429。

### 20.2 流水读

- [ ] `GET /api/ledger` 返回裸数组、按 `created_at` 倒序、默认 200 条。
- [ ] `GET /api/ledger?limit=0` → 200 条；`?limit=0.5` → `[]`；`?limit=1000` → ≤500 条；`?limit=abc` → 200 条。
- [ ] `GET /api/ledger?status=pending` 只回 pending；`?status=` 回全部；`?status=null` 回 `[]`；`?status=xxx` 回 `[]`（不报错）。
- [ ] `GET /api/ledger?since=<某条 created_at>` 不含该条本身。
- [ ] 记录里每个字段都能被 Dart 模型解析（含 `member` 缺失、`status` 为 null 的情况）。

### 20.3 流水写 + 闸门

- [ ] `POST /api/ledger` body `{"task_id":"clean_room","id":"<uuid>"}` → 201 `status:"pending"`，且家长信箱出现 `checkin_pending` 通知。
- [ ] 同一 id 重发 → 200 `duplicate:true`，账本**没有**新增。
- [ ] 非法 id（如 `"-abc"`）→ 服务端返回 201 且 `id` 是 UUID（被替换）⇒ 用它重试会新增第二条（验证坑 #19）。
- [ ] `{"task_id":"不存在"}` → 403 `未知任务，不能记账`。
- [ ] `{"task_id":"seed_welcome_bonus"}` → 403 `「开户礼金」由服务端自动记账，不能直接提交`。
- [ ] `{"task_id":"user_task_exec"}`（不传 amount）→ 400 `amount 非法`。
- [ ] `{"task_id":"user_task_exec","amount":9999,"task_name":"x"}` → 金额夹到 +200。
- [ ] `{"task_id":"user_task_exec","amount":-50,"task_name":"y"}` → `type:"spending"`、`amount:-50`。
- [ ] `{"task_id":"garden_legacy","amount":5000}` → 记为 +2000。
- [ ] `{"task_id":"custom:english_words10","amount":100}` → 记账金额是 **10**（仅校验不采纳）。
- [ ] `clean_room` 连发 3 次（不同 id）→ 第 3 次 409 `「整理房间」每天最多 2 次，今天用完啦`。
- [ ] `sleep_on_time` 在东八区 19:00 前提交 → 409 `「按时睡觉」只能在 19:00-22:00 之间打卡`。
- [ ] `garden:chinese` 第二次提交 → 409 `「语文预习 15 分钟」今天已经打过卡啦`（证明 autoApprove 不绕过日限）。
- [ ] `user_task_exec` 同名重发 → 409 `「<名>」今天已经打过卡啦`。
- [ ] `eye_penalty` 连发 3 次 → 全部成功（无日限，验证坑 #26）。
- [ ] `payout` 传 `amount:100` → 记为 0 分支出；传 `amount:-50` → 记为 -50。

### 20.4 审批与删除

- [ ] `PATCH /api/ledger/:id {"status":"approved"}` → 200 `{ok:true}`，孩子信箱出现 `approved`。
- [ ] 同一条再次 PATCH 成 approved → 200，但**不产生第二条**通知。
- [ ] `{"status":"rejected","reason":"<60字>}` → 通知正文是 `妈妈说：<reason>`，超长被截断到 60。
- [ ] `{"status":"pending"}` → 家长收到 `resubmitted`。
- [ ] `{"status":"xxx"}` → 400 `status 非法`；不存在的 id → 404 `记录不存在`。
- [ ] `DELETE /api/ledger/:id`（带图）→ 200 `{ok:true}`，且 `GET /api/images/<key>` 变成 404 纯文本。

### 20.5 余额

- [ ] `GET /api/ledger/summary` → `{family,sun}`，且 `family+sun == 全表 approved/NULL 的 amount 之和`（SQL 手算对照）。
- [ ] 制造 >200 条流水后确认 `summary` 与"窗口求和"出现差异（证明必须用 summary）。

### 20.6 日结算

- [ ] 空库首次 `POST /api/ledger/settle {}` → `applied` 含 `seed_welcome_bonus`，`family` = 100，`day` 存在。
- [ ] 立刻再调一次 → `applied: []`（幂等），余额不变。
- [ ] 东八区 <22:00 调用 → `day` = 昨天；`day` 恢复 22:00 后调用 → `day` = 今天。
- [ ] 造"当天无 sleep_on_time"的过去一天 + 显式 `date` → `applied` 含 `sleep_penalty_<day>`，金额 -20，且该记录 `created_at` 是那天的东八区正午。
- [ ] 当天完成数 <5 的日子 → `applied` 含 `daily_penalty_<day>`，金额 -10。
- [ ] `{"date":"2026-02-31"}` → 400 `date 必须是合法的 YYYY-MM-DD`；`{"date":"<明天>"}` → 400 `不能结算未来的日期`。
- [ ] `GET /api/ledger/settle` → 不是 200（预期 405）。
- [ ] 客户端节流键存的是响应里的 `day`，不是本地当天。

### 20.7 计划

- [ ] `GET /api/plans`（无参数）→ 400 `缺少 week 参数`。
- [ ] `GET /api/plans?week=2026-W34` → 裸数组（可能为空）。
- [ ] `POST /api/plans {"week_label":"2026-W34","items":[...模板8条...]}` → 201 + 8 条；重复调用 → 仍 8 条（不重复插）。
- [ ] `POST /api/plans {"week_label":"x","items":[]}` → 400 `items 非法`；`items` 全是非法项 → 400 `items 无有效条目`。
- [ ] `PATCH /api/plans/:id {"current":999}` → 返回被夹到 target 的值；`{"current":"abc"}` → 200 + 原值。
- [ ] 跨年周验证：`2027-01-01` 生成的标签是 `2026-W53`（ISO 周年）而不是 `2027-W01`。

### 20.8 图片

- [ ] `curl -X POST --data-binary @a.jpg -H "Content-Type: image/jpeg" "$BASE/api/upload"` → 201 `{url,key}`。
- [ ] 用 `Content-Type: image/jpg` → 415 `仅支持 jpg / png / webp / gif 图片`。
- [ ] 空文件 → 400 `文件为空`；>5MB → 413 `图片不能超过 5MB`。
- [ ] `GET <url>` → 200 + `Cache-Control: public, max-age=31536000, immutable` + `Access-Control-Allow-Origin: *`。
- [ ] `GET $BASE/api/images/tasks/nope.jpg` → 404 且响应体是纯文本 `Not Found`（不是 JSON）。

### 20.9 通知

- [ ] `GET /api/notifications`（无 audience）→ 400 `audience 非法（应为 parent 或 child）`。
- [ ] `GET /api/notifications?audience=parent` → `{items,unreadCount,ready:true}`，items 按时间倒序，无 `dedupe_key` 字段。
- [ ] `limit` 边界同账本（0.5 → 空、1000 → 200、abc → 50）。
- [ ] `PATCH /api/notifications/:id {"status":"read"}` → `read_at` 有值；`{"status":"unread"}` → `read_at` 为 null。
- [ ] `POST /api/notifications/read-all {"audience":"parent"}` → `{ok:true,updated:n}`；再调一次 → `updated:0`。
- [ ] 在未跑 0003 迁移的库上：GET 返回 200 + `ready:false`，而 PATCH/read-all 返回 503。

### 20.10 设置

- [ ] `GET /api/settings` → 默认 `{momCall:'妈妈',momNickname:'',kidCall:'女儿',kidNickname:'',background:''}`。
- [ ] `PATCH {"momNickname":"老妈"}` → 只改昵称，其他三项不动（部分更新验证）。
- [ ] `PATCH {"momNickname":""}` → 昵称被清空；`PATCH {"momCall":""}` → 变回 `妈妈`。
- [ ] `PATCH {"momCall":null}` → 400 `称呼必须是文字`。
- [ ] `PATCH {"momCall":"<13个字>"}` → 400 `称呼最多 12 个字`。
- [ ] `PATCH {"background":"https://example.com/a.jpg"}` → 400 背景图不合法；`PATCH {"background":""}` → 背景被清掉。
- [ ] `PATCH {"foo":1}` → 400 `没有要保存的设置`。
- [ ] 通知文案里的称呼随 settings 变化（换名后新通知用新称呼）。

### 20.11 管理员

- [ ] `POST /api/admin {"action":"verify","password":"3398377037"}` → 200 `{family,sun}`。
- [ ] 未知 action（如 `{"action":"nope","password":"正确"}`）→ 200（静默按 verify）⇒ 客户端自己枚举。
- [ ] `{"action":"adjust","password":"正确","family":500}` → 200 `{family:500,sun,changed:["家庭积分 X → 500"]}`，账本多一条 `admin_adjust` 的 `管理员调整`。
- [ ] 重复提交相同 `family:500` → 200，**不新增**流水。
- [ ] `{"action":"adjust","password":"正确"}`（不带 family/sun）→ 400 `没有要修改的积分`。
- [ ] `{"action":"adjust","password":"正确","family":null}` → 400 `家庭积分需要是 ±1000000 之间的整数`。
- [ ] `{"action":"adjust","password":"正确","sun":30}` → 账本多一条 `garden:admin_adjust`，且 `GET /api/ledger/summary` 的 `sun` 变化。
- [ ] `{"action":"password","password":"正确","newPassword":"12"}` → 400 `新密码需为 4-32 位`；合法新密码 → `passwordChanged:true`，旧密码随即失效。
- [ ] `{"action":"adjustments","password":"正确"}` → `adjustments` 数组最多 20 条，字段为 `{id,ledger,amount,note,createdAt}`。
- [ ] 用 `DELETE /api/ledger/:id` 删掉一条调整 → 余额回到调整前。

### 20.12 维护

- [ ] `GET /api/maintenance/orphans` → `{total,referenced,orphans,keys}`，`keys.length <= 200`，`orphans` 是全量计数。
- [ ] 刚上传（<6 小时）未被引用的图**不在**可清理集合里。
- [ ] 设了全局背景图后，该图**不会**被判为闲置。
- [ ] `POST /api/maintenance/orphans {}` → 400 `危险操作：请在请求体中传入 {"confirm": true} 以确认清理闲置照片`。
- [ ] `POST {"confirm":true}` → 200 `{deleted,failed,keys}`；再扫描 `orphans` 归零。

### 20.13 版本日志

- [ ] `GET /api/changelog` → 200 `{version,entries,ready}`；`entries` 最新在前，`version` = `entries[0].version`。
- [ ] 表没迁移 / 还没同步时 → 200 且 `ready:false`、`entries:[]`（**不是** 4xx/5xx），客户端退回本机那份。
- [ ] 同步后条数与 Web 仓库 `src/config/changelog.ts` 的 `CHANGELOG.length` 一致（Flutter 这份 `lib/config/changelog.dart` 由 `npm run changelog:fallback` 生成，条数相同）。

## 21. 手机提醒（`/api/push/*`）与全站自检（`/api/admin/selftest`）

> 这两组接口是 Web Push 提醒与「设置 → 管理员 → 全站自检」用的。**完整契约在 Web 仓库**：
> [`docs/selftest-console.md`](../../SekaiNook/docs/selftest-console.md)（自检）、
> [`workers/reminder/README.md`](../../SekaiNook/workers/reminder/README.md)（提醒 Worker）。
> 下面是 Flutter 端要用到的要点。

### 21.1 推送订阅

- `GET /api/push/key` → `{publicKey, subject, ready}`；`ready:false` = 订阅表还没迁移（VAPID 公钥没配）。
- `POST /api/push/subscribe` body `{endpoint, keys:{p256dh,auth}, audience?}`（`audience` 缺省 `child`）→ 200 `{ok:true,endpoint}`；
  `endpoint` 必须 `https://` 开头、`keys.p256dh`/`keys.auth` 非空，否则 400；写库失败 503 `推送订阅表尚未就绪…`。
- `DELETE /api/push/subscribe` body `{endpoint}`（**取不到时回退 `?endpoint=`** —— Flutter 的 `ApiClient.deleteJson` 不带 body，用查询参数即可）。
- 表：`push_subscriptions(endpoint PK, audience, p256dh, auth, ua, created_at, updated_at)`。

### 21.2 自检

- `GET /api/admin/selftest` → **清单，不需要密码**：`{version, generatedAt, groups, params, presets, clientChecks}`。
  - `groups[].items[]`：`{id, name, desc, side: "server"|"client", client: null|"web"|"flutter", mutates, danger, params: string[], estMs}`。
  - `params[]`：`{name, label, type: "bool"|"string"|"int"|"enum", desc, default?, options?}` —— **按它动态渲染表单，不要硬编码**。
  - `presets[]` 三种形态：`skipMutating:true` / `itemIds:[…]` / `params:{…}`。
  - `clientChecks`：`{web:[…], flutter:[…]}`；Flutter 端要跑的是 `flutter.routes`、`flutter.theme`、
    `flutter.notify.permission`、`flutter.notify.schedule`、`flutter.notify.cancel`、`flutter.storage`、`flutter.image`。
- `POST /api/admin/selftest` body `{password, items?, groups?, params?, clientResults?, includeClient?}` → 管理员口令（与 `POST /api/admin` 同一套，含节流）。
  响应 `{ranAt, durationMs, env, params, summary, results, clientMissing, notes}`；
  `results[]`：`{id, group, name, side, mutates, ms, status: "pass"|"fail"|"warn"|"skip", detail, data?}`。
- 当前清单 **71 项 / 11 组**；`clientMissing` 是「这轮选了但没回传结果的客户端项」，前端要提示出来。
- 写库类检查（`mutates:true`）在 `params.dryRun=true` 时只预演；真跑时会自清理，`keep:true` 才保留。
- `flutter.notify.*` 三项**依赖 `flutter_local_notifications`，目前 App 未接入**，如实返回 `skip`（不要为自检加依赖）。

## 22. 版本日志（`/api/changelog`）

> 版本日志（设置页底部那份）的**真源在 D1 的 `changelog` 表**，网页版与 Flutter 版读同一份 ——
> 以前两端各存一份代码常量（`src/config/changelog.ts` / `lib/config/changelog.dart`），改一边另一边不跟着变。
> 现在代码里那份的身份是**播种数据 + 兜底**。

### 22.1 `GET /api/changelog`

无参数、**不需要鉴权**（与 `/api/settings` 同类：给全家看的公开信息）。**正常一律 200**，用 `ready` 区分数据能不能用：

```jsonc
{
  "version": "1.31.0",     // 最新一条的版本号；没有内容时为 null
  "entries": [             // 最新在前
    { "version": "1.31.0", "date": "2026-10-17 22:40:00", "title": "…", "changes": ["…", "…"] }
  ],
  "ready": true            // = entries 非空。false 时 entries 一定是 []
}
```

- `ready:false` 的两种原因：① `changelog` 表还没迁移（Web 仓库 `migrations/0006_changelog.sql` 没跑）；
  ② 表建好了但还没同步（Web 仓库跑 `npm run changelog:sync`）。**不要把 `ready:false` 当错误显示**，
  静默用自己 bundle 里那份 `lib/config/changelog.dart` 兜底即可（App 已这么做）。
- `date` 是**展示用字符串**（`YYYY-MM-DD HH:mm:ss`），原样显示、不做时区换算；顺序以服务端返回为准（最新在前），
  客户端不要再按 `date` 排序。
- 没有写接口：改日志的唯一入口是 Web 仓库的 `src/config/changelog.ts` + `npm run changelog:sync`
  （脚本把它同步进 D1，`npm run changelog:fallback` 顺手重新生成 Flutter 这份 `lib/config/changelog.dart`）。
- handler 内部 try/catch，读库失败也回 200 + `ready:false`；所以拿不到 200 只可能是平台级故障。

