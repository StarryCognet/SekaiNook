/// 全局常量。
///
/// 后端接口地址可在构建时覆盖：
/// `flutter run --dart-define=API_BASE=http://127.0.0.1:8788`
///
/// 注意本地调试必须写 `127.0.0.1` 不能写 `localhost` —— 与 Web 版铁律同因：
/// Node / 浏览器可能把 localhost 解析到 IPv6 `::1`，而 workerd 只监听 IPv4，
/// 表现为 500/502。
abstract final class AppConstants {
  static const String appName = 'SekaiNook';
  static const String appTitle = '晴空小筑';

  /// 后端根地址（不带尾斜杠）
  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://sekainook.pages.dev',
  );

  /// 单次请求超时（与 Web 版 DEFAULT_TIMEOUT_MS 一致）
  static const Duration requestTimeout = Duration(milliseconds: 12000);

  /// 通知信箱轮询间隔（与 Web 版一致：10 秒）
  static const Duration notificationPollInterval = Duration(seconds: 10);

  // ---- 本地存储键（各设备独立，不跨设备同步）----

  /// 主题选择
  static const String keyTheme = 'sekainook_theme';

  /// 身份选择（妈妈 / 女儿）
  static const String keyRole = 'sekainook_role';

  /// 日结算节流标记（对应 Web 版 `sekainook_settle_day`）。
  /// **纯粹为省流量，任何情况下都不能当防重复扣的手段** ——
  /// 幂等性由后端固定 id 保证。
  static const String keySettleDay = 'sekainook_settle_day';

  /// 家庭称呼设置（妈妈/女儿怎么叫）
  static const String keyFamilyNames = 'sekainook_family_names';

  /// 自定义背景图缓存（本机存的图片字节 / 校验信息）
  static const String keyBackgroundCache = 'sekainook_bg_cache_v1';

  /// 家长口令的 SHA-256 十六进制值
  static const String keyParentPinHash = 'sekainook_parent_pin_hash';

  /// 老版本存的明文口令（读到后要迁移成 hash 并删掉老键）
  static const String keyParentPinLegacy = 'sekainook_parent_pin';

  /// 口令连续输错次数（试错节流用）
  static const String keyPinFails = 'sekainook_parent_pin_fails';

  /// 口令锁定截止时间戳（试错节流用）
  static const String keyPinLockUntil = 'sekainook_parent_pin_lock_until';

  /// 花园全部本地状态打包成一个 JSON（不是拆成多个键）
  static const String keyGardenState = 'sekainook_garden_state';

  /// 花园状态迁移标记
  static const String keyGardenMigrated = 'sekainook_garden_migrated';

  /// 花园本地待同步队列（还没写进后端的打卡/兑换）
  static const String keyGardenPending = 'sekainook_garden_pending';

  /// 自定义任务（家长新增的任务）本地列表
  static const String keyCustomTasks = 'sekainook_custom_tasks_v1';

  /// 上一次用的浅色主题（切到深色时记住，切回来用）
  static const String keyThemeLight = 'sekainook_theme_light';

  /// 上一次用的深色主题
  static const String keyThemeDark = 'sekainook_theme_dark';

  /// 孩子已看过的驳回记录 id（首页红点用）
  static const String keyKidSeenRejects = 'sekainook_kid_seen_rejects';

  /// 已经庆祝过的勋章 id（避免每次进页面都弹一次庆祝动画）
  static const String keyBadgesCelebrated = 'sekainook_badges_celebrated';
}
