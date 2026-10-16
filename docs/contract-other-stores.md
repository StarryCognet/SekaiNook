# 其余四个 Store 行为契约（Flutter 移植依据）

> 调研对象（只读，位于 `E:\Git\SekaiNook`）：
> `src/store/useCustomTasksStore.ts`（334 行）、`src/store/useNotificationStore.ts`（141 行）、
> `src/store/useThemeStore.ts`（134 行）、`src/store/useSettingsStore.ts`（83 行）。
> 依赖：`src/api/notifications.ts`、`src/api/settings.ts`、`src/api/familyLedger.ts`、`src/api/http.ts`、
> `src/utils/taskRules.ts`、`src/types/notification.ts`、`src/types/settings.ts`、`src/types/family.ts`、
> `src/theme/themes.ts`、`src/App.tsx`、`src/layouts/MainLayout.tsx`、`src/views/settings/SettingsPage.tsx`、
> `src/views/home/NotificationsPage.tsx`、`src/views/home/KidHome.tsx`、`src/views/family/FamilyDashboard.tsx`。
>
> 约定：下文 `文件:行号` 一律相对 `E:\Git\SekaiNook`。zustand 的 `create((set, get) => ...)` 语义：
> `set(partial)` 是浅合并；闭包变量（如 `limit`、`removedPresets`）不进 state、不触发重渲染，
> 但跨 action 调用存活。移植到 Dart 时需要显式用实例字段承载这些闭包变量。

---

## 0. 共性：HTTP 客户端与错误语义（所有 store 共用）

`src/api/http.ts`：

- `ApiError extends Error`，携带 `status`（`http.ts:9-17`）；`status = 0` 表示网络层失败（断网 / DNS / 连接被拒 / 超时 abort）。
- 超时：`DEFAULT_TIMEOUT_MS = 12000`（`http.ts:28`），用 `AbortController` 实现（`http.ts:68-70`）。
- 可重试状态码：`[429, 500, 502, 503, 504]`（`http.ts:20`）；`GET` 默认自动重试 2 次（`MAX_RETRIES = 2`，`http.ts:22`）；
  写请求（POST/PATCH/DELETE）**默认不重试**，只有调用方显式传 `{ retry: true }` 才重试 1 次（`MAX_RETRIES_WRITE = 1`，`http.ts:23-24`、`http.ts:50-53`）。
- 重试等待：`RETRY_DELAYS = [400, 1200]` 毫秒，下标即已重试次数，越界回退 1200（`http.ts:26`、`http.ts:78`、`http.ts:91`）。
- 非 2xx 时：先尝试解析响应体 `{error?: string}`，有 `error` 字段就用它当 `message`，否则 `请求失败（${status}）`，然后抛 `ApiError`（`http.ts:95-102`）。
- `res.status === 204` 直接返回 `undefined`（`http.ts:105`）；否则 `res.json()`。
- 有 body 时自动加 `Content-Type: application/json`（`http.ts:63-65`）。

**移植要点**：Dart 里四个 store 用同一套 `ApiClient`；区分「网络层失败（status 0，可留待下轮）」与「4xx 明确拒绝（不要重试）」。

---

## 1. useCustomTasksStore

### 1.1 定位与关键结论（先讲清问题里的三个为什么）

- **不入账**：这份列表是**纯本机存档**，没有对应的服务端表（文件头注释 `useCustomTasksStore.ts:1-9`：「自定义任务列表（本地存档，**不加表**：线上 D1 没有 migration 执行通道）」）。
  点「添加任务」只写进列表，**不写流水**；只有打卡完成时才写流水（`FamilyDashboard.tsx:310-321` 的 `handleCustomTask` 明确「这里绝不调 addLedgerRecord」）。
- **`USER_TASK_EXEC_ID = 'user_task_exec'`**（`useCustomTasksStore.ts:22`）：所有**非预置**任务的打卡流水统一用这一个 `task_id` 上报；名称由客户端带（`task_name`），金额由客户端带（`amount`），
  `type` 由服务端按 `amount` 符号覆盖；**未知 `task_id` 一律 403，所以绝不能自造 id 上报**（`useCustomTasksStore.ts:18-22`、`KidHome.tsx:249-253`）。
  服务端对 `user_task_exec` 按**规范化后的任务名**判重 + 三层闸门（同名当日重复 / 当日条数 ≥20 / 当日正分累计 ≥50 均返回 409）。
- **`PRESET_TASK_IDS` 为什么带 autoApprove**：`['custom:english_words10', 'custom:poem2']`（`useCustomTasksStore.ts:25`）这两条在**服务端已登记为独立 task_id**（各自日限 1、即时到账），
  且「不占 50 分自定义额度」（`useCustomTasksStore.ts:24`）。它们的 `createdBy` 被硬编码为 `'parent'`（`useCustomTasksStore.ts:73`、`useCustomTasksStore.ts:83`），
  于是调用侧 `addLedgerRecord(execTask, undefined, { autoApprove: task.createdBy === 'parent' })` 对它们（以及家长加的所有任务）为 `true`，
  走「POST 记账 + 立即 PATCH approved」两步即时到账；孩子自己加的（`createdBy === 'child'`）为 `false`，落到 pending 等家长审批——否则就是「自己加任务自己发钱」的刷分口子（`KidHome.tsx:249-274`）。
- **自定义任务与固定任务如何合并**：`ensurePresets()` 把两条预置任务**追加**进同一个 `tasks` 数组（`kind: 'preset'`），
  消费侧用 `selectPresetTasks()` 过滤 `kind === 'preset'`；UI 侧（`FamilyDashboard.tsx:329-335`、`KidHome.tsx:259-266`）用 `toExecTask` 把 `CustomTask` 映射成 `TaskConfig`：
  `id = task.kind === 'preset' ? task.id : USER_TASK_EXEC_ID`，`name/type/value` 原样带过去，`unit: '积分'`。
  即：**合并发生在一个数组里，靠 `kind` 分流上报 id**，不存在两套数据源合并的动作。
- **id 怎么生成**：家长 `custom_<ms>`、孩子 `wish_<ms>`，同一毫秒撞了 `stamp += 1` 往后挪（`useCustomTasksStore.ts:190-196`）。
- **删除时怎么处理历史流水**：**完全不动服务端流水**。`removeTask` 只做三件事——把预置 id 记进 `removedPresets`（防「自动加回来」）、从 `tasks` 移除、删掉该 id 的 `doneDate` 条目（`useCustomTasksStore.ts:243-254`）。
  历史流水留在服务端账本里，照旧显示在流水列表中（任务名存在流水的 `task_name` 上，所以删任务不会让历史失去可读性）。

### 1.2 常量与类型

| 名称 | 值 / 定义 | 位置 |
| --- | --- | --- |
| `CUSTOM_TASKS_KEY` | `'sekainook_custom_tasks_v1'`（注释「契约 §4 写死，不得改名」） | `useCustomTasksStore.ts:16` |
| `USER_TASK_EXEC_ID` | `'user_task_exec'` | `useCustomTasksStore.ts:22` |
| `PRESET_TASK_IDS` | `['custom:english_words10', 'custom:poem2'] as const` | `useCustomTasksStore.ts:25` |
| `MAX_TASK_VALUE` | `200`（服务端 `clientAmount` 夹取范围 `-200~200`） | `useCustomTasksStore.ts:28` |
| `SYSTEM_TASK_IDS` | `['seed_welcome_bonus', 'daily_min_tasks_penalty', 'sleep_penalty']` | `useCustomTasksStore.ts:31-35` |
| `PRESET_TASKS` | 两条预置任务定义（见下） | `useCustomTasksStore.ts:66-88` |
| `BEIJING_OFFSET_MS` | `8 * 60 * 60 * 1000` | `useCustomTasksStore.ts:98` |

`CustomTask`（`useCustomTasksStore.ts:38-49`，字段名不得改）：

| 字段 | 类型 | 语义 |
| --- | --- | --- |
| `id` | `string` | 本地 id；预置任务 = `preset.id` 且与服务端 `task_id` 同名 |
| `name` | `string` | 任务名（判重依据，上报时进 `task_name`） |
| `value` | `number` | 完成可得（正）/ 需扣（负） |
| `type` | `'earning' \| 'spending'` | 币种方向 |
| `createdBy` | `'parent' \| 'child'` | 决定打卡是即时到账还是走待审批 |
| `createdAt` | `string` | ISO 字符串；预置任务定义里是 `''`，`ensurePresets` 落地时填当前时间 |
| `kind` | `'preset' \| 'custom'` | 决定上报用自带 id 还是 `user_task_exec` |
| `repeatDaily` | `boolean` | 默认 `true`：每天可再打卡一次 |

`CustomTaskInput`（`useCustomTasksStore.ts:52-63`）：`name`、`value`、`type: TaskType`、`createdBy: 'parent'|'child'` 必填；
`kind?` 缺省 `'custom'`；`repeatDaily?` 缺省 `true`；`id?` 不传则按 `createdBy` 生成。

