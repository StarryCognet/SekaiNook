/**
 * 孤儿图片维护接口。
 * 路由：GET /api/maintenance/orphans（只扫描不删除，dry run）
 *       POST /api/maintenance/orphans（真正删除孤儿对象，需 confirm: true）
 *
 * 「孤儿图片」= R2 中 tasks/ 前缀下存在、但没有任何 family_ledger.image_url 引用它的对象。
 * 上传接口（functions/api/upload.ts）把图片写入 tasks/ 前缀，故扫描只针对该前缀，其他前缀一律不碰。
 */

interface Env {
  DB: D1Database;
  STARRYMIKU_BUCKET: R2Bucket;
}

/** 图片对象前缀：与 functions/api/upload.ts 的上传 key 规则保持一致 */
const IMAGE_PREFIX = 'tasks/';

/** R2 list 单页拉取上限 */
const LIST_LIMIT = 500;

/** 响应中最多返回的 key 数量（数量统计仍为全量，避免响应过大） */
const MAX_KEYS = 200;

/** 从图片 URL（.../api/images/<key>）中还原 R2 对象 key，非法则返回 null */
function extractImageKey(imageUrl: string): string | null {
  const prefix = '/api/images/';
  try {
    const { pathname } = new URL(imageUrl);
    if (!pathname.startsWith(prefix)) return null;
    const key = pathname.slice(prefix.length);
    return key ? decodeURIComponent(key) : null;
  } catch {
    return null;
  }
}

/** 分页列举 R2 中 tasks/ 前缀下的全部对象 key（循环到 truncated === false） */
async function listImageKeys(bucket: R2Bucket): Promise<string[]> {
  const keys: string[] = [];
  let cursor: string | undefined;

  for (;;) {
    const listed = await bucket.list({ prefix: IMAGE_PREFIX, limit: LIST_LIMIT, cursor });
    for (const object of listed.objects) keys.push(object.key);

    if (!listed.truncated) break;
    // truncated 却无 cursor 视为已到末页，防死循环
    cursor = listed.cursor;
    if (!cursor) break;
  }

  return keys;
}

/** 查询 family_ledger.image_url 并归一化为被引用的 R2 key 集合 */
async function collectReferencedKeys(db: D1Database): Promise<Set<string>> {
  const { results } = await db
    .prepare('SELECT image_url FROM family_ledger WHERE image_url IS NOT NULL')
    .all<{ image_url: string | null }>();

  const referenced = new Set<string>();
  for (const row of results ?? []) {
    if (!row.image_url) continue;
    const key = extractImageKey(row.image_url);
    if (key) referenced.add(key);
  }
  return referenced;
}

/** 计算 tasks/ 前缀下的孤儿 key（存在对象、无任何引用） */
async function findOrphanKeys(env: Env): Promise<string[]> {
  const objectKeys = await listImageKeys(env.STARRYMIKU_BUCKET);
  const referenced = await collectReferencedKeys(env.DB);
  return objectKeys.filter((key) => !referenced.has(key));
}

/** 扫描孤儿图片（只读，绝不删除） */
export const onRequestGet: PagesFunction<Env> = async ({ env }) => {
  let objectKeys: string[];
  let referenced: Set<string>;
  try {
    objectKeys = await listImageKeys(env.STARRYMIKU_BUCKET);
    referenced = await collectReferencedKeys(env.DB);
  } catch {
    return Response.json({ error: '扫描孤儿图片失败（R2 列举或 D1 查询异常）' }, { status: 500 });
  }

  const orphanKeys = objectKeys.filter((key) => !referenced.has(key));
  return Response.json({
    total: objectKeys.length,
    referenced: objectKeys.length - orphanKeys.length,
    orphans: orphanKeys.length,
    keys: orphanKeys.slice(0, MAX_KEYS),
  });
};

/** 删除孤儿图片（危险操作，需请求体 { confirm: true }） */
export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  let body: Record<string, unknown>;
  try {
    body = await request.json<Record<string, unknown>>();
  } catch {
    return Response.json({ error: '请求体不是合法 JSON' }, { status: 400 });
  }

  if (body.confirm !== true) {
    return Response.json(
      { error: '危险操作：请在请求体中传入 {"confirm": true} 以确认删除孤儿图片' },
      { status: 400 }
    );
  }

  let orphanKeys: string[];
  try {
    orphanKeys = await findOrphanKeys(env);
  } catch {
    return Response.json({ error: '扫描孤儿图片失败（R2 列举或 D1 查询异常）' }, { status: 500 });
  }

  const deletedKeys: string[] = [];
  let failed = 0;
  for (const key of orphanKeys) {
    try {
      await env.STARRYMIKU_BUCKET.delete(key);
      deletedKeys.push(key);
    } catch {
      // 单个对象删除失败不影响整体，计入 failed
      failed += 1;
    }
  }

  return Response.json({
    deleted: deletedKeys.length,
    failed,
    keys: deletedKeys.slice(0, MAX_KEYS),
  });
};
