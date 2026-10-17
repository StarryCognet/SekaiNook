/**
 * Web Push 的浏览器侧实现：能不能用、现在是什么状态、开启与关闭。
 *
 * 注册 Service Worker 的活不在这里 —— 由 src/utils/swUpdate.ts 用 /sw.js?v=<构建标识>
 * 注册（每次发布换 URL，配合 sw.js 的缓存名）。这里只等 navigator.serviceWorker.ready，
 * 绝不重复注册。
 */

import {
  fetchPushKey,
  subscribePush,
  unsubscribePush,
  type PushAudience,
} from "../api/push";

/** 本机订阅状态：不支持 / 权限被拒 / 已订阅 / 没开 */
export type PushState = "unsupported" | "denied" | "subscribed" | "off";

/**
 * 这个浏览器到底能不能用通知。
 * 安卓 Chrome 与「已添加到主屏幕」的 iOS 16.4+ PWA 都返回 true；
 * 桌面 Safari、iOS 16.4 以下的普通标签页会有一项缺失。
 */
export function pushSupported(): boolean {
  if (typeof window === "undefined") return false;
  return (
    "serviceWorker" in navigator &&
    "PushManager" in window &&
    "Notification" in window
  );
}

/**
 * 是不是 iOS / iPadOS 设备。
 * 坑：iPad 上的 Safari 从 iPadOS 13 起默认「请求桌面网站」，UA 报的是 MacIntel，
 * 只能再用触摸点数（maxTouchPoints > 1）把它和真的 Mac 分开。
 */
function isIosDevice(): boolean {
  if (typeof navigator === "undefined") return false;
  if (/iPad|iPhone|iPod/.test(navigator.userAgent)) return true;
  return navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1;
}

/**
 * 是不是「已添加到主屏幕、从图标打开」的独立应用形态。
 * iOS 用私有字段 navigator.standalone；其他浏览器看 display-mode。
 */
function isStandalone(): boolean {
  if (typeof window === "undefined") return false;
  // navigator.standalone 是 iOS Safari 私有字段，标准 DOM 类型里没有，这里补一个可选字段
  const iosNavigator = navigator as Navigator & { standalone?: boolean };
  if (iosNavigator.standalone === true) return true;
  return window.matchMedia("(display-mode: standalone)").matches;
}

/**
 * iOS 上还没「添加到主屏幕」（或没从图标打开）时为 true。
 * 这种状态下 iOS 根本不给 PushManager，光提示「不支持通知」没用，得先教怎么装。
 */
export function isIosNeedsInstall(): boolean {
  return isIosDevice() && !isStandalone();
}

/**
 * 读当前状态。
 * 权限被拒时不必再问订阅（问了也来不了通知）；权限还没给就是「没开」；
 * 只有权限已授予时才继续看有没有真的订阅。
 */
export async function getPushState(): Promise<PushState> {
  if (!pushSupported()) return "unsupported";
  if (Notification.permission === "denied") return "denied";
  if (Notification.permission !== "granted") return "off";

  try {
    const registration = await getRegistration();
    if (!registration) return "off";
    const subscription = await registration.pushManager.getSubscription();
    return subscription ? "subscribed" : "off";
  } catch {
    // SW 还没就绪等异常：当作没开，用户点开启时会重新走一遍
    return "off";
  }
}

/** 等 SW 就绪的最长时间：首次打开时注册还在路上，但绝不能无限等下去 */
const SW_READY_TIMEOUT_MS = 3000;

/**
 * 取当前页面的 Service Worker 注册。
 *
 * 为什么不直接 await navigator.serviceWorker.ready：开发模式**刻意不注册 SW**
 * （src/main.tsx 里的 import.meta.env.PROD 判断），隐私模式下注册也会失败；
 * 这两种情况 ready 永远不会 resolve，设置页会一直停在「正在检查…」。
 * 所以先看有没有现成的注册，没有才给 ready 一个上限。
 */
