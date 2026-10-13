/**
 * 管理员接口（家庭后台）。
 * 路由：POST /api/admin —— 校验密码 / 直接改积分数 / 改密码
 *
 * **为什么单独开一个接口，而不是复用 POST /api/ledger**：
 *   记账接口有一整套防刷闸门（当天条数 ≤ 20、正向总额 ≤ 50、同名当天只算一次），
 *   那些是给孩子打卡用的；管理员是家长本人手动校准余额，按差额补一笔流水即可，
 *   那套闸门会把「把余额改成 500」这种大调整直接拦死。
 *
 * **为什么是「按差额记一条流水」而不是直接改余额**：余额是流水聚合出来的
 *   （见 functions/api/ledger/summary.ts），库里没有单独的余额字段可改。
 *   记一条「管理员调整」流水的好处是留痕可审计，也能在账本页直接删掉回退。
 *
 * **为什么密码校验必须在服务端**：这个接口能改余额，只在前端拦一道的话，
 *   任何人直接 POST /api/admin 就能改账本。密码存在 settings 表，
 *   没设过就回退出厂密码（functions/_lib/settings.ts 的 DEFAULT_ADMIN_PASSWORD）。
 *
 * 幂等：调整是按「目标值 − 当前值」算差额，重复提交时差额已经归零，不会再写。
 */

import {
  MAX_ADMIN_PASSWORD_LENGTH,
  MIN_ADMIN_PASSWORD_LENGTH,
  readAdminPassword,
  sanitizeAdminPassword,
  writeAdminPassword,
} from '../../_lib/settings';
import { GARDEN_ID_PREFIXES } from '../../_lib/rules';
import { LEDGER_SUMMARY_SQL } from '../ledger/summary';

interface Env {
  DB: D1Database;
}

/** 管理员调整在流水里的 task_id。花园那条必须带花园前缀，才会被算进「阳光」总额 */
const ADMIN_FAMILY_TASK_ID = 'admin_adjust';
const ADMIN_SUN_TASK_ID = `${GARDEN_ID_PREFIXES[0] ?? 'garden:'}admin_adjust`;

/** 管理员调整流水里显示的任务名 */
const ADMIN_TASK_NAME = '管理员调整';

/** 一次调整的绝对值上限：防手滑多打几位把余额推到天文数字 */
const MAX_ADJUST_ABS = 1_000_000;

interface Summary {
  family: number;
  sun: number;
}

/** 当前两个余额（与全量余额接口同一套 SQL，口径不会漂） */
async function readSummary(db: D1Database): Promise<Summary> {
  const row = await db
    .prepare(LEDGER_SUMMARY_SQL)
    .first<{ family: number | null; sun: number | null }>();
  return { family: row?.family ?? 0, sun: row?.sun ?? 0 };
}

/** 目标积分是否合法：算成整数后必须落在 ±MAX_ADJUST_ABS 内 */
function normalizeTarget(value: unknown): number | null {
  if (typeof value !== 'number' || !Number.isFinite(value)) return null;
  const rounded = Math.round(value);
  if (Math.abs(rounded) > MAX_ADJUST_ABS) return null;
  return rounded;
}

/** 记一条调整流水；差额为 0（目标值就是当前值）时什么都不写 */
async function writeAdjustment(
  db: D1Database,
  taskId: string,
  delta: number,
  note: string
): Promise<void> {
  if (delta === 0) return;
  const id = `${taskId}_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  await db
    .prepare(
      `INSERT INTO family_ledger (id, task_id, task_name, type, amount, note, status, created_at)
       VALUES (?, ?, ?, ?, ?, ?, 'approved', ?)`
    )
    .bind(
      id,
      taskId,
      ADMIN_TASK_NAME,
      delta > 0 ? 'earning' : 'spending',
      delta,
      note,
      new Date().toISOString()
    )
    .run();
}

/** 统一的成功响应：把最新余额带回去，前端不用再拉一次 */
function respond(summary: Summary, extra: Record<string, unknown> = {}): Response {
  return Response.json({ family: summary.family, sun: summary.sun, ...extra });
}

export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return Response.json({ error: '请求体不是合法 JSON' }, { status: 400 });
  }

  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    return Response.json({ error: '请求体必须是对象' }, { status: 400 });
  }

  const body = payload as Record<string, unknown>;
  const action = typeof body.action === 'string' ? body.action : 'verify';
  const password = typeof body.password === 'string' ? body.password.trim() : '';

  let stored: string;
  try {
    stored = await readAdminPassword(env.DB);
  } catch (error) {
    console.error('admin password read failed', error);
    return Response.json({ error: '设置表尚未就绪，请先执行数据库迁移' }, { status: 503 });
  }

  // 不区分「没填」和「填错了」，也不透露任何关于正确密码的信息
  if (!password || password !== stored) {
    return Response.json({ error: '管理员密码不对' }, { status: 401 });
  }

  try {
    if (action === 'password') {
      const next = sanitizeAdminPassword(body.newPassword);
      if (!next) {
        return Response.json(
          { error: `新密码需为 ${MIN_ADMIN_PASSWORD_LENGTH}-${MAX_ADMIN_PASSWORD_LENGTH} 位` },
          { status: 400 }
        );
      }
      await writeAdminPassword(env.DB, next);
      return respond(await readSummary(env.DB), { passwordChanged: true });
    }

    if (action === 'adjust') {
      const before = await readSummary(env.DB);
      const changed: string[] = [];

      if ('family' in body) {
        const target = normalizeTarget(body.family);
        if (target === null) {
          return Response.json(
            { error: `家庭积分需要是 ±${MAX_ADJUST_ABS} 之间的整数` },
            { status: 400 }
          );
        }
        await writeAdjustment(
          env.DB,
          ADMIN_FAMILY_TASK_ID,
          target - before.family,
          `管理员把家庭积分改成 ${target}（原来 ${before.family}）`
        );
        changed.push(`家庭积分 ${before.family} → ${target}`);
      }

      if ('sun' in body) {
        const target = normalizeTarget(body.sun);
        if (target === null) {
          return Response.json(
            { error: `花园阳光需要是 ±${MAX_ADJUST_ABS} 之间的整数` },
            { status: 400 }
          );
        }
        await writeAdjustment(
          env.DB,
          ADMIN_SUN_TASK_ID,
          target - before.sun,
          `管理员把花园阳光改成 ${target}（原来 ${before.sun}）`
        );
        changed.push(`花园阳光 ${before.sun} → ${target}`);
      }

      if (changed.length === 0) {
        return Response.json({ error: '没有要修改的积分' }, { status: 400 });
      }

      return respond(await readSummary(env.DB), { changed });
    }

    // 默认动作：只校验密码，把当前余额带回去（进管理员面板第一步）
    return respond(await readSummary(env.DB));
  } catch (error) {
    console.error('admin action failed', error);
    return Response.json({ error: '操作失败，请重试' }, { status: 500 });
  }
};
