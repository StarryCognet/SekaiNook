/**
 * 后端 REST 客户端。
 *
 * 统一负责：JSON 序列化、错误归一化、弱网自动重试。
 * 所有业务接口都应通过这里访问 /api/*，不要直接 fetch。
 */

/** 接口请求失败（携带 HTTP 状态码；0 表示网络层失败，如断网/弱网） */
export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

/** 值得重试的状态码：服务端临时故障或限流 */
const RETRYABLE_STATUS: readonly number[] = [429, 500, 502, 503, 504];
/** 最多重试次数（不含首次请求）：手机在电梯/WiFi 抖动里很容易丢一两次 */
const MAX_RETRIES = 2;
/** 第 n 次重试前的等待毫秒数 */
const RETRY_DELAYS: readonly number[] = [400, 1200];

/** 等待指定毫秒 */
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * 是否允许自动重试。
 * 只重试幂等的 GET：POST /api/ledger 重试可能给小孩重复入账。
 */
function canRetry(init?: RequestInit): boolean {
  return (init?.method ?? 'GET').toUpperCase() === 'GET';
}

/** 发起请求并解析 JSON 响应（attempt 为已重试次数） */
async function request<T>(path: string, init?: RequestInit, attempt = 0): Promise<T> {
  const headers = new Headers(init?.headers);
  if (init?.body !== undefined) {
    headers.set('Content-Type', 'application/json');
  }

  let res: Response;
  try {
    res = await fetch(path, { ...init, headers });
  } catch {
    // 网络层就失败了（断网、DNS、连接被拒），fetch 不会给出状态码
    if (canRetry(init) && attempt < MAX_RETRIES) {
      await sleep(RETRY_DELAYS[attempt] ?? 1200);
      return request<T>(path, init, attempt + 1);
    }
    throw new ApiError('网络连接失败，请检查网络后重试', 0);
  }

  if (!res.ok) {
    if (canRetry(init) && attempt < MAX_RETRIES && RETRYABLE_STATUS.includes(res.status)) {
      await sleep(RETRY_DELAYS[attempt] ?? 1200);
      return request<T>(path, init, attempt + 1);
    }

    let message = `请求失败（${res.status}）`;
    try {
      const data = (await res.json()) as { error?: string };
      if (data?.error) message = data.error;
    } catch {
      // 响应体不是 JSON，保留默认提示
    }
    throw new ApiError(message, res.status);
  }

  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

export const http = {
  get: <T>(path: string) => request<T>(path),
  post: <T>(path: string, body?: unknown) =>
    request<T>(path, { method: 'POST', body: body === undefined ? undefined : JSON.stringify(body) }),
  patch: <T>(path: string, body?: unknown) =>
    request<T>(path, { method: 'PATCH', body: body === undefined ? undefined : JSON.stringify(body) }),
  delete: <T>(path: string) => request<T>(path, { method: 'DELETE' }),
};
