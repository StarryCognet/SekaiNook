import '../../core/api_client.dart';
import '../models/notification_record.dart';

/// 通知接口（对应 Web 版 `src/api/notifications.ts`）。
///
/// **没有「创建」接口**：通知全部由服务端在记账 / 审批 / 结算处写入，
/// 前端只读与标记已读。
class NotificationApi {
  NotificationApi(this._client);

  final ApiClient _client;

  /// 默认拉多少条
  static const int defaultLimit = 50;

  /// 拉某一格信箱（`GET /api/notifications?audience=&limit=`）。
  ///
  /// limit 被规整为 `max(1, floor(limit))`，与 Web 版一致。
  Future<NotificationBox> fetchNotifications(
    NotifyAudience audience, {
    int limit = defaultLimit,
  }) async {
    final safeLimit = limit < 1 ? 1 : limit.floor();
    final raw = await _client.getJson<dynamic>(
      '/api/notifications',
      query: <String, dynamic>{'audience': audience.wire, 'limit': safeLimit},
    );
    return NotificationBox.fromJson(raw);
  }

  /// 标记一条已读（`PATCH /api/notifications/:id`）
  Future<void> markNotificationRead(String id) async {
    await _client.patchJson<dynamic>(
      '/api/notifications/${Uri.encodeComponent(id)}',
      data: const <String, dynamic>{'status': 'read'},
    );
  }

  /// 整格信箱一键已读（`POST /api/notifications/read-all`）
  Future<void> markAllNotificationsRead(NotifyAudience audience) async {
    await _client.postJson<dynamic>(
      '/api/notifications/read-all',
      data: <String, dynamic>{'audience': audience.wire},
    );
  }
}
