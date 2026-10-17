/**
 * Web Push 订阅接口（前端封装）。
 *
 * 对应后端：functions/api/push/key.ts（公钥）与 functions/api/push/subscribe.ts（登记/退订）。
 * 请求一律走 src/api/http.ts，不裸写 fetch（项目铁律）。
 */

import { http } from "./http";

/** 订阅归属：这个 endpoint 是家长还是小孩的（worker 按它决定给谁发） */
export type PushAudience = "parent" | "child";

/**
 * VAPID 公钥。
 * ready: false 且 publicKey 为空串 = 服务端（Pages 环境变量）还没配密钥，
 * 属于「还没上架」而不是故障：UI 显示「服务端还没配推送密钥」并禁用开启按钮。
 */
export interface PushKeyResponse {
  publicKey: string;
  subject: string;
  ready: boolean;
}

/** 订阅请求体：endpoint + 两个推送密钥，后端用 endpoint 做唯一键 UPSERT */
export interface PushSubscribePayload {
  endpoint: string;
  keys: {
    p256dh: string;
    auth: string;
  };
  audience: PushAudience;
}

/** 登记成功 */
export interface PushSubscribeResponse {
  ok: boolean;
  endpoint: string;
}

/** 退订结果：removed 为 false 表示这台设备本来就没有订阅（也算成功） */
export interface PushUnsubscribeResponse {
  ok: boolean;
  removed: boolean;
}

/** 取 VAPID 公钥（订阅时当 applicationServerKey 用） */
export function fetchPushKey(): Promise<PushKeyResponse> {
  return http.get<PushKeyResponse>("/api/push/key");
}

/** 登记（或更新）一条订阅；已存在的 endpoint 会被后端更新 keys/audience，不会弄丢旧订阅 */
export function subscribePush(
  payload: PushSubscribePayload
): Promise<PushSubscribeResponse> {
  return http.post<PushSubscribeResponse>("/api/push/subscribe", payload);
}

/**
 * 退订一条订阅。
 *
 * 契约里 endpoint 走请求体，但 http.ts 的 delete 只接受 (path, options)、不支持 body
 * （项目铁律：业务代码禁止裸写 fetch），所以走后端同样支持的 ?endpoint= 兜底路径
 * —— functions/api/push/subscribe.ts 的 onRequestDelete 取不到请求体时就读查询参数。
 */
export function unsubscribePush(
  endpoint: string
): Promise<PushUnsubscribeResponse> {
  return http.delete<PushUnsubscribeResponse>(
    `/api/push/subscribe?endpoint=${encodeURIComponent(endpoint)}`
  );
}
