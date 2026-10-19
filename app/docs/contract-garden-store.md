# SekaiNook 花园状态层（`useGardenStore.ts`）行为契约

> **用途**：Flutter 重写（`E:\Git\SekaiNook-App`）时状态层逐条等价移植的唯一依据。
> **主源文件**：`E:\Git\SekaiNook\src\store\useGardenStore.ts`（979 行，React + zustand `create`）。
> **对读文件**：`src/config/garden.ts`、`src/types/garden.ts`、`src/api/familyLedger.ts`、`src/api/http.ts`、`src/store/useFamilyStore.ts`、`src/types/family.ts`、`src/layouts/GardenLayout.tsx`、`functions/_lib/rules.ts`、`functions/api/ledger/index.ts`、`functions/api/ledger/summary.ts`。
> 下文所有 `文件:行号` 均指 Web 仓库 `E:\Git\SekaiNook`。

## 0. 模块总览

- 模块只有**一个写入口**：私有函数 `commit(patch)`（`src/store/useGardenStore.ts:510-542`）。所有 action 都只构造 `Partial<GardenStore>` 交给 `commit`，由 `commit` 统一重算 4 个派生值（`pendingDelta` / `cachedSun` / `balance` / `completedCount`）并落盘。
- store 由 `create<GardenStore>((_set, get) => ({...}))` 建立（`:649`）；`_set` **未被使用**，`commit` 内部直接调用 `useGardenStore.setState(...)`。因此不能把 `commit` 想成「局部 set」，它是读最新 state 的函数式 setState。
- 模块级可变状态（**不在 store 里**）：`let flushing = false`（`:545`，补发并发闸）、`let syncLoopReady = false`（`:631`，监听器只挂一次）。
- 模块级导出：`ShopBuyResult`（类型，`:51`）、`PendingGardenOp`（接口，`:54-65`）、`useGardenStore`（`:649`）、`todayKey()`（`:193`）、`resolveSunBase(input)`（`:424`）。
- `init()` 不在模块加载时自动调用；调用点是花园布局挂载（`src/layouts/GardenLayout.tsx:88-91`：`useEffect(() => { init(); }, [init])`），可重复调用。

**常量**（`src/store/useGardenStore.ts`）：

| 常量 | 值 | 行 |
| --- | --- | --- |
| `STORAGE_KEY` | `'sekainook_garden_state'` | 27 |
| `MIGRATED_KEY` | `'sekainook_garden_migrated'` | 33 |
| `PENDING_KEY` | `'sekainook_garden_pending'` | 38 |
| `MIGRATION_LEGACY_ID` | `'mig_legacy'` | 40 |
| `MIGRATION_SHOP_ID_PREFIX` | `'mig_shop_'` | 41 |
| `FLUSH_INTERVAL_MS` | `30_000` | 44 |
| `POEM_TASK_ID` | `'poem'` | 47 |
| `CHINESE_TASK_ID` | `'chinese'` | 48 |

**外部常量**：`GARDEN_MAX_DECOR = 3`（`src/config/garden.ts:113`）；`GARDEN_LEGACY_MAX = 2000`（`src/api/familyLedger.ts:11`，与 `functions/_lib/rules.ts:135` 必须一致）；`GARDEN_TASKS` 奖励合计 `GARDEN_DAILY_TASK_REWARD = 110`（`src/config/garden.ts:110`）；任务奖励 10/15/15/20/10/5/20/15，练习奖励 5/5/10（次数上限 3/2/1），古诗奖励全部 10，商城价格 60/80/100/120/150/200。

---

## 1. 状态字段清单

### 1.1 完整字段表（初值取自 `create` 对象，`:650-677`）

| 字段 | 类型 | 初值 | 落 `sekainook_garden_state` | 派生 | 语义 |
| --- | --- | --- | --- | --- | --- |
| `balance` | `number` | `0` | ✅ | ✅ 每次 `commit` 重算 | 花园阳光**显示余额** = `cachedSun + pendingDelta`。页面直接读它（`GardenLayout.tsx:82`、`OverviewPage.tsx:15`） |
| `tasks` | `GardenTask[]` | `GARDEN_TASKS` | ✅ | — | 今日任务列表（8 条，含 `done` / `completedAt`） |
| `badges` | `Badge[]` | `GARDEN_BADGES` | ✅ | 由 `resolveBadges` 更新 | 7 枚勋章（含 `earned`） |
| `streakDays` | `number` | `0` | ✅ | 由 `nextStreak` 更新 | 连续学习天数（跨天累计，不重置） |
| `completedCount` | `number` | `0` | ✅（但从不读回） | ✅ `tasks.filter(t => t?.done).length` | **今日完成的花园任务数**。永远 ≤ `tasks.length` |
| `totalCompleted` | `number` | `0` | ✅ | 每次活动 `+1` | **累计活动次数**（背 3 首诗算 3 次；不是去重后的天数） |
| `lastActiveDate` | `string \| null` | `null` | ✅ | 活动日 | YYYY-MM-DD 本地时区，最近一次完成任务/背诗/练习的日期 |
| `poemCount` | `number` | `0` | ✅ | `recitePoem` 时 `+1` | 累计背会古诗首数 |
| `gardenCareDays` | `number` | `0` | ✅ | `nextCompletionStats` / `careForGarden` | 累计照顾花园**自然日**数（按 `lastGardenedDate` 去重） |
| `ownedItems` | `string[]` | `[]` | ✅ | `buyItem` 追加；`mergeOwnedItems` 与账本并集；拒绝时移除 | 已拥有商品 id |
| `equippedAvatar` | `string \| null` | `null` | ✅ | `equipItem`/`unequipItem` | 正戴的头像框 id |
| `equippedTitle` | `string \| null` | `null` | ✅ | 同上 | 正挂的称号 id |
| `equippedDecor` | `string[]` | `[]` | ✅ | 同上，最多 3 件，**先挂的在前** | 花园装饰 id 列表 |
| `todayPoemIds` | `string[]` | `[]` | ✅ | `recitePoem` 追加 | 今日已背会的古诗 id（同诗同日去重） |
| `poemDate` | `string` | `''` | ✅ | 动作里写 `today` | `todayPoemIds` 所属的自然日 |
| `chineseSteps` | `Record<string, number>` | `{}` | ✅ | `completeChineseStep` 自增 | 今日语文练习打卡次数（practiceId → 次数） |
| `chineseDate` | `string` | `''` | ✅ | 动作里写 `today` | `chineseSteps` 所属的自然日 |
| `todayEarned` | `number` | `0` | ✅ | 入账时累加（不含消费） | 今日实际入账阳光 |
| `todayEarnedDate` | `string` | `''` | ✅ | 动作里写 `today` | `todayEarned` 所属的自然日 |
| `lastWaterDate` | `string \| null` | `null` | ✅ | `careForGarden` | 最近一次**浇水**的自然日（只管浇水） |
| `lastGardenedDate` | `string \| null` | `null` | ✅ | 活动 / 浇水 | 最近一次「照顾花园」的自然日（去重基准） |
| `tasksDate` | `string` | `''` | ✅ | `init` / `completeTask` | `tasks` 所属自然日 |
| `summarySun` | `number \| null` | `null` | ❌ | `refreshLedger` / `settleOp` | 全量余额接口给的权威阳光（不含未同步增量） |
| `cachedRecords` | `LedgerRecord[]` | `[]` | ❌ | `refreshLedger` | 本地缓存的花园流水（仅按前缀过滤） |
| `cachedSun` | `number` | `0` | ✅ | ✅ `resolveSunBase(...)` | 上次算出的权威余额（离线冷启动兜底） |
| `pending` | `PendingGardenOp[]` | `[]` | ❌（另存 `sekainook_garden_pending`） | — | 离线/未入账的乐观操作队列，**先到先发** |
| `pendingDelta` | `number` | `0` | ❌ | ✅ `pending.reduce((s, op) => s + op.amount, 0)` | 未同步增量金额之和 |

### 1.2 持久化子集 `PersistedGarden`（逐字，`:157-182`）

```ts
/** 需要持久化的字段（完整写入，避免局部保存覆盖其它字段） */
type PersistedGarden = Pick<
  GardenStore,
  | 'balance'
  | 'tasks'
  | 'badges'
  | 'streakDays'
  | 'completedCount'
  | 'totalCompleted'
  | 'lastActiveDate'
  | 'poemCount'
  | 'gardenCareDays'
  | 'ownedItems'
  | 'equippedAvatar'
  | 'equippedTitle'
  | 'equippedDecor'
  | 'todayPoemIds'
  | 'poemDate'
  | 'chineseSteps'
  | 'chineseDate'
  | 'todayEarned'
  | 'todayEarnedDate'
  | 'lastWaterDate'
  | 'lastGardenedDate'
  | 'tasksDate'
  | 'cachedSun'
>;
```

**注意**：`completedCount` 在持久化白名单里，但 `init` **不读回**（见 §4.13）；`summarySun` / `cachedRecords` / `pending` / `pendingDelta` 都不进这个键。

### 1.3 三个派生值的精确表达式（`commit`，`:510-537`）

```ts
const pendingDelta = pending.reduce((sum, op) => sum + op.amount, 0);
const cachedSun = resolveSunBase({ summarySun, cachedRecords, cachedSun: patch.cachedSun ?? state.cachedSun });
const completedCount = Array.isArray(tasks) ? tasks.filter((task) => task?.done).length : 0;
// 最终写回：
{ ...patch, pending, pendingDelta, cachedSun, balance: cachedSun + pendingDelta, completedCount }
```

- 这 4 个键**总是**被覆盖，即使 `patch` 里没写。
- `cachedRecords` 用 `patch.cachedRecords ?? state.cachedRecords`（传 `[]` 有效，传 `undefined` 保留）。
- 其余字段是 `{...patch}` 浅合并，不传就不动。

---

## 2. 持久化格式

### 2.1 三个 localStorage 键

| 键 | 内容 | 谁写 | 何时写 |
| --- | --- | --- | --- |
| `sekainook_garden_state` | `PersistedGarden` 的 JSON（单对象，23 个字段全量写） | `saveState`（`:376-382`） | **每一次 `commit` 之后**（`:539`），包括 init / 每个 action / `settleOp` / `refreshLedger` |
| `sekainook_garden_migrated` | 字符串 `'1'`（只判「非 null」） | `writeMigratedFlag`（`:393-399`） | `init` 里「无需迁移」时（`:759`）；或 `markMigratedIfSettled` 判定迁移流水全部有结果时（`:568-572`） |
| `sekainook_garden_pending` | `PendingGardenOp[]` 的 JSON 数组 | `savePending`（`:412-418`） | 仅在 `commit` 的 `patch.pending` 存在时（`:541`）：压队列（完成/背诗/练习/购买）、补发出队（`settleOp`） |

