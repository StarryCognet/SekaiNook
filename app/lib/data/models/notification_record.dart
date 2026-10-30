/// 通知收件人（对应 Web 版 `NotifyAudience`）
enum NotifyAudience {
  parent('parent'),
  child('child');

  const NotifyAudience(this.wire);
  final String wire;

  static NotifyAudience parse(Object? value) =>
      value == 'child' ? NotifyAudience.child : NotifyAudience.parent;

  String get label => this == NotifyAudience.parent ? '家长' : '孩子';
}

/// 通知类型（对应 Web 版 `NotifyType`）
enum NotifyType {
  checkinPending('checkin_pending'),
  approved('approved'),
  rejected('rejected'),
  resubmitted('resubmitted'),
  recorded('recorded'),
  payout('payout');

  const NotifyType(this.wire);
  final String wire;

  static NotifyType? parse(Object? value) {
    for (final item in NotifyType.values) {
      if (item.wire == value) return item;
    }
    return null;
  }
}

/// 一条通知（对应 Web 版 `NotificationRecord`）
class NotificationRecord {
  const NotificationRecord({
    required this.id,
    required this.audience,
    required this.type,
    required this.title,
    required this.createdAt,
    this.body,
    this.link,
    this.status = 'unread',
    this.readAt,
  });

  final String id;
  final NotifyAudience audience;
  final NotifyType? type;
  final String title;
  final String? body;

  /// 点进去要跳的站内路径（如 `/family?tab=pending`）；可能为空
  final String? link;
  final String status;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => status != 'read';

  /// 宽松取字符串：服务端字段类型漂移（如 id 变数字）时回落默认值，
  /// 而不是 `as String` 直接抛 TypeError 把整页通知炸掉（D-9）。
  static String _asString(Object? value) => value is String ? value : '';

  static String? _asStringOrNull(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  factory NotificationRecord.fromJson(Map<String, dynamic> json) => NotificationRecord(
        id: _asString(json['id']),
        audience: NotifyAudience.parse(json['audience']),
        type: NotifyType.parse(json['type']),
        title: _asString(json['title']),
        body: _asStringOrNull(json['body']),
        link: _asStringOrNull(json['link']),
        status: _asStringOrNull(json['status']) ?? 'unread',
        createdAt: _parseTime(json['created_at']) ?? DateTime.now(),
        readAt: _parseTime(json['read_at']),
      );

  static DateTime? _parseTime(Object? value) {
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value)?.toLocal();
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt()).toLocal();
    return null;
  }

  NotificationRecord copyWith({String? status, DateTime? readAt}) => NotificationRecord(
        id: id,
        audience: audience,
        type: type,
        title: title,
        body: body,
        link: link,
        status: status ?? this.status,
        createdAt: createdAt,
        readAt: readAt ?? this.readAt,
      );
}

/// 一个信箱的内容（对应 Web 版 `NotificationBox`）
class NotificationBox {
  const NotificationBox({
    this.items = const <NotificationRecord>[],
    this.unreadCount = 0,
    this.ready = true,
  });

  final List<NotificationRecord> items;
  final int unreadCount;

  /// false = 通知表还没迁移，前端按空信箱显示、**不要报错**
  final bool ready;

  static const NotificationBox empty = NotificationBox();

  factory NotificationBox.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = <NotificationRecord>[];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is! Map) continue;
        try {
          items.add(NotificationRecord.fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {
          // 一条坏记录不该让整箱通知消失（D-9）：跳过它，其余照常显示
        }
      }
    }
    return NotificationBox(
      items: items,
      unreadCount: (json['unreadCount'] as num?)?.toInt() ??
          (json['unread_count'] as num?)?.toInt() ??
          0,
      ready: json['ready'] as bool? ?? true,
    );
  }
}
