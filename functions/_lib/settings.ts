/**
 * 家庭称呼（settings 表）的读写工具。
 *
 * 为什么要放服务端：通知文案是在记账/审批时由服务端拼出来的
 *（「妹妹提交了打卡」这类），所以称呼必须能被 Functions 读到；
 * 同时两个人在不同手机上打开要看到同一套称呼，因此存 D1 而不是 localStorage。
 *
 * 路由说明：下划线开头的路径不会被 Pages 当成接口，真正的接口在 functions/api/settings/。
 *
 * 语义（和界面上的视角一致）：
 *   - momCall / momNickname：女儿怎么叫妈妈（妈妈的身份由女儿设置）
 *   - kidCall / kidNickname：妈妈怎么叫女儿（女儿的身份由妈妈设置）
 *   - 显示时昵称优先，没填昵称才用称呼
 */

export type FamilyNamesKey = 'momCall' | 'momNickname' | 'kidCall' | 'kidNickname';

export interface FamilyNames {
  /** 女儿对妈妈的称呼，例如「妈妈」 */
  momCall: string;
  /** 女儿给妈妈起的昵称，例如「老妈」（填了就优先显示） */
  momNickname: string;
  /** 妈妈对女儿的称呼，例如「女儿」 */
  kidCall: string;
  /** 妈妈给女儿起的昵称，例如「妹妹」（填了就优先显示） */
  kidNickname: string;
}

export const FAMILY_NAME_KEYS: readonly FamilyNamesKey[] = ['momCall', 'momNickname', 'kidCall', 'kidNickname'];

export const DEFAULT_FAMILY_NAMES: FamilyNames = {
  momCall: '妈妈',
  momNickname: '',
  kidCall: '女儿',
  kidNickname: '',
};

/** 一个称呼最多几个字（界面与接口同一口径） */
export const MAX_NAME_LENGTH = 12;

/** camelCase ↔ 数据库键名 */
const COLUMN_BY_KEY: Record<FamilyNamesKey, string> = {
  momCall: 'mom_call',
  momNickname: 'mom_nickname',
  kidCall: 'kid_call',
  kidNickname: 'kid_nickname',
};

/**
 * 界面上统一用它取名字：昵称优先，没填昵称才用称呼。
 * who='mom' 取「妈妈」那一套，who='kid' 取「女儿」那一套。
 */
export function displayName(names: FamilyNames, who: 'mom' | 'kid'): string {
  const fallback = who === 'mom' ? DEFAULT_FAMILY_NAMES.momCall : DEFAULT_FAMILY_NAMES.kidCall;
  const call = who === 'mom' ? names.momCall : names.kidCall;
  const nickname = who === 'mom' ? names.momNickname : names.kidNickname;
  return (nickname || call || fallback).trim() || fallback;
}

/** 清洗单个称呼：非字符串按默认值、去首尾空白、截断；称呼留空回退默认值，昵称留空就是空 */
export function sanitizeName(value: unknown, key: FamilyNamesKey): string {
  if (typeof value !== 'string') return DEFAULT_FAMILY_NAMES[key];
  const trimmed = value.trim().slice(0, MAX_NAME_LENGTH);
  if (trimmed) return trimmed;
  return key === 'momCall' || key === 'kidCall' ? DEFAULT_FAMILY_NAMES[key] : '';
}

/** 读取家庭称呼；表不存在或查询失败都回退默认值（不阻塞业务） */
export async function readFamilyNames(db: D1Database): Promise<FamilyNames> {
  const names: FamilyNames = { ...DEFAULT_FAMILY_NAMES };

  try {
    const result = await db
      .prepare(
        `SELECT key, value FROM settings
          WHERE key IN ('mom_call', 'mom_nickname', 'kid_call', 'kid_nickname')`
      )
      .all<{ key: string; value: string }>();

    for (const row of result.results ?? []) {
      const matched = FAMILY_NAME_KEYS.find((key) => COLUMN_BY_KEY[key] === row.key);
      if (matched) names[matched] = sanitizeName(row.value, matched);
    }
  } catch (error) {
    // 常见原因：库里还没跑 0004 迁移（老库）。页面用默认称呼即可。
    console.error('readFamilyNames failed', error);
  }

  return names;
}