`PRESET_TASKS` 两条（`useCustomTasksStore.ts:66-88`）：

| id | name | value | type | createdBy | createdAt | kind | repeatDaily |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `custom:english_words10` | `十个英语单词` | 10 | earning | parent | `''` | preset | true |
| `custom:poem2` | `两首古诗` | 10 | earning | parent | `''` | preset | true |

`StoredPayload`（`useCustomTasksStore.ts:91-96`）：`{ tasks: CustomTask[]; doneDate: Record<string,string>; removedPresets: string[] }`。

### 1.3 持久化

- 键名：`localStorage['sekainook_custom_tasks_v1']`，值是一段 JSON 字符串，结构就是 `StoredPayload`：
  ```json
  {"tasks":[{"id":"custom:poem2","name":"两首古诗","value":10,"type":"earning",
             "createdBy":"parent","createdAt":"2025-01-01T00:00:00.000Z","kind":"preset","repeatDaily":true}],
   "doneDate":{"custom:poem2":"2025-01-01"},
   "removedPresets":["custom:english_words10"]}
  ```
- `removedPresets` **不进 state**（UI 不需要），是 store 闭包变量，但每次 `persist` 都会写回存档（`useCustomTasksStore.ts:213-218`）。
- 读时机：仅在 store 创建时读一次（`useCustomTasksStore.ts:212`，`const restored = readStored()`），赋给 `tasks` / `doneDate` 初值（`useCustomTasksStore.ts:221-222`）。
- 写时机：`addTask`（`:239`）、`removeTask`（`:253`）、`ensurePresets`（`:267`，仅当有变更）、`markDone`（`:273`）——即**每个改动 state 的 action 都同步落盘**。
- **老数据迁移 / 容错**（`readStored`，`useCustomTasksStore.ts:142-179`）：
  1. `localStorage.getItem` 抛异常（隐私模式）→ 返回空存档 `{tasks:[],doneDate:{},removedPresets:[]}`（`:143-149`）。
  2. JSON 解析失败 → 返回空存档（`:176-178`）。
  3. **最早版本直接存数组**：`Array.isArray(parsed)` 时把整个值当 `tasks`，`doneDate` 与 `removedPresets` 视为空（`:154-156`、`:160-162`、`:169-171`）——这是唯一的「老数据迁移」，没有版本号字段。
  4. 逐条 `toTask` 校验并**规范化**，非法的丢弃（`:157-159`）。
  5. `doneDate` 只保留 value 为 `string` 的项；`removedPresets` 只保留 `string` 元素。
  - 写入失败被吞（`writeStored`，`:182-188`，注释「本机存储不可用：退化成只在内存里生效」）。

`toTask` 规范化细节（`useCustomTasksStore.ts:121-139`）——存档被手改也不能把页面搞崩：

- `id` 必须是非空 string，否则整条丢弃；`name` 必须是非空 string，否则丢弃；`value` 必须是有限 number，否则丢弃。
- `type = raw.type === 'spending' ? 'spending' : 'earning'`（其余一切值都归 earning）。
- `value2 = type === 'earning' ? Math.abs(raw.value) : -Math.abs(raw.value)`（符号一律按 type 重算）。
- `createdBy = raw.createdBy === 'child' ? 'child' : 'parent'`。
- `createdAt = typeof raw.createdAt === 'string' ? raw.createdAt : new Date().toISOString()`。
- `kind = raw.kind === 'preset' ? 'preset' : 'custom'`。
- `repeatDaily = raw.repeatDaily !== false`（只有显式 `false` 才是 false）。

### 1.4 State 与 action 全集

`CustomTasksState`（`useCustomTasksStore.ts:198-208`）：

| 字段 | 类型 | 初值 | 持久化 |
| --- | --- | --- | --- |
| `tasks` | `CustomTask[]` | `restored.tasks`（`:221`） | 是（同一键内 `tasks`） |
| `doneDate` | `Record<string,string>` | `restored.doneDate`（`:222`） | 是（同一键内 `doneDate`） |
| `addTask` | `(input) => CustomTask` | — | — |
| `removeTask` | `(id) => void` | — | — |
| `ensurePresets` | `() => void` | — | — |
| `markDone` | `(id) => void` | — | — |
| `isDoneToday` | `(id) => boolean` | — | — |

**`addTask(input): CustomTask`**（`useCustomTasksStore.ts:224-241`）

1. `type = input.type === 'spending' ? 'spending' : 'earning'`。
2. `abs = Math.min(Math.max(Math.round(Math.abs(input.value)) || 1, 1), MAX_TASK_VALUE)`——注意顺序：
   先 `Math.abs` → `Math.round` → `|| 1`（`0`/`NaN` 变成 `1`）→ 下限夹 `1` → 上限夹 `200`。
3. `id = input.id ?? nextTaskId(input.createdBy, get().tasks)`。
4. `name = normalizeTaskName(input.name) || '未命名任务'`（规范化后为空则用中文兜底 `未命名任务`）。
5. `value = type === 'earning' ? abs : -abs`；`createdAt = new Date().toISOString()`；`kind = input.kind ?? 'custom'`；`repeatDaily = input.repeatDaily !== false`。
6. 浅合并写入：`tasks = [...get().tasks.filter((t) => t.id !== created.id), created]`——**同 id 覆盖且挪到末尾**（`:237`）。
7. `persist(tasks, get().doneDate)`；返回 `created`。
8. 无 try/catch：本方法不抛（存档写入失败已在 `writeStored` 内吞掉）。

**`removeTask(id): void`**（`useCustomTasksStore.ts:243-254`）

1. `target = get().tasks.find((t) => t.id === id)`。
2. **若 `target?.kind === 'preset'` 且 `!removedPresets.includes(id)`**，把 id 追加进 `removedPresets`（`:246-248`，注释「否则删除按钮看起来是坏的」）。
3. `tasks = get().tasks.filter((t) => t.id !== id)`。
4. `doneDate = {...get().doneDate}` 后 `delete doneDate[id]`。
5. `set({tasks, doneDate})` + `persist`。**不删服务端流水，不发任何请求。**
6. 传不存在的 id：`target` 为 `undefined`，仍执行 3-5（幂等空操作）。

**`ensurePresets(): void`**（`useCustomTasksStore.ts:256-268`）

1. `tasks = [...get().tasks]`，`changed = false`。
2. 遍历 `PRESET_TASKS`：若 `removedPresets.includes(preset.id)` 跳过；若 `tasks.some(t => t.id === preset.id)` 跳过；
   否则 `tasks.push({...preset, createdAt: new Date().toISOString()})` 并置 `changed = true`。
3. `if (!changed) return;`——**没有变更就完全不写盘、不 set**（幂等，不覆盖用户改过/删过的）。
4. 有变更才 `set({tasks})` + `persist(tasks, get().doneDate)`。
5. 调用时机：页面挂载时的 `useEffect`（`FamilyDashboard.tsx:187-190`、`KidHome.tsx:146-149`），两处都在 `useEffect(..., [ensurePresets])` 里每次挂载调一次。

**`markDone(id): void`**（`useCustomTasksStore.ts:270-274`）

1. `doneDate = {...get().doneDate, [id]: beijingDayKey()}`——**无条件覆盖**，不检查是否已打卡。
2. `set({doneDate})` + `persist(get().tasks, doneDate)`。
3. 调用时机：打卡**成功之后**（`KidHome.tsx:268`），以及 `LedgerApprovalError` 分支——账已记上但立即审批失败时也调 `markDone`（`KidHome.tsx:276-282`，注释「本地也要算今天已完成，不然孩子再点一次，只会撞上服务端的同名日限」）。
   服务端 409（三层闸门）时**不调** `markDone`（直接 `message.error`，`KidHome.tsx:284-286`）。

**`isDoneToday(id): boolean`**（`useCustomTasksStore.ts:276-283`）

1. `day = get().doneDate[id]`；`if (!day) return false`。
2. `task = get().tasks.find(t => t.id === id)`。
3. **若 `task && !task.repeatDaily`** → 直接 `return true`（一次性任务完成过就一直算完成，跨天也 true）。
4. 否则 `return day === beijingDayKey()`（每天可重复的任务只认「今天」）。

### 1.5 纯函数与导出

**`beijingDayKey(now = new Date()): string`**（`useCustomTasksStore.ts:105-110`）

```ts
const shifted = new Date(now.getTime() + 8*60*60*1000); // 整体移到 UTC+8 再取 UTC 字段
return `${year}-${MM}-${DD}` // 月/日 padStart(2,'0')
```
即 **东八区日历天 `YYYY-MM-DD`**。注释理由（`:100-104`）：服务端日限/判重/结算都按东八区，本地记「今天完成过」必须同一时区，否则晚上 8 点后本机把今天算成明天，打卡按钮会莫名复活。

