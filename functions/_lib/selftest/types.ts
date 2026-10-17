/**
 * 全站自检的类型定义（见 docs/selftest-console.md）。
 *
 * 设计要点：清单与执行都在服务端，客户端只渲染 + 跑自己的本地项。
 * 所以这里的类型同时描述「清单里一条长什么样」与「跑完一条返回什么」。
 */

/** 一条检查的结果状态：pass 通过 / fail 失败 / warn 值得看一眼 / skip 没跑（预演或客户端项） */
export type SelftestStatus = 'pass' | 'fail' | 'warn' | 'skip';

/** 检查项的危险程度：safe 只读 / write 会写库 / destructive 会删数据 */
export type SelftestDanger = 'safe' | 'write' | 'destructive';

/** 参数类型：bool / int / string / enum */
export interface SelftestParamSpec {
  name: string;
  label: string;
  type: 'bool' | 'int' | 'string' | 'enum';
  desc: string;
  default?: string | number | boolean;
  options?: string[];
}

/** 参数规格表：清单顶层给一份，检查项只声明自己用哪些（避免每个 item 重复贴 schema） */
export const PARAM_SPECS: Record<string, SelftestParamSpec> = {
  dryRun: {
    name: 'dryRun',
    label: '预演（不写库）',
    type: 'bool',
    desc: '写库类检查在预演模式下只计算不落库；关掉才会真写，跑完仍会自清理',
    default: true,
  },
  now: {
    name: 'now',
    label: '时间旅行',
    type: 'string',
    desc: 'ISO 时间，替代真实时间参与口径计算（日界、22 点、周标签）',
  },
  simulateDone: {
    name: 'simulateDone',
    label: '模拟今天完成数',
    type: 'int',
    desc: '假装今天已完成 N 个任务，用于通知文案与罚款预演',
  },
  dayKey: {
    name: 'dayKey',
    label: '指定日期',
    type: 'string',
    desc: '东八区日期 YYYY-MM-DD，留空 = 今天',
  },
  taskId: {
    name: 'taskId',
    label: '任务 id',
    type: 'string',
    desc: '自检写入用的任务，默认 clean_room',
    default: 'clean_room',
  },
  amount: { name: 'amount', label: '金额', type: 'int', desc: '自检写入的积分数', default: 10 },
  note: { name: 'note', label: '备注', type: 'string', desc: '自检写入的备注', default: '自检' },
  weekLabel: { name: 'weekLabel', label: '周标签', type: 'string', desc: '如 2026-W42，留空 = 当前周' },
  audience: {
    name: 'audience',
    label: '推送目标',
    type: 'enum',
    desc: '推送发给谁',
    options: ['all', 'parent', 'child'],
    default: 'all',
  },
  endpoint: { name: 'endpoint', label: '指定设备', type: 'string', desc: 'push_subscriptions.endpoint，留空 = 全部设备' },
  channel: {
    name: 'channel',
    label: '推送通道',
    type: 'enum',
    desc: '走哪条通道',
    options: ['webpush', 'ntfy', 'bark', 'webhook'],
  },
  title: { name: 'title', label: '通知标题', type: 'string', desc: '自定义标题，留空 = 用真实文案' },
  message: { name: 'message', label: '通知正文', type: 'string', desc: '自定义正文，留空 = 用真实文案' },
  click: { name: 'click', label: '点击打开', type: 'string', desc: '通知点击后打开的地址' },
  priority: { name: 'priority', label: '优先级', type: 'int', desc: '1–5，默认 4' },
  force: { name: 'force', label: '跳过幂等标记', type: 'bool', desc: '推送：忽略当天已发标记再发一次' },
  keep: { name: 'keep', label: '保留测试数据', type: 'bool', desc: '写库类检查跑完不清理（默认清理）' },
};

/** 归一化后的参数：检查项直接读这里，不用再管类型转换 */
export interface SelftestParams {
  dryRun: boolean;
  now: Date;
  simulateDone: number | null;
  dayKey: string | null;
  taskId: string;
  amount: number;
  note: string;
  weekLabel: string | null;
  audience: 'all' | 'parent' | 'child';
  endpoint: string | null;
  channel: 'webpush' | 'ntfy' | 'bark' | 'webhook' | null;
  title: string | null;
  message: string | null;
  click: string | null;
  priority: number | null;
  force: boolean;
  keep: boolean;
  /** 客户端上报的结果（按 id 索引），供「口径对账」类检查取数 */
  clientResults: Map<string, ClientResult>;
}

