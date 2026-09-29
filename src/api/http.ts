/**
 * 后端 REST 客户端。
 *
 * 统一负责：JSON 序列化、错误归一化、超时、弱网自动重试。
 * 所有业务接口都应通过这里访问 /api/*，不要直接 fetch。
 */

/** 接口请求失败（携带 HTTP 状态码；0 表示网络层失败，如断网/超时） */
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
/** GET 最多重试次数（不含首次请求）：手机在电梯/WiFi 抖动里很容易丢一两次 */
const MAX_RETRIES = 2;
/** 显式要求重试的写请求最多重试 1 次：重试可能造成重复写入，不适合多试 */
const MAX_RETRIES_WRITE = 1;
/** 第 n 次重试前的等待毫秒数 */
const RETRY_DELAYS: readonly number[] = [400, 1200];
/** 默认超时：12 秒没有响应就判定超时（弱网下比无限等待体验好得多） */
const DEFAULT_TIMEOUT_MS = 12000;

/** 单次请求的可选参数 */
export interface RequestOptions {
  /**
   * 写请求（POST/PATCH/DELETE）是否允许自动重试，默认关闭。
   * 只有调用方能保证幂等（例如带客户端唯一键 client_request_id）时才传 true。
   */
  retry?: boolean;
  /** 超时毫秒数，默认 DEFAULT_TIMEOUT_MS */
  timeoutMs?: number;
}

/** 等待指定毫秒 */
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * 本次调用最多允许重试几次（不含首次请求）。
 * GET 天然幂等，默认重试；写请求只有调用方显式 retry: true 才重试一次。
 */
function retryLimit(init: RequestInit | undefined, options: RequestOptions): number {
  if ((init?.method ?? 'GET').toUpperCase() === 'GET') return MAX_RETRIES;
  return options.retry === true ? MAX_RETRIES_WRITE : 0;
}

/** 发起请求并解析 JSON 响应（attempt 为已重试次数） */
async function request<T>(
  path: string,
  init?: RequestInit,
  options: RequestOptions = {},
  attempt = 0
): Promise<T> {
  const headers = new Headers(init?.headers);
  if (init?.body !== undefined) {
    headers.set('Content-Type', 'application/json');
  }

  // 超时用 AbortController 实现；signal 由本函数接管，调用方不要再传自己的 signal
  const controller = new AbortController();
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  let res: Response;
  try {
    res = await fetch(path, { ...init, headers, signal: controller.signal });
  } catch {
    // 网络层就失败了（断网、DNS、连接被拒、超时被 abort），fetch 不会给出状态码
    if (attempt < retryLimit(init, options)) {
      await sleep(RETRY_DELAYS[attempt] ?? 1200);
      return request<T>(path, init, options, attempt + 1);
    }
    throw new ApiError(
      controller.signal.aborted ? '请求超时，检查一下网络' : '网络连接失败，请检查网络后重试',
      0
    );
  } finally {
    clearTimeout(timer);
  }

  if (!res.ok) {
    if (attempt < retryLimit(init, options) && RETRYABLE_STATUS.includes(res.status)) {
      await sleep(RETRY_DELAYS[attempt] ?? 1200);
      return request<T>(path, init, options, attempt + 1);
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
  get: <T>(path: string, options?: RequestOptions) => request<T>(path, undefined, options),
  post: <T>(path: string, body?: unknown, options?: RequestOptions) =>
    request<T>(
      path,
      { method: 'POST', body: body === undefined ? undefined : JSON.stringify(body) },
      options
    ),
  patch: <T>(path: string, body?: unknown, options?: RequestOptions) =>
    request<T>(
      path,
      { method: 'PATCH', body: body === undefined ? undefined : JSON.stringify(body) },
      options
    ),
  delete: <T>(path: string, options?: RequestOptions) =>
    request<T>(path, { method: 'DELETE' }, options),
};
