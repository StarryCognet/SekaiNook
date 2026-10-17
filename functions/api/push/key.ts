/**
 * Web Push 的 VAPID 公钥（前端订阅时当 applicationServerKey 用）。
 * 路由：GET /api/push/key —— 返回公钥与 subject；没配就 ready:false，不报错
 *
 * 为什么没配也不报错：密钥是运维在 Cloudflare Pages 环境变量里配的，没配属于「还没上架」，
 * 不是故障。前端拿到 ready:false 显示「服务端还没配推送密钥」，页面其余部分照常用；
 * 若这里返 500，前端会把整个设置页当异常处理，反而多出一堆无意义的报错。
 */

interface Env {
  /** VAPID 公钥（base64url）。Pages 环境变量，可能还没配 */
  VAPID_PUBLIC_KEY?: string;
  /** VAPID subject（mailto: 或站点 URL）。部分推送服务会校验，可能还没配 */
  VAPID_SUBJECT?: string;
}

/** 读取 VAPID 公钥（前端订阅时要用） */
export const onRequestGet: PagesFunction<Env> = async ({ env }) => {
  const publicKey = env.VAPID_PUBLIC_KEY?.trim() ?? '';
  const subject = env.VAPID_SUBJECT?.trim() ?? '';

  if (!publicKey) {
    return Response.json({ publicKey: '', subject: '', ready: false });
  }

  return Response.json({ publicKey, subject, ready: true });
};