/** 写入部分称呼并回读；表没迁移时会抛错，由接口转成 503 */
export async function writeFamilyNames(db: D1Database, patch: Partial<FamilyNames>): Promise<FamilyNames> {
  const updatedAt = new Date().toISOString();
  const statements = FAMILY_NAME_KEYS.filter((key) => patch[key] !== undefined).map((key) =>
    db
      .prepare(
        `INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`
      )
      .bind(COLUMN_BY_KEY[key], sanitizeName(patch[key], key), updatedAt)
  );

  if (statements.length > 0) await db.batch(statements);

  return readFamilyNames(db);
}

/* ===== 全局背景图 =====
   用户上传的背景图地址也寄存在 settings 表（键名 background）。
   放服务端的理由和称呼一样：换台手机要看到同一张背景图；
   顺带让闲置照片清理知道它「有人用着」，不会把背景图当垃圾删掉。 */

/** 背景图在 settings 表里的键名（值是图片 URL，空 = 没设） */
export const BACKGROUND_KEY = 'background';

/** 只接受站内上传的图片地址（防外链，也保证清理逻辑认得出） */
const IMAGE_URL_MARK = '/api/images/';

/** 背景图地址最长多少字符（URL 长度兜底） */
export const MAX_BACKGROUND_LENGTH = 400;

/** 清洗背景图地址：非字符串、太长、不是站内图片都算非法（返回 null）；空串合法（= 移除） */
export function sanitizeBackground(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (trimmed.length > MAX_BACKGROUND_LENGTH) return null;
  if (trimmed && !trimmed.includes(IMAGE_URL_MARK)) return null;
  return trimmed;
}

/** 读取全局背景图地址；表不存在或没设都返回空串 */
export async function readBackground(db: D1Database): Promise<string> {
  try {
    const row = await db
      .prepare('SELECT value FROM settings WHERE key = ?')
      .bind(BACKGROUND_KEY)
      .first<{ value: string }>();
    return sanitizeBackground(row?.value ?? '') ?? '';
  } catch (error) {
    // 常见原因：库里还没跑 0004 迁移（老库）。按「没设背景图」处理。
    console.error('readBackground failed', error);
    return '';
  }
}

/** 写入全局背景图（传空串 = 恢复纯色背景）；表没迁移时会抛错，由接口转成 503 */
export async function writeBackground(db: D1Database, url: string): Promise<string> {
  if (!url) {
    await db.prepare('DELETE FROM settings WHERE key = ?').bind(BACKGROUND_KEY).run();
    return '';
  }

  await db
    .prepare(
      `INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?)
       ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`
    )
    .bind(BACKGROUND_KEY, url, new Date().toISOString())
    .run();

  return readBackground(db);
}

/* ===== 管理员密码 =====
   「管理员」二级页的进门密码。存 D1 而不是本机 localStorage：家长换台手机、
   清一次浏览器缓存也进得去，两台设备看到的是同一个密码。
   默认值是出厂密码，家长进后台可以自己改。 */

/** 管理员密码在 settings 表里的键名 */
export const ADMIN_PASSWORD_KEY = 'admin_password';

/** 出厂管理员密码（第一次进后台用它，进去后建议改掉） */
export const DEFAULT_ADMIN_PASSWORD = '3398377037';

/** 密码长度范围：短到 4 位（自己改时好记），长到 32 位（出厂那串 10 位塞得下） */
export const MIN_ADMIN_PASSWORD_LENGTH = 4;
export const MAX_ADMIN_PASSWORD_LENGTH = 32;

/** 清洗管理员密码：非字符串、太短、太长都算非法（返回 null）；首尾空白去掉 */
export function sanitizeAdminPassword(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (
    trimmed.length < MIN_ADMIN_PASSWORD_LENGTH ||
    trimmed.length > MAX_ADMIN_PASSWORD_LENGTH
  ) {
    return null;
  }
  return trimmed;
}

/** 当前生效的管理员密码；没设过或表不可用都回退出厂密码 */
export async function readAdminPassword(db: D1Database): Promise<string> {
  try {
    const row = await db
      .prepare('SELECT value FROM settings WHERE key = ?')
      .bind(ADMIN_PASSWORD_KEY)
      .first<{ value: string }>();
    return sanitizeAdminPassword(row?.value) ?? DEFAULT_ADMIN_PASSWORD;
  } catch (error) {
    // 常见原因：库里还没跑 0004 迁移（老库）。回退出厂密码，别把人锁在门外。
    console.error('readAdminPassword failed', error);
    return DEFAULT_ADMIN_PASSWORD;
  }
}

