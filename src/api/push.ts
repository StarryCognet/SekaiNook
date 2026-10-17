/**
 * Web Push 订阅接口（前端封装）。
 *
 * 对应后端：functions/api/push/key.ts（公钥）、functions/api/push/subscribe.ts（登记/退订）、
 * functions/api/push/test.ts（测试通知）。
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

/** 测试通知实际发给了谁：不指定 audience 时后端回 all */
export type PushTestAudience = PushAudience | "all";

/**
 * 测试通知结果（200）。
 * 注意 200 不等于「发出去了」：sent 为 false 且 detail 说「还没有设备订阅推送」时，
 * 是「一台都没订阅」而不是故障，界面该提示用户先去打开开关。
 */
export interface PushTestResponse {
  ok: true;
  /** 至少送达一台设备才为 true */
  sent: boolean;
  /** 推送服务商信道（如 webpush），后端拿不到时为 null */
  channel: string | null;
  /** 给人看的结果说明：「已送达 1/1 台设备…」或「还没有设备订阅推送…」 */
  detail: string;
  audience: PushTestAudience;
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

/**
 * 发一条测试通知（用来确认通道通不通）。
 *
 * audience 不传 = 给所有已订阅设备发；传了就只发给这一种身份。
 * 后端明确要求字段缺省而不是 null（null 会被判成 400），所以这里不能写成 { audience }。
 *
 * 失败一律以 ApiError 抛出，后端 429 / 502 / 503 的 { error } 已被 http.ts 归一成 message
 * （冷却剩余秒数、detail 不在 ApiError 上透出，UI 直接用 message 即可）。
 * 后端对同一 audience 有 15 秒冷却，所以刻意不开 http 的自动重试。
 */
export function sendTestPush(
  audience?: PushAudience
): Promise<PushTestResponse> {
  return http.post<PushTestResponse>(
    "/api/push/test",
    audience === undefined ? {} : { audience }
  );
}