### 2.2 `sekainook_garden_state` 的 JSON 形状（真实示例）

```json
{
  "balance": 130,
  "tasks": [
    { "id": "poem", "name": "背一首古诗", "duration": 10, "description": "背诵并理解一首古诗",
      "reward": 10, "icon": "book", "done": true, "completedAt": "2025-01-02T03:04:05.678Z" },
    { "id": "chinese", "name": "语文预习 15 分钟", "duration": 15, "description": "预习明天要学的课文",
      "reward": 15, "icon": "read", "done": false }
  ],
  "badges": [
    { "id": "sunrise", "name": "第一缕阳光", "description": "完成第一个任务", "icon": "sun", "earned": true }
  ],
  "streakDays": 3,
  "completedCount": 1,
  "totalCompleted": 12,
  "lastActiveDate": "2025-01-02",
  "poemCount": 5,
  "gardenCareDays": 4,
  "ownedItems": ["avatar_sun", "decor_rainbow"],
  "equippedAvatar": "avatar_sun",
  "equippedTitle": null,
  "equippedDecor": ["decor_rainbow"],
  "todayPoemIds": ["jingyesi"],
  "poemDate": "2025-01-02",
  "chineseSteps": { "read_aloud": 1, "new_words": 2 },
  "chineseDate": "2025-01-02",
  "todayEarned": 35,
  "todayEarnedDate": "2025-01-02",
  "lastWaterDate": "2025-01-02",
  "lastGardenedDate": "2025-01-02",
  "tasksDate": "2025-01-02",
  "cachedSun": 130
}
```

- `tasks` 元素类型见 `src/types/garden.ts:2-17`：`{ id: string; name: string; duration: number; description: string; reward: number; icon: string; done: boolean; completedAt?: string }`（`completedAt` 是 `new Date().toISOString()` 的 UTC ISO 串，可能缺席）。
- `badges` 元素类型见 `src/types/garden.ts:20-27`：`{ id: string; name: string; description: string; icon: string; earned: boolean }`。
- `cachedSun` 由 `toSafeAmount` 规整过（`Math.round`，可为负/0），写入时**已包含 pendingDelta 之外的一切**；注意字段名叫 `cachedSun` 但写的是 `resolveSunBase` 的结果（权威基准值），`balance` 才是显示值。

### 2.3 `sekainook_garden_pending` 的元素结构（`PendingGardenOp`，`:54-65`）

```ts
export interface PendingGardenOp {
  /** 客户端生成的幂等 id：重试必须复用同一个（服务端靠主键去重） */
  id: string;
  /** 账本 task_id：'garden:xxx' / 'garden_shop:xxx' / 'garden_legacy' */
  taskId: string;
  kind: 'earn' | 'spend';
  /** 正数加分、负数扣分；乐观值就是它 */
  amount: number;
  /** 购买类操作的商品 id（被服务端拒绝时用来收回物品） */
  itemId?: string;
  at: number;
}
```

示例：`[{"id":"mig_legacy","taskId":"garden_legacy","kind":"earn","amount":130,"at":1735780000000},{"id":"mig_shop_avatar_sun","taskId":"garden_shop:avatar_sun","kind":"spend","amount":-60,"itemId":"avatar_sun","at":1735780000000}]`

### 2.4 逐字读写代码（`:365-418`）

```ts
/** 从 localStorage 读取状态 */
function loadState(): Partial<GardenStore> {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

/** 保存状态到 localStorage（写入失败不能影响内存里的账） */
function saveState(state: PersistedGarden): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  } catch {
    // 隐私模式 / 配额满：这一份存不下就存不下，内存里的账照常
  }
}

/** 老数据迁移标志：读过就不再搬（标志位本身丢了也不要紧，迁移 id 是确定性的） */
function readMigratedFlag(): boolean {
  try {
    return localStorage.getItem(MIGRATED_KEY) !== null;
  } catch {
    return false;
  }
}

function writeMigratedFlag(): void {
  try {
    localStorage.setItem(MIGRATED_KEY, '1');
  } catch {
    // 写不进去也不影响这次的账
  }
}

/** 读取离线队列（坏数据一律丢掉，宁可少发一笔也别拿它去记账） */
function loadPending(): PendingGardenOp[] {
  try {
    const raw = localStorage.getItem(PENDING_KEY);
    return raw ? toSafePendingOps(JSON.parse(raw)) : [];
  } catch {
    return [];
  }
}

/** 写离线队列（写入失败不能影响内存里的账） */
function savePending(ops: PendingGardenOp[]): void {
  try {
    localStorage.setItem(PENDING_KEY, JSON.stringify(ops));
  } catch {
    // 存不下就存不下：内存里的队列还在，本次会话照样补发
  }
}
```

`commit` 里的落盘两行（`:538-541`）：

```ts
const state = useGardenStore.getState();
saveState(toPersisted(state));
// 离线队列单独存一个键：只有它变了才写，免得每次打卡都整车重写一遍
if (patch.pending) savePending(state.pending);
```

### 2.5 读档时的脏数据清洗（全部在 `init` 之前/之中使用）

| 函数 | 行 | 行为 |
| --- | --- | --- |
| `toSafeCount(value)` | 198-200 | 有限数且 `> 0` → `Math.floor`，否则 `0`（负数、`NaN`、`Infinity`、字符串一律 0） |
| `toSafeAmount(value)` | 203-205 | 有限数 → `Math.round`，否则 `0`（**0 与负数保留**，所以不能复用 `toSafeCount`） |
| `toSafeStringArray(value)` | 208-210 | 非数组 → `[]`；数组只保留 `typeof item === 'string'` 的项（**不去重、不裁剪空串**） |
| `toSafeId(value)` | 213-215 | 非空字符串 → 原值，否则 `null`（空串算「没设」） |
| `toSafeCountRecord(value)` | 218-226 | 非对象 → `{}`；每项过 `toSafeCount`，只保留 `> 0` 的键 |
| `toSafePendingOps(value)` | 232-254 | 非数组 → `[]`；逐条要求 `id` 非空字符串且未出现（`Set` 去重）、`taskId` 非空字符串、`kind ∈ {'earn','spend'}`、`amount` 有限数（`Math.round`）；`itemId` 只在非空字符串时带上；`at` 非有限数时归 `0`。**任何一项不满足就整条丢弃**（宁可少发一笔也不拿坏数据记账） |

---

## 3. 日切重置

### 3.1 「今天」的定义

```ts
/** 本地日期键（YYYY-MM-DD） */
function toDateKey(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

/** 今日日期键（供页面判断「今天是否已打卡」） */
export function todayKey(): string {
  return toDateKey(new Date());
}
```
（`:184-195`）

- 用 `getFullYear/getMonth/getDate` → **设备本地时区**的 `YYYY-MM-DD`，**没有东八区处理**。
- 东八区只出现在服务端日结算路径（`src/api/familyLedger.ts:131-141` 的 `expectedSettleDay`、服务端 `beijingDayBounds`），花园 store 完全不使用；两套「今天」口径不同，不要混。
- 页面侧判断「今天」也用 `todayKey()`：`ChinesePage.tsx:13`、`GardenPage.tsx:27`、`PoemPage.tsx:13`、`RecordsPage.tsx:17`。

### 3.2 重置规则表（数据 ↔ 伴生日期字段 ↔ 重置触发点）

| 数据 | 伴生日期字段 | 判定 | 重置发生处 |
| --- | --- | --- | --- |
| `tasks[].done` | `tasksDate` | `saved.tasksDate === today` | **只有 `init`**：不等则整份替换为 `GARDEN_TASKS`（`:724`）。`completeTask` 会写 `tasksDate: today`，但**不重置已完成项** |
| `todayPoemIds` | `poemDate` | `state.poemDate === today` | `init`（`:743`）、`completeTask`（`:792`）、`recitePoem`（`:810`）、`completeChineseStep`（`:885`）：不等则 `[]` |
| `chineseSteps` | `chineseDate` | `state.chineseDate === today` | 同上四处对称逻辑（`init` `:745`、`completeTask` `:794`、`recitePoem` `:842`、`completeChineseStep` `:857`）：不等则 `{}` |
| `todayEarned` | `todayEarnedDate` | `source.todayEarnedDate === today` | `init`（`:747`，另见 legacy 兜底）、`nextCompletionStats`（`:329`）：`(source.todayEarnedDate === today ? source.todayEarned : 0) + reward` |
| 「今天浇过水没有」 | `lastWaterDate`（自身即日期） | `state.lastWaterDate === today` | 不重置；判定在 `careForGarden`（`:900`） |
| `gardenCareDays` 去重 | `lastGardenedDate` | `state.lastGardenedDate === today` | 不重置；判定在 `nextCompletionStats`（`:330-331`）与 `careForGarden`（`:903-904`） |
| `streakDays` | `lastActiveDate` | `nextStreak` | 不重置（跨天累计） |
| `poemCount` / `totalCompleted` / `ownedItems` / `equipped*` / `badges.earned` | — | — | 不重置（永久累计） |

### 3.3 日切时机与已知缺口

- **重置只在 `init()` 与各 action 的惰性判定里发生**；没有定时器/跨零点监听。花园长时间挂着不重进布局时，`tasks` 的 `done` 标记会一直保留到下次 `init`。
- 只有 `completeTask` 会写 `tasksDate`；`recitePoem`（`:818-846`）、`completeChineseStep`（`:865-891`）、`careForGarden`（`:906-917`）都**不写** `tasksDate`（移植时保持原样，别"顺手补上"）。
- `init` 无条件把 `poemDate` / `chineseDate` / `todayEarnedDate` / `tasksDate` 写成 `today`（`:744,746,748,751`），不管是否重置。

---

## 4. 每个函数 / 私有工具的完整逻辑

### 4.1 `nextStreak(lastActiveDate, streakDays, today): number`（`:256-262`）

```ts
function nextStreak(lastActiveDate: string | null, streakDays: number, today: string): number {
  if (!lastActiveDate) return 1;
  if (lastActiveDate === today) return streakDays;
  const yesterday = toDateKey(new Date(Date.now() - 86400000));
  return lastActiveDate === yesterday ? streakDays + 1 : 1;
}
```

