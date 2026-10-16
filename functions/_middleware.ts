/**
 * 全局中间件：**只做 CORS，不碰业务逻辑**。
 *
 * 为什么需要：Flutter Web 版（独立仓库 SekaiNook-App）与 Web 版不是同一个 origin，
 * 浏览器会拦跨域请求 —— 而 functions/ 下此前只有 /api/images/[[key]].ts 设了 CORS 头。
 * 本文件只追加响应头、应答 OPTIONS 预检，**不读数据库、不写数据库、不做任何鉴权、
 * 不改任何状态码与响应体**（仓库铁律「不引入鉴权中间件」针对的是鉴权，这里刻意不做鉴权）。
 *
 * 生效范围由 public/_routes.json 的 include:["/api/*"] 决定，只覆盖 /api/* 路由。
 */

const CORS_HEADERS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PATCH, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Max-Age': '86400',
};

export const onRequest: PagesFunction = async (context) => {
  // 预检：直接应答，不进业务路由
  if (context.request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  const response = await context.next();
  const headers = new Headers(response.headers);
  for (const [key, value] of Object.entries(CORS_HEADERS)) {
    headers.set(key, value);
  }

  // 204 / 205 / 304 不允许带 body，必须单独构造
  const status = response.status;
  const statusText = response.statusText;
  if (status === 204 || status === 205 || status === 304) {
    return new Response(null, { status, statusText, headers });
  }
  return new Response(response.body, { status, statusText, headers });
};
