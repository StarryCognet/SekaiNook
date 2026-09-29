/**
 * 积分流水集合接口。
 * 路由：GET /api/ledger（支持 ?status= 与 ?member= 过滤）、POST /api/ledger
 *
 * 说明：member 列由 migrations/0002_ledger_member.sql 引入（可选，多孩子场景）。
 * 为了兼容尚未执行该迁移的库，GET 用 SELECT *（列不存在只是读不到该字段），
 * POST 仅在请求真的带了 member 时才写这一列。
 */

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
        typeof status === 'string' ? status : 'approved',
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
        typeof status === 'string' ? status : 'approved',
        createdAt
      )
      .run();
  }

  return Response.json({ id }, { status: 201 });
};