**`normalizeTaskName(name): string`**（`useCustomTasksStore.ts:116-118`）
```ts
name.trim().replace(/\s+/g, ' ').slice(0, 30)
```
即 **trim + 折叠连续空白为单个空格 + 截断 30 字符**，「与服务端同一套」（`:112-115`）。

**`nextTaskId(createdBy, tasks): string`**（`useCustomTasksStore.ts:191-196`）
```ts
const prefix = createdBy === 'child' ? 'wish_' : 'custom_';
let stamp = Date.now();
while (tasks.some((t) => t.id === `${prefix}${stamp}`)) stamp += 1;
return `${prefix}${stamp}`;
```
注意：**撞检查只在同前缀内做**（`custom_` 与 `wish_` 各自独立序列），且不是毫秒时间戳格式化的字符串，就是十进制毫秒数。

**`selectPresetTasks(tasks?): CustomTask[]`**（`useCustomTasksStore.ts:288-291`）
```ts
const list = tasks ?? useCustomTasksStore.getState().tasks;
return list.filter((t) => t.kind === 'preset');
```

**`countDoneToday(records, now = new Date()): number`**（`useCustomTasksStore.ts:298-310`）——「今日完成数」，与**服务端 `daily_min_tasks_penalty` 口径完全一致**（`:293-297`）：

逐条流水，满足全部条件才算数：
1. `if (record.status && record.status !== 'approved') continue;`——**无状态视为已审批**（兼容存量数据），只有显式非 `approved` 才跳过。
2. `if (record.type !== 'earning' || record.amount <= 0) continue;`——花钱 / 罚款不算完成。
3. `if (SYSTEM_TASK_IDS.includes(record.task_id)) continue;`——排除三条系统流水。
4. `at = new Date(record.created_at)`；`Number.isNaN(at.getTime()) || beijingDayKey(at) !== day` → 跳过（按**东八区天**过滤，不是本机 `toDateString`）。
5. `done.add(record.task_id)`——**按 `task_id` 去重**。
返回 `done.size`。语义：一天背三首诗只算 1 个任务（`:296`）。

**`isRecordedToday(task, records, now = new Date()): boolean`**（`useCustomTasksStore.ts:319-334`）——按钮置灰用；注释强调「⚠️ 这只是省一次白跑的请求，**正确性在服务端**（同名当日第二次会 409）」（`:313-318`）。

- 若 `task.kind === 'preset'`：`return countTodaySubmissions(records, task.id, now) > 0`。
  `countTodaySubmissions`（`src/utils/taskRules.ts:11-23`）口径 = `r.task_id === taskId && r.status !== 'rejected' && new Date(r.created_at).toDateString() === today` 的条数，`today = now.toDateString()`——
  **含待审批、不含被驳回**；注意它用的是**本机时区** `toDateString()`，与 `beijingDayKey` 不一致（这是现有实现里的真实细节，移植时照抄以便行为一致）。
- 否则（自定义任务，全部写 `user_task_exec`，服务端按任务名判重，本地也只能按规范化名字认）：
  ```ts
  const name = normalizeTaskName(task.name);
  const today = now.toDateString();
  return records.some((record) =>
    record.task_id === USER_TASK_EXEC_ID &&
    record.status !== 'rejected' &&
    normalizeTaskName(record.task_name) === name &&
    new Date(record.created_at).toDateString() === today
  );
  ```
- UI 用法：`isRecordedToday(task, records, now) || isTaskDoneToday(task.id)`（`FamilyDashboard.tsx:538`、`:586`；`KidHome.tsx:558`）。

### 1.6 与后端交互

本 store 自身**不发请求**。打卡请求由视图层发起，契约如下（移植时属于同一功能域）：

- 入口 `addLedgerRecord(task, extra?, opts?)`（`src/api/familyLedger.ts:266-289`）→ `postLedgerRecord`（`familyLedger.ts:200-224`）：
  - `POST /api/ledger`，body：
    ```json
    {"id":"<createRequestId()>","task_id":"user_task_exec","task_name":"<任务名>",
     "type":"earning","amount":10,"note":null,"image_url":null}
    ```
    其中 `task_id` 对预置任务换成其自带 id（`custom:english_words10` / `custom:poem2`）。
  - 请求带 `{ retry: true }`（`familyLedger.ts:222`）——服务端靠主键 `INSERT OR IGNORE` 幂等去重（`familyLedger.ts:196-198`）。
  - 响应字段：`{ id, status?, duplicate? }`（`familyLedger.ts:190-193`）。
- `opts.autoApprove === true`（`task.createdBy === 'parent'`）时，紧接着 `PATCH /api/ledger/{id}` body `{"status":"approved"}`（`familyLedger.ts:280-287`、`familyLedger.ts:297-299`）；
  第二步失败抛 `LedgerApprovalError`（message = `已记账，但审批没成功 —— 记录在待审批里，去点一下通过`，`familyLedger.ts:245-254`），调用方据此 `markDone` + 重新拉账本 + `message.warning`（`KidHome.tsx:276-283`）。
- 失败处理：4xx（日限、金额非法）用服务端 `error` 文案直接 `message.error`（`KidHome.tsx:284-286`）；`isRejectedWriteError` 判定 `status >= 400 && status < 500 && status !== 429`（`familyLedger.ts:231-235`）。

---

## 2. useNotificationStore

### 2.1 角色与分工

文件头注释（`useNotificationStore.ts:9-16`）：与 `useFamilyStore` 的分工——家庭 store 管账（余额、流水、待审批），这里管「谁对谁做了什么」的消息；两者都在轮询里刷新。标记已读走**乐观更新**：先改本地（角标立刻变小），失败再拉一次真实数据兜底。

**通知没有「创建」接口**：全部由服务端在记账 / 审批 / 结算处写入（`src/api/notifications.ts:1-6`），前端只读与标记已读。通知类型 `NotifyType = 'checkin_pending' | 'approved' | 'rejected' | 'resubmitted' | 'recorded' | 'payout'`（`src/types/notification.ts:11-17`）。

### 2.2 状态字段

`NotificationState`（`useNotificationStore.ts:20-39`）：

| 字段 | 类型 | 初值 | 语义 |
| --- | --- | --- | --- |
| `audience` | `NotifyAudience \| null` | `null`（`:46`） | 当前身份对应的信箱（未选身份时为 null） |
| `items` | `NotificationRecord[]` | `[]`（`:47`） | 当前页通知列表（服务端已按时间倒序） |
| `unreadCount` | `number` | `0`（`:48`） | 未读数，来自服务端计数，**不受分页影响** |
| `loading` | `boolean` | `false`（`:49`） | 首次加载中（下拉刷新式的静默刷新不算） |
| `ready` | `boolean` | `true`（`:50`） | `false` = 后端通知表尚未迁移好 |
| `error` | `string \| null` | `null`（`:51`） | 最近一次 `load` 的失败文案 |
| `load` | `(audience, limit?) => Promise<void>` | — | 切换到某格信箱并加载 |
| `refresh` | `() => Promise<void>` | — | 静默刷新（轮询用） |
| `markRead` | `(id: string) => Promise<void>` | — | 标记一条已读 |
| `markAllRead` | `() => Promise<void>` | — | 整格信箱一键已读 |

**闭包变量**：`let limit = DEFAULT_LIMIT`（`useNotificationStore.ts:43`，`DEFAULT_LIMIT = 50`，`:18`）——「当前已加载的分页大小（刷新时沿用）」，不在 state 里。

`NotificationRecord`（`src/types/notification.ts:20-31`）：`{ id: string; audience: NotifyAudience; type: NotifyType|string; title: string; body?: string|null; link?: string|null; status: 'unread'|'read'; created_at: string; read_at?: string|null }`。

`NotificationBox`（`src/types/notification.ts:34-39`）：`{ items: NotificationRecord[]; unreadCount: number; ready: boolean }`。

### 2.3 持久化

**无任何 localStorage 持久化**。全部为内存态，刷新即回到初值。

### 2.4 action 完整逻辑

**`load(audience, nextLimit = DEFAULT_LIMIT): Promise<void>`**（`useNotificationStore.ts:53-80`）

1. `limit = nextLimit`（写入闭包变量，供后续 `refresh` 沿用）。
2. `switching = get().audience !== audience`。
3. `set({ audience, loading: true, ...(switching ? { items: [], unreadCount: 0, error: null } : {}) })`——
   **换身份时先清空**，避免把上一格信箱的消息递给另一个人看（`:59`）；同一身份重载则保留旧列表（下拉刷新不闪空）。
4. `await fetchNotifications(audience, nextLimit)`。
5. **竞态守卫**：`if (get().audience !== audience) return;`——请求期间身份又变了就丢掉过期结果（`:65-66`，**注意此分支直接 return，不改 `loading`**）。
6. 成功：`set({ items: box.items, unreadCount: box.unreadCount, ready: box.ready, loading: false, error: null })`。
7. 失败：`set({ loading: false, error: e instanceof Error ? e.message : '通知加载失败' })`——**不 rethrow**（`:74-79`），但调用方仍普遍 `.catch(() => undefined)` 兜一层。

