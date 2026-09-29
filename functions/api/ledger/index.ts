/**
 * 积分流水集合接口。
 * 路由：GET /api/ledger（支持 ?status= 与 ?member= 过滤）、POST /api/ledger
 *
 * 说明：member 列由 migrations/0002_ledger_member.sql 引入（历史遗留：多成员功能已下线，前端不再传该字段，接口保留此列只为兼容老数据）。
 * 为了兼容尚未执行该迁移的库，GET 用 SELECT *（列不存在只是读不到该字段），
 * POST 仅在请求真的带了 member 时才写这一列。
 */

import { amountText, pushNotifications } from '../../_lib/notifications';
import { displayName, readFamilyNames } from '../../_lib/settings';

interface Env {
  DB: D1Database;
}

const LEDGER_STATUSES: readonly string[] = ['pending', 'approved', 'rejected'];
const TASK_TYPES: readonly string[] = ['earning', 'spending'];
/** 成员名长度上限，避免脏数据撑爆界面 */
const MEMBER_MAX_LENGTH = 20;

/** 查询流水列表，按创建时间倒序，可按状态/成员过滤 */
export const onRequestGet: PagesFunction<Env> = async ({ request, env }) => {
  const search = new URL(request.url).searchParams;
  const status = search.get('status');
  const member = search.get('member');

  const clauses: string[] = [];
  const values: string[] = [];
  if (status) {
    clauses.push('status = ?');
    values.push(status);
  }
  if (member) {
    clauses.push('member = ?');
    values.push(member);
  }
  const where = clauses.length > 0 ? ` WHERE ${clauses.join(' AND ')}` : '';

  const stmt = env.DB.prepare(`SELECT * FROM family_ledger${where} ORDER BY created_at DESC`);
  const { results } = await (values.length > 0 ? stmt.bind(...values) : stmt).all();
  return Response.json(results ?? []);
};

/** 新增一条流水 */
export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  let body: Record<string, unknown>;
  try {
    body = await request.json<Record<string, unknown>>();
  } catch {
    return Response.json({ error: '请求体不是合法 JSON' }, { status: 400 });
  }

  const { task_id, task_name, type, amount, note, image_url, status } = body;

  if (typeof task_id !== 'string' || !task_id) {
    return Response.json({ error: 'task_id 非法' }, { status: 400 });
  }
  if (typeof task_name !== 'string' || !task_name) {
    return Response.json({ error: 'task_name 非法' }, { status: 400 });
  }
  if (typeof type !== 'string' || !TASK_TYPES.includes(type)) {
    return Response.json({ error: 'type 非法' }, { status: 400 });
  }
  if (typeof amount !== 'number' || !Number.isFinite(amount)) {
    return Response.json({ error: 'amount 非法' }, { status: 400 });
  }
  if (status !== undefined && (typeof status !== 'string' || !LEDGER_STATUSES.includes(status))) {
    return Response.json({ error: 'status 非法' }, { status: 400 });
  }

  const member =
    typeof body.member === 'string' && body.member.trim()
      ? body.member.trim().slice(0, MEMBER_MAX_LENGTH)
      : null;

  const id = crypto.randomUUID();
  const createdAt = new Date().toISOString();
  const finalStatus = typeof status === 'string' ? status : 'approved';

  if (member) {
    await env.DB.prepare(
      `INSERT INTO family_ledger (id, task_id, task_name, type, amount, note, image_url, status, created_at, member)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    )
      .bind(
        id,
        task_id,
        task_name,
        type,
        amount,
        typeof note === 'string' ? note : null,
        typeof image_url === 'string' ? image_url : null,
        finalStatus,
        createdAt,
        member
      )
      .run();
  } else {
    // 未指定成员：沿用不含 member 的语句，兼容没跑过 0002 迁移的库
    await env.DB.prepare(
      `INSERT INTO family_ledger (id, task_id, task_name, type, amount, note, image_url, status, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
    )
      .bind(
        id,
        task_id,
        task_name,
        type,
        amount,
        typeof note === 'string' ? note : null,
        typeof image_url === 'string' ? image_url : null,
        finalStatus,
        createdAt
      )
      .run();
  }

  // 记完账再写通知（写通知失败不影响记账）：
  //   孩子提交打卡 → 告诉家长；家长直接记账 / 结算兑现 → 告诉孩子
  // 文案里的称呼按设置表走（女儿怎么叫妈妈、妈妈怎么叫女儿），读不到就用默认值
  const amountLabel = amountText(type, amount);
  if (finalStatus === 'pending') {
    const names = await readFamilyNames(env.DB);
    await pushNotifications(env.DB, [
      {
        audience: 'parent',
        type: 'checkin_pending',
        title: `${displayName(names, 'kid')}提交了打卡`,
        body: `${task_name} ${amountLabel}`,
        link: '/family',
        dedupeKey: `ledger:${id}:pending`,
      },
    ]);
  } else if (finalStatus === 'approved' && task_id === 'payout') {
    const names = await readFamilyNames(env.DB);
    await pushNotifications(env.DB, [
      {
        audience: 'child',
        type: 'payout',
        title: `${displayName(names, 'mom')}兑现了 ${Math.abs(amount)} 积分`,
        body: '余额已清零，明天继续加油',
        link: '/family',
        dedupeKey: `ledger:${id}:payout`,
      },
    ]);
  } else if (finalStatus === 'approved') {
    const names = await readFamilyNames(env.DB);
    await pushNotifications(env.DB, [
      {
        audience: 'child',
        type: 'recorded',
        title: `${displayName(names, 'mom')}记了一笔`,
        body: `${task_name} ${amountLabel}`,
        link: '/family',
        dedupeKey: `ledger:${id}:recorded`,
      },
    ]);
  }

  return Response.json({ id }, { status: 201 });
};
