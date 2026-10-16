import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_constants.dart';
import '../data/api/settings_api.dart';
import '../theme/app_theme.dart';

/// 主题与全局背景图（对应 Web 版 `src/store/useThemeStore.ts`）。
///
/// 两件事放在一起是因为它们都影响「整个 App 长什么样」，也都由设置页控制：
/// - [themeId]：主题，**存本机**（每台设备各选各的）；右上角太阳/月亮按钮也走这里，
///   在「上次用的浅色」与「上次用的深色」之间来回切；
/// - [background]：全局背景图地址，**存服务端 settings 表**
///   （两台设备看到同一张，且服务端知道它被引用，不会被「闲置照片清理」误删）。
///
/// **不跟随系统**：没有任何 `prefers-color-scheme` 参与主题选择，
/// `themeId` 只来自本机存储或默认值。跟随系统这件事完全由用户手动点的那颗按钮替代。
class ThemeState extends ChangeNotifier {
  ThemeState({
    required SharedPreferences prefs,
    required SettingsApi settingsApi,
  })  : _prefs = prefs,
        _api = settingsApi {
    _themeId = _loadThemeId();
    // 首屏就把当前这套登记进它所属的深/浅格，免得第一次点切换时没有可回的目标。
    // 移植时这一句千万别漏 —— 它是「第一次点切换会跳错」的根因修复。
    _rememberBrightness(_themeId);
  }

  final SharedPreferences _prefs;
  final SettingsApi _api;

  late ThemeId _themeId;

  /// 当前主题
  ThemeId get themeId => _themeId;

  /// 当前主题预设
  AppThemePreset get preset => AppTheme.preset(_themeId);

  String _background = '';

  /// 全局背景图地址，`''` = 没设
  String get background => _background;

  bool get hasBackground => _background.isNotEmpty;

  bool _backgroundReady = false;

  /// 背景图是否已问过服务端（避免首屏先铺一层纯色再跳成照片）
  bool get backgroundReady => _backgroundReady;

  // ---- 主题 ----

  /// 读主题：`isThemeId` 不通过就回出厂默认；读到脏值也一样
  ThemeId _loadThemeId() {
    final raw = _prefs.getString(AppTheme.storageKey);
    for (final item in AppTheme.all) {
      if (item.id.name == raw) return item.id;
    }
    return AppTheme.defaultThemeId;
  }

  Future<void> _saveThemeId(ThemeId id) async {
    // 存不住也没关系，本次会话内仍然生效
    try {
      await _prefs.setString(AppTheme.storageKey, id.name);
    } catch (_) {}
  }

  /// 把 [id] 登记进它所属的深浅格（记不住就退回出厂的那套深浅主题）
  Future<void> _rememberBrightness(ThemeId id) async {
    final key = AppTheme.preset(id).dark
        ? AppConstants.keyThemeDark
        : AppConstants.keyThemeLight;
    try {
      await _prefs.setString(key, id.name);
    } catch (_) {}
  }

  /// 读「上次用过的浅色 / 深色」。
  ///
  /// 两处必须照抄：① 深色的出厂回落是**硬编码 `midnight`**（浅色才是 `original`）；
  /// ② 合法性判定要求「是合法 id **且**深浅相符」—— 两个键写反就会被判非法。
  ThemeId _loadBrightness({required bool dark}) {
    final fallback = dark ? ThemeId.midnight : AppTheme.defaultThemeId;
    final raw = _prefs.getString(dark ? AppConstants.keyThemeDark : AppConstants.keyThemeLight);
    for (final item in AppTheme.all) {
      if (item.id.name == raw && item.dark == dark) return item.id;
    }
    return fallback;
  }

  /// 切换主题（设置页点一下即生效并落盘）
  Future<void> setThemeId(ThemeId id) async {
    // 顺序固定：先落盘两个键，再改 state
    await _saveThemeId(id);
    await _rememberBrightness(id);
    if (_themeId == id) return;
    _themeId = id;
    notifyListeners();
  }

  /// 在「上次用的浅色」与「上次用的深色」之间来回切（右上角太阳/月亮按钮）
  Future<void> toggleBrightness() async {
    final targetDark = !AppTheme.preset(_themeId).dark;
    final next = _loadBrightness(dark: targetDark);
    await _saveThemeId(next);
    await _rememberBrightness(next);
    if (_themeId == next) return;
    _themeId = next;
    notifyListeners();
  }

  // ---- 背景图 ----

  /// 打开 App 时问一次服务端有没有设背景图。
  ///
  /// 失败就当没设，不打扰用户 —— 但**不会把 background 清空**，保留旧值。
  Future<void> loadBackground() async {
    try {
      final payload = await _api.fetchSettings();
      _background = payload.background;
      _backgroundReady = true;
      await _syncBackgroundCache();
      notifyListeners();
    } catch (_) {
      _backgroundReady = true;
      await _syncBackgroundCache();
      notifyListeners();
    }
  }

  /// 保存 / 移除背景图（传 `''` 表示移除）。失败**不吞**，异常抛给调用方提示。
  Future<void> saveBackground(String url) async {
    final payload = await _api.saveSettings(<String, dynamic>{'background': url});
    _background = payload.background;
    _backgroundReady = true;
    await _syncBackgroundCache();
    notifyListeners();
  }

  /// 本机影子缓存：背景图存在服务端，刷新时首帧拿不到，所以每台设备拿到后
  /// 往本机存一份地址。**只有 [backgroundReady] 为真时才动缓存** ——
  /// 否则首帧那个空字符串会把上一份缓存抹掉，下次刷新就又只剩纯色。
  Future<void> _syncBackgroundCache() async {
    if (!_backgroundReady) return;
    try {
      if (hasBackground) {
        await _prefs.setString(AppConstants.keyBackgroundCache, _background);
      } else {
        await _prefs.remove(AppConstants.keyBackgroundCache);
      }
    } catch (_) {}
  }
}
