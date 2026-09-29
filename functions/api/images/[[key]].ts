/**
 * Cloudflare Pages Function：读取 R2 中的图片。
 * 需要在 Pages 项目 Settings → Bindings → R2 中绑定 bucket，绑定名 STARRYMIKU_BUCKET。
 * 路由：GET /api/images/:key
 */

interface Env {
  STARRYMIKU_BUCKET: R2Bucket;
}

export const onRequestGet: PagesFunction<Env> = async (context) => {
  const bucket = context.env.STARRYMIKU_BUCKET;
  const key = (context.params.key as string[]).join('/');

  const object = await bucket.get(key);
  if (!object) {
    return new Response('Not Found', { status: 404 });
  }

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set('etag', object.httpEtag);
  headers.set('Access-Control-Allow-Origin', '*');
  // 图片 key 由上传接口生成且不可变（tasks/<时间戳>-<随机>.<ext>），内容换不掉，
  // 因此可以放心长缓存：省回源与流量，也不会出现「改了图还看到旧图」。
  headers.set('Cache-Control', 'public, max-age=31536000, immutable');
  return new Response(object.body, { headers });
};