- `yesterday` = 当前时刻减 `86400000` ms 后再取本地日期（不是「日历昨天」；中国无夏令时，等价）。
- 语义：昨天活动过 → `+1`；今天已活动过 → 不变（同日多次活动不叠加）；断档 → 归 1。

### 4.2 `resolveBadges(badges, stats): Badge[]`（`:265-285`）

```ts
function resolveBadges(badges, stats): Badge[] {
  const unlocked: Record<string, boolean> = {
    sunrise: stats.totalCompleted >= 1,
    gardener: stats.totalCompleted >= 10,
    streak3: stats.streakDays >= 3,
    week_champ: stats.streakDays >= 7,
    poet: stats.poemCount >= 10,
    plant_warrior: stats.gardenCareDays >= 7,
    sun_rich: stats.balance >= 500,
  };
  return badges.map((b) => (unlocked[b.id] ? { ...b, earned: true } : b));
}
```

- 入参：`badges`（当前数组）、`stats: { totalCompleted, balance, streakDays, poemCount, gardenCareDays }`。
- **单调**：只置 `earned = true`，从不撤销；`unlocked` 里没有的 id 原样返回。
- 返回**新数组**（`map`），元素为浅拷贝（仅 `earned` 变）。

### 4.3 `nextCompletionStats(source, reward, today): CompletionStats`（`:319-334`）

```ts
function nextCompletionStats(source: CounterSource, reward: number, today: string): CompletionStats {
  return {
    balance: source.balance + reward,
    streakDays: nextStreak(source.lastActiveDate, source.streakDays, today),
    totalCompleted: source.totalCompleted + 1,
    lastActiveDate: today,
    todayEarned: (source.todayEarnedDate === today ? source.todayEarned : 0) + reward,
    gardenCareDays:
      source.lastGardenedDate === today ? source.gardenCareDays : source.gardenCareDays + 1,
    lastGardenedDate: today,
  };
}
```

- `CounterSource` = `Pick<GardenStore, 'balance'|'streakDays'|'totalCompleted'|'lastActiveDate'|'todayEarned'|'todayEarnedDate'|'gardenCareDays'|'lastGardenedDate'>`（`:299-309`）。
- **不产 `completedCount`**（理由见 `:311-318` 与 `:521-524`：分子分母必须同口径，否则会出现 11/8）。
- `balance: source.balance + reward` 用的是**显示余额**（含 `pendingDelta`）。
- `totalCompleted + 1` **每次活动都加**（背 3 首诗 = +3，语文练习每次打卡都 +1）。
- `gardenCareDays` 任一种花园活动都算一天照顾，同日只记一次。

### 4.4 `toPersisted(state): PersistedGarden`（`:336-363`）

逐字段拷贝 23 个键，顺序：`balance, tasks, badges, streakDays, completedCount, totalCompleted, lastActiveDate, poemCount, gardenCareDays, ownedItems, equippedAvatar, equippedTitle, equippedDecor, todayPoemIds, poemDate, chineseSteps, chineseDate, todayEarned, todayEarnedDate, lastWaterDate, lastGardenedDate, tasksDate, cachedSun`。**无任何转换**。

### 4.5 `resolveSunBase(input): number`（导出，`:424-433`）

```ts
export function resolveSunBase(input: {
  summarySun: number | null;
  cachedRecords: LedgerRecord[];
  cachedSun: number;
}): number {
  const { summarySun, cachedRecords, cachedSun } = input;
  if (typeof summarySun === 'number' && Number.isFinite(summarySun)) return summarySun;
  if (cachedRecords.length > 0) return calcGardenBalance(cachedRecords);
  return Number.isFinite(cachedSun) ? cachedSun : 0;
}
```

三段回退：① 全量接口值 → ② 本地花园流水求和（`calcGardenBalance`，`src/api/familyLedger.ts:342-344`，只计 `status` 为空或 `approved` 的花园记录）→ ③ 上次存的 `cachedSun`。注意 `cachedRecords.length > 0` 就采用 ②，哪怕算出来是 0。

### 4.6 操作工场：`earnOp` / `spendOp` / `pushOp` / `isMigrationOp`（`:435-453`）

```ts
function earnOp(taskId: string, amount: number): PendingGardenOp {
  return { id: createRequestId(), taskId, kind: 'earn', amount, at: Date.now() };
}
function spendOp(taskId: string, itemId: string, cost: number): PendingGardenOp {
  return { id: createRequestId(), taskId, kind: 'spend', amount: -cost, itemId, at: Date.now() };
}
function pushOp(pending: PendingGardenOp[], op: PendingGardenOp): PendingGardenOp[] {
  return pending.some((item) => item.id === op.id) ? pending : [...pending, op];
}
function isMigrationOp(op: PendingGardenOp): boolean {
  return op.id === MIGRATION_LEGACY_ID || op.id.startsWith(MIGRATION_SHOP_ID_PREFIX);
}
```

- `createRequestId()`（`src/api/familyLedger.ts:46-51`）：有 `crypto.randomUUID` 用它，否则 `` `req-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}` ``。
- `pushOp` **按 id 去重**（同 id 不重复入队）。

### 4.7 `buildMigrationOps(legacyBalance, ownedItems): PendingGardenOp[]`（`:460-492`）

```ts
function buildMigrationOps(legacyBalance: number, ownedItems: string[]): PendingGardenOp[] {
  const at = Date.now();
  const ops: PendingGardenOp[] = [];
  const ownedCost = ownedItems.reduce(
    (sum, id) => sum + (GARDEN_SHOP_ITEMS.find((item) => item.id === id)?.cost ?? 0), 0);
  // 服务端会把 garden_legacy 夹到 [0, GARDEN_LEGACY_MAX]：客户端先夹一次，两边算出来的数一致
  const legacyAmount = Math.min(Math.max(Math.round(legacyBalance) + ownedCost, 0), GARDEN_LEGACY_MAX);
  if (legacyAmount > 0) {
    ops.push({ id: MIGRATION_LEGACY_ID, taskId: GARDEN_LEGACY_TASK_ID, kind: 'earn', amount: legacyAmount, at });
  }
  for (const itemId of ownedItems) {
    const item = GARDEN_SHOP_ITEMS.find((i) => i.id === itemId);
    if (!item) continue; // 不认识的物品（老版本删过的商品）搬不了，跳过
    ops.push({ id: `${MIGRATION_SHOP_ID_PREFIX}${itemId}`, taskId: gardenShopTaskId(itemId), kind: 'spend', amount: -item.cost, itemId, at });
  }
  return ops;
}
```

- 确定性 id：`mig_legacy`、`mig_shop_<itemId>` → 重启重发同 id，服务端 `INSERT OR IGNORE` 幂等。
- 目的（`:455-459`）：老余额 + 已购物品钱先一次性搬进来，随后补发的购买记录扣完，派生余额正好等于老余额。
- `GARDEN_LEGACY_MAX = 2000` 两侧都夹（`src/api/familyLedger.ts:11`、`functions/_lib/rules.ts:135、164`）。

### 4.8 `mergeOwnedItems(local, records): string[]`（`:495-503`）

```ts
function mergeOwnedItems(local: string[], records: LedgerRecord[]): string[] {
  const owned = new Set(local);
  for (const record of records) {
    if (record.status === 'rejected') continue;
    const itemId = gardenShopItemId(record.task_id);
    if (itemId && GARDEN_SHOP_ITEMS.some((item) => item.id === itemId)) owned.add(itemId);
  }
  return Array.from(owned);
}
```

- 起点是**本地清单本身**（不做差集：账本里没有的本地物品不会被移除）。
- 只吸收 `garden_shop:*`、且能在 `GARDEN_SHOP_ITEMS` 里找到的 id，跳过 `rejected`。
- 返回顺序：先本地顺序，后新发现的账本顺序（`Set` 插入序）。

### 4.9 `commit(patch): void`（`:505-542`，逐字）

```ts
function commit(patch: Partial<GardenStore>): void {
  useGardenStore.setState((state) => {
    const summarySun = patch.summarySun !== undefined ? patch.summarySun : state.summarySun;
    const cachedRecords = patch.cachedRecords ?? state.cachedRecords;
    const pending = patch.pending ?? state.pending;
    const pendingDelta = pending.reduce((sum, op) => sum + op.amount, 0);
    const cachedSun = resolveSunBase({
      summarySun,
      cachedRecords,
      cachedSun: patch.cachedSun ?? state.cachedSun,
    });
    const tasks = patch.tasks ?? state.tasks;
    const completedCount = Array.isArray(tasks)
      ? tasks.filter((task) => task?.done).length
      : 0;
    return {
      ...patch,
      pending,
      pendingDelta,
      cachedSun,
      balance: cachedSun + pendingDelta,
      completedCount,
    };
  });
  const state = useGardenStore.getState();
  saveState(toPersisted(state));
  if (patch.pending) savePending(state.pending);
}
```

- 幂等/无异常：`saveState` / `savePending` 内部吞掉存储异常；无网络调用；**同步返回**。
- `patch.summarySun` 用 `!== undefined` 判断，所以传 `null` 可以显式清空。
- 两次 `[续]` 读取 state：`setState` 更新后再 `getState()` 落盘（拿的是更新后的值）。

### 4.10 `settleOp(op, outcome): void`（`:547-565`）

```ts
function settleOp(op: PendingGardenOp, outcome: 'written' | 'rejected'): void {
  const state = useGardenStore.getState();
  const patch: Partial<GardenStore> = {
    pending: state.pending.filter((item) => item.id !== op.id),
  };
  if (outcome === 'written') {
    patch.summarySun = resolveSunBase(state) + op.amount;
  } else if (op.kind === 'spend' && op.itemId) {
    patch.ownedItems = state.ownedItems.filter((id) => id !== op.itemId);
  }
  commit(patch);
}
```

- `'written'`：出队 + 把这笔金额从「未同步增量」搬进`summarySun` → **显示值 `balance` 在出队那一刻不跳变**（`cachedSun` 涨 `op.amount`，`pendingDelta` 掉 `op.amount`）。随后 `flushPending` 末尾的 `refreshLedger` 才给出真正权威值。
- `'rejected'` + `earn`：只出队 → 乐观加分被撤掉（`pendingDelta` 减掉这笔）。
- `'rejected'` + `spend` 且有 `itemId`：出队 + 从 `ownedItems` 移除该商品 → 退款（`pendingDelta` 回升）。
- **不处理 `equipped*`**：被拒的购买若已被戴上/挂上，仍留在 `equippedAvatar/Title/Decor` 里（见 §9）。

### 4.11 `markMigratedIfSettled(): void`（`:568-572`）