**`refresh(): Promise<void>`**（`useNotificationStore.ts:82-97`）

1. `audience = get().audience`；`if (!audience) return;`（未选身份直接返回）。
2. `await fetchNotifications(audience, limit)`（沿用闭包 `limit`）。
3. 同样的竞态守卫 `if (get().audience !== audience) return;`。
4. 成功：`set({ items, unreadCount, ready, error: null })`——**不动 `loading`**。
5. 失败：**空 catch，什么都不做**（`:94-96`，注释「轮询失败不打扰用户：保留上一次的数据，等下一轮」）。

**`markRead(id): Promise<void>`**（`useNotificationStore.ts:99-116`）

1. `target = get().items.find(i => i.id === id)`；`if (!target || target.status === 'read') return;`——**不在列表里或已读直接返回**（幂等）。
2. `readAt = new Date().toISOString()`。
3. 乐观更新：`items` 里把该条替换为 `{ ...item, status: 'read', read_at: readAt }`；`unreadCount = Math.max(0, get().unreadCount - 1)`。
4. `await markNotificationRead(id)` → `PATCH /api/notifications/{encodeURIComponent(id)}` body `{"status":"read"}`（`api/notifications.ts:22-26`）。
5. 失败：`await get().refresh()`（拉真实数据兜底），**吞掉异常**（`:113-115`）；即调用方 await 不会抛。

**`markAllRead(): Promise<void>`**（`useNotificationStore.ts:118-139`）

1. `const { audience, items, unreadCount } = get()`；`if (!audience || unreadCount === 0) return;`——**未读数已经是 0 就不发请求**。
2. `readAt = new Date().toISOString()`。
3. 乐观更新：`items` 中 `item.status === 'unread'` 的改为 `{ ...item, status: 'read', read_at: readAt }`；`unreadCount: 0`。
4. `await markAllNotificationsRead(audience)` → `POST /api/notifications/read-all` body `{"audience":"parent"|"child"}`（`api/notifications.ts:29-33`）。
5. 失败：**先 `await get().refresh()`**（未读数会老老实实涨回去），**再 `throw e`**（`:130-138`）。
   注释说明这条是刻意修的 bug（`:132-135`）：「以前这里吞掉异常，页面照样弹『已全部标记为已读』，用户接着看到角标又回来了 —— 提示成功但实际没成功。」
   调用方 `NotificationsPage.tsx:89-100`：成功 `message.success('已全部标记为已读')`，失败 `message.error('没能全部已读，请稍后重试')`。

### 2.5 轮询机制（启停条件、间隔、页面可见性）

轮询**不在 store 内**，在 `src/layouts/MainLayout.tsx:139-158`：

```ts
if (!audience) return;                    // 未选身份不轮询
const refresh = () => {
  if (document.hidden) return;            // 页面在后台（息屏/切走）时暂停
  refreshNotifications().catch(() => undefined);
  if (role === 'parent') refreshPending().catch(() => undefined);  // 待审批只有家长端要盯
};
refresh();                                // 挂载立刻来一次
const timer = setInterval(refresh, 15000); // 15 秒
const onVisible = () => { if (!document.hidden) refresh(); };
document.addEventListener('visibilitychange', onVisible);
window.addEventListener('focus', onVisible);
return () => { clearInterval(timer); /* 摘掉两个监听 */ };
// deps: [audience, refreshNotifications, role, refreshPending]
```

- **间隔 15000 ms（15 秒）**；页面隐藏时定时器照跑但 `refresh` 直接 return（省电），回到前台由 `visibilitychange` / `focus` 立刻补一次。
- 启停条件：`audience` 非空才启动；`useEffect` 依赖变化会重建定时器。
- 另有身份→信箱的选择逻辑（`MainLayout.tsx:124-128`）：`if (!role) return; loadNotifications(role === 'parent' ? 'parent' : 'child')`。
- 通知页自身也会 `load(targetAudience)`，`targetAudience = role === 'parent' ? 'parent' : 'child'`（`NotificationsPage.tsx:57-62`）。

### 2.6 `ready === false` 的降级

- 服务端 `NotificationBox.ready === false` 时 `load`/`refresh` 照常成功返回，`ready` 落进 state；此时 `items` / `unreadCount` 按空信箱处理（`src/types/notification.ts:37-38`：「此时前端按空信箱显示，不报错」）。
- UI 降级文案（`NotificationsPage.tsx:137-141`）：
  ```
  通知功能还没就绪（服务端通知表尚未创建），等家长执行一次数据库迁移就会出现。
  ```
- 失败态另有三种渲染（`NotificationsPage.tsx:143-154`）：
  - `error && items.length > 0` → 顶部 `RefreshFailedBar`，文案 `通知没刷新成功，下面是上次看到的内容`（保留旧列表，不把看过的通知藏起来）；
  - `loading && items.length === 0` → `PageLoading`；
  - `error && items.length === 0` → `ErrorState`（必须看得见，不能落进「暂时没有通知」空态）；
  - `visible.length === 0` → `EmptyState`，文案 `没有未读通知` / `暂时没有通知`（按 `filter` 区分）。
- 筛选：`visible = filter === 'unread' ? items.filter(n => n.status === 'unread') : items`（`NotificationsPage.tsx:64`）。
- 点击一条：`status === 'unread'` 才 `markRead(id)`（不 await，`.catch(() => undefined)`），有 `link` 就 `navigate(link)`（`NotificationsPage.tsx:82-87`）。
- 页头文案：`audience === 'parent' ? `${kidName}的打卡动态` : `${momName}说的话``，未读后缀 ` · ${unreadCount} 条未读` 否则 ` · 都看过了`（`NotificationsPage.tsx:111-112`）。

### 2.7 与后端交互汇总

| 动作 | 方法 + 路径 | 请求 body / query | 响应字段 | 失败处理 |
| --- | --- | --- | --- | --- |
| `fetchNotifications(audience, limit = 50)` | `GET /api/notifications?audience=<parent\|child>&limit=<max(1,floor(limit))>` | — | `{ items, unreadCount, ready }` | 抛 `ApiError`；`load` 落到 `error`，`refresh` 静默吞掉 |
| `markNotificationRead(id)` | `PATCH /api/notifications/{encodeURIComponent(id)}` | `{"status":"read"}` | `{ ok: boolean }` | `markRead` 里吞掉并 `refresh()` 兜底 |
| `markAllNotificationsRead(audience)` | `POST /api/notifications/read-all` | `{"audience": "<parent\|child>"}` | `{ ok: boolean; updated: number }` | `markAllRead` 先 `refresh()` 再 rethrow |

`limit` 在 API 层被规整为 `Math.max(1, Math.floor(limit))`（`api/notifications.ts:17`）。

---

## 3. useThemeStore

### 3.1 定位

文件头注释（`useThemeStore.ts:1-12`）：两件事放在一起是因为它们都影响「整个 App 长什么样」，也都由设置页控制：

- `themeId`：主题，**存本机 localStorage**（每台设备各选各的）；右上角太阳/月亮按钮也走这里，在「上次用的浅色」与「上次用的深色」之间来回切；
- `background`：全局背景图地址，**存服务端 settings 表**（两台设备看到同一张，且服务端知道它被引用，不会被「闲置照片清理」误删）。

真正的上色在 `App.tsx`：`themeId` 写到 `<html data-theme>`（`App.tsx:89`），图片写到 `--app-bg-image` 并切 `data-bg="on"/"off"`（`App.tsx:90-91`），同时把 `preset.palette.bg` 写成内联 `backgroundColor` 与 `<meta name="theme-color">`（`App.tsx:94-98`）。

### 3.2 七套主题（`src/theme/themes.ts`）

`ThemeId = 'original' | 'midnight' | 'sakura' | 'forest' | 'sunset' | 'crimson' | 'graphite'`（`themes.ts:19-26`）。
`DEFAULT_THEME_ID: ThemeId = 'original'`（`themes.ts:256`）——出厂默认，什么都不用设。

