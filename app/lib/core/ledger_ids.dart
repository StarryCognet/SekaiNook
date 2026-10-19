/// 账本 id 的前缀约定（对应 Web 版 `src/api/familyLedger.ts` 里的常量）。
///
/// 花园的流水和家庭账本共用同一张表、同一个接口，靠 task_id 前缀区分。
/// 前缀写错会让花园的阳光算进家庭余额（或反过来），所以全站只在这里定义一次。
abstract final class LedgerIds {
  /// 花园任务打卡
  static const String gardenTaskPrefix = 'garden:';

  /// 花园商城兑换
  static const String gardenShopPrefix = 'garden_shop:';

  /// 历史遗留：早期花园流水没有前缀，统一归到这条 id 下
  static const String gardenLegacyTaskId = 'garden_legacy';

  /// 遗留花园余额的封顶值（超过这个数的老数据按上限截断，避免早年脏数据把余额撑爆）
  static const int gardenLegacyMax = 2000;

  /// 是不是花园流水
  static bool isGardenTaskId(String? taskId) {
    if (taskId == null) return false;
    return taskId.startsWith(gardenTaskPrefix) ||
        taskId.startsWith(gardenShopPrefix) ||
        taskId == gardenLegacyTaskId;
  }

  /// 花园任务 -> 账本 task_id
  static String gardenTaskId(String id) => '$gardenTaskPrefix$id';

  /// 商城物品 -> 账本 task_id
  static String gardenShopTaskId(String id) => '$gardenShopPrefix$id';

  /// 账本 task_id -> 商城物品 id（不是商城流水时返回 null）
  static String? gardenShopItemId(String taskId) => taskId.startsWith(gardenShopPrefix)
      ? taskId.substring(gardenShopPrefix.length)
      : null;
}

/// 生产一条请求 id（对应 Web 版 `createRequestId`）。
///
/// 后端按这个 id 去重，所以**同一条逻辑记录重试时必须复用同一个 id**，
/// 换了 id 就会记两笔账。
///
/// 这里不用 UUID 包：时间戳（36 进制）+ 随机后缀已经足够唯一，
/// 且少一个依赖。格式 `req-<base36 毫秒>-<8 位随机>`。
String createRequestId() {
  final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final rand = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final suffix = rand.padLeft(8, '0');
  return 'req-$ts-${suffix.substring(suffix.length - 8)}';
}
