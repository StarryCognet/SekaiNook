/**
 * Cloudflare Pages Function：图片上传到 R2。
 * 需要在 wrangler.jsonc 的 r2_buckets 中绑定 bucket，绑定名 STARRYMIKU_BUCKET；
 * 需要 D1 绑定（DB）来记每日上传配额。
 * 路由：POST /api/upload
 *
 * 注意：这个接口**没有鉴权**（项目整体不加登录）。能挡的只有：
 *   - 只收 4 种图片类型 + 魔数校验（防伪装成图片的脚本）；
 *   - 单张 5MB 上限；
 *   - 每天全家合计的上传张数上限（防有人脚本刷桶把 R2 写满）。
 * 家里人在同一 WiFi 下用，真正的门是「别人不知道域名」；要更强的保护再加 Turnstile。
 */

interface Env {
  STARRYMIKU_BUCKET: R2Bucket;
  /** D1 绑定（记每日上传配额） */
  DB: D1Database;
}

/** 允许的图片类型 → 扩展名 */
const ALLOWED_TYPES: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/gif': 'gif',
};

/** 单张图片大小上限：5MB */
const MAX_SIZE = 5 * 1024 * 1024;

/** 每天全家合计最多传几张（家庭用量一天 20 张顶天；挡住的是脚本刷桶） */
const DAILY_UPLOAD_LIMIT = 200;

/** 占一张今日配额：原子自增并返回是否仍在额度内（写失败放行，不挡拍照上传） */
async function takeDailyQuota(db: D1Database, now: Date): Promise<boolean> {
  const dayKey = `upload_count_${now.toISOString().slice(0, 10)}`;
  try {
    const result = await db
      .prepare(
        `INSERT INTO settings (key, value, updated_at) VALUES (?, '1', ?)
          ON CONFLICT(key) DO UPDATE SET
            value = CAST(CAST(settings.value AS INTEGER) + 1 AS TEXT),
            updated_at = excluded.updated_at
          RETURNING value`
      )
      .bind(dayKey, now.toISOString())
      .first<{ value: string }>();
    const count = Number.parseInt(result?.value ?? '1', 10);
    return !Number.isFinite(count) || count <= DAILY_UPLOAD_LIMIT;
  } catch (error) {
    console.error('take upload quota failed', error);
    return true;
  }
}

/** 文件头是不是真的图片（Content-Type 是客户端自己填的，可以伪造） */
function looksLikeImage(bytes: Uint8Array, contentType: string): boolean {
  if (bytes.length < 12) return false;
  const is = (offset: number, signature: number[]): boolean =>
    signature.every((byte, i) => bytes[offset + i] === byte);

  switch (contentType) {
    case 'image/jpeg':
      return is(0, [0xff, 0xd8, 0xff]);
    case 'image/png':
      return is(0, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    case 'image/gif':
      return is(0, [0x47, 0x49, 0x46, 0x38]); // GIF8
    case 'image/webp':
      return (
        is(0, [0x52, 0x49, 0x46, 0x46]) && // RIFF
        is(8, [0x57, 0x45, 0x42, 0x50]) // WEBP
      );
    default:
      return false;
  }
}

export const onRequestPost: PagesFunction<Env> = async (context) => {
  const bucket = context.env.STARRYMIKU_BUCKET;

  const contentType = (context.request.headers.get('Content-Type') || '').split(';')[0].trim();
  const ext = ALLOWED_TYPES[contentType];
  if (!ext) {
    return Response.json({ error: '仅支持 jpg / png / webp / gif 图片' }, { status: 415 });
  }

  // 有 Content-Length 就先挡掉超大请求，别先把 5MB 传完再判长度
  const declaredLength = Number(context.request.headers.get('Content-Length') || '0');
  if (Number.isFinite(declaredLength) && declaredLength > MAX_SIZE) {
    return Response.json({ error: '图片不能超过 5MB' }, { status: 413 });
  }

  if (!(await takeDailyQuota(context.env.DB, new Date()))) {
    return Response.json({ error: '今天上传的照片太多了，明天再试' }, { status: 429 });
  }

  const body = await context.request.arrayBuffer();
  if (body.byteLength === 0) {
    return Response.json({ error: '文件为空' }, { status: 400 });
  }
  if (body.byteLength > MAX_SIZE) {
    return Response.json({ error: '图片不能超过 5MB' }, { status: 413 });
  }
  if (!looksLikeImage(new Uint8Array(body), contentType)) {
    return Response.json({ error: '文件内容不是有效的图片' }, { status: 415 });
  }

  const key = `tasks/${Date.now()}-${crypto.randomUUID().slice(0, 8)}.${ext}`;
  await bucket.put(key, body, { httpMetadata: { contentType } });

  const url = new URL(context.request.url);
  return Response.json({ url: `${url.origin}/api/images/${key}`, key }, { status: 201 });
};