| id | name | description | swatch `[底, 卡片, 强调]` | dark | primary | bg / surface |
| --- | --- | --- | --- | --- | --- | --- |
| `original` | 原始 | 浅色卡片 + 深蓝主色，出厂默认 | `#f5f6fa / #ffffff / #1a1a2e` | `false` | `designTokens.colors.primary` | `designTokens.colors.bg` / `designTokens.colors.surface` |
| `midnight` | 午夜蓝 | 午夜蓝墨底 + 青蓝高光，晚上看不刺眼 | `#060c1c / #0e1a33 / #2b7fe0` | `true` | `#2b7fe0` | `#060c1c` / `#0e1a33` |
| `sakura` | 樱花粉 | 奶粉底 + 樱花主色，软软的一天 | `#fff5f8 / #ffffff / #e8628f` | `false` | `#e8628f` | `#fff5f8` / `#ffffff` |
| `forest` | 森林绿 | 薄荷底 + 森林绿，清清爽爽像早上 | `#f2f9f5 / #ffffff / #2f9e6e` | `false` | `#2f9e6e` | `#f2f9f5` / `#ffffff` |
| `sunset` | 暖阳橙 | 米白底 + 暖橙主色，像傍晚的客厅 | `#fff8f1 / #ffffff / #e07b39` | `false` | `#e07b39` | `#fff8f1` / `#ffffff` |
| `crimson` | 暗夜红 | 墨红底 + 霓虹红，像游戏界面（夜里护眼） | `#140609 / #1f0c11 / #f04a5a` | `true` | `#f04a5a` | `#140609` / `#1f0c11` |
| `graphite` | 石墨黑 | 近黑底 + 白墨 + 玻璃胶囊，笔记工具风（夜里最安静） | `#141414 / #242424 / #0f77f0` | `true` | `#0f77f0` | `#141414` / `#1f1f1f` |

`ThemePreset`（`themes.ts:55-66`）：`{ id, name, description, swatch: [string,string,string], dark: boolean, palette: ThemePalette }`。
`ThemePalette` 17 个字段（`themes.ts:29-53`）：`primary`、`primarySoft`（主色浅一档，用于渐变尾、选中底色）、`success`、`danger`、`warning`、`bg`、`surface`、`surfaceSoft`、`text`、`textSecondary`、`textTertiary`、`border`、`sider`（PC 侧边栏 / 暗色菜单底）、`siderSelected`、`segmentedSelected`（antd Segmented 选中项底）、`surfaceGlass`、`surfaceSoftGlass`。
`GLASS_LIGHT = 'rgba(255, 255, 255, 0.82)'`、`GLASS_SOFT_LIGHT = 'rgba(255, 255, 255, 0.7)'`（`themes.ts:68-69`），三套浅色主题的玻璃底都用这两个常量。

深色主题共 **3 套**（`midnight` / `crimson` / `graphite`），浅色 **4 套**（`original` / `sakura` / `forest` / `sunset`）。

工具函数：
- `isThemeId(value): value is ThemeId` = `THEMES.some(item => item.id === value)`（`themes.ts:261-263`）。
- `themePreset(id): ThemePreset` = `THEMES.find(item => item.id === id) ?? THEMES[0]`（`themes.ts:265-267`，**未知 id 回落到 `original`**）。
- `buildAntdTheme(id, hasBackground = false)`（`themes.ts:274-316`）：`algorithm = preset.dark ? darkAlgorithm : defaultAlgorithm`；`surface = hasBackground ? palette.surfaceGlass : palette.surface`；
  `colorBgLayout` / `bodyBg` 在 `hasBackground` 时是 `'transparent'`；`Layout.headerHeight: 56`；`Menu.itemBorderRadius: 999`；token 一律取自 `palette`（不写死色值）。

**是否跟随系统**：**不跟随**。没有任何 `prefers-color-scheme` / `mediaQuery` 参与主题选择；`themeId` 只来自 localStorage 或默认值。跟随系统这件事完全由用户手动点的那颗按钮替代。

### 3.3 持久化：三个键的配合

| 键名 | 常量 | 写入内容 | 位置 |
| --- | --- | --- | --- |
| `sekainook_theme` | `THEME_STORAGE_KEY`（`themes.ts:259`，注释「主题选择存在本机（每台设备各选各的，不跨设备同步）」） | 当前 `ThemeId` 明文（**不是 JSON**，直接 `setItem(key, id)`） | `useThemeStore.ts:35-41` |
| `sekainook_theme_light` | `LAST_LIGHT_KEY`（`useThemeStore.ts:48`） | 「上次用过的浅色主题」`ThemeId` 明文 | `useThemeStore.ts:51-57` |
| `sekainook_theme_dark` | `LAST_DARK_KEY`（`useThemeStore.ts:49`） | 「上次用过的深色主题」`ThemeId` 明文 | `useThemeStore.ts:51-57` |

三者都是**裸字符串**，没有 JSON 包装，所以 Dart 侧直接 `prefs.setString` / `getString`。

**配合逻辑**（读 → 决定初值 → 写）：

- `loadThemeId()`（`useThemeStore.ts:26-33`）：读 `sekainook_theme` → `isThemeId(raw) ? raw : DEFAULT_THEME_ID`；读异常（隐私模式）也回 `DEFAULT_THEME_ID`。**不做「深浅格」校验**。
- `saveThemeId(id)`（`:35-41`）：写 `sekainook_theme`；失败静默（注释「隐私模式：存不住也没关系，本次会话内仍然生效」）。
- `rememberBrightness(id)`（`:51-57`）：按 `themePreset(id).dark` 决定写哪个键——深色写 `sekainook_theme_dark`，浅色写 `sekainook_theme_light`；失败静默（注释「记不住就退回出厂的那套深浅主题」）。
- `loadBrightness(dark)`（`:59-68`）：
  ```ts
  const fallback: ThemeId = dark ? 'midnight' : DEFAULT_THEME_ID;   // 深→midnight，浅→original
  const raw = localStorage.getItem(dark ? LAST_DARK_KEY : LAST_LIGHT_KEY);
  if (isThemeId(raw) && themePreset(raw).dark === dark) return raw;  // 必须「是合法 id 且深浅相符」
  return fallback;
  ```
  注意 **`dark` 分支的出厂回落是硬编码的 `'midnight'`**（不是 `DEFAULT_THEME_ID`）。
- **store 创建时就登记一次**（`useThemeStore.ts:85-88`）：
  ```ts
  const initialThemeId = loadThemeId();
  rememberBrightness(initialThemeId);   // 首屏就把当前这套登记进它所属的深/浅格
  ```
  目的（`:87` 注释）：「免得第一次点切换时没有可回的目标」。移植时这一句千万别漏——它是「第一次点切换会跳错」的根因修复。

**切换主题时如何记住「上次的浅色/深色」**：

- `setThemeId(id)`（`useThemeStore.ts:95-99`）：`saveThemeId(id)` → `rememberBrightness(id)` → `set({ themeId: id })`。顺序固定：**先落盘两个键，再改 state**。
- `toggleBrightness()`（`useThemeStore.ts:101-106`）：
  ```ts
  const next = loadBrightness(!themePreset(get().themeId).dark); // 目标是「相反的那一档」
  saveThemeId(next); rememberBrightness(next); set({ themeId: next });
  ```
  即：从当前主题取 `dark`，取反，去对应的记忆键里读「上次那套」，拿到后同样「写当前键 + 写记忆格 + set」。若记忆格为空/非法/深浅不符，则落到 `midnight`（转深）或 `original`（转浅）。
- 读界面用 `useThemePreset()`（`:127-129`，`themePreset(useThemeStore(s => s.themeId))`）与 `useThemePalette()`（`:132-134`，`.palette`）。

### 3.4 State 与 action

`ThemeState`（`useThemeStore.ts:70-83`）：

| 字段 | 类型 | 初值 | 持久化 |
| --- | --- | --- | --- |
| `themeId` | `ThemeId` | `loadThemeId()`（`:91`） | 是 → `sekainook_theme`（+ 深/浅记忆键） |
| `background` | `string` | `''`（`:92`，`''` = 没设） | 否（localStorage 侧只有 `App.tsx` 的影子缓存，见 3.6） |
| `backgroundReady` | `boolean` | `false`（`:93`） | 否；语义「背景图是否已问过服务端（避免首屏先铺一层纯色再跳成照片）」 |

**`loadBackground(): Promise<void>`**（`useThemeStore.ts:108-115`）
1. `const { background } = await fetchSettings()` → `GET /api/settings`。
2. `set({ background: background ?? '', backgroundReady: true })`——`undefined`/`null` 归一成 `''`。
3. 失败：`set({ backgroundReady: true })` 并**吞掉异常**（注释「失败就当没设，不打扰用户」）——注意**不会把 `background` 清空**，保留旧值。
4. 调用时机：`App.tsx:82-84` 的 `useEffect(() => { void loadBackground(); }, [loadBackground])`，打开 App 时问一次。

**`saveBackground(url): Promise<string>`**（`useThemeStore.ts:117-122`）
1. `const { background } = await saveSettings({ background: url })` → `PATCH /api/settings`，body `{"background":"<url>"}`。
2. `next = background ?? ''`；`set({ background: next, backgroundReady: true })`；`return next`。
3. **失败不吞**：异常直接抛给调用方。调用侧（`SettingsPage.tsx:575-599`）：上传成功 `saveBackground(url)`，移除走 `saveBackground("")`（文案 `已移除背景图`），失败 `message.error(e.message ?? "移除失败，请重试")`。

> 与设置页的另一处联动：`SettingsPage.tsx:547` 调 `setThemeId(id)` 完成主题切换（点一下即生效并落盘）。

### 3.5 与后端交互