/** 写入新密码；表没迁移时会抛错，由接口转成 503 */
export async function writeAdminPassword(db: D1Database, password: string): Promise<void> {
  await db
    .prepare(
      `INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?)
       ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`
    )
    .bind(ADMIN_PASSWORD_KEY, password, new Date().toISOString())
    .run();
}

/* ===== 管理员密码试错节流 =====
   「管理员」入口对全家开放（妈妈和女儿都能看见），密码就成了唯一的门。
   没有节流的话，在那张弹窗里可以无限次试 —— 默认密码是 10 位纯数字，
   知道手机号、生日这类习惯用法的孩子试几次就可能中。所以连续错
   ADMIN_MAX_ATTEMPTS 次就锁 ADMIN_LOCK_MS，成功一次立刻清零。
   状态同样寄存在 settings 表（不加表），键名见下面两个常量。 */

/** 连续失败次数在 settings 表里的键名 */
export const ADMIN_FAIL_COUNT_KEY = 'admin_fail_count';

/** 解锁时间（毫秒时间戳，空/0 = 没锁）在 settings 表里的键名 */
export const ADMIN_LOCK_UNTIL_KEY = 'admin_lock_until';

/** 连续错几次就锁 */
export const ADMIN_MAX_ATTEMPTS = 5;

/** 锁多久（毫秒） */
export const ADMIN_LOCK_MS = 5 * 60 * 1000;

export interface AdminLockState {
  /** 还要等多少毫秒才能再试；0 = 现在就能试 */
  lockRemainingMs: number;
  /** 本轮已经连续错了几次（锁定中会归 0） */
  failedAttempts: number;
}

/** 读取当前锁定状态；表不可用时当作没锁（不能因为库的问题把人锁在门外） */
export async function readAdminLock(db: D1Database): Promise<AdminLockState> {
  try {
    const result = await db
      .prepare('SELECT key, value FROM settings WHERE key IN (?, ?)')
      .bind(ADMIN_FAIL_COUNT_KEY, ADMIN_LOCK_UNTIL_KEY)
      .all<{ key: string; value: string }>();

    let failedAttempts = 0;
    let lockUntil = 0;
    for (const row of result.results ?? []) {
      const value = Number.parseInt(row.value ?? '', 10);
      if (!Number.isFinite(value)) continue;
      if (row.key === ADMIN_FAIL_COUNT_KEY) failedAttempts = Math.max(0, value);
      if (row.key === ADMIN_LOCK_UNTIL_KEY) lockUntil = Math.max(0, value);
    }

    return {
      lockRemainingMs: Math.max(0, lockUntil - Date.now()),
      failedAttempts,
    };
  } catch (error) {
    console.error('readAdminLock failed', error);
    return { lockRemainingMs: 0, failedAttempts: 0 };
  }
}

/** 记一次密码失败；错到次数就上锁，返回记完之后的状态（写失败不影响拒绝本次请求） */
export async function registerAdminFailure(db: D1Database): Promise<AdminLockState> {
  const current = await readAdminLock(db);
  const failedAttempts = current.failedAttempts + 1;
  const locked = failedAttempts >= ADMIN_MAX_ATTEMPTS;
  const lockUntil = locked ? Date.now() + ADMIN_LOCK_MS : 0;

  try {
    const updatedAt = new Date().toISOString();
    const upsert = `INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?)
       ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`;
    await db.batch([
      db.prepare(upsert).bind(ADMIN_FAIL_COUNT_KEY, String(locked ? 0 : failedAttempts), updatedAt),
      db.prepare(upsert).bind(ADMIN_LOCK_UNTIL_KEY, String(lockUntil), updatedAt),
    ]);
  } catch (error) {
    console.error('registerAdminFailure failed', error);
  }

  return {
    lockRemainingMs: locked ? ADMIN_LOCK_MS : 0,
    failedAttempts: locked ? 0 : failedAttempts,
  };
}

/** 密码输对了：把失败次数和锁定一起清掉 */
export async function clearAdminLock(db: D1Database): Promise<void> {
  try {
    await db
      .prepare('DELETE FROM settings WHERE key IN (?, ?)')
      .bind(ADMIN_FAIL_COUNT_KEY, ADMIN_LOCK_UNTIL_KEY)
      .run();
  } catch (error) {
    console.error('clearAdminLock failed', error);
  }
}