```ts
function markMigratedIfSettled(): void {
  if (readMigratedFlag()) return;
  if (useGardenStore.getState().pending.some(isMigrationOp)) return;
  writeMigratedFlag();
}
```

- 只有「队列里再无迁移流水」才落标志位；中途网络失败 → 下次启动重来（确定性 id 保证不重复入账）。

### 4.12 `flushPending(): Promise<void>`（`:574-611`，同时作为 store action 挂出，`:976`）

```ts
let flushing = false;   // :545

async function flushPending(): Promise<void> {
  if (flushing) return;
  flushing = true;
  let settled = 0;
  let migrationRejected = false;
  try {
    for (;;) {
      const op = useGardenStore.getState().pending[0];
      if (!op) break;
      try {
        await postLedgerRecord(op.taskId, {
          requestId: op.id,
          amount: op.amount,
          name: op.taskId,
          type: op.kind === 'spend' ? 'spending' : 'earning',
        });
        settleOp(op, 'written');
        settled += 1;
      } catch (error) {
        if (!isRejectedWriteError(error)) break;
        if (isMigrationOp(op)) migrationRejected = true;
        settleOp(op, 'rejected');
        settled += 1;
      }
    }
    if (!migrationRejected) markMigratedIfSettled();
  } finally {
    flushing = false;
  }
  if (settled > 0) await refreshLedger();
}
```

- 严格顺序：**只发队头**，成功或被拒才继续下一笔；任何「暂时不通」的错误直接 `break`（队头阻塞，后面的操作这次不发）。
- 并发闸 `flushing`：并发调用**直接丢弃**（不是排队）。
- 返回值：`Promise<void>`；自身不抛（`refreshLedger` 也不抛）。
- 迁移流水被拒 → `migrationRejected = true` → 本次不落迁移标志位（注释 `:605-606`：老余额可能撞上「一天只能迁一次」的限制，明天再来）。

### 4.13 `refreshLedger(): Promise<void>`（`:613-628`，同时作为 store action 挂出，`:978`）

```ts
async function refreshLedger(): Promise<void> {
  const state = useGardenStore.getState();
  const [summary, records] = await Promise.allSettled([fetchLedgerSummary(), fetchLedgerRecords()]);
  if (summary.status === 'rejected' && records.status === 'rejected') return;
  const patch: Partial<GardenStore> = {};
  if (summary.status === 'fulfilled') patch.summarySun = summary.value.sun;
  if (records.status === 'fulfilled') {
    patch.cachedRecords = records.value.filter((record) => isGardenTaskId(record.task_id));
    patch.ownedItems = mergeOwnedItems(state.ownedItems, records.value);
  }
  commit(patch);
}
```

- 两个请求并行、独立容忍；**两个都失败**才整体返回（连 `saveState` 都不发生 → 保留旧值，绝不因一次失败把阳光清零）。
- `summary` 成功 → `summarySun = sun`（只取 `sun`，家庭积分由 `useFamilyStore` 负责）。
- `records` 成功 → `cachedRecords` 只留花园前缀的记录（`isGardenTaskId`，`src/api/familyLedger.ts:26-28`：`garden:` / `garden_shop:` / `garden_legacy`）；`ownedItems` 与账本并集。
- `GET /api/ledger` 默认只回最近 200 条；`GET /api/ledger/summary` 是整表聚合（`functions/api/ledger/index.ts:32-33`、`functions/api/ledger/summary.ts:24-28`）——**余额只信 summary**，200 条窗口只用来兜底认商品（注释 `:621`）。

### 4.14 `ensureSyncLoop(): void`（`:630-647`）

```ts
let syncLoopReady = false;
function ensureSyncLoop(): void {
  if (syncLoopReady) return;
  syncLoopReady = true;
  if (typeof window !== 'undefined') {
    window.addEventListener('online', () => { void flushPending(); });
  }
  if (typeof setInterval === 'function') {
    setInterval(() => {
      if (typeof document !== 'undefined' && document.hidden) return;
      void flushPending();
    }, FLUSH_INTERVAL_MS);
  }
}
```

- 模块级 `syncLoopReady` 保证只挂一次；定时器**永不清理**（`setInterval` 无 `clearInterval`）。
- 30 秒一次，页面隐藏时跳过。
- **陷阱**：注释 `:642` 说「回到前台时 visibilitychange / focus 会补一次」，但本 store **没有**注册这两个监听（全仓库只有 `MainLayout.tsx:148-152`、`KidHome.tsx:172-185`、`FamilyDashboard.tsx:204`、`ParentHome.tsx:87` 注册，且它们只刷通知/待审批/家庭账本，**不调** `flushPending`）。所以花园队列的真实触发点是：`init`、`window online`、可见时的 30 秒 tick、以及每次入账/购买 action 末尾的 `void flushPending()`。

### 4.15 `init(): void`（`:679-764`）

逐步逻辑（顺序即执行顺序）：

1. `const saved = loadState()`；`const today = toDateKey(new Date())`。
2. 读旧值：`balance = toSafeCount(saved.balance)`、`streakDays`、`totalCompleted`、`poemCount`、`gardenCareDays` 同法（`:682-686`）。**注意 `balance` 这个局部变量不写回 state**（`commit` 会重算 `balance`），它只用于迁移与 init 的勋章判定。
3. 四个「是不是今天」布尔：`samePoemDay = saved.poemDate === today`、`sameChineseDay = saved.chineseDate === today`、`sameTaskDay = saved.tasksDate === today`、`sameEarnedDay = saved.todayEarnedDate === today`（`:688-693`）。旧存档没有这些字段 → 一律 `false` → 当作全新一天。
4. `lastWaterDate = toSafeId(saved.lastWaterDate)`；老字段兼容 `legacyCareDate = (saved as Record<string, unknown>).lastCareDate`；`lastGardenedDate = toSafeId(saved.lastGardenedDate) ?? toSafeId(legacyCareDate)`（`:696-699`）。
5. 老存档 `todayEarned` 兜底：`legacyEarned = sameTaskDay && Array.isArray(saved.tasks) ? saved.tasks.reduce((sum, task) => sum + (task?.done ? toSafeCount(task.reward) : 0), 0) : 0`（`:702-705`）。
6. `ownedItems = toSafeStringArray(saved.ownedItems)`。
7. `migrated = readMigratedFlag()`；`needsMigration = !migrated && (balance > 0 || ownedItems.length > 0)`（`:710`）。
8. `cachedSun = needsMigration ? 0 : typeof saved.cachedSun === 'number' ? toSafeAmount(saved.cachedSun) : toSafeAmount(saved.balance)`（`:713-717`）——要迁移的老用户从 0 起算（老余额由迁移流水搬进来）。
9. `let pending = loadPending()`，再把 `buildMigrationOps(balance, ownedItems)` 逐条 `pushOp`（`:719-721`）。
10. `commit({...})`（`:723-757`），patch 明细：
    - `tasks: sameTaskDay ? (saved.tasks ?? GARDEN_TASKS) : GARDEN_TASKS`（**存档 tasks 不做清洗**，直接信任）
    - `badges: resolveBadges(saved.badges ?? GARDEN_BADGES, { totalCompleted, balance, streakDays, poemCount, gardenCareDays })`（这里 `balance` 是**存档老余额**，与运行期口径不同）
    - `streakDays, totalCompleted, lastActiveDate: saved.lastActiveDate ?? null, poemCount, gardenCareDays, ownedItems`
    - `equippedAvatar: toSafeId(...)`、`equippedTitle: toSafeId(...)`、`equippedDecor: toSafeStringArray(...).slice(0, GARDEN_MAX_DECOR)`
    - `todayPoemIds: samePoemDay ? toSafeStringArray(saved.todayPoemIds) : []`、`poemDate: today`
    - `chineseSteps: sameChineseDay ? toSafeCountRecord(saved.chineseSteps) : {}`、`chineseDate: today`
    - `todayEarned: sameEarnedDay ? toSafeCount(saved.todayEarned) : legacyEarned`、`todayEarnedDate: today`
    - `lastWaterDate, lastGardenedDate, tasksDate: today, cachedSun, pending`
    - `summarySun: get().summarySun`、`cachedRecords: get().cachedRecords`（重复 init 时保留已拿到的权威值，注释 `:754`）
    - **不传 `completedCount`**：由 `commit` 从上面的 `tasks` 派生（注释 `:733-734`）。
11. `if (!needsMigration) writeMigratedFlag()`（`:759`）。
12. `ensureSyncLoop()`（`:760`）。
13. `void flushPending()`；`void refreshLedger()`（`:762-763`，都是 fire-and-forget）。

返回值：`void`。可重入：重复调用会重新读 localStorage（因为每次 `commit` 都全量落盘，所以基本等价于「重新加载」），但 `pending` 会被存储里的版本**覆盖**（若上次 `savePending` 失败，内存里未落盘的操作会丢）。

### 4.16 `completeTask(taskId): void`（`:766-802`）

```ts
const state = get();
const task = state.tasks.find((t) => t.id === taskId);
if (!task || task.done) return;               // 未知 id 或已完成 → 静默 no-op

const today = toDateKey(new Date());
const stats = nextCompletionStats(state, task.reward, today);
commit({
  tasks: state.tasks.map((t) => t.id === taskId ? { ...t, done: true, completedAt: new Date().toISOString() } : t),
  badges: resolveBadges(state.badges, { totalCompleted: stats.totalCompleted, balance: stats.balance,
    streakDays: stats.streakDays, poemCount: state.poemCount, gardenCareDays: stats.gardenCareDays }),
  streakDays: stats.streakDays,
  totalCompleted: stats.totalCompleted,
  lastActiveDate: stats.lastActiveDate,
  gardenCareDays: stats.gardenCareDays,
  lastGardenedDate: stats.lastGardenedDate,
  todayEarned: stats.todayEarned,
  todayEarnedDate: today,
  todayPoemIds: state.poemDate === today ? state.todayPoemIds : [],
  poemDate: today,
  chineseSteps: state.chineseDate === today ? state.chineseSteps : {},
  chineseDate: today,
  tasksDate: today,
  pending: pushOp(state.pending, earnOp(gardenTaskId(task.id), task.reward)),
});
void flushPending();
```

- 返回 `undefined`（不是 boolean）；UI 侧「是否已完成」由页面自查 `tasks`（`TasksPage.tsx:30`）。
- 阳光奖励用**客户端 `task.reward`** 造队列金额，但服务端按自己的规则给钱（两边奖励表必须手工一致，`functions/_lib/rules.ts:142-155`）。
- `gardenTaskId('math')` → `'garden:math'`（`src/api/familyLedger.ts:31-33`）。