| 动作 | 方法 + 路径 | 请求 body | 响应字段 | 失败处理 |
| --- | --- | --- | --- | --- |
| `loadBackground` → `fetchSettings()` | `GET /api/settings` | — | `{ names, background, ready? }`（`api/settings.ts:13-19`） | 吞掉，只置 `backgroundReady = true` |
| `saveBackground(url)` → `saveSettings({background})` | `PATCH /api/settings`，`http.patch`（写请求，**不带 retry**） | `{"background": "<url>"}` | `{ names, background, ready? }` | 抛出异常，由设置页提示 |

`saveBackground` 传 `''` 即移除背景图（`:117-122` 注释「传 '' 表示移除」）。

### 3.6 背景图的本机影子缓存（属同一功能域，移植时需一并实现）

`App.tsx:55-60`：`const BG_CACHE_KEY = "sekainook_bg_cache_v1"`——背景图存在服务端，刷新时首帧拿不到，所以每台设备拿到后往本机存一份地址，交给 `index.html` 里那段内联脚本先铺上；只存服务端返回的稳定地址（`/api/images/xxx`）。

`App.tsx:100-110`：**只有 `backgroundReady` 为真时才动缓存**——否则首帧那个空字符串会把上一份缓存抹掉，下次刷新就又只剩纯色：
```ts
if (backgroundReady) {
  if (hasBackground) localStorage.setItem(BG_CACHE_KEY, background);
  else localStorage.removeItem(BG_CACHE_KEY);
}
```
`hasBackground = background !== ""`（`App.tsx:79`）。

---

## 4. useSettingsStore

### 4.1 定位与同步方向

文件头注释（`useSettingsStore.ts:1-6`）：「权威数据在服务端（D1 settings 表），localStorage 只当缓存：打开 App 先用缓存渲染，再去服务端对一次，这样两个人换手机也能看到同一套称呼。」

**同步方向（谁覆盖谁）**：

- 启动：`names` 初值 = `loadCache()`（本地缓存或默认值），立即可渲染；随后 `load()` 拉服务端并**用服务端值覆盖本地缓存与 state**（`useSettingsStore.ts:58-60`）。即**服务端覆盖本地**。
- 保存：`save(patch)` 是**只提交自己那一半**的 PATCH，成功后用**服务端返回的完整 `names`** 覆盖 state 与缓存（`:67-72`）。即**服务端返回值覆盖本地**，不是本地乐观值。
- 因此不存在本地写入先行的乐观更新：`save` 必须先成功返回。

`FamilyNames`（`src/types/settings.ts:12-21`）：`{ momCall, momNickname, kidCall, kidNickname }`，四项都是 `string`。
视角约定（`types/settings.ts:4-9`）：妈妈的界面里另一个人是「女儿」→ `kidCall`/`kidNickname`；妹妹的界面里另一个人是「妈妈」→ `momCall`/`momNickname`，她自己一律是「我」；**妈妈的身份由女儿设置，女儿的身份由妈妈设置（各改各的那一半）**。

`DEFAULT_FAMILY_NAMES`（`types/settings.ts:32-37`）：`{ momCall: '妈妈', momNickname: '', kidCall: '女儿', kidNickname: '' }`。
`FAMILY_NAME_KEYS`（`types/settings.ts:25-30`）：`['momCall','momNickname','kidCall','kidNickname']`。

### 4.2 状态字段

`SettingsState`（`useSettingsStore.ts:39-46`）：

| 字段 | 类型 | 初值 | 持久化 |
| --- | --- | --- | --- |
| `names` | `FamilyNames` | `loadCache()`（`:49`） | 是 → `sekainook_family_names`（JSON） |
| `loading` | `boolean` | `false`（`:50`） | 否 |
| `ready` | `boolean` | `false`（`:51`） | 否；注释「false = 服务端还没就绪（表没迁移 / 请求失败），当前用缓存或默认值」 |
| `load` | `() => Promise<void>` | — | — |
| `save` | `(patch: Partial<FamilyNames>) => Promise<FamilyNames>` | — | — |

注意：`useSettingsStore` 用的是 `create<SettingsState>((set, get) => ({...}))`——**直接返回对象**（`:48`），没有闭包变量。

### 4.3 `sekainook_family_names` 的读写与本地缓存策略

- 键名常量：`const CACHE_KEY = 'sekainook_family_names'`（`useSettingsStore.ts:12`）。
- 值：`JSON.stringify(names)`，即 `{"momCall":"妈妈","momNickname":"","kidCall":"女儿","kidNickname":""}`（`useSettingsStore.ts:31-37`）。
- **读（`loadCache`，`useSettingsStore.ts:15-29`）字段级容错**（「坏数据一律回默认值，不让设置问题拦住首页」）：
  ```ts
  momCall:     typeof parsed.momCall === 'string' && parsed.momCall ? parsed.momCall : DEFAULT_FAMILY_NAMES.momCall,
  momNickname: typeof parsed.momNickname === 'string' ? parsed.momNickname : '',
  kidCall:     typeof parsed.kidCall === 'string' && parsed.kidCall ? parsed.kidCall : DEFAULT_FAMILY_NAMES.kidCall,
  kidNickname: typeof parsed.kidNickname === 'string' ? parsed.kidNickname : '',
  ```
  逐字段规则：`momCall` / `kidCall` 要求是**非空 string**，否则回中文默认（`妈妈` / `女儿`）；`momNickname` / `kidNickname` 只要是 string 就收（**允许空字符串**，回落的 `''` 与默认值一致）。
  `raw` 为空（键不存在）→ 直接 `DEFAULT_FAMILY_NAMES`；`JSON.parse` 抛异常或 `getItem` 抛异常（隐私模式）→ 也 `DEFAULT_FAMILY_NAMES`（`:16-28`）。
- **写（`saveCache`，`useSettingsStore.ts:31-37`）**：`setItem` 抛异常被吞（注释「隐私模式 / 存储满：拿不到缓存也不影响本次使用」）。
- 写时机：`load()` 成功后（`:59`）与 `save()` 成功后（`:69`）各写一次。**没有定时写、没有退出时写**。

### 4.4 action 完整逻辑

**`load(): Promise<void>`**（`useSettingsStore.ts:54-64`）

1. `if (get().loading) return;`——**并发去重**（防重入；重复调用直接返回，不报错不排队）。
2. `set({ loading: true })`。
3. `const { names, ready } = await fetchSettings()` → `GET /api/settings`。
4. `saveCache(names)`（把服务端值写进本地缓存）。
5. `set({ names, ready: ready !== false, loading: false })`——**`ready` 用 `!== false` 判定**：服务端没回这个字段就算 `true`（老部署兼容）。
6. 失败：`set({ loading: false, ready: false })`，**保留当前 `names`（缓存/默认值）**，**吞掉异常**（注释「失败保留当前值（缓存/默认），不打扰用户”）。
   注意：失败时 **`ready` 被显式置回 `false`**，即使之前是 `true`。
7. 调用时机：`MainLayout.tsx:130-134`（`useEffect(() => { loadNames().catch(() => undefined); }, [loadNames])`，进 App 对一次）；`SettingsPage.tsx:138` 也取 `ready: namesReady` 做 UI 判断。

**`save(patch): Promise<FamilyNames>`**（`useSettingsStore.ts:67-72`）

1. `const { names } = await saveSettings(patch)` → `PATCH /api/settings`，body = patch（**只含要改的字段**，`SettingsPatch = Partial<FamilyNames> & { background?: string }`，`api/settings.ts:22`）。
2. `saveCache(names)`；`set({ names, ready: true })`——成功后**无条件把 `ready` 置 `true`**。
3. `return names`（服务端返回的完整称呼，调用方拿它算显示名）。
4. **失败不吞**：异常直接抛给调用方。`SettingsPage.tsx:632-633`：`message.error(e instanceof Error ? e.message : "保存失败，请重试")`。
5. 调用侧构造 patch（`SettingsPage.tsx:617-631`）：`nameTarget === 'kid'` 时提交 `{ kidCall: callValue || DEFAULT_FAMILY_NAMES.kidCall, kidNickname: nicknameValue }`，
   否则 `{ momCall: callValue || DEFAULT_FAMILY_NAMES.momCall, momNickname: nicknameValue }`；
   保存成功后 `clearNameDraft(nameTarget)`（草稿退休），提示 `已保存，界面上会显示「${displayName(saved, nameTarget)}」`。

### 4.5 称呼校验

校验逻辑**不在 store 里**，在 `src/types/settings.ts` 与设置页：

- `MAX_NAME_LENGTH = 12`（`types/settings.ts:40`，「一个称呼最多几个字（界面与接口同一口径）」）。
- `validateName(value): string | null`（`types/settings.ts:51-53`）：
  ```ts
  return value.trim().length > 12 ? `最多 ${MAX_NAME_LENGTH} 个字` : null;
  ```
  超长返回中文提示 **`最多 12 个字`**，合法返回 `null`。**只校验长度，不校验字符集**。
