/**
 * 闲置照片维护接口（界面上叫「闲置照片」，代码里沿用 orphan = 未被引用）。
 * 路由：GET /api/maintenance/orphans（只扫描不删除，dry run）
 *       POST /api/maintenance/orphans（真正删除无人引用的对象，需 confirm: true）
 *
 * 「闲置照片」= R2 中 tasks/ 前缀下存在、但没有任何 family_ledger.image_url 引用它的对象
 * （打卡记录被删除后，照片仍留在云端的那种）。
 * 设置页设的全局背景图同样算「被引用」——它寄存在 settings 表里，不能被当垃圾清掉。
 * 上传接口（functions/api/upload.ts）把图片写入 tasks/ 前缀，故扫描只针对该前缀，其他前缀一律不碰。
 *
 * 另有一条保护：上传成功到「打卡记录写入 image_url」之间存在时间差（弱网下可能很长），
 * 这段窗口里的新图看起来无人引用、其实在途。因此只清理写入时间早于 6 小时前的对象。
 */

import { readBackground } from '../../_lib/settings';

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

/** 新图保护期：6 小时内的对象一律不清理（上传与落库之间的时间差） */
const ORPHAN_GRACE_MS = 6 * 60 * 60 * 1000;

/**
 * key 内嵌时间戳的兜底解析规则。
 * 依据：functions/api/upload.ts:39 生成的 key 是
 * `tasks/${Date.now()}-${crypto.randomUUID().slice(0, 8)}.${ext}`，
 * 即前缀就是毫秒级时间戳。只有稳定匹配到 10~16 位数字前缀时才采信，
 * 匹配不上就返回 null（宁可不删）。
 */
const KEY_TIMESTAMP_RE = /^(\d{10,16})-/;

/** 参与清理判定的对象：key + 写入时间 */
interface ImageObject {
  key: string;
  /** 写入时间（毫秒）；null = 两个来源都拿不到，保守按「不清理」处理 */
  uploadedAt: number | null;
}

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

/** 组合 R2 列表自带的 uploaded 与 key 内嵌时间戳，得到对象的写入时间 */
function resolveUploadedAt(key: string, uploaded: Date | undefined): number | null {
  // 优先用 R2 记录的 uploaded：它是存储侧的事实，比 key 命名约定可靠
  if (uploaded instanceof Date) {
    const time = uploaded.getTime();
    if (Number.isFinite(time)) return time;
  }

  // 兜底：从 key 前缀解析（规则与依据见 KEY_TIMESTAMP_RE 注释）
  const relative = key.startsWith(IMAGE_PREFIX) ? key.slice(IMAGE_PREFIX.length) : key;
  const match = KEY_TIMESTAMP_RE.exec(relative);
  if (!match) return null;
  const time = Number(match[1]);
  return Number.isFinite(time) ? time : null;
}

/**
 * 是否已过早于保护期（= 可以清理）。
 * 拿不到写入时间、或时间落在未来（时钟异常）时一律返回 false——保守不删。
 */
function isPastGrace(object: ImageObject, now: number): boolean {
  if (object.uploadedAt === null) return false;
  if (object.uploadedAt > now) return false;
  return now - object.uploadedAt >= ORPHAN_GRACE_MS;
}

/** 分页列举 R2 中 tasks/ 前缀下的全部对象（含写入时间），循环到 truncated === false */
async function listImageObjects(bucket: R2Bucket): Promise<ImageObject[]> {
  const objects: ImageObject[] = [];
  let cursor: string | undefined;

  for (;;) {
    const listed = await bucket.list({ prefix: IMAGE_PREFIX, limit: LIST_LIMIT, cursor });
    for (const object of listed.objects) {
      objects.push({ key: object.key, uploadedAt: resolveUploadedAt(object.key, object.uploaded) });
    }

    if (!listed.truncated) break;
    // truncated 却无 cursor 视为已到末页，防死循环
    cursor = listed.cursor;
    if (!cursor) break;
  }

  return objects;
}

/** 查询 family_ledger.image_url 与设置里的全局背景图，归一化为被引用的 R2 key 集合 */
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

  // 设置页上传的全局背景图也是「有人在用」的图
  const backgroundKey = extractImageKey(await readBackground(db));
  if (backgroundKey) referenced.add(backgroundKey);

  return referenced;
}

/** 扫描结果：总数 / 不可清理数 / 可清理的闲置 key */
interface OrphanScan {
  total: number;
  referenced: number;
  orphanKeys: string[];
}

/**
 * 计算 tasks/ 前缀下「可以清理」的闲置 key：
 * 存在对象、无任何引用、且写入时间已早于 6 小时保护期。
 * referenced 取 total - 可清理数，即「不可清理」（含保护期内的新图），
 * 这样界面上「共 N 张 / M 张还在用 / K 张闲置」三个数字仍然对得上。
 */
async function scanOrphans(env: Env, now: number): Promise<OrphanScan> {
  const objects = await listImageObjects(env.STARRYMIKU_BUCKET);
  const referenced = await collectReferencedKeys(env.DB);
  const orphanKeys = objects
    .filter((object) => !referenced.has(object.key) && isPastGrace(object, now))
    .map((object) => object.key);

  return {
    total: objects.length,
    referenced: objects.length - orphanKeys.length,
    orphanKeys,
  };
}

/** 扫描闲置照片（只读，绝不删除；报出的数量就是点「清理」真会删掉的数量） */
export const onRequestGet: PagesFunction<Env> = async ({ env }) => {
  let scan: OrphanScan;
  try {
    scan = await scanOrphans(env, Date.now());
  } catch {
    return Response.json({ error: '扫描闲置照片失败（存储列举或数据库查询异常）' }, { status: 500 });
  }

  return Response.json({
    total: scan.total,
    referenced: scan.referenced,
    orphans: scan.orphanKeys.length,
    keys: scan.orphanKeys.slice(0, MAX_KEYS),
  });
};

/** 删除闲置照片（危险操作，需请求体 { confirm: true }） */
export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  let body: Record<string, unknown>;
  try {
    body = await request.json<Record<string, unknown>>();
  } catch {
    return Response.json({ error: '请求体不是合法 JSON' }, { status: 400 });
  }

  if (body.confirm !== true) {
    return Response.json(
      { error: '危险操作：请在请求体中传入 {"confirm": true} 以确认清理闲置照片' },
      { status: 400 }
    );
  }

  let orphanKeys: string[];
  try {
    orphanKeys = (await scanOrphans(env, Date.now())).orphanKeys;
  } catch {
    return Response.json({ error: '扫描闲置照片失败（存储列举或数据库查询异常）' }, { status: 500 });
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
