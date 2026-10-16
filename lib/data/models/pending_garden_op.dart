/// 花园离线队列里的一笔待同步操作（对应 Web 版 `PendingGardenOp`）。
///
/// **重试必须复用同一个 [id]** —— 服务端靠主键 `INSERT OR IGNORE` 做幂等，
/// 每次重试新造 id 会导致重复入账。
class PendingGardenOp {
  const PendingGardenOp({
    required this.id,
    required this.taskId,
    required this.kind,
    required this.amount,
    required this.at,
    this.itemId,
  });

  /// 客户端生成的幂等 id
  final String id;

  /// 账本 task_id：`garden:xxx` / `garden_shop:xxx` / `garden_legacy`
  final String taskId;

  final GardenOpKind kind;

  /// 正数加分、负数扣分；乐观值就是它
  final int amount;

  /// 购买类操作的商品 id（被服务端拒绝时用来收回物品）
  final String? itemId;

  /// 入队时刻（毫秒时间戳）
  final int at;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'taskId': taskId,
        'kind': kind.wire,
        'amount': amount,
        if (itemId != null) 'itemId': itemId,
        'at': at,
      };

  /// 解析一条。**任何一项不满足就整条丢弃** —— 宁可少发一笔，也不拿坏数据去记账。
  static PendingGardenOp? fromStored(dynamic raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final taskId = raw['taskId'];
    final kind = GardenOpKind.parse(raw['kind']);
    final amount = raw['amount'];
    if (id is! String || id.isEmpty) return null;
    if (taskId is! String || taskId.isEmpty) return null;
    if (kind == null) return null;
    if (amount is! num || !amount.isFinite) return null;
    final itemId = raw['itemId'];
    final at = raw['at'];
    return PendingGardenOp(
      id: id,
      taskId: taskId,
      kind: kind,
      amount: amount.round(),
      itemId: (itemId is String && itemId.isNotEmpty) ? itemId : null,
      at: (at is num && at.isFinite) ? at.toInt() : 0,
    );
  }

  /// 解析整个队列：逐条过 [fromStored]，并**按 id 去重**（后出现的重复项丢弃）。
  static List<PendingGardenOp> listFromStored(dynamic raw) {
    if (raw is! List) return <PendingGardenOp>[];
    final seen = <String>{};
    final ops = <PendingGardenOp>[];
    for (final item in raw) {
      final op = fromStored(item);
      if (op == null) continue;
      if (!seen.add(op.id)) continue;
      ops.add(op);
    }
    return ops;
  }
}

/// 待同步操作的方向
enum GardenOpKind {
  earn('earn'),
  spend('spend');

  const GardenOpKind(this.wire);

  final String wire;

  static GardenOpKind? parse(Object? value) {
    for (final item in GardenOpKind.values) {
      if (item.wire == value) return item;
    }
    return null;
  }
}