- 设置页用法（`SettingsPage.tsx:603-615`）：先对 `callValue` 与 `nicknameValue` 都 `trim()`；
  `const tooLong = validateName(callValue) ?? validateName(nicknameValue);` → 有值就 `message.error(`称呼${tooLong}`)`（最终文案形如 `称呼最多 12 个字`）并 return；
  再 `if (!callValue && !nicknameValue) message.error("称呼和昵称至少要填一个")` 并 return。
- **两个校验都在客户端**；服务端也会校验同一口径（注释「界面与接口同一口径」），但前端不做服务端错误文案的特殊映射，直接显示 `ApiError.message`。

### 4.6 派生 getter

**`displayName(names, who): string`**（`src/types/settings.ts:43-48`）：
```ts
const fallback = who === 'mom' ? DEFAULT_FAMILY_NAMES.momCall : DEFAULT_FAMILY_NAMES.kidCall; // '妈妈' / '女儿'
const call     = who === 'mom' ? names.momCall     : names.kidCall;
const nickname = who === 'mom' ? names.momNickname : names.kidNickname;
return (nickname || call || fallback).trim() || fallback;
```
即**昵称优先 → 称呼兜底 → 出厂中文兜底 → trim 后仍为空再回出厂值**。

- `useMomName()`（`useSettingsStore.ts:76-78`）= `displayName(useSettingsStore(s => s.names), 'mom')`。
- `useKidName()`（`useSettingsStore.ts:81-83`）= `displayName(..., 'kid')`。
- 消费点：通知页标题（`NotificationsPage.tsx:111`）、打卡成功文案 `「X」已提交，等${momName}审批`（`KidHome.tsx:273`、`:302`）、家长页/花园页标题等。

### 4.7 与后端交互汇总

| 动作 | 方法 + 路径 | 请求 body | 响应字段 | 失败处理 |
| --- | --- | --- | --- | --- |
| `load()` → `fetchSettings()` | `GET /api/settings` | — | `{ names: {momCall,momNickname,kidCall,kidNickname}, background: string, ready?: boolean }` | 吞掉；`loading=false, ready=false`，保留旧 `names` |
| `save(patch)` → `saveSettings(patch)` | `PATCH /api/settings` | 只含要改的字段，如 `{"kidCall":"女儿","kidNickname":"妹妹"}`（也可带 `background`） | 同上（返回**完整**设置） | 抛出，设置页提示 `e.message` 或 `保存失败，请重试` |

> 注意：`useThemeStore.loadBackground` 与 `useSettingsStore.load` **打的是同一个 `GET /api/settings`**，各自独立请求、各自取自己关心的字段（`background` / `names`）。移植时要么保持两次请求（行为等价），要么合并成一次并保证两边的 `ready`/`backgroundReady` 语义不变。

---

## 5. 四个 store 的持久化键总表

| 键名 | 归属文件 | 值形态 | 读取时机 | 写入时机 |
| --- | --- | --- | --- | --- |
| `sekainook_custom_tasks_v1` | `useCustomTasksStore.ts:16` | JSON `StoredPayload` | store 创建时一次（`:212`） | 每个改动 action（`:239/:253/:267/:273`） |
| `sekainook_theme` | `themes.ts:259` | 裸 `ThemeId` 字符串 | store 创建时（`useThemeStore.ts:86`） | `setThemeId`（`:96`）、`toggleBrightness`（`:103`） |
| `sekainook_theme_light` | `useThemeStore.ts:48` | 裸 `ThemeId` 字符串 | `loadBrightness(false)`（`:62`） | `rememberBrightness`（`:53`），含 store 创建时（`:88`） |
| `sekainook_theme_dark` | `useThemeStore.ts:49` | 裸 `ThemeId` 字符串 | `loadBrightness(true)`（`:62`） | `rememberBrightness`（`:53`），含 store 创建时（`:88`） |
| `sekainook_family_names` | `useSettingsStore.ts:12` | JSON `FamilyNames` | store 创建时（`:49`） | `load` 成功（`:59`）、`save` 成功（`:69`） |
| `sekainook_bg_cache_v1` | `App.tsx:60` | 裸图片地址字符串 | `index.html` 内联防闪脚本（不在 store 内） | `App.tsx:103-109`，**仅 `backgroundReady === true` 时** |

`useNotificationStore`：无持久化。

---

## 6. Dart 移植注意事项

### 6.1 跨 store 通用

1. **zustand 闭包变量必须显式建模**。`removedPresets`（`useCustomTasksStore.ts:214`）、`limit`（`useNotificationStore.ts:43`）不是 state，set 不触发重建，但跨 action 存活。
   Dart 侧放进 store 类的普通字段（`List<String> _removedPresets`、`int _limit`），**不要**塞进 `ChangeNotifier` 的通知载荷里，否则 UI 重建次数与原版不一致。
2. **「吞异常的 action」与「抛异常的 action」要严格对齐**，这是最容易在 Dart 里被 `try/catch` 一把抓平的地方：
   - 吞：`useCustomTasksStore` 全部（含 localStorage 失败）、`useNotificationStore.refresh`、`useThemeStore.loadBackground`、`useSettingsStore.load`、`markRead`。
   - 抛：`useNotificationStore.markAllRead`（**先 `refresh()` 再 rethrow**，`useNotificationStore.ts:136-137`）、`useThemeStore.saveBackground`、`useSettingsStore.save`。
   Dart 里对应「返回 `Future<void>` 且内部 catch 掉」vs「`Future<T>` 直接让异常冒泡」。
3. **浅合并 vs 深覆盖**：`set(partial)` 是浅合并。`markDone` 与 `removeTask` 里都**显式复制了 `doneDate`**（`{...get().doneDate}`）再改，
   而 `tasks` 每次都是新数组——Dart 里如果用可变 `Map`/`List` 就地改，会丢掉「新引用触发重建」的语义，也会让 `persist` 的时机变得隐晦。建议一律 copy-on-write。
4. **错误文案原文**（会被测试与 UI 断言比对）：
   `通知加载失败`（`useNotificationStore.ts:77`）、`未命名任务`（`useCustomTasksStore.ts:229`）、
   `最多 12 个字`（`types/settings.ts:52`）、`称呼和昵称至少要填一个` / `称呼最多 12 个字`（`SettingsPage.tsx:609`、`:613`）、
   `已全部标记为已读` / `没能全部已读，请稍后重试`（`NotificationsPage.tsx:93`、`:96`）、
   `通知功能还没就绪（服务端通知表尚未创建），等家长执行一次数据库迁移就会出现。`（`NotificationsPage.tsx:139`）、
   `通知没刷新成功，下面是上次看到的内容`（`NotificationsPage.tsx:145`）、`没有未读通知` / `暂时没有通知`（`NotificationsPage.tsx:154`）、
   `已保存，界面上会显示「X」`（`SettingsPage.tsx:631`）、`已移除背景图`（`SettingsPage.tsx:594`）。
5. **HTTP 层语义**：GET 自动重试 2 次（等待 400ms / 1200ms），写请求默认不重试（只有 `postLedgerRecord` 显式 `retry: true`，`familyLedger.ts:222`）；
   超时 12 秒；`status == 0` 表示网络层失败。Dart 的 `http`/`dio` 默认行为与这三点都不同，需要显式实现。
6. **`ApiError.message` 直接上屏**：`NotificationsPage` / `SettingsPage` 多处是 `e is Error ? e.message : '…'`，即优先显示服务端返回的 `error` 字段。
   移植时把 `{error}` 解析逻辑一并搬过去，否则用户会看到 Dart 侧通用文案而不是服务端文案。

### 6.2 useCustomTasksStore

7. **`beijingDayKey` 不能退化成 `DateTime.now()` 的本地日期**。它是「`now + 8h` 后取 UTC 字段」的固定东八区日历天（`useCustomTasksStore.ts:105-110`）。
   Dart 里应写 `DateTime.now().toUtc().add(Duration(hours: 8))` 然后取 `year/month/day`，**受设备时区影响就是 bug**。
8. **两套「今天」口径并存，别统一**：`beijingDayKey`（东八区，用于 `doneDate` / `countDoneToday`）与 `new Date(x).toDateString()`（本机时区，用于 `isRecordedToday` / `countTodaySubmissions`，`useCustomTasksStore.ts:326-332`、`taskRules.ts:16-22`）。
   移植时若把两者都换成同一套，会在跨时区设备上产生与 Web 版不同的置灰行为。
9. **`addTask` 的金额夹取顺序**：`Math.min(Math.max(Math.round(Math.abs(v)) || 1, 1), 200)`（`useCustomTasksStore.ts:226`）。
   注意 `|| 1` 在 `Math.round` 之后、下限夹取之前，所以 `0` → `1`、`NaN` → `1`、`-0.4` → `Math.round(0.4)=0` → `1`。
   Dart 里 `(v.abs().round()).abs()` 这类写法容易把 `0`/`NaN` 分支做错（`double.nan.round()` 会抛 `UnsupportedError`）。