### 4.17 `recitePoem(poemId): boolean`（`:804-849`）

```ts
const poem = GARDEN_POEMS.find((p) => p.id === poemId);
if (!poem) return false;                                   // 未知诗 id

const today = toDateKey(new Date());
const todayPoemIds = state.poemDate === today ? state.todayPoemIds : [];
if (todayPoemIds.includes(poemId)) return false;           // 同日同诗只计一次

const poemTaskDone = state.tasks.find((t) => t.id === POEM_TASK_ID)?.done ?? false;
const stats = nextCompletionStats(state, poem.reward, today);
const poemCount = state.poemCount + 1;
commit({
  tasks: poemTaskDone ? state.tasks
    : state.tasks.map((t) => t.id === POEM_TASK_ID ? { ...t, done: true, completedAt: new Date().toISOString() } : t),
  badges: resolveBadges(state.badges, { totalCompleted: stats.totalCompleted, balance: stats.balance,
    streakDays: stats.streakDays, poemCount, gardenCareDays: stats.gardenCareDays }),
  streakDays: stats.streakDays, totalCompleted: stats.totalCompleted, lastActiveDate: stats.lastActiveDate,
  poemCount, gardenCareDays: stats.gardenCareDays, lastGardenedDate: stats.lastGardenedDate,
  todayEarned: stats.todayEarned, todayEarnedDate: today,
  todayPoemIds: [...todayPoemIds, poemId], poemDate: today,
  chineseSteps: state.chineseDate === today ? state.chineseSteps : {}, chineseDate: today,
  pending: pushOp(state.pending, earnOp(gardenTaskId(POEM_TASK_ID), poem.reward)),
});
void flushPending();
return true;
```

- 任务 id 固定 `'garden:poem'`（`POEM_TASK_ID = 'poem'`），服务端该规则**无日限**（`functions/_lib/rules.ts:144`），一天可多首。
- 会**顺手点亮**今日任务 `'poem'`（未完成时），因此 `completedCount` 自然 +1，但只 +1（`commit` 从 tasks 派生）。
- `totalCompleted` / `gardenCareDays` / `todayEarned` 仍按每次背诗累加。
- **不写 `tasksDate`**。
- 返回值：`true` = 计入并已入队；`false` = 未知诗或今日已背过。

### 4.18 `completeChineseStep(practiceId): boolean`（`:851-894`）

```ts
const practice = GARDEN_CHINESE_PRACTICES.find((p) => p.id === practiceId);
if (!practice) return false;                               // 未知练习 id

const today = toDateKey(new Date());
const steps = state.chineseDate === today ? state.chineseSteps : {};
const done = steps[practiceId] ?? 0;
if (done >= practice.timesPerDay) return false;            // 本地日限

const chineseTaskDone = state.tasks.find((t) => t.id === CHINESE_TASK_ID)?.done ?? false;
const stats = nextCompletionStats(state, practice.reward, today);
commit({ ...同 recitePoem 的形状...,
  tasks: chineseTaskDone ? state.tasks
    : state.tasks.map((t) => t.id === CHINESE_TASK_ID ? { ...t, done: true, completedAt: new Date().toISOString() } : t),
  todayPoemIds: state.poemDate === today ? state.todayPoemIds : [], poemDate: today,
  chineseSteps: { ...steps, [practiceId]: done + 1 }, chineseDate: today,
  pending: pushOp(state.pending, earnOp(gardenTaskId(practiceId), practice.reward)),
});
void flushPending();
return true;
```

- `timesPerDay`：`read_aloud` 3、`new_words` 2、`write_words` 1（`src/config/garden.ts:67-71`），与 `functions/_lib/rules.ts:153-155` 的 `dailyLimit` 一一对应（**服务端是最后一道**）。
- 任务 id 是 `'garden:' + practiceId`（例：`'garden:read_aloud'`）。
- 顺手点亮今日任务 `'chinese'`（多次打卡只点亮这一个任务，`completedCount` 只 +1）。
- **不写 `tasksDate`**。

### 4.19 `careForGarden(): boolean`（`:896-919`）

```ts
const state = get();
const today = toDateKey(new Date());
if (state.lastWaterDate === today) return false;          // 今天浇过了（只看浇水记录）
const gardenCareDays = state.lastGardenedDate === today ? state.gardenCareDays : state.gardenCareDays + 1;
commit({
  lastWaterDate: today,
  lastGardenedDate: today,
  gardenCareDays,
  badges: resolveBadges(state.badges, { totalCompleted: state.totalCompleted, balance: state.balance,
    streakDays: state.streakDays, poemCount: state.poemCount, gardenCareDays }),
});
return true;
```

- **不发阳光、不写后端、不进 pending、不调 `flushPending`**（注释 `:905`：服务端没有对应规则）。
- 任务完成也会更新 `lastGardenedDate`，所以「照顾花园」的日期去重跨动作共享；但「今天浇过水没有」只看 `lastWaterDate`（注释 `:899`：以前做完任务会把浇水顶掉，白点）。
- 返回值 `false` = 今天已浇过水。

### 4.20 `buyItem(itemId): ShopBuyResult`（`:921-935`）

```ts
const item = GARDEN_SHOP_ITEMS.find((i) => i.id === itemId);
if (!item) return 'unknown';
if (state.ownedItems.includes(itemId)) return 'owned';
if (state.balance < item.cost) return 'insufficient';
commit({
  ownedItems: [...state.ownedItems, itemId],
  pending: pushOp(state.pending, spendOp(gardenShopTaskId(itemId), itemId, item.cost)),
});
void flushPending();
return 'ok';
```

- 类型 `ShopBuyResult = 'ok' | 'owned' | 'insufficient' | 'unknown'`（`:51`）。
- 拦截顺序：未知商品 → 已拥有 → 余额不足（`state.balance` 是**显示余额含未同步增量**）。
- 只做「拥有 + 扣钱」，**不自动装备**；`equipped*` 只由 `equipItem` 改。
- 详情见 §7。

### 4.21 `equipItem(itemId): 'ok' | 'owned' | 'unknown'`（`:937-959`）

```ts
const item = GARDEN_SHOP_ITEMS.find((i) => i.id === itemId);
if (!item) return 'unknown';
if (!state.ownedItems.includes(itemId)) return 'owned';
if (item.category === 'avatar') { commit({ equippedAvatar: itemId }); }
else if (item.category === 'title') { commit({ equippedTitle: itemId }); }
else {
  const rest = state.equippedDecor.filter((id) => id !== itemId);
  const kept = rest.length >= GARDEN_MAX_DECOR ? rest.slice(rest.length - (GARDEN_MAX_DECOR - 1)) : rest;
  commit({ equippedDecor: [...kept, itemId] });
}
return 'ok';
```

- 分类来自 `GARDEN_SHOP_ITEMS[].category`（`avatar` / `title` / `decor`）。
- 头像框 / 称号是**单值**：换新的直接覆盖旧的。
- 装饰：先去掉同件（避免重复），若「去掉后」已有 ≥3 件则 `slice(rest.length - 2)`（保留最后 2 件）+ 追加新的 → 结果恒 ≤3，被淘汰的永远是**数组头部（最早挂上的那件）**。
- **纯本地**：不写后端、不进队列、不调 `flushPending`。

### 4.22 `unequipItem(itemId): void`（`:961-974`）

```ts
const item = GARDEN_SHOP_ITEMS.find((i) => i.id === itemId);
if (!item) return;                                          // 未知物品静默忽略
if (item.category === 'avatar') { if (state.equippedAvatar === itemId) commit({ equippedAvatar: null }); }
else if (item.category === 'title') { if (state.equippedTitle === itemId) commit({ equippedTitle: null }); }
else { commit({ equippedDecor: state.equippedDecor.filter((id) => id !== itemId) }); }
```

- 无返回值；`avatar` / `title` 只在「当前正是它」时才清空；`decor` 一律 filter（幂等）。
- 摘下的物品**不会**从 `ownedItems` 移除。

### 4.23 store 上的两个透传 action

- `flushPending`（`:976`）= 模块函数本身（同一个函数引用）。
- `refreshLedger`（`:978`）= 模块函数本身。
- store 接口里**没有其它 getter**；页面需要派生值时自己算（例：`GardenLayout.tsx:93-96` `percent = totalTasks > 0 ? Math.min(100, Math.max(0, Math.round(completedCount / totalTasks * 100))) : 0`；`RecordsPage.tsx:17` `earnedToday = todayEarnedDate === todayKey() ? todayEarned : 0`；`PoemPage.tsx:10-13`、`ChinesePage.tsx:10-13` 均用 `xxxDate === todayKey()` 判断）。

---

## 5. 与后端的交互

### 5.1 用到的接口

| 调用点 | 方法/路径 | 参数 | 说明 |
| --- | --- | --- | --- |
| `refreshLedger` → `fetchLedgerSummary()` | `GET /api/ledger/summary` | 无 | 整表聚合，返回 `{ family, sun }`；字段不是有限数就抛 `余额接口返回的格式不对`（`src/api/familyLedger.ts:77-81`） |
| `refreshLedger` → `fetchLedgerRecords()` | `GET /api/ledger` | 无 | 返回最近 200 条（服务端 `DEFAULT_LIMIT = 200`，`functions/api/ledger/index.ts:32-33`） |
| `flushPending` → `postLedgerRecord(taskId, opts)` | `POST /api/ledger` | 见下 | 带 `{ retry: true }` |

### 5.2 POST body（`src/api/familyLedger.ts:200-224`）

```ts
return http.post<LedgerWriteResult>('/api/ledger', {
  id: options.requestId,
  task_id: taskId,
  task_name: options.name ?? taskId,
  type: options.type ?? 'earning',
  amount: options.amount ?? 0,
  note: options.note ?? null,
  image_url: options.imageUrl ?? null,
}, { retry: true });
```

`flushPending` 实际传的是（`:589-594`）：

```ts
await postLedgerRecord(op.taskId, {
  requestId: op.id,
  amount: op.amount,
  name: op.taskId,                                   // 于是 task_name 就等于 task_id，如 "garden:poem"
  type: op.kind === 'spend' ? 'spending' : 'earning',
});
```

