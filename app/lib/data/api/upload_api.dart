import '../../core/api_client.dart';

/// 上传结果（对应 Web 版 `src/api/upload.ts`）
class UploadResult {
  const UploadResult({required this.url, required this.key});

  /// 完整可访问 URL（origin 由服务端按本次请求拼，**不要自己拼**）
  final String url;

  /// R2 key，形如 `tasks/1755661234567-1a2b3c4d.jpg`
  final String key;
}

/// 图片上传（对应 Web 版 `src/api/upload.ts`）。
///
/// 注意：请求体是**原始二进制**，`Content-Type` 必须是白名单里的精确 MIME
/// （`image/jpeg` / `image/png` / `image/webp` / `image/gif`，
/// **`image/jpg` 不在白名单**）。压缩后统一走 JPEG。
class UploadApi {
  UploadApi(this._api);

  final ApiClient _api;

  static const String path = '/api/upload';

  /// 服务端上限 5MB，超了返回 413
  static const int maxBytes = 5 * 1024 * 1024;

  static const List<String> allowedTypes = <String>[
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
  ];

  Future<UploadResult> upload(List<int> bytes, {String contentType = 'image/jpeg'}) async {
    final raw = await _api.postBytes<Map<String, dynamic>>(
      path,
      bytes: bytes,
      contentType: contentType,
    );
    return UploadResult(
      url: (raw?['url'] ?? '') as String,
      key: (raw?['key'] ?? '') as String,
    );
  }
}