10. **`addTask` 是同 id 覆盖且挪到末尾**（`:237` 先 filter 再 append），不是「已存在就跳过」。预置任务若被再次 `addTask` 同 id，会覆盖并把 `createdAt` 刷新。
11. **`ensurePresets` 的「不写盘」分支**（`:265` `if (!changed) return;`）：没有变更时既不改 state 也不写存档；Dart 里不要顺手每次都 `persist()`。
12. **`removedPresets` 的持久化隐形依赖**：它只存在闭包变量里，只靠 `persist` 顺带写回。任何绕过 `persist` 的写入（例如 Dart 侧单独 `save()`）都会把它丢掉，导致删掉的预置任务下次又回来。
13. **`isDoneToday` 的 `repeatDaily === false` 短路**（`:281`）：一次性任务完成过**永远** true，跨天也不复活；`repeatDaily` 缺省/`true` 才按 `day === beijingDayKey()`。
14. **`removeTask` 不删服务端流水**，也不删 `tasks` 之外的东西；`doneDate` 里对应条目要删。删除后重启 App 不会「复活」（`removedPresets` 只对预置任务生效；自定义任务靠存档里没有它）。
15. **`toTask` 的 type↔符号重算**（`:127-128`）：存档里 `value` 的符号被无视，按 `type` 重新赋号。手改存档为 `{"type":"earning","value":-50}` 会被读成 `+50`。
16. **`createdAt` 是 `''` 的两条预置定义**（`:74`、`:84`）：只有走 `ensurePresets` 落地才会被填上 `new Date().toISOString()`（`:262`）。所以「预置任务的 createdAt」= 首次补进列表的时间，不是某个固定出厂时间。
17. **`nextTaskId` 的撞号循环是「+1 毫秒」而不是自增后缀**（`:194`），生成的是 `custom_1735689600000` 这种纯数字毫秒串；`custom_` 与 `wish_` 各自独立检查。
18. **`USER_TASK_EXEC_ID` 绝不能换成自定义任务的本地 id**：服务端对未知 `task_id` 一律 403（`useCustomTasksStore.ts:18-22`、`KidHome.tsx:251`）。
    本地 `custom_<ts>` / `wish_<ts>` **只用于本地列表与 `doneDate`**，永不上报。
19. **`countDoneToday` 的 `status` 判定是「无状态视为 approved」**（`:302`），且用**东八区**过滤 `created_at`、按 `task_id` 去重、排除 `SYSTEM_TASK_IDS` 三条。四点缺一都会与服务端 `daily_min_tasks_penalty` 口径分叉。
20. **预置任务的两条 id 字符串本身是 `custom:` 前缀**（`custom:english_words10`），看起来像本地生成 id 但其实是服务端登记的 task_id；不要因为前缀像 `custom_` 就当成同类。

### 6.3 useNotificationStore

21. **两个竞态守卫的位置与副作用不同**：`load` 的守卫 `return` 时**不改 `loading`**（会一直挂着 `loading: true`，`useNotificationStore.ts:66`）；`refresh` 的守卫则什么都不用改。Dart 里若「顺手把 loading 置 false」会与原版 UI 表现不同。
22. **`load` 只在「换身份」时清空**（`switching`，`:55-60`）：同一身份重新 `load` 保留旧 `items`，这是下拉刷新不闪空的依赖。
23. **`markRead` 的两个提前返回条件**（`:100-101`）：不在 `items` 里、或已是 `read`，都直接返回**且不发请求**。因此「标记一条不在当前页的通知」在本 store 里是空操作——页码之外的通知要靠 `markAllRead`。
24. **`markAllRead` 的 `unreadCount === 0` 短路**（`:120`）：未读数为 0 时按钮也是 disabled（`NotificationsPage.tsx:117`），两层一致。
25. **`markAllRead` 失败必须 rethrow**：不要为了「统一错误处理」把它也吞掉——那正是文件注释里记录的已修复 bug（`:132-135`）。Dart 侧 `Future<void>` 要让异常冒泡到 UI 弹 `没能全部已读，请稍后重试`。
26. **轮询参数**：间隔 **15000ms**，`if (!audience) return`，`if (document.hidden) return`（Dart/Flutter 对应 `AppLifecycleState`），并在 `visibilitychange` 与 `focus` 两个事件上补一次；
    待审批轮询（`refreshPending`）**只在 `role === 'parent'`** 时跑（`MainLayout.tsx:141-145`）。
27. **`ready === false` 不是错误**：`markRead` / `markAllRead` 仍会照常发请求；UI 只提示「通知功能还没就绪…」。不要把 `ready === false` 与 `error != null` 合并成同一个状态。
28. **`unreadCount` 与 `items` 是两个独立来源**：未读数来自服务端计数、不受分页影响；本地乐观更新只做 `-1` / 归零。因此 `items` 里 `status === 'unread'` 的条数**不等价于** `unreadCount`（页码只取前 50 条），Dart 里不要用「列表里未读条数」去算角标。
29. **`fetchNotifications` 的 `limit` 规整**：`Math.max(1, Math.floor(limit))`（`api/notifications.ts:17`）。默认 50。

### 6.4 useThemeStore

30. **`rememberBrightness(initialThemeId)` 必须在 store 初始化时执行一次**（`useThemeStore.ts:88`）。漏掉它的症状：第一次点左右切换按钮会跳到「出厂主题」而不是「上次用的那套」。
31. **深色回落的出厂值是硬编码 `'midnight'`，不是 `DEFAULT_THEME_ID`**（`useThemeStore.ts:60`）。浅色回落才是 `'original'`。写成对称的两行很容易错。
32. **`loadBrightness` 的合法性判定包含「深浅必须相符」**：`isThemeId(raw) && themePreset(raw).dark === dark`（`:63`）。
    所以往 `sekainook_theme_light` 里写入一个深色 id（或反之）会被判为非法并回落——移植时两个键别写反。
33. **三个键都是裸字符串，不是 JSON**（`setItem(key, id)`）。Dart 里 `prefs.setString` 直接对应；用 `jsonEncode` 会与 Web 版不兼容（若要做数据迁移/互通就会读不出来）。
34. **`isThemeId` 是唯一合法性来源**（`themes.ts:261-263`），`themePreset` 对未知 id 静默回落 `THEMES[0]`（`:266`）。Dart 枚举别用 `values.byName` 抛异常版本。
35. **没有「跟随系统」**：任何 `MediaQuery.platformBrightness` 驱动的自动换主题都是新增行为，会与 Web 版不一致（Web 版只有 `sekainook_theme` 一个来源）。
36. **主题不跨设备同步，背景图跨设备同步**（`useThemeStore.ts:5-9`）：`themeId` 只在本机 localStorage，`background` 走 `PATCH /api/settings`。Dart 侧别把 themeId 顺手也存服务端。
37. **`loadBackground` 失败时不清空 `background`、但一定把 `backgroundReady` 置 `true`**（`:112-114`）。`backgroundReady` 的语义是「已问过服务端」，不是「拿到了值」——`App.tsx:103` 的缓存写入完全依赖它，写成「成功才置 true」会让首屏影子缓存永远不更新。

### 6.5 useSettingsStore

38. **`load` 的重入保护**：`if (get().loading) return;`（`useSettingsStore.ts:55`）——第二次调用**直接返回、不排队、不抛错**。Dart 里用 `if (_loading) return;` 即可，别改成 `await` 同一个 future（会让调用方拿到别人的结果语义）。
39. **`ready` 的两个取值细节**：`load` 成功用 `ready !== false`（缺省即 `true`），失败显式置 `false`；`save` 成功无条件置 `true`（`:60`、`:62`、`:70`）。
40. **`loadCache` 逐字段容错规则不对称**（`:21-24`）：`momCall`/`kidCall` 空字符串会回默认中文；`momNickname`/`kidNickname` 空字符串**原样保留**。
41. **`save` 返回服务端完整 `names` 并覆盖本地**，不是本地 patch 合并（`:68-71`）。Dart 里若先本地合并再发请求，会在「另一半被对方改了」时产生错位。
42. **客户端校验只有两条**：长度 `> 12`（`trim()` 后）与「称呼和昵称不能同时为空」。**没有必填、没有字符集、没有去重校验**；且校验不在 store 里，`save` 方法本身不做任何校验（调用方负责）。
43. **`displayName` 的三级兜底 + trim**（`types/settings.ts:47`）：`(nickname || call || fallback).trim() || fallback`。注意 `trim()` 在**最外层**：nickname 是空格串时会被 trim 成空，然后… 直接返回 `fallback`（因为 `|| fallback` 在 trim 之后），**不会回退到 call**。这个细节照抄才能一致。
44. **`GET /api/settings` 会被两个 store 各请求一次**（`loadBackground` 与 `load`）；两条路径的失败语义不同（一个吞、一个也吞但会把 `ready` 置 false），合并请求时不要顺手把 `ready` 的语义改掉。