- 请求头 `Content-Type: application/json`（`src/api/http.ts:63-65`），body 为 JSON 字符串。
- 响应类型 `LedgerWriteResult = { id: string; status?: LedgerStatus; duplicate?: boolean }`（`src/api/familyLedger.ts:187-193`）；**store 只关心「有没有抛错」**，响应体被忽略。
- 服务端对 `task_name` / `type` / `amount` 一律以 `LEDGER_TASK_RULES` 为准（`functions/api/ledger/index.ts:91-139`）：花园任务没有 `clientName`，所以 `task_name` 被忽略；只有 `garden_legacy`（`clientAmount: { min: 0, max: 2000 }`）会采纳客户端 `amount` 并夹取（`functions/_lib/rules.ts:158-165`、`functions/api/ledger/index.ts:113-121`）。注意：`garden_legacy` 的 `min = 0`，所以 `finalType` 仍是 `earning`。
- 服务端未知 `task_id` → 403 `未知任务，不能记账`（`functions/api/ledger/index.ts:97-99`）→ 被客户端判为「明确拒绝」。

### 5.3 requestId 的生成与复用

- 生成：`createRequestId()`（`src/api/familyLedger.ts:46-51`），在 `earnOp`（`:436-438`）/ `spendOp`（`:441-443`）里**每次新造一笔操作时生成一次**。
- 复用：`id` 随 `PendingGardenOp` 一起写进 `sekainook_garden_pending`（`:412-418`）；补发、重启、离线重试都用**同一个 id**；`pushOp` 按 id 去重（`:446-448`）。
- 迁移流水用**确定性 id**：`mig_legacy`、`mig_shop_<itemId>`（`:40-41, 471, 483`）。
- 服务端幂等：`INSERT OR IGNORE` + 主键冲突返回已有记录（`duplicate: true`）（`functions/api/ledger/index.ts:235-280`）。
- 关键服务端行为（必须一起移植认知）：日限判定命中时，服务端**先按 `providedId` 查库**，若已存在则返回 `200 {id, status, duplicate:true}` 而不是 409（`functions/api/ledger/index.ts:209-222`）——否则「响应丢在路上」的重发会让客户端回滚已经到账的阳光、迁移永远搬不完。
- 客户端不校验 id 长度/字符集，但服务端要求 `ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_:.-]*$/` 且 ≤64 字符，不匹配则服务端自造 id（`functions/api/ledger/index.ts:35-36, 151-153`）。

### 5.4 失败分类与重试策略

| 层 | 行为 |
| --- | --- |
| `src/api/http.ts` | 超时 12s（`:28`）；可重试状态码 `[429, 500, 502, 503, 504]`（`:20`）；GET 最多重试 2 次、写请求仅在 `retry: true` 时最多重试 1 次（`:22-24, 50-53`）；重试前等待 `[400, 1200]` ms（`:26`）；网络层失败抛 `ApiError(status 0)`，文案 `请求超时，检查一下网络` / `网络连接失败，请检查网络后重试`（`:81-84`） |
| `src/api/familyLedger.ts:231-235` | `isRejectedWriteError(error)` = `error instanceof ApiError && error.status >= 400 && error.status < 500 && error.status !== 429` → 「服务端明确拒绝」 |
| `flushPending` | 明确拒绝 → 出队 + 回滚（`settleOp(op,'rejected')`），继续下一笔；其余（status 0 / 429 / 5xx）→ **留在队列里，`break` 结束本轮** |
| 触发补发的时机 | `init()`；`window` 的 `online` 事件；30 秒定时器（页面可见时）；`completeTask` / `recitePoem` / `completeChineseStep` / `buyItem` 末尾各一次 fire-and-forget |

- 队列顺序 = 插入顺序（先到先发，`pending[0]`）。
- 队列在 localStorage 里**跨会话持久**（刷新/重启继续补发）。
- 出队成功那一笔通过 `settleOp` 立刻把金额并入 `summarySun`，随后 `refreshLedger` 校正。

### 5.5 「本地先算、不写后端」的操作

| 操作 | 是否写后端 | 备注 |
| --- | --- | --- |
| `careForGarden` | ❌ | 浇水不发阳光，`lastWaterDate`/`gardenCareDays`/勋章全本地 |
| `equipItem` / `unequipItem` | ❌ | 装扮**完全不落服务端**，换设备丢失 |
| 任务 `done` 标记、`completedCount`、`streakDays`、`totalCompleted`、`todayEarned` | ❌ | 本地派生，只落 localStorage |
| 勋章 `earned` | ❌ | 只在本地存档 |
| `completeTask` / `recitePoem` / `completeChineseStep` | ✅（入账那一笔） | 本地先加钱（`pendingDelta` 乐观生效），队列补发 |
| `buyItem` | ✅（消费那一笔） | 立即加 `ownedItems` + 乐观扣钱 |
| 老数据迁移 | ✅（`garden_legacy` + 每件 `garden_shop:*`） | 先本地造队列，`flushPending` 补发 |

---

## 6. 勋章解锁（7 枚）

### 6.1 精确解锁表达式（`resolveBadges`，`:275-283`）

| id | 名称（`src/config/garden.ts:16-24`） | 判定表达式 | 阈值含义 |
| --- | --- | --- | --- |
| `sunrise` | 第一缕阳光 / 完成第一个任务 | `stats.totalCompleted >= 1` | 完成第 1 次花园活动 |
| `gardener` | 小园丁 / 累计完成 10 个任务 | `stats.totalCompleted >= 10` | 累计活动次数 ≥10（背诗/练习也计入次数） |
| `streak3` | 坚持 3 天 / 连续学习 3 天 | `stats.streakDays >= 3` | `streakDays` |
| `week_champ` | 一周冠军 / 连续学习 7 天 | `stats.streakDays >= 7` | `streakDays` |
| `poet` | 小诗人 / 背诵 10 首古诗 | `stats.poemCount >= 10` | 累计背诗首数 |
| `plant_warrior` | 植物战士 / 照顾花园植物 7 天 | `stats.gardenCareDays >= 7` | 累计照顾自然日 |
| `sun_rich` | 阳光富翁 / 累计获得 500 阳光 | `stats.balance >= 500` | **当前显示余额**（不是累计所得） |

- 目标值另有一份给 UI 用的派生常量 `GARDEN_BADGE_TARGETS = { poet: 10, plant_warrior: 7 }`（`src/config/garden.ts:125-128`）——判定仍以 store 里的表达式为准。
- `sun_rich` 名字说「累计获得」，实现是「当前余额 ≥500」且 `resolveBadges` 单调 → 一旦解锁永不再撤销。

### 6.2 判定时机与传入的 `balance` 口径

| 时机 | 传的 `balance` | 传的其它 stats |
| --- | --- | --- |
| `init`（`:725-731`） | **存档 `toSafeCount(saved.balance)`**（老本地值） | `totalCompleted / streakDays / poemCount / gardenCareDays` 全来自存档 |
| `completeTask`（`:777-783`） | `stats.balance = 当前显示余额 + task.reward` | 来自 `nextCompletionStats` 与 `state` |
| `recitePoem`（`:825-831`） | `stats.balance = 当前显示余额 + poem.reward`；`poemCount = state.poemCount + 1` | 同上 |
| `completeChineseStep`（`:871-877`） | `stats.balance = 当前显示余额 + practice.reward` | 同上 |
| `careForGarden`（`:910-916`） | `state.balance`（不变，只是重判一次） | 全量取 `state`，`gardenCareDays` 为刚算出的值 |
| `buyItem` / `equipItem` / `unequipItem` | — | **不判定勋章** |

### 6.3 `earned` 存哪、怎么持久化

- `badges` 是 store 字段（`Badge[]`，7 个元素，`earned` 布尔）→ 随每次 `commit` 整份写进 `sekainook_garden_state`（`toPersisted` `:341`）。
- 读回：`init` 里 `saved.badges ?? GARDEN_BADGES`（`:725`），**存档元素的 `earned` 直接沿用**，再用 `resolveBadges` 单向补齐。
- 「新勋章弹窗只弹一次」的标志**不在 store 里**：`KidHome.tsx:62-83` 另用 localStorage 键 `sekainook_badges_celebrated`（`string[]`，`JSON.stringify`）。首次读到 `null` 时把当时所有已获得的 id 写进去、不弹窗；之后只弹第一个「已获得但没庆祝过」的。

---

## 7. 商城兑换

### 7.1 商品表（`src/config/garden.ts:96-103`，服务端价格见 `functions/_lib/rules.ts:167-172`）

| id | name | cost | category | 图标 |
| --- | --- | --- | --- | --- |
| `avatar_sun` | 阳光头像框 | 60 | `avatar` | sun |
| `avatar_star` | 星星头像框 | 80 | `avatar` | star |
| `title_poet` | 称号・小诗人 | 100 | `title` | feather |
| `title_gardener` | 称号・小园丁 | 120 | `title` | flower |
| `decor_rainbow` | 装饰・彩虹花架 | 150 | `decor` | flower |
| `decor_lantern` | 装饰・星星灯串 | 200 | `decor` | star |

（展示用短名去掉 `・`（`\u30FB`）前缀，由 `toShopItemShortName` 处理，`src/config/garden.ts:116-122`。）

### 7.2 一次兑换的完整流程（`buyItem`，`:921-935`）

1. `GARDEN_SHOP_ITEMS.find(id)`，找不到 → 返回 `'unknown'`，**不改任何状态**。
2. `state.ownedItems.includes(itemId)` 为真 → 返回 `'owned'`，**不改状态**（一次性拥有，不可重复兑换）。
3. `state.balance < item.cost` → 返回 `'insufficient'`，**不改状态**。`state.balance` 是显示余额（含未同步增量）→ 离线时也能拦住「同一台设备上的连续超支」。
4. 通过 → 一次 `commit`：
   - `ownedItems: [...state.ownedItems, itemId]`（**立即拥有**，不等服务端）；
   - `pending: pushOp(state.pending, spendOp(gardenShopTaskId(itemId), itemId, item.cost))`，其中 `spendOp` 的 `amount = -cost`、`kind = 'spend'`、`itemId` 带上。
5. `commit` 重算 → `pendingDelta` 立即为负 → `balance = cachedSun + pendingDelta` 立刻少掉 `cost`（乐观扣款）。
6. `void flushPending()` → 立刻尝试 `POST /api/ledger`；离线则留在 `sekainook_garden_pending`，等 `online`/30s tick。
7. 返回 `'ok'`。

### 7.3 后续：写账本与结算

