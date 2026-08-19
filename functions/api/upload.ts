/**
 * Cloudflare Pages Function：图片上传到 R2。
 * 需要在 Pages 项目 Settings → Bindings → R2 中绑定 bucket，绑定名 SEKAINOOK_BUCKET。
 * 路由：POST /api/upload
 */

interface Env {
  SEKAINOOK_BUCKET: R2Bucket;
}

export const onRequestPost: PagesFunction<Env> = async (context) => {
  const bucket = context.env.SEKAINOOK_BUCKET;

  // CORS 预检
  if (context.request.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
      },
    });
  }

  const contentType = context.request.headers.get('Content-Type') || 'application/octet-stream';
  const body = await context.request.arrayBuffer();
  const key = `tasks/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.jpg`;
  await bucket.put(key, body, { httpMetadata: { contentType } });

  const url = new URL(context.request.url);
  const imageUrl = `${url.origin}/api/images/${key}`;

  return Response.json(
    { url: imageUrl, key },
    { headers: { 'Access-Control-Allow-Origin': '*' } }
  );
};
