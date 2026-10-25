import 'package:flutter/foundation.dart';

import '../core/api_exception.dart';
import '../data/api/notification_api.dart';
import '../data/models/notification_record.dart';

/// 通知 / 消息（对应 Web 版 `src/store/useNotificationStore.ts`）。
///
/// 与家庭 store 的分工：家庭 store 管账（余额、流水、待审批），这里管
/// 「谁对谁做了什么」的消息。标记已读走**乐观更新**：先改本地（角标立刻变小），
/// 失败再拉一次真实数据兜底。
class NotificationState extends ChangeNotifier {
  NotificationState({required NotificationApi api}) : _api = api;

  final NotificationApi _api;

  NotifyAudience? _audience;

  /// 当前身份对应的信箱；未选身份时为 null
  NotifyAudience? get audience => _audience;

  List<NotificationRecord> _items = <NotificationRecord>[];

  /// 当前页通知列表（服务端已按时间倒序）
  List<NotificationRecord> get items => List<NotificationRecord>.unmodifiable(_items);

  int _unreadCount = 0;

  /// 未读数，来自服务端计数，**不受分页影响**
  int get unreadCount => _unreadCount;

  bool _loading = false;

  /// 首次加载中（下拉刷新式的静默刷新不算）
  bool get loading => _loading;

  bool _ready = true;

  /// false = 后端通知表尚未迁移好（此时按空信箱显示，不报错）
  bool get ready => _ready;

  String? _error;

  /// 最近一次 [load] 的失败文案
  String? get error => _error;

  /// 当前已加载的分页大小（刷新时沿用）。不在 state 里，对 UI 不可见。
  int _limit = NotificationApi.defaultLimit;

  /// 请求序号（M-8）：轮询刷新与下拉/切身份会并发，
  /// 只让最后一次发出的请求落库，否则旧响应会把未读数覆盖回去。
  int _refreshSeq = 0;

  /// 切换到某格信箱并加载。
  ///
  /// 换身份时先清空本地列表，避免把上一格信箱的消息递给另一个人看；
  /// 同一身份重载则保留旧列表（下拉刷新不闪空）。
  Future<void> load(NotifyAudience audience, {int? limit}) async {
    if (limit != null) _limit = limit;
    final seq = ++_refreshSeq;
    final switching = _audience != audience;
    _audience = audience;
    _loading = true;
    if (switching) {
      _items = <NotificationRecord>[];
      _unreadCount = 0;
      _error = null;
    }
    notifyListeners();

    try {
      final box = await _api.fetchNotifications(audience, limit: _limit);
      // 竞态守卫：请求期间身份又变了、或又发了一次新请求，就丢掉过期结果。
      // **注意此分支直接 return，不改 loading** —— 顺手置 false 会让新身份那次加载提前结束。
      if (seq != _refreshSeq || _audience != audience) return;
      _items = box.items;
      _unreadCount = box.unreadCount;
      _ready = box.ready;
      _loading = false;
      _error = null;
      notifyListeners();
    } catch (e) {
      _loading = false;
      _error = e is ApiException ? e.message : '通知加载失败';
      notifyListeners();
      // 不 rethrow：加载失败不该把页面炸掉
    }
  }

  /// 静默刷新（轮询用）。失败什么都不做 —— 保留上一次的数据，等下一轮。
  Future<void> refresh() async {
    final audience = _audience;
    if (audience == null) return;
    final seq = ++_refreshSeq;
    try {
      final box = await _api.fetchNotifications(audience, limit: _limit);
      if (seq != _refreshSeq || _audience != audience) return;
      _items = box.items;
      _unreadCount = box.unreadCount;
      _ready = box.ready;
      _error = null;
      notifyListeners();
    } catch (_) {
      // 轮询失败不打扰用户
    }
  }

  /// 标记一条已读。不在列表里或已读直接返回（幂等）。失败会拉真实数据兜底且不抛。
  Future<void> markRead(String id) async {
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0 || !_items[index].isUnread) return;

    final readAt = DateTime.now().toUtc();
    final next = List<NotificationRecord>.from(_items);
    next[index] = next[index].copyWith(status: 'read', readAt: readAt);
    _items = next;
    _unreadCount = _unreadCount > 0 ? _unreadCount - 1 : 0;
    notifyListeners();

    try {
      await _api.markNotificationRead(id);
    } catch (_) {
      await refresh();
    }
  }

  /// 整格信箱一键已读。
  ///
  /// 失败时**先 `refresh()` 拉回真实未读数、再 `rethrow`** —— 这条是刻意修的 bug：
  /// 「以前这里吞掉异常，页面照样弹『已全部标记为已读』，用户接着看到角标又回来了
  ///  —— 提示成功但实际没成功。」
  Future<void> markAllRead() async {
    final audience = _audience;
    if (audience == null || _unreadCount == 0) return;

    final readAt = DateTime.now().toUtc();
    _items = _items
        .map((item) => item.isUnread ? item.copyWith(status: 'read', readAt: readAt) : item)
        .toList(growable: false);
    _unreadCount = 0;
    notifyListeners();

    try {
      await _api.markAllNotificationsRead(audience);
    } catch (_) {
      await refresh();
      rethrow;
    }
  }
}