- 请求体：`{ id: op.id, task_id: 'garden_shop:<itemId>', task_name: 'garden_shop:<itemId>', type: 'spending', amount: -cost, note: null, image_url: null }`。
- 服务端按规则记 `type: 'spending'`、`amount: -60/-80/-100/-120/-150/-200`，`autoApprove: true` → 直接 `approved` 入账，不进家长审批（`functions/_lib/rules.ts:167-172`、`functions/api/ledger/index.ts:139`）。
- 成功（含 `duplicate`）→ `settleOp(op,'written')`：出队 + `summarySun += (-cost)`；显示值不跳变。
- 被明确拒绝（4xx≠429，实际只有「未知商品」这种规则漂移才会发生）→ `settleOp(op,'rejected')`：出队 + `ownedItems` 移除该 itemId（退钱 + 收回物品）。
  - **已知缺口**：`equippedAvatar` / `equippedTitle` / `equippedDecor` **不回滚**（`settleOp` `:561-563` 只碰 `ownedItems`）→ 可能出现「没拥有但还戴着」。移植时照抄（若修，需另行决策）。
- **服务端不做余额校验**：`garden_shop:*` 规则没有 `dailyLimit` 也没有 `clientAmount`，POST 只校验 `task_id` 是否存在（`functions/api/ledger/index.ts:92-99, 156`），`summary.ts` 的 `SUM` 也不夹 0 → 权威 `sun` 可以是负数。「余额不足」**只有客户端一道闸门**。

### 7.4 装备与装饰槽位

- 兑换**不会自动装备**；装备走 `equipItem`（§4.21），纯本地。
- 槽位规则：
  - `avatar` → `equippedAvatar: string | null`，单件，换新覆盖旧。
  - `title` → `equippedTitle: string | null`，单件。
  - `decor` → `equippedDecor: string[]`，**最多 `GARDEN_MAX_DECOR = 3`**，数组**头部 = 最早挂上**。
- 替换规则（`:951-956` 逐字）：

```ts
const rest = state.equippedDecor.filter((id) => id !== itemId);
const kept = rest.length >= GARDEN_MAX_DECOR ? rest.slice(rest.length - (GARDEN_MAX_DECOR - 1)) : rest;
commit({ equippedDecor: [...kept, itemId] });
```

→ 挂第 4 件时淘汰 `rest[0]`（最早挂的那件），保留 `rest` 的最后 `GARDEN_MAX_DECOR - 1 = 2` 件，再追加新件。
- `init` 时对存档做一次上限裁剪：`toSafeStringArray(saved.equippedDecor).slice(0, GARDEN_MAX_DECOR)`（`:742`）。
- 摘除：`unequipItem`（§4.22）。

---

## 8. 古诗背诵 / 语文练习

### 8.1 数据源

- 古诗：`GARDEN_POEMS`（12 首，`src/config/garden.ts:38-51`），每首 `reward: 10`；`GardenPoem = { id, title, author, text, reward }`（同文件 `:27-35`）。**不在 store 里**，每次 `find` 全局常量。
- 语文练习：`GARDEN_CHINESE_PRACTICES`（3 项，`src/config/garden.ts:67-71`）：

| id | title | actionLabel | reward | timesPerDay |
| --- | --- | --- | --- | --- |
| `read_aloud` | 课文朗读 | 我读完了 | 5 | 3 |
| `new_words` | 生字认读 | 我认读完了 | 5 | 2 |
| `write_words` | 生字书写 | 我写完了 | 10 | 1 |

`GardenChinesePractice = { id, title, desc, actionLabel, reward, timesPerDay }`（同文件 `:54-64`）。

### 8.2 背会判定

- 「背会」= 用户手动触发 `recitePoem(poemId)`；**没有任何自动判定逻辑**（无输入校验、无填空/听写比对）。
- 去重：`todayPoemIds`（自然日维度），同一天同一首只计一次；跨天由 `poemDate` 失效。
- 返回 `false` 的两种情况：`GARDEN_POEMS` 里没有这个 id；或今天已经背过这首。

### 8.3 每日次数上限

- 古诗：**无上限**（本地不去重每日总量；服务端 `garden:poem` 也无 `dailyLimit`，`functions/_lib/rules.ts:144`）→ 一天可以把 12 首都背一遍。
- 语文练习：`chineseSteps[practiceId] >= practice.timesPerDay` → 返回 `false`（本地一道闸门），服务端 `dailyLimit` 是第二道（超限返回 409 `「课文朗读」每天最多 3 次，今天用完啦` / 日限 1 时文案 `「xxx」今天已经打过卡啦`，`functions/api/ledger/index.ts:202-207`）。

### 8.4 奖励发放

- 一次 `recitePoem`：`pending` 加 `earnOp(gardenTaskId('poem'), poem.reward)` → `task_id = 'garden:poem'`，`amount = 10`。
- 一次 `completeChineseStep`：`earnOp(gardenTaskId(practiceId), practice.reward)` → `task_id = 'garden:read_aloud'`（等），`amount = 5/5/10`。
- 乐观生效路径：`commit` 后 `pendingDelta` 立刻变正 → `balance` 立刻增加；`todayEarned` 也立刻增加。
- 结算后由服务端 `rule.value` 决定真实入账额（两边必须一致：`functions/_lib/rules.ts:144, 153-155`）。
- 伴随副作用：点亮今日任务 `'poem'` / `'chinese'`（`completedCount` +1，仅第一次），`totalCompleted` +1（每次），`gardenCareDays` +1（每天一次），`streakDays` 按 `nextStreak` 更新，`lastActiveDate = today`。

### 8.5 记录的存储形状

| 记录 | 字段 | 形状 |
| --- | --- | --- |
| 今日已背古诗 | `todayPoemIds: string[]` + `poemDate: string` | 例 `["jingyesi","chunxiao"]`，`poemDate: "2025-01-02"` |
| 累计背会首数 | `poemCount: number` | 每次成功背诗 `+1`（同日不同诗也各自 +1） |
| 今日练习次数 | `chineseSteps: Record<string, number>` + `chineseDate: string` | 例 `{ "read_aloud": 2, "write_words": 1 }` |
| 云端流水 | `LedgerRecord[]`（`GET /api/ledger`，`src/types/family.ts:28-46`） | `task_id = 'garden:poem' / 'garden:<practiceId>'`，服务端写 `task_name` 为规则名、`status: 'approved'`（`autoApprove`）、`amount` 由规则定 |
| 本地缓存的云端流水 | `cachedRecords: LedgerRecord[]`（不持久化） | 只含花园前缀记录 |

---

## 9. 边界与坑（代码注释里明写的 + 代码结构隐含的）

**代码注释明确写的**

1. `completedCount` 一律从 `tasks` 派生（`:79-80, 311-318, 521-524, 733-734`）：分子分母同口径；并且**老存档里被撑大的数字（例如 11/8）下次启动自愈**。绝不能改回「每次活动自增」。
2. `todayEarned` 只累加入账奖励，商城消费不走它（`:317`）：花掉的不冲掉赚到的。
3. 迁移标志位「没写就下次启动重试 —— 迁移流水用的是确定性 id，重复搬不会重复入账」（`:29-32`）。
4. 离线队列「同一个操作重试复用同一个 id，服务端靠主键做幂等」（`:34-37`）→ **队列元素绝不能换成「每次重试新造 id」**。
5. 坏 pending 数据「宁可少发一笔，也别拿坏数据去记账」（`:228-231`）。
6. `settleOp` 的 'written' 分支目的是「显示值在出队那一刻不跳变」（`:547-552`）——不要简化成「直接刷新下拉」。
7. 迁移被拒「宁可不落标志位：老余额可能是撞上『一天只能迁一次』的限制，明天再来」（`:605-606`）。
8. `refreshLedger`「两个都没通：保留上一次的值（宁可显示旧数字，也不要因为一次失败把阳光清零）」（`:617`）；且「已经拿到过全量值时，records 那 200 条窗口只用来兜底认商品，不用来改余额」（`:621`）。
9. 浇水与照顾花园是两个口径（`:110-116, 694-696, 899`）：老存档缺 `lastWaterDate` 时当作「今天还没浇水」，当天还能浇一次；GARDEN 的去重基准改用 `lastGardenedDate`。
10. 老字段兼容 `lastCareDate`（`:697-699`，旧版本任务完成也写它）。
11. 老存档没有「今日入账」时用当天已完成任务 reward 求和兜底（`:700-705`）。
12. `equipItem` 注释：装饰「挂满 GARDEN_MAX_DECOR 件时，替换掉最早挂上的那件（数组头部）」（`:953`）。
13. `unequipItem`「没戴着也安全，什么也不做」（`:148-149`）。
14. `toSafeAmount` 注释：0 要保留，所以不能用 `toSafeCount`（`:202`）。
15. 服务端 `garden_legacy` 会把金额夹到 `[0, GARDEN_LEGACY_MAX]`，「客户端先夹一次，两边算出来的数一致」（`:467`）。
16. `mergeOwnedItems` 目的：「换手机后买到的东西还在」（`:494`）。
17. 「同一个 id 已经在队列里就不重复压」（`:445`）。

**代码结构隐含的坑（移植时容易踩）**

18. **不认识的商品直接跳过**：`buildMigrationOps` 里老版本删过的商品搬不了（`:480-481`）。
19. `flushPending` 队头阻塞：非「明确拒绝」的错误直接 `break`，后面的操作本轮全不发（`:599`）。
20. `flushing` 并发闸是**丢弃**语义，不是排队（`:579`）。
21. `tasksDate` 只在 `init` / `completeTask` 里更新 → 跨零点不重启时 tasks 的 `done` 不自动清（§3.3）。
22. `equipped*` 三处：被拒购买不回滚装备（§7.3）、换设备不同步（§5.5）、`init` 只裁剪长度不校验是否仍拥有。
23. `settleOp('written')` 时若 `summarySun === null`，`resolveSunBase(state)` 会回退到 `cachedRecords` / `cachedSun`（旧值）再加上这笔金额；真正的权威值要等 `refreshLedger`（`:560`）。
24. `cachedRecords` 只按前缀过滤，**包含 `rejected` 记录**（`:624`）；余额计算才跳过 rejected（`src/api/familyLedger.ts:327-334`）。
25. `ownedItems` 只增不减（除被拒回滚）：账本里查不到的物品不会被移除（`:496-502`）。
26. `refreshLedger` 捕获的是 `await` **之前**的 `state`（`:615`），`mergeOwnedItems` 用的是一个可能已过期的本地清单（只会导致少合并，无副作用）。
27. `ensureSyncLoop` 的注释宣称 visibilitychange/focus 会补发，但 store 并未注册这两个监听（`:630-647`；全仓库 `flushPending` 无外部调用点）。
28. `setInterval` 永不清理、`syncLoopReady` 永不重置（`:631-646`）——热重载/多实例场景下会有重复定时器风险。
29. 初始 `tasks` / `badges` **直接引用模块常量数组**（`:651-652`）；所有更新都用 `map`/`filter`/展开造新数组，从不原地改。移植时若用可变 List 直接持有常量表，会被污染。
30. store 用 `localStorage` 存储：`init` 之前不会有任何写入；`localStorage` 抛错（隐私模式/配额）只影响持久化，不影响内存账（`:376-418`）。
31. `summarySun` / `cachedRecords` 在重复 `init` 时保留内存值（`:754-756`），但 `pending` 会被存储版本覆盖（`:718`）。
32. 代码里**没有** `TODO` / `FIXME` / `HACK` 注释（已确认）；所有"看起来可以优化但不能改"的点都在上面 1-31 条里，主要是：`completedCount` 派生口径、出队不跳变、迁移幂等 id、两个浇水日期字段、装饰淘汰顺序。
33. 服务端 D1 是跨设备唯一真相的只有**流水**（family ledger）；花园的 `ownedItems` 靠账本 `garden_shop:*` 记录恢复，其余（`tasks`、`equipped*`、`badges`、`streakDays`、`poemCount`、`gardenCareDays`、`todayPoemIds`、`chineseSteps`）**完全不跨设备**。