/** 客户端跑完回传的一条结果 */
export interface ClientResult {
  id: string;
  status: SelftestStatus;
  ms?: number;
  detail?: string;
  data?: unknown;
}

/** 自检运行上下文：检查项拿它打接口、读库、记备注 */
export interface SelftestCtx {
  env: SelftestEnv;
  db: D1Database;
  /** 站点根地址（自打接口用，测的就是真实 HTTP 路径） */
  origin: string;
  params: SelftestParams;
  /** 打本站接口：path 以 / 开头 */
  api: (path: string, init?: RequestInit) => Promise<Response>;
  /** 打提醒 Worker（走 REMIND_TOKEN，令牌不出服务端） */
  worker: (path: string, init?: RequestInit) => Promise<Response>;
  /** 管理员密码（已通过闸门；部分检查项要拿它调 /api/admin） */
  password: string;
  /** 记一条运行备注（会出现在响应的 notes 里） */
  note: (text: string) => void;
}

/** 检查项运行函数返回的东西（status 之外都可省） */
export interface SelftestOutcome {
  status: SelftestStatus;
  detail: string;
  data?: unknown;
  hint?: string;
}

export interface SelftestItem {
  id: string;
  name: string;
  desc: string;
  group: string;
  side: 'server' | 'client';
  /** 客户端项：这一项该在哪个平台跑 */
  client?: 'web' | 'flutter';
  mutates?: boolean;
  danger?: SelftestDanger;
  /** 用到的参数名（对应 PARAM_SPECS） */
  uses?: string[];
  estMs?: number;
  /** 客户端项没有 run；服务端项必须有 */
  run?: (ctx: SelftestCtx) => Promise<SelftestOutcome>;
}

/** 一键预设：常用场景的组合 + 预填参数 */
export interface SelftestPreset {
  id: string;
  name: string;
  desc: string;
  /** 预填参数（覆盖默认值） */
  params?: Record<string, unknown>;
  /** 只跑这些项（省略 = 全部） */
  itemIds?: string[];
  /** 过滤掉所有会写数据的项（只读体检用） */
  skipMutating?: boolean;
}

export interface SelftestGroup {
  id: string;
  name: string;
  desc: string;
  /** 分组下的检查项：注册表里只声明分组，清单生成时按 group 归集（见 run.ts buildCatalog） */
  items?: SelftestItem[];
}

/** 检查项结果（清单项 + 运行结果） */
export interface SelftestResult extends SelftestOutcome {
  id: string;
  group: string;
  name: string;
  side: 'server' | 'client';
  mutates: boolean;
  ms: number;
}

/** 自检用到的绑定：DB 必有；R2 与提醒 Worker 的相关配置可能没配 */
export interface SelftestEnv {
  DB: D1Database;
  STARRYMIKU_BUCKET?: R2Bucket;
  /** 提醒 Worker 的地址（var） */
  REMINDER_URL?: string;
  /** 提醒 Worker 的 /trigger 令牌（Pages secret，不下发到浏览器） */
  REMIND_TOKEN?: string;
}

/** POST /api/admin/selftest 的请求体 */
export interface SelftestRunRequest {
  password: string;
  /** 只跑这些项（省略 = 全部） */
  items?: string[];
  /** 只跑这些分组（与 items 取并集；都省略 = 全部） */
  groups?: string[];
  params?: Record<string, unknown>;
  /** 客户端本地项的运行结果，回传进来参与对账 */
  clientResults?: ClientResult[];
  /** 是否在结果里保留客户端项（默认保留并标记 skip: client-side） */
  includeClient?: boolean;
}

/** 一次自检的汇总结果 */
export interface SelftestRunResponse {
  ranAt: string;
  durationMs: number;
  env: { db: string; origin: string; now: string; worker: string };
  params: Record<string, unknown>;
  summary: { total: number; passed: number; failed: number; skipped: number; warned: number };
  results: SelftestResult[];
  /** 这一轮选了、但前端没回传结果的客户端检查项 id（前端据此提示「还有 N 项没跑」） */
  clientMissing: string[];
  notes: string[];
}
