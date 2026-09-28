/**
 * Cloudflare Pages Function：图片上传到 R2。
 * 需要在 wrangler.jsonc 的 r2_buckets 中绑定 bucket，绑定名 STARRYMIKU_BUCKET。
 * 路由：POST /api/upload（受 /api/_middleware.ts 鉴权保护）
 */

interface Env {
  STARRYMIKU_BUCKET: R2Bucket;
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

export const onRequestPost: PagesFunction<Env> = async (context) => {
  const bucket = context.env.STARRYMIKU_BUCKET;

  const contentType = (context.request.headers.get('Content-Type') || '').split(';')[0].trim();
  const ext = ALLOWED_TYPES[contentType];
  if (!ext) {
    return Response.json({ error: '仅支持 jpg / png / webp / gif 图片' }, { status: 415 });
  }

  const body = await context.request.arrayBuffer();
  if (body.byteLength === 0) {
    return Response.json({ error: '文件为空' }, { status: 400 });
  }
  if (body.byteLength > MAX_SIZE) {
    return Response.json({ error: '图片不能超过 5MB' }, { status: 413 });
  }

  const key = `tasks/${Date.now()}-${crypto.randomUUID().slice(0, 8)}.${ext}`;
  await bucket.put(key, body, { httpMetadata: { contentType } });

  const url = new URL(context.request.url);
  return Response.json({ url: `${url.origin}/api/images/${key}`, key }, { status: 201 });
};
