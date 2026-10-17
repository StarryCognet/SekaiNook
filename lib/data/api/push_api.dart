import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../models/notification_record.dart';

/// 「手机提醒」的接口层（`POST /api/push/test`）。
///
/// 契约见 `docs/api-contract.md` §21（提醒 Worker 的完整说明在 Web 仓库
/// `workers/reminder/README.md`）。这一层只做两件事：
/// - 把一条测试通知发出去，把 200 的响应收成 [PushTestResult]；
/// - 把失败响应翻成一句能直接给用户看的中文（[pushTestErrorMessage]）。
///
/// 失败**不在这里吞**：`ApiClient` 的非 2xx 一律抛 [ApiException]，429 的
/// `remainingSeconds`、400 / 502 / 503 的 `error` + `detail` 都在 `error.body` 里，
/// 所以这里既不重写一份请求逻辑，也不去改 `ApiClient`。
class PushApi {
  PushApi({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  /// 测试通知接口
  static const String testPath = '/api/push/test';

  /// 发一条测试通知。
  ///
  /// [audience] 传 null 表示「给所有已订阅设备发」—— 这时**不带这个字段**
  /// （契约里没有 `all` 这个取值，缺省才是全部）。
  Future<PushTestResult> sendTest({NotifyAudience? audience}) async {
    final raw = await _api.postJson<Map<String, dynamic>>(
      testPath,
      data: <String, dynamic>{
        if (audience != null) 'audience': audience.wire,
      },
    );
    if (raw == null) throw const ApiException('测试通知没有返回内容', 0);
    return PushTestResult.fromJson(raw);
  }
}

/// 一条测试通知的结果（`POST /api/push/test` 的 200 响应）。
class PushTestResult {
  const PushTestResult({
    required this.sent,
    required this.channel,
    required this.detail,
    required this.audience,
  });

  /// 至少送达一台设备
  final bool sent;

  /// 服务端实际用的提醒通道（没配 / 没渠道时是 null）
  final String? channel;

  /// 这一趟的明细，形如「已送达 1/1 台设备，清理失效订阅 0 条，失败 0 条：…」，
  /// 或者「还没有设备订阅推送：在设置页打开「手机提醒」」。
  /// **直接拿它当提示正文**：本地再润色一遍只会丢信息。
  final String detail;

  /// 服务端回显的收件范围：`parent` / `child` / `all`
  final String audience;

  factory PushTestResult.fromJson(Map<String, dynamic> json) => PushTestResult(
        sent: json['sent'] == true,
        channel: json['channel']?.toString(),
        detail: (json['detail'] as String?) ?? '',
        audience: json['audience']?.toString() ?? 'all',
      );
}

/// 把 [ApiException] 翻成给用户看的一句话。
///
/// 契约里三种失败形状（`ApiClient` 已经把 body 里的 `error` 塞进
/// [ApiException.message]，所以这里只补它没带上的信息）：
/// - 429 `{ok:false, cooldown:true, remainingSeconds:N, error:'刚发过，N 秒后再试'}`
///   —— 用 `remainingSeconds` 自己拼，冷却秒数以它为准；
/// - 400 `{error:'audience 非法（应为 parent 或 child）'}`
/// - 502 / 503 `{error:…, detail?:…}` —— 有 `detail` 就拼在后面，
///   用户报错时能一眼看出是提醒服务没回应、还是 Worker 地址 / 令牌没配。
String pushTestErrorMessage(ApiException error) {
  final Map<String, dynamic>? body = error.body;
  final int? remainingSeconds = (body?['remainingSeconds'] as num?)?.ceil();
  if (remainingSeconds != null) return '刚发过，$remainingSeconds 秒后再试';

  final String detail = (body?['detail'] as String?)?.trim() ?? '';
  if (detail.isEmpty) return error.message;
  return '${error.message}（$detail）';
}
