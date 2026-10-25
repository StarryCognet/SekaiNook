import 'dart:convert';

/// 家庭页首屏的卡片 —— 顺序可拖（对应 FlClash 首页的 DashboardWidget）。
///
/// 家长和孩子要的东西不一样：孩子希望「任务区」在首屏最上面，家长希望
/// 「待审批」一眼看到。固定的顺序照顾不了两种人，所以顺序做成每人一份的本机偏好。
enum FamilyCard {
  status(id: 'status', label: '状态条'),
  trend(id: 'trend', label: '积分趋势'),
  tasks(id: 'tasks', label: '任务区');

  const FamilyCard({required this.id, required this.label});

  final String id;
  final String label;

  /// 能不能删掉：状态条和任务区是页面骨架，删了就没东西可看；只有趋势卡可以收起来
  bool get removable => this == FamilyCard.trend;

  static FamilyCard? byId(String value) {
    for (final card in values) {
      if (card.id == value) return card;
    }
    return null;
  }
}

/// 卡片顺序的存档格式与编解码（**纯本机偏好**，后端没有这个字段）。
///
/// 写盘只存 id；读的时候把存档里缺的卡按默认顺序补到末尾 —— 以后加新卡，
/// 老存档不会因为少一个 id 就整份作废。
class FamilyCardOrderData {
  const FamilyCardOrderData({required this.order, required this.hidden});

  final List<FamilyCard> order;
  final Set<FamilyCard> hidden;

  static const List<FamilyCard> defaultOrder = <FamilyCard>[
    FamilyCard.status,
    FamilyCard.trend,
    FamilyCard.tasks,
  ];

  static const FamilyCardOrderData defaults = FamilyCardOrderData(
    order: defaultOrder,
    hidden: <FamilyCard>{},
  );

  List<FamilyCard> get visibleOrder =>
      order.where((card) => !hidden.contains(card)).toList(growable: false);

  String encode() => jsonEncode(<String, dynamic>{
        'order': order.map((card) => card.id).toList(),
        'hidden': hidden.map((card) => card.id).toList(),
      });

  static FamilyCardOrderData decode(String? raw) {
    if (raw == null || raw.isEmpty) return defaults;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map) return defaults;

      final order = <FamilyCard>[];
      final orderRaw = parsed['order'];
      if (orderRaw is List) {
        for (final item in orderRaw) {
          final card = FamilyCard.byId('$item');
          if (card != null && !order.contains(card)) order.add(card);
        }
      }
      for (final card in defaultOrder) {
        if (!order.contains(card)) order.add(card);
      }

      final hidden = <FamilyCard>{};
      final hiddenRaw = parsed['hidden'];
      if (hiddenRaw is List) {
        for (final item in hiddenRaw) {
          final card = FamilyCard.byId('$item');
          if (card != null && card.removable) hidden.add(card);
        }
      }
      return FamilyCardOrderData(order: order, hidden: hidden);
    } catch (_) {
      return defaults;
    }
  }

  /// 拖动排序：[oldIndex]/[newIndex] 都是**可见列表**里的下标
  /// （ReorderableListView 的 newIndex 在向下拖时会自动减一，这里按它的口径处理）。
  FamilyCardOrderData moved(int oldIndex, int newIndex) {
    final visible = visibleOrder;
    if (oldIndex < 0 || oldIndex >= visible.length) return this;
    if (newIndex < 0) newIndex = 0;
    if (newIndex >= visible.length) newIndex = visible.length - 1;
    if (oldIndex == newIndex) return this;

    final next = <FamilyCard>[...visible];
    final card = next.removeAt(oldIndex);
    next.insert(newIndex, card);
    return copyWith(
      // 隐藏的卡排在可见卡后面，保持它原来的相对位置
      order: <FamilyCard>[...next, ...order.where(hidden.contains)],
    );
  }

  FamilyCardOrderData toggled(FamilyCard card) {
    if (!card.removable) return this;
    final next = <FamilyCard>{...hidden};
    if (!next.remove(card)) next.add(card);
    return copyWith(hidden: next);
  }

  FamilyCardOrderData copyWith({List<FamilyCard>? order, Set<FamilyCard>? hidden}) =>
      FamilyCardOrderData(order: order ?? this.order, hidden: hidden ?? this.hidden);
}
