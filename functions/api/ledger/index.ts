/**
 * 积分流水集合接口。
 * 路由：GET /api/ledger（?status= / ?member= / ?limit= / ?since=）、POST /api/ledger
 *
 * 两条硬规矩：
 *  1. **POST 不采信客户端声称的审批状态**。除了服务端规则里标了 autoApprove 的花园奖励，
 *     其余一律写成 pending；只有 PATCH /api/ledger/:id 才能把它改成 approved。
 *     积分值、任务名、类型也一律以服务端规则（functions/_lib/rules.ts）为准。
 *  2. **幂等**：客户端可以自带 id（网络重试、离线补发都用同一个 id），
 *     主键冲突时直接返回已有记录，不会重复入账。
 *
 * 说明：member 列由 migrations/0002_ledger_member.sql 引入（历史遗留：多成员功能已下线，
 * 前端不再传该字段，接口保留此列只为兼容老数据）。
 */

import { amountText, pushNotifications } from '../../_lib/notifications';
import { displayName, readFamilyNames } from '../../_lib/settings';
import { LEDGER_TASK_RULES, beijingDayBounds, checkLedgerRule } from '../../_lib/rules';

interface Env {
  DB: D1Database;
}

const TASK_TYPES: readonly string[] = ['earning', 'spending'];
/** 成员名长度上限，避免脏数据撑爆界面 */
const MEMBER_MAX_LENGTH = 20;
/** 一次最多拉多少条；不传时默认最近 200 条（原先无上限整表拉取） */
const DEFAULT_LIMIT = 200;
const MAX_LIMIT = 500;
const ID_MAX_LENGTH = 64;
const ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_:.-]*$/;

/** 查询流水列表，按创建时间倒序，可按状态/成员过滤，支持增量与分页 */
export const onRequestGet: PagesFunction<Env> = async ({ request, env }) => {
  const search = new URL(request.url).searchParams;
  const status = search.get('status');
  const member = search.get('member');
  const since = search.get('since');
  const limitRaw = Number(search.get('limit'));
  const limit =
    Number.isFinite(limitRaw) && limitRaw > 0
      ? Math.min(Math.floor(limitRaw), MAX_LIMIT)
      : DEFAULT_LIMIT;

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
  if (since) {
    // 增量拉取：只要比上次拿到的更新的记录
    clauses.push('created_at > ?');
    values.push(since);
  }
  const where = clauses.length > 0 ? ` WHERE ${clauses.join(' AND ')}` : '';

  const stmt = env.DB.prepare(
    `SELECT * FROM family_ledger${where} ORDER BY created_at DESC LIMIT ${limit}`
  );
  const { results } = await (values.length > 0 ? stmt.bind(...values) : stmt).all();
  return Response.json(results ?? []);
};

