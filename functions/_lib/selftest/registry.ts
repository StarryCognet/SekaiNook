/**
 * 自检清单的注册表：分组、客户端项、预设。
 *
 * 检查项本体分散在 checks-core / checks-rules / checks-rest，这里只做装配，
 * 所以「清单」与「执行」永远是同一份数据 —— 加一项检查只需改一个数组。
 */

import { CORE_ITEMS } from './checks-core';
import { RULES_ITEMS } from './checks-rules';
import { REST_ITEMS } from './checks-rest';
import { skip } from './helpers';
import type { SelftestGroup, SelftestItem, SelftestPreset } from './types';

/** 清单版本：客户端会把它显示出来，改动检查项集合时 +1（0006 起多了 env.changelog） */
export const SELFTEST_VERSION = 2;

export const SELFTEST_GROUPS: SelftestGroup[] = [
  { id: 'env', name: '环境与部署', desc: '绑定、数据表、迁移、CORS、静态资源' },
  { id: 'ledger', name: '流水与账本', desc: '记账、审批、驳回、撤回、余额、结算' },
  { id: 'rules', name: '规则与结算', desc: '任务规则表、防刷闸门、周计划、ISO 周标签' },
  { id: 'plans', name: '每周学习计划', desc: '计划读取、创建、改数值' },
  { id: 'notify', name: '通知', desc: '信箱、未读数、全部已读、跨端文案' },
  { id: 'settings', name: '设置', desc: '称呼、背景图、参数校验' },
  { id: 'images', name: '图片', desc: '匿名读取、上传链路、闲置清理' },
  { id: 'push', name: '手机提醒（推送）', desc: 'VAPID、订阅、Worker、真发一条' },
  { id: 'admin', name: '管理员', desc: '密码节流、调整留痕、一键清零' },
  { id: 'maintenance', name: '维护体检', desc: 'settings 键、时间戳、数据卫生' },
  { id: 'client', name: '客户端', desc: '在浏览器 / Flutter 里本地跑的检查' },
];

/** 客户端检查项：服务端只声明与登记，真正的执行在客户端，跑完把结果回传 */
function clientItem(
  id: string,
  name: string,
  desc: string,
  client: 'web' | 'flutter',
  estMs: number
): SelftestItem {
  return {
    id,
    name,
    desc,
    group: 'client',
    side: 'client',
    client,
    estMs,
    run: async () => skip('client-side'),
  };
}

export const CLIENT_ITEMS: SelftestItem[] = [
  clientItem('web.routes', '7 条路由', '逐条切过去，页面根节点有内容且无异常', 'web', 900),
  clientItem('web.theme', '7 套主题 × 浅/深', '切换后 data-theme 与 CSS 变量生效', 'web', 700),
  clientItem('web.sw', 'Service Worker', '/sw.js 已注册、push 能力可用', 'web', 300),
  clientItem('web.push', '推送订阅状态', '权限、PushManager、当前订阅与 iOS 提示', 'web', 400),
  clientItem('web.storage', 'localStorage', '读写删 + sekainook_* 键清单', 'web', 200),
  clientItem('web.export', '导出数据源', 'CSV/JSON 能生成（不触发下载）', 'web', 300),
  clientItem('flutter.routes', '7 条路由', 'go 之后对应页面构建成功', 'flutter', 900),
  clientItem('flutter.theme', '7 套主题与对比度', '主题构建 + 色板对比度不低于 4.5:1', 'flutter', 700),
  clientItem('flutter.notify.permission', '通知权限', '查询 + 请求（Android 13+）', 'flutter', 400),
  clientItem('flutter.notify.schedule', '排一条本地通知', '排 5 秒后的通知并断言已排程', 'flutter', 500),
  clientItem('flutter.notify.cancel', '取消本地通知', '取消上面那条并断言已取消', 'flutter', 300),
  clientItem('flutter.storage', 'SharedPreferences', '读写删 + 键清单', 'flutter', 200),
  clientItem('flutter.image', '图片压缩', '测试图长边 ≤ 1600 且体积变小', 'flutter', 600),
];

export const SELFTEST_ITEMS: SelftestItem[] = [
  ...CORE_ITEMS,
  ...RULES_ITEMS,
  ...REST_ITEMS,
  ...CLIENT_ITEMS,
];

/**
 * 预设：一键切到常见场景。
 * `skipMutating` 用来做「只读体检」——把所有会写数据的项过滤掉。
 */
export const SELFTEST_PRESETS: SelftestPreset[] = [
  { id: 'readonly', name: '只读体检', desc: '只跑不会动数据的项，随时可跑', skipMutating: true },
  { id: 'all', name: '全量检查', desc: '所有服务端项，含写库与真发通知' },
  { id: 'ledger.cycle', name: '记一笔闭环', desc: '写流水 → 幂等重发 → 审批 → 驳回重提', itemIds: ['ledger.write.idempotent', 'ledger.approve', 'ledger.reject.resubmit'] },
  { id: 'rules.check', name: '规则与闸门', desc: '规则表、防刷闸门、客户端对照表', itemIds: ['rules.snapshot', 'rules.sleep_window', 'rules.completion.sql', 'rules.client.table', 'ledger.write.daily_limit', 'ledger.write.unknown_task'] },
  { id: 'notify.short3', name: '还差 3 个任务', desc: '预演/真发「今天还差 3 个任务」', params: { simulateDone: 2 } },
  { id: 'notify.done', name: '任务已经做够', desc: '预演/真发「已完成 5/5」，验证不推', params: { simulateDone: 5 } },
  { id: 'notify.custom', name: '自定义文案', desc: '用自定义标题与正文真发一条', params: { title: 'SekaiNook 自检', message: '这是一条来自自检控制台的测试通知。' } },
  { id: 'push.chain', name: '推送全链路', desc: 'VAPID → 订阅 → Worker 在线 → 预演 → 真发', itemIds: ['push.key', 'push.list', 'push.worker.health', 'push.worker.dry', 'push.send'] },
  { id: 'client.web', name: '浏览器端检查', desc: '只在 Web 设置页里跑', itemIds: CLIENT_ITEMS.filter((item) => item.client === 'web').map((item) => item.id) },
  { id: 'client.flutter', name: 'Flutter 端检查', desc: '只在 App 设置页里跑', itemIds: CLIENT_ITEMS.filter((item) => item.client === 'flutter').map((item) => item.id) },
];

/** 按 id 取检查项（未知名忽略，由调用方决定怎么提示） */
export function findItems(ids: readonly string[]): SelftestItem[] {
  const wanted = new Set(ids);
  return SELFTEST_ITEMS.filter((item) => wanted.has(item.id));
}

/** 清单里客户端检查 id 的分组（给两端各自的 UI 用） */
export function clientChecks(): { web: string[]; flutter: string[] } {
  return {
    web: CLIENT_ITEMS.filter((item) => item.client === 'web').map((item) => item.id),
    flutter: CLIENT_ITEMS.filter((item) => item.client === 'flutter').map((item) => item.id),
  };
}