async function getRegistration(): Promise<ServiceWorkerRegistration | null> {
  if (typeof navigator === "undefined" || !("serviceWorker" in navigator)) {
    return null;
  }

  const existing = await navigator.serviceWorker.getRegistration();
  if (existing) return existing;

  return await Promise.race([
    navigator.serviceWorker.ready,
    new Promise<null>((resolve) => {
      setTimeout(() => resolve(null), SW_READY_TIMEOUT_MS);
    }),
  ]);
}

/**
 * VAPID 公钥（base64url）→ Uint8Array（subscribe 的 applicationServerKey 要用）。
 * base64url 去掉了填充并由 +/ 变成 -_，这里全部还原回来。
 */
export function urlBase64ToUint8Array(base64url: string): Uint8Array {
  const padding = "=".repeat((4 - (base64url.length % 4)) % 4);
  const base64 = (base64url + padding).replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(base64);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i += 1) {
    bytes[i] = raw.charCodeAt(i);
  }
  return bytes;
}

/**
 * 开启提醒：取公钥 → 要权限 → 订阅 → 登记到服务端。
 *
 * 已存在订阅时先 unsubscribe 再重订阅：audience 是跟着订阅走的，
 * 换了身份（家长↔小孩）必须重新登记，否则提醒会发错人。
 */
export async function enablePush(audience: PushAudience): Promise<void> {
  if (!pushSupported()) {
    throw new Error("这个浏览器不支持通知");
  }

  const key = await fetchPushKey();
  if (!key.ready || !key.publicKey) {
    throw new Error("服务端还没配推送密钥");
  }

  // 老 iOS 的 requestPermission 走回调、可能返回 undefined，拿不到就回读当前权限
  const asked: NotificationPermission | undefined =
    await Notification.requestPermission();
  const permission = asked ?? Notification.permission;
  if (permission !== "granted") {
    throw new Error("通知权限被拒绝了，去浏览器设置里允许一下");
  }

  const registration = await getRegistration();
  if (!registration) {
    throw new Error("还没连上提醒服务，刷新一下页面再试");
  }

  const existing = await registration.pushManager.getSubscription();
  if (existing) {
    try {
      await existing.unsubscribe();
    } catch {
      // 退不掉不致命：新订阅会复用同一个 endpoint，服务端按 endpoint UPSERT 一样能改对 audience
    }
  }

  const subscription = await registration.pushManager.subscribe({
    userVisibleOnly: true,
    // 这里又套了一层 new Uint8Array(...)：TS 5.9 起 Uint8Array 带 buffer 类型参数
    // （urlBase64ToUint8Array 的返回类型是 Uint8Array<ArrayBufferLike>），
    // 而 applicationServerKey 要的是 ArrayBufferView<ArrayBuffer>。
    // 复制一份换个确切类型，比写 as 断言干净（就几十个字节）。
    applicationServerKey: new Uint8Array(urlBase64ToUint8Array(key.publicKey)),
  });

  const json = subscription.toJSON();
  const p256dh = json.keys?.p256dh;
  const auth = json.keys?.auth;
  if (!subscription.endpoint || !p256dh || !auth) {
    throw new Error("浏览器没给出完整的订阅信息，请重试");
  }

  try {
    await subscribePush({
      endpoint: subscription.endpoint,
      keys: { p256dh, auth },
      audience,
    });
  } catch (e) {
    // 登记失败就把刚建的订阅撤掉：否则本机显示「已订阅」、服务端却不知道，白等一场
    try {
      await subscription.unsubscribe();
    } catch {
      // 撤不掉也无所谓，下次开启会重新走一遍
    }
    throw e;
  }
}

/**
 * 关闭提醒：先删服务端登记，再退本地订阅。
 * 顺序不能反 —— 本地先退掉的话 endpoint 就再也拿不到，服务端那条记录只能靠发失败后自己清。
 */
export async function disablePush(): Promise<void> {
  if (!pushSupported()) return;

  const registration = await getRegistration();
  if (!registration) return;
  const subscription = await registration.pushManager.getSubscription();
  if (!subscription) return;

  await unsubscribePush(subscription.endpoint);
  await subscription.unsubscribe();
}