---

## 10. Dart 移植注意事项（React / zustand 特有写法的等价实现）

### 10.1 zustand 的 `setState` 语义 → Dart 状态容器

- `commit` 用的是**函数式 setState**：`setState((state) => ({...}))`。语义 = 「基于最新 state 计算补丁，再浅合并」。Dart 里对应：

```dart
void commit(Map<String, Object?> patch) {
  final s = _state; // 或 notify 前的最新快照
  final pending = patch.containsKey('pending') ? patch['pending'] as List<PendingGardenOp> : s.pending;
  final pendingDelta = pending.fold<int>(0, (a, op) => a + op.amount);
  final cachedSun = resolveSunBase(...);
  final tasks = patch.containsKey('tasks') ? patch['tasks'] as List<GardenTask> : s.tasks;
  final completedCount = tasks.where((t) => t.done).length;
  _state = s.copyWith(..., pending: pending, pendingDelta: pendingDelta, cachedSun: cachedSun,
      balance: cachedSun + pendingDelta, completedCount: completedCount);
  _saveState(); // 全量写
  if (patch.containsKey('pending')) _savePending();
  notifyListeners();
}
```

- **必须复刻的两点**：① 4 个派生字段（`pendingDelta`/`cachedSun`/`balance`/`completedCount`）无条件重算；② 任何字段都可以通过 patch 覆盖（zustand 是浅合并任意 `Partial`）。不要只做「每种 action 一个专用方法 + 各自手算 balance」——会漏掉 `settleOp` / `refreshLedger` 那两条路径。
- zustand 的 `commit` 是**同步**的（`setState` 同步执行，落盘同步），Dart 里也应该同步改状态、同步落盘，异步只发生在那两个 `void flushPending()/refreshLedger()` 上。

### 10.2 immer？

- 本 store **没有使用 immer**（`package.json` 里没有 `zustand/middleware/immer` 的 import；store 只 `import { create } from 'zustand'`）。所有更新都是 `map` / `filter` / 展开运算符手动造新对象。Dart 侧用 `copyWith` + 新 List 即可，不需要任何不可变集合库。
- 但「浅合并」意味着 `tasks` / `badges` / `pending` 的**新数组必须整体替换**，不能原地 `add` 后指望 zustand 感知——Dart 里如果用 `ChangeNotifier` 也一样，记得 `notifyListeners()`。

### 10.3 selector / 浅比较

- 页面用 `useGardenStore()` 默认挂载（`GardenLayout.tsx:82` 整对象解构）或 `useGardenStore((s) => s.x)` 选字段。zustand 的 selector 用引用比较（默认 `Object.is`），**没有深比较、也没有 `shallow`**（本仓库未使用 `shallow`）。Dart 里最稳的等价做法：单一状态对象 + `ChangeNotifier`，或 Riverpod 的 `select`。若用 Riverpod，注意选择器同样按 `==` 比较：Dart 的 `List` 默认是**引用相等**，因此新 List 实例会正常触发重建，而 `int`/`String`/`bool` 按值比较——与 zustand 的引用比较行为一致。
- `Array.from(new Set(...))`（`mergeOwnedItems`）在 Dart 里是 `toSet().toList()`：**顺序**要保持插入序（Dart 的 `LinkedHashSet` 默认就是插入序，OK）。

### 10.4 模块级可变状态

- `flushing`（补发闸）、`syncLoopReady`（监听器只挂一次）是**模块单例**，不是 store 字段。Dart 里对应 `static bool`/库级变量或单例服务上的字段。`flushing` 的语义是「并发调用直接 return」，用 `bool _flushing` + `try/finally` 即可（不要换成 Future 复用，语义不同：并发调用应被**丢弃**，不是等待同一个 Future —— 虽然实践中差别很小，但 `init` 里 `flushPending` 与 action 末尾的 `flushPending` 会真的并发）。
- `setInterval(30s)` → `Timer.periodic(const Duration(seconds: 30), ...)`；页面隐藏仍然触发 → 用 `AppLifecycleState`/`WidgetsBindingObserver` 判断并跳过，等价 `document.hidden`。`window.addEventListener('online')` → `connectivity_plus` 的连通性恢复回调。

### 10.5 时间与日期

- `toDateKey` 用**设备本地时区**；Dart 用 `DateTime.now()`（本地）+ 手写 `padLeft(2,'0')` 拼 `yyyy-MM-dd`，不要用 `toIso8601String().substring(0,10)`（那是 UTC），也不要用东八区换算。
- `new Date(Date.now() - 86400000)` → `DateTime.now().subtract(const Duration(days: 1))`（不要用 `DateTime(now.year, now.month, now.day - 1)`——虽等价于本仓库语义，但 `Duration` 写法与源码一一对应，更不容易出差）。
- `new Date().toISOString()`（`completedAt`）→ `DateTime.now().toUtc().toIso8601String()`（保持 UTC ISO 串格式，如 `2025-01-02T03:04:05.678Z`）。
- `createRequestId` 的 `crypto.randomUUID()` → Dart 用 `Uuid().v4()`（或 `Random` 拼 base36 的兜底分支，保持字符集满足服务端 `^[A-Za-z0-9][A-Za-z0-9_:.-]*$`）。

### 10.6 存储与 JSON

- `localStorage` 三个键 → `shared_preferences`（键名逐字保持 `sekainook_garden_state` / `sekainook_garden_migrated` / `sekainook_garden_pending`，方便将来导入 Web 旧档）。注意 `sekainook_garden_migrated` 的判据是**键存在**（值恒为 `'1'`），不是值为真。
- JSON 结构**逐字段对齐**（`tasks` 用 `id/name/duration/description/reward/icon/done/completedAt`；`badges` 用 `id/name/description/icon/earned`；pending 用 `id/taskId/kind/amount/itemId?/at`）→ 需要 `fromJson/toJson`，且**容错解析必须复刻** `toSafeCount` / `toSafeAmount` / `toSafeStringArray` / `toSafeId` / `toSafeCountRecord` / `toSafePendingOps` 六个函数的边界（尤其：`toSafeCount` 对 ≤0 返 0、`toSafeAmount` 保留 0 与负数、`toSafePendingOps` 一票否决整条）。Dart 里 `as int` 会对 `double`/`null` 抛错 → 用 `(json['x'] as num?)` 判断 `isFinite` + `toInt()/round()`，且 `Math.floor` → `value.floor()`，`Math.round` → `value.round()`（Dart 的 `round()` 对 `.5` 远离零取整，JS `Math.round` 对 `-0.5` 得 `-0`（等价 0）——金额只在 `toSafeAmount` 里 round，可能为负，注意负数半值差异：JS `Math.round(-0.5) === -0`，Dart `(-0.5).round() == -1`；实际金额都是整数，影响可忽略）。
- 「写入失败不能影响内存里的账」→ Dart 里给存储调用加 `try/catch` 并**忽略异常**，不要让它冒泡到 action。

### 10.7 HTTP 层要一起搬

- 12s 超时（`AbortController` → Dio 的 `connectTimeout/receiveTimeout` 或 `http` 包 + `.timeout()`）。
- 重试矩阵：GET 最多 2 次、写请求 `retry:true` 最多 1 次，等待 400ms/1200ms，仅对 `429/500/502/503/504` 与网络层失败重试；**POST /api/ledger 是带幂等 id 的**，所以可以安全重试 1 次。
- 错误分类 `isRejectedWriteError` 需要保留 HTTP 状态码：Dart 里自定义 `ApiException{message, status}`；status 0 表示网络/超时。**不能用「是否抛异常」来判断能否重试**。

### 10.8 迁移与幂等 id

- 迁移流水的确定性 id（`mig_legacy` / `mig_shop_<itemId>`）、`GARDEN_LEGACY_MAX = 2000` 的双侧夹取、以及「被拒就不落 `migrated` 标志位」三件事必须一起搬，否则会出现「迁移搬不完」或「重复入账」。
- 服务端「日限命中时先按 id 认幂等、再 409」的行为意味着客户端**不要**在收到 409 且它其实已入账时回滚——客户端不需要特殊处理，因为它只按 4xx 判「拒绝」；但如果 Flutter 端自行解析 `duplicate` 字段，要注意 200 + `duplicate:true` 也算成功。

### 10.9 装饰槽位与装备

- `equippedDecor` 的**顺序即语义**（头部最早）；Dart 里用 `List<String>` 并复刻 `slice(rest.length - 2)` 的语义：`kept = rest.length >= 3 ? rest.sublist(rest.length - 2) : rest;`。
- `init` 时的 `.slice(0, 3)` → `take(3).toList()`。
- 「被拒购买不回滚装备」是现状，若要修需明确记录为**有意偏离**。

### 10.10 需要额外补齐（Web 端由 React 生命周期代劳）

- 花园布局挂载时调 `init()`；Flutter 里对应「进入花园页面 / 应用首帧」调用一次，并保证可重复调用（幂等）。
- Web 端靠 `GardenLayout` 每次进入花园重挂载来触发日切；Flutter 应显式处理：**应用回到前台（`AppLifecycleState.resumed`）时**调 `flushPending()`，并在发现本地日期与各 `xxxDate` 不一致时按 §3.2 重置（Web 端只靠 `init`，所以 Flutter 端「更及时」是安全增强，但要保证与 `init` 完全相同的重置口径：只有 `tasksDate` 要整份换 `GARDEN_TASKS`）。
