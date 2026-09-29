/**
 * 家庭设置接口（跨设备同步的那一份）。
 * 路由：GET   /api/settings —— 读全部设置（表没迁移时回默认值，ready:false）
 *       PATCH /api/settings —— 改部分设置（称呼最多 12 个字；背景图只认站内图片）
 *
 * 为什么是 PATCH：两个人各管一半 —— 女儿改妈妈的称呼、妈妈改女儿的称呼，
 * 每次只提交自己改的那一两个字段，另一方的设置不会被覆盖。
 * 背景图同理：它和称呼共用这张表，但互不影响。
 */

import {
  DEFAULT_FAMILY_NAMES,
  FAMILY_NAME_KEYS,
  MAX_BACKGROUND_LENGTH,
  MAX_NAME_LENGTH,
  readBackground,
  readFamilyNames,
  sanitizeBackground,
  sanitizeName,
  writeBackground,
  writeFamilyNames,
  type FamilyNames,
} from '../../_lib/settings';

interface Env {
  DB: D1Database;
}

/** 读取家庭设置（称呼 + 背景图） */
export const onRequestGet: PagesFunction<Env> = async ({ env }) => {
  try {
    const [names, background] = await Promise.all([readFamilyNames(env.DB), readBackground(env.DB)]);
    return Response.json({ names, background, ready: true });
  } catch (error) {
    console.error('get settings failed', error);
    return Response.json({ names: DEFAULT_FAMILY_NAMES, background: '', ready: false });
  }
};

/** 修改家庭设置（部分字段） */
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
  let background: string | undefined;

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

  if ('background' in source) {
    const cleaned = sanitizeBackground(source.background);
    if (cleaned === null) {
      return Response.json({ error: `背景图地址不合法（只能是本站上传的图片，且不超过 ${MAX_BACKGROUND_LENGTH} 个字符）` }, { status: 400 });
    }
    background = cleaned;
  }

  if (Object.keys(patch).length === 0 && background === undefined) {
    return Response.json({ error: '没有要保存的设置' }, { status: 400 });
  }

  try {
    const names = Object.keys(patch).length > 0 ? await writeFamilyNames(env.DB, patch) : await readFamilyNames(env.DB);
    const savedBackground = background === undefined ? await readBackground(env.DB) : await writeBackground(env.DB, background);
    return Response.json({ names, background: savedBackground, ready: true });
  } catch (error) {
    // 常见原因：远端/本地库还没跑 0004 迁移
    console.error('save settings failed', error);
    return Response.json({ error: '设置表尚未就绪，请先执行数据库迁移' }, { status: 503 });
  }
};
