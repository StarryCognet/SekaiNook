import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config/app_constants.dart';
import 'api_exception.dart';

/// 全站唯一的 HTTP 出口（对应 Web 版 `src/api/http.ts`）。
///
/// 行为逐条对齐 Web 版，务必不要「顺手优化」：
/// - 超时 12s，超时文案「请求超时，检查一下网络」
/// - 网络层失败文案「网络连接失败，请检查网络后重试」，status = 0
/// - **GET 默认重试 2 次**；写请求（POST/PATCH/DELETE）默认一次都不重试，
///   只有显式传 `retry: true` 才重试 1 次
/// - 可重试状态码 429 / 500 / 502 / 503 / 504
/// - 重试间隔 400ms、1200ms
/// - 失败响应先看 body 里的 `error` 字段当提示文案，没有才用「请求失败（状态码）」
/// - 204 返回 null
///
/// 为什么写请求要这么保守：记账接口不是幂等语义（虽然靠 id 去重，
/// 但客户端不该在用户没点重试时替他重发一次扣分）。
class ApiClient {
  ApiClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: AppConstants.apiBase,
                connectTimeout: AppConstants.requestTimeout,
                receiveTimeout: AppConstants.requestTimeout,
                sendTimeout: AppConstants.requestTimeout,
                responseType: ResponseType.json,
                headers: <String, dynamic>{
                  'Accept': 'application/json',
                  // 自建服务器（IP + HTTP）前面挂着 nginx Basic Auth，
                  // 安卓端没有浏览器那种弹框，只能在每个请求上带凭证。
                  if (AppConstants.basicAuth.isNotEmpty)
                    'Authorization':
                        'Basic ${base64Encode(utf8.encode(AppConstants.basicAuth))}',
                },
                // 状态码一律不抛，交给下面自己判，这样能统一读 body 里的 error
                validateStatus: (_) => true,
              ),
            );

  final Dio _dio;

  /// 全局共享实例：给那些不在 Provider 树里、只能自己 new 客户的 API 用。
  ///
  /// 以前页面里写 `UploadApi(ApiClient())`，每次换页/每次上传都新建一个 Dio
  /// 和一套连接池（ApiClient 没有 close，旧连接只能等 GC）。共享实例没有状态
  /// 需要隔离，合一个是安全的，也让「在途 GET 合并」覆盖到所有调用方。
  static final ApiClient shared = ApiClient();

  static const List<int> retryableStatus = <int>[429, 500, 502, 503, 504];
  static const List<Duration> retryDelays = <Duration>[
    Duration(milliseconds: 400),
    Duration(milliseconds: 1200),
  ];

  /// GET 默认重试次数
  static const int maxRetriesGet = 2;

  /// 写请求在显式要求重试时的重试次数
  static const int maxRetriesWrite = 1;

  static const String _timeoutMessage = '请求超时，检查一下网络';
  static const String _networkMessage = '网络连接失败，请检查网络后重试';

  /// 在途 GET 合并表：key = path + 排序后的 query。
  ///
  /// 同一个 URL 在上一轮还没回来时又发一次（多路轮询撞在一起，或弱网下
  /// 12s 超时 + 重试把一轮拖过 10s 间隔），这里只保留一个在途请求，
  /// 所有调用方共享同一份结果 —— 既省流量，也让「在途请求数」有上界。
  /// **只合并 GET**：写请求不幂等，绝不能替调用方合并。
  final Map<String, Future<dynamic>> _inflightGet = <String, Future<dynamic>>{};

  /// GET 并解码 JSON。默认重试 2 次；同一 URL 在途时复用同一个请求。
  ///
  /// 用法：`final json = await api.getJson<Map<String, dynamic>>('/api/ledger/summary');`
  Future<T?> getJson<T>(String path, {Map<String, dynamic>? query}) {
    final key = _getKey(path, query);
    final existing = _inflightGet[key];
    if (existing != null) {
      return existing.then((raw) => _cast<T>(raw, path));
    }
    final pending = _send(
      path,
      method: 'GET',
      query: query,
      retries: maxRetriesGet,
    );
    _inflightGet[key] = pending;
    return pending.then((raw) => _cast<T>(raw, path)).whenComplete(() {
      if (identical(_inflightGet[key], pending)) _inflightGet.remove(key);
    });
  }

  /// 把 path 与 query 拼成稳定的 key（参数顺序不同也命中同一个在途请求）
  static String _getKey(String path, Map<String, dynamic>? query) {
    if (query == null || query.isEmpty) return path;
    final keys = query.keys.toList()..sort();
    return '$path?${keys.map((k) => '$k=${query[k]}').join('&')}';
  }

  /// POST 并解码 JSON。默认**不**重试。
  ///
  /// [headers] 用于需要额外鉴权信息的写请求（如管理员口令 `x-admin-password`）。
  Future<T?> postJson<T>(
    String path, {
    Object? data,
    bool retry = false,
    Map<String, dynamic>? headers,
  }) async {
    final raw = await _send(
      path,
      method: 'POST',
      data: data,
      headers: headers,
      retries: retry ? maxRetriesWrite : 0,
    );
    return _cast<T>(raw, path);
  }

  /// PATCH 并解码 JSON。默认**不**重试。
  Future<T?> patchJson<T>(
    String path, {
    Object? data,
    bool retry = false,
    Map<String, dynamic>? headers,
  }) async {
    final raw = await _send(
      path,
      method: 'PATCH',
      data: data,
      headers: headers,
      retries: retry ? maxRetriesWrite : 0,
    );
    return _cast<T>(raw, path);
  }

  /// DELETE 并解码 JSON。默认**不**重试。
  ///
  /// DELETE 没有 body，鉴权信息只能走 [headers]（如 `x-admin-password`）。
  Future<T?> deleteJson<T>(
    String path, {
    bool retry = false,
    Map<String, dynamic>? headers,
  }) async {
    final raw = await _send(
      path,
      method: 'DELETE',
      headers: headers,
      retries: retry ? maxRetriesWrite : 0,
    );
    return _cast<T>(raw, path);
  }

  /// 以**原始二进制** body 上传（不是 multipart）。
  ///
  /// 上传接口（`POST /api/upload`）读的是 `request.arrayBuffer()`，
  /// Content-Type 直接来自请求头，所以这里必须发裸字节 + 显式 MIME。
  /// 上传是写操作，默认不重试 —— 图片大、重传代价高，且用户能看到进度，
  /// 失败时让他手动再点一次比偷偷重传更可控。
  Future<T?> postBytes<T>(
    String path, {
    required List<int> bytes,
    required String contentType,
  }) async {
    final raw = await _send(
      path,
      method: 'POST',
      // 调用方通常传的就是 Uint8List（见 upload_api.dart），别再整份复制一遍
      data: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      headers: <String, dynamic>{'Content-Type': contentType},
      retries: 0,
    );
    return _cast<T>(raw, path);
  }

  /// 给 Json 结果做一次窄化转换；结果为空（204）时返回 null。
  T? _cast<T>(dynamic raw, String path) {
    if (raw == null) return null;
    if (raw is T) return raw;
    throw ApiException('接口 $path 返回的格式不对', 0);
  }

  Future<dynamic> _send(
    String path, {
    required String method,
    Map<String, dynamic>? query,
    Object? data,
    Map<String, dynamic>? headers,
    required int retries,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        final res = await _dio.request<dynamic>(
          path,
          data: data,
          queryParameters: query,
          options: Options(
            method: method,
            headers: headers,
            validateStatus: (_) => true,
          ),
        );

        final status = res.statusCode ?? 0;

        if (status >= 200 && status < 300) {
          if (status == 204) return null;
          return res.data;
        }

        if (attempt < retries && retryableStatus.contains(status)) {
          await Future<void>.delayed(_delayFor(attempt));
          attempt++;
          continue;
        }

        throw ApiException(
          _errorMessage(res.data, status),
          status,
          body: res.data is Map
              ? (res.data as Map).map((key, value) => MapEntry(key.toString(), value))
              : null,
        );
      } on ApiException {
        rethrow;
      } on DioException catch (e) {
        final isTimeout = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout;
        // 只对「可能是一过性」的失败重试（M-6）：超时、连接失败。
        // 取消、证书错误重试也没用，只会让人白等 36 秒。
        final isConnection = e.type == DioExceptionType.connectionError;
        if ((isTimeout || isConnection) && attempt < retries) {
          await Future<void>.delayed(_delayFor(attempt));
          attempt++;
          continue;
        }

        throw ApiException(isTimeout ? _timeoutMessage : _networkMessage, 0);
      } catch (error) {
        // 非 Dio 的异常是代码 bug（M-5），别再伪装成「网络连接失败」——
        // 那样真实错误会被当成网络抖动，永远修不掉。
        throw ApiException('$error', 0);
      }
    }
  }

  Duration _delayFor(int attempt) =>
      attempt < retryDelays.length ? retryDelays[attempt] : retryDelays.last;

  /// 拿 body 里的 `error` 当提示文案；没有就用兜底文案（文案与 Web 版一字不差）
  String _errorMessage(dynamic body, int status) {
    if (body is Map) {
      final error = body['error'];
      if (error is String && error.trim().isNotEmpty) return error;
    }
    return '请求失败（$status）';
  }
}