/** 新增一条流水（默认进待审批，除服务端标记 autoApprove 的花园奖励） */
export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  let body: Record<string, unknown>;
  try {
    body = await request.json<Record<string, unknown>>();
  } catch {
    return Response.json({ error: '请求体不是合法 JSON' }, { status: 400 });
  }

  const { task_id, task_name, type, amount, note, image_url } = body;

  if (typeof task_id !== 'string' || !task_id || task_id.length > ID_MAX_LENGTH) {
    return Response.json({ error: 'task_id 非法' }, { status: 400 });
  }

  // 已知任务：名字 / 类型 / 积分全部以服务端规则为准，客户端改不动
  const rule = LEDGER_TASK_RULES[task_id];
  if (!rule) {
    if (typeof task_name !== 'string' || !task_name) {
      return Response.json({ error: 'task_name 非法' }, { status: 400 });
    }
    if (typeof type !== 'string' || !TASK_TYPES.includes(type)) {
      return Response.json({ error: 'type 非法' }, { status: 400 });
    }
    if (typeof amount !== 'number' || !Number.isFinite(amount)) {
      return Response.json({ error: 'amount 非法' }, { status: 400 });
    }
  }
  const finalName = rule ? rule.name : (task_name as string);
  const finalType = rule ? rule.type : (type as string);
  const finalAmount = rule ? rule.value : (amount as number);

  // 客户端传来的 status 一律忽略：只有服务端标了 autoApprove 的才直接入账
  const finalStatus = rule?.autoApprove ? 'approved' : 'pending';

  const now = new Date();
  if (rule && !rule.autoApprove) {
    const blocked = checkLedgerRule(rule, now);
    if (blocked) {
      return Response.json({ error: blocked }, { status: 409 });
    }
  }

  const { startIso, endIso } = beijingDayBounds(now);
  if (rule?.dailyLimit !== undefined) {
    const counted = await env.DB.prepare(
      `SELECT COUNT(*) AS c FROM family_ledger
       WHERE task_id = ? AND status != 'rejected' AND created_at >= ? AND created_at < ?`
    )
      .bind(task_id, startIso, endIso)
      .first<{ c: number }>();
    if ((counted?.c ?? 0) >= rule.dailyLimit) {
      const message =
        rule.dailyLimit === 1
          ? `「${rule.name}」今天已经打过卡啦`
          : `「${rule.name}」每天最多 ${rule.dailyLimit} 次，今天用完啦`;
      return Response.json({ error: message }, { status: 409 });
    }
  }

  const id =
    typeof body.id === 'string' && ID_PATTERN.test(body.id)
      ? body.id.slice(0, ID_MAX_LENGTH)
      : crypto.randomUUID();
  const createdAt = now.toISOString();

  const member =
    typeof body.member === 'string' && body.member.trim()
      ? body.member.trim().slice(0, MEMBER_MAX_LENGTH)
      : null;

  const noteValue = typeof note === 'string' ? note : null;
  const imageValue = typeof image_url === 'string' ? image_url : null;

  // INSERT OR IGNORE：同一个 id 重发（网络重试 / 离线补发）直接命中主键，不会重复入账
  const result = member
    ? await env.DB.prepare(
        `INSERT OR IGNORE INTO family_ledger (id, task_id, task_name, type, amount, note, image_url, status, created_at, member)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      )
        .bind(
          id,
          task_id,
          finalName,
          finalType,
          finalAmount,
          noteValue,
          imageValue,
          finalStatus,
          createdAt,
          member
        )
        .run()
    : await env.DB.prepare(
        `INSERT OR IGNORE INTO family_ledger (id, task_id, task_name, type, amount, note, image_url, status, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
      )
        .bind(
          id,
          task_id,
          finalName,
          finalType,
          finalAmount,
          noteValue,
          imageValue,
          finalStatus,
          createdAt
        )
        .run();

  if (!result.meta.changes) {
    // 主键撞上了：这条请求之前已经成功写入过（重试或离线补发），把已有记录还给调用方
    const existing = await env.DB.prepare('SELECT id, status FROM family_ledger WHERE id = ?')
      .bind(id)
      .first<{ id: string; status: string }>();
    if (existing) {
      return Response.json({ id: existing.id, status: existing.status, duplicate: true });
    }
    return Response.json({ error: '写入失败，请重试' }, { status: 500 });
  }

  // 记完账再写通知（写通知失败不影响记账）：
  //   孩子提交打卡 → 告诉家长；花园奖励即时到账，不打扰家长；
  //   家长记账 / 审批结果 → 由 PATCH /api/ledger/:id 通知孩子
  if (finalStatus === 'pending') {
    const names = await readFamilyNames(env.DB);
    await pushNotifications(env.DB, [
      {
        audience: 'parent',
        type: 'checkin_pending',
        title: `${displayName(names, 'kid')}提交了打卡`,
        body: `${finalName} ${amountText(finalType, finalAmount)}`,
        link: '/family',
        dedupeKey: `ledger:${id}:pending`,
      },
    ]);
  }

  return Response.json({ id, status: finalStatus }, { status: 201 });
};
