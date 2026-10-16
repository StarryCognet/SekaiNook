/// 接口层异常（对应 Web 版 `src/api/http.ts` 的 `ApiError`）。
///
/// [status] == 0 表示连请求都没发出去（网络不通 / 超时），不是 HTTP 状态码。
class ApiException implements Exception {
  const ApiException(this.message, this.status, {this.body});

  /// 给用户看的中文文案
  final String message;

  /// HTTP 状态码；0 = 网络层失败
  final int status;

  /// 服务端返回的原始 JSON body（可能为 null）。
  ///
  /// 管理员接口要靠它读 `lockRemainingMs` / `attemptsLeft` 这类附加字段 ——
  /// 只看 message 没法知道还剩几次机会、还要锁多久。
  final Map<String, dynamic>? body;

  /// 写请求收到 4xx（429 除外）时，重试没有意义 —— 调用方应把这条记录
  /// 从待重试队列里出队并回滚乐观更新。
  ///
  /// status 0 与 5xx / 429 属于「暂时不通」，记录要留在队列里等下次。
  bool get isRejectedWrite => status >= 400 && status < 500 && status != 429;

  @override
  String toString() => 'ApiException($status): $message';
}
