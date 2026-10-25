/**
 * Cloudflare Pages Function：读取 R2 中的图片。
 * 需要在 Pages 项目 Settings → Bindings → R2 中绑定 bucket，绑定名 STARRYMIKU_BUCKET。
 * 路由：GET /api/images/:key
 */

interface Env {
  STARRYMIKU_BUCKET: R2Bucket;
}

/** 上传接口只会往这个前缀写（见 functions/api/upload.ts） */
const IMAGE_KEY_PREFIX = 'tasks/';

/** key 长度上限：超长路径只会喂大日志，一律 404 */
const MAX_KEY_LENGTH = 200;

/**
 * 只把这些类型原样发给浏览器；其它一律 application/octet-stream + nosniff。
 * 否则一个上传了 HTML 的对象（魔数校验挡不住所有情况，旧数据也可能有）会被同源执行。
 */
const SAFE_IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/gif']);

export const onRequestGet: PagesFunction<Env> = async (context) => {
  const bucket = context.env.STARRYMIKU_BUCKET;
  const key = (context.params.key as string[]).join('/');

  // 只放行上传接口生成的那一段 key：否则整个 R2 桶都成了公开只读网关
  // （settings 里还能填任意站内图片地址，前缀不收窄等于把桶交出去）
  if (
    !key.startsWith(IMAGE_KEY_PREFIX) ||
    key.length > MAX_KEY_LENGTH ||
    key.includes('..') ||
    key.includes('//')
  ) {
    return new Response('Not Found', { status: 404 });
  }

  const object = await bucket.get(key);
  if (!object) {
    return new Response('Not Found', { status: 404 });
  }

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  const contentType = (object.httpMetadata?.contentType ?? '').toLowerCase();
  headers.set(
    'Content-Type',
    SAFE_IMAGE_TYPES.has(contentType) ? contentType : 'application/octet-stream'
  );
  headers.set('X-Content-Type-Options', 'nosniff');
  headers.set('etag', object.httpEtag);
  headers.set('Access-Control-Allow-Origin', '*');
  // 图片 key 由上传接口生成且不可变（tasks/<时间戳>-<随机>.<ext>），内容换不掉，
  // 因此可以放心长缓存：省回源与流量，也不会出现「改了图还看到旧图」。
  headers.set('Cache-Control', 'public, max-age=31536000, immutable');
  return new Response(object.body, { headers });
};
