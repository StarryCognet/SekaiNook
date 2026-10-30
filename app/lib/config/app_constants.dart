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
    defaultValue: 'https://sn.starrymiku.com',
  );

  /// 单次请求超时（与 Web 版 DEFAULT_TIMEOUT_MS 一致）
  static const Duration requestTimeout = Duration(milliseconds: 12000);

  /// 应用内更新的清单地址：Cloudflare R2 上的一个静态 `latest.json`，
  /// 由 `tool/publish_apk.ps1` 发布（和 APK 放在一起，见 docs/android-update.md）。
  ///
  /// 走的是独立域名，不经过自家 API —— 更新这件事必须在 API 挂掉时也能用。
  /// 构建时可覆盖，方便对着本地文件试：
  /// `flutter build apk --dart-define=UPDATE_MANIFEST_URL=http://127.0.0.1:8788/latest.json`
  static const String appUpdateManifestUrl = String.fromEnvironment(
    'UPDATE_MANIFEST_URL',
    defaultValue: 'https://pub.starrymiku.com/sekainook/latest.json',
  );

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

  // ---- 设置 ----

  /// 称呼草稿的存储键前缀（后面接 `:kid` / `:mom`）。
  ///
  /// 对应 Web 版 `sekainook_name_draft:<target>`：称呼改了一半就走开
  /// （切身份 / 关掉标签）也不丢。真正保存成功之后这份草稿就退休。
  static const String keyNameDraftPrefix = 'sekainook_name_draft';

  // ---- 首页与通知 ----

  /// 通知页上次选的筛选（`all` / `unread`）。
  ///
  /// Web 版这一项落在 sessionStorage（`useViewState('home.noticeFilter')`）；
  /// Flutter 侧地址栏的 `?filter=` 才是落地时的唯一真相，这个键只是**设备记忆**：
  /// 从铃铛 / 首页宫格进来时（那些入口不带 query）拿它兜底，省得每次重选一遍。
  static const String keyNoticeFilter = 'sekainook_notice_filter';

  // ---- App 本地通知（安卓系统通知栏）----

  /// 本地提醒开关（开着的设备每天 21:30 弹一条「今天还差几个任务」）
  static const String keyLocalNotifyEnabled = 'sekainook_local_notify_on';

  /// 已排程的下一次提醒时刻（ISO 字符串，本机时区）——
  /// 插件的 pendingNotificationRequests 不返回触发时间，只能自己记
  static const String keyLocalNotifyNext = 'sekainook_local_notify_next';

  /// 上一次排程时算的是哪一天（东八区日期键），用于判断文案是否过期
  static const String keyLocalNotifyDay = 'sekainook_local_notify_day';

  /// 提醒项列表（JSON 数组：类型/时间/重复/文案/声音震动悬浮锁屏）
  static const String keyLocalNotifyReminders = 'sekainook_local_notify_items';

  /// 准时模式（精确闹钟；关着时用省电模式，到点可能晚几分钟）
  static const String keyLocalNotifyExact = 'sekainook_local_notify_exact';

  // ---- 应用内更新 ----

  /// 用户点过「以后再说」的那个版本号（如 `1.31.1`）。
  /// 效果只是**不再自动弹**：手动点「检查更新」照样能装。
  static const String keySkipUpdateVersion = 'sekainook_skip_update_version';

  /// 「自动检测更新」开关。没写过这个键时按开处理（默认开）。
  static const String keyAutoCheckUpdate = 'sekainook_auto_check_update';
}
