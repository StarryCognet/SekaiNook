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
  return new Response(object.body, { headers });
};
