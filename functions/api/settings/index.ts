/**
 * 家庭称呼设置接口。
 * 路由：GET   /api/settings —— 读当前称呼（表没迁移时回默认值，ready:false）
 *       PATCH /api/settings —— 改部分称呼（只认四个已知字段，最多 12 个字）
 *
 * 为什么是 PATCH：两个人各管一半 —— 女儿改妈妈的称呼、妈妈改女儿的称呼，
 * 每次只提交自己改的那一两个字段，另一方的设置不会被覆盖。
 */

import {
  DEFAULT_FAMILY_NAMES,
  FAMILY_NAME_KEYS,
  MAX_NAME_LENGTH,
  readFamilyNames,
  sanitizeName,
  writeFamilyNames,
  type FamilyNames,
} from '../../_lib/settings';

interface Env {
  DB: D1Database;
}

/** 读取家庭称呼 */
export const onRequestGet: PagesFunction<Env> = async ({ env }) => {
  try {
    const names = await readFamilyNames(env.DB);
    return Response.json({ names, ready: true });
  } catch (error) {
    console.error('get settings failed', error);
    return Response.json({ names: DEFAULT_FAMILY_NAMES, ready: false });
  }
};

/** 修改家庭称呼（部分字段） */
export const onRequestPatch: PagesFunction<Env> = async ({ request, env }) => {
  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return Response.json({ error: '请求体不是合法 JSON' }, { status: 400 });
  }

  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    return Response.json({ error: '请求体必须是对象' }, { status: 400 });
  }

  const source = payload as Record<string, unknown>;
  const patch: Partial<FamilyNames> = {};

  for (const key of FAMILY_NAME_KEYS) {
    if (!(key in source)) continue;
    const value = source[key];

    if (typeof value !== 'string') {
      return Response.json({ error: '称呼必须是文字' }, { status: 400 });
    }
    if (value.trim().length > MAX_NAME_LENGTH) {
      return Response.json({ error: `称呼最多 ${MAX_NAME_LENGTH} 个字` }, { status: 400 });
    }

    patch[key] = sanitizeName(value, key);
  }

  if (Object.keys(patch).length === 0) {
    return Response.json({ error: '没有要保存的称呼' }, { status: 400 });
  }

  try {
    const names = await writeFamilyNames(env.DB, patch);
    return Response.json({ names, ready: true });
  } catch (error) {
    // 常见原因：远端/本地库还没跑 0004 迁移
    console.error('save settings failed', error);
    return Response.json({ error: '称呼表尚未就绪，请先执行数据库迁移' }, { status: 503 });
  }
};
