/**
 * 管理员密码闸门（共用版）。
 *
 * 逻辑与 `functions/api/admin/index.ts:138-165` 完全一致：先看锁定期 → 读密码 →
 * 不区分「没填」和「填错」→ 记一次失败并回剩余次数。
 * 自检控制台也要用同一套节流，所以抽到这里；那边保持原样没动，避免碰生产主接口。
 *
 * 为什么不在自检里"宽松一点"：自检接口能改数据（真发通知、清闲置照片），
 * 放宽闸门等于给了一个免费的爆破入口。
 */

import {
  ADMIN_MAX_ATTEMPTS,
  clearAdminLock,
  readAdminLock,
  registerAdminFailure,
  verifyAdminPassword,
} from './settings';

export interface AdminGateOk {
  ok: true;
}

export interface AdminGateDenied {
  ok: false;
  status: number;
  body: Record<string, unknown>;
}

export type AdminGate = AdminGateOk | AdminGateDenied;

/** 锁定期内的统一回应：429 + 还要等多少秒 */
export function adminLockedResponse(lockRemainingMs: number): Response {
  const seconds = Math.max(1, Math.ceil(lockRemainingMs / 1000));
  return Response.json(
    { error: `密码错误次数太多，请等 ${seconds} 秒后再试`, lockRemainingMs },
    { status: 429 }
  );
}

/** 校验管理员密码；通过时顺手清掉失败计数。envPassword = 环境变量 ADMIN_PASSWORD（首次初始化用） */
export async function gateAdminPassword(
  db: D1Database,
  password: string,
  envPassword?: string
): Promise<AdminGate> {
  const lock = await readAdminLock(db);
  if (lock.lockRemainingMs > 0) {
    return { ok: false, status: 429, body: { error: `密码错误次数太多，请等 ${Math.max(1, Math.ceil(lock.lockRemainingMs / 1000))} 秒后再试`, lockRemainingMs: lock.lockRemainingMs } };
  }

  const verification = await verifyAdminPassword(db, envPassword, password);
  if (verification === 'unconfigured') {
    return {
      ok: false,
      status: 503,
      body: { error: '管理员口令还没配置：请给 Pages 项目加 ADMIN_PASSWORD 环境变量（secret）后重试' },
    };
  }

  if (verification !== 'ok') {
    const next = await registerAdminFailure(db);
    if (next.lockRemainingMs > 0) {
      return { ok: false, status: 429, body: { error: `密码错误次数太多，请等 ${Math.max(1, Math.ceil(next.lockRemainingMs / 1000))} 秒后再试`, lockRemainingMs: next.lockRemainingMs } };
    }
    return {
      ok: false,
      status: 401,
      body: {
        error: `管理员密码不对，还可以试 ${ADMIN_MAX_ATTEMPTS - next.failedAttempts} 次`,
        attemptsLeft: ADMIN_MAX_ATTEMPTS - next.failedAttempts,
      },
    };
  }

  await clearAdminLock(db);
  return { ok: true };
}
