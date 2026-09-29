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
