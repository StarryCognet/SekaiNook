import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_constants.dart';
import '../data/api/settings_api.dart';
import '../theme/app_theme.dart';

/// 主题与全局背景图（对应 Web 版 `src/store/useThemeStore.ts`）。
///
/// 三件事放在一起是因为它们都影响「整个 App 长什么样」，也都由设置页控制：
/// - [themeId]：用哪个**种子色**，整套色板由它推出来，**存本机**；
/// - [brightness]：浅色 / 深色 / **跟随系统**，也存本机；
/// - [background]：全局背景图地址，**存服务端 settings 表**
///   （两台设备看到同一张，且服务端知道它被引用，不会被「闲置照片清理」误删）。
///
/// 主题与明暗是**两件独立的事**（FlClash 也是这么分的）：主题只管「什么颜色」，
/// 浅色还是深色是另一档偏好，「跟随系统」只是明暗里的一个选项 —— 不是第七套主题。
class ThemeState extends ChangeNotifier {
  ThemeState({
    required SharedPreferences prefs,
    required SettingsApi settingsApi,
  })  : _prefs = prefs,
        _api = settingsApi {
    _themeId = _loadThemeId();
    _brightness = _loadBrightness();
    _navOpacity = _loadNavOpacity();
  }

  final SharedPreferences _prefs;
  final SettingsApi _api;

  late ThemeId _themeId;

  /// 当前主题（种子色）
  ThemeId get themeId => _themeId;

  /// 当前主题预设
  AppThemePreset get preset => AppTheme.preset(_themeId);

  late ThemeBrightness _brightness;

  /// 当前明暗偏好（可能是「跟随系统」）
  ThemeBrightness get brightness => _brightness;

  String _background = '';

  /// 全局背景图地址，`''` = 没设
  String get background => _background;

  bool get hasBackground => _background.isNotEmpty;

  // ---- 底栏胶囊的不透明度 ----

  /// 完全不透明 —— 出厂默认
  static const double navOpacityOpaque = 1;

  /// 下限。再低胶囊几乎看不见，图标与文字会失去底色衬托，对比度掉得厉害。
  static const double navOpacityMin = 0.5;

  double _navOpacity = navOpacityOpaque;

  /// 底部悬浮胶囊的不透明度：1.0 = 实心（默认），越小越能透出从底下滚过的内容。
  ///
  /// **存本机**：这是「这台设备看起来怎么样」的偏好，与主题同类，不跨设备同步。
  double get navBarOpacity => _navOpacity;

  double _loadNavOpacity() {
    final raw = _prefs.getDouble(AppConstants.keyNavBarOpacity);
    // 没写过这个键 = 没调过 = 出厂的不透明；脏值一律夹回合法区间
    if (raw == null) return navOpacityOpaque;
    return raw.clamp(navOpacityMin, navOpacityOpaque).toDouble();
  }

  /// 改底栏不透明度（设置页拖一下即生效并落盘）
  Future<void> setNavBarOpacity(double value) async {
    final next = value.clamp(navOpacityMin, navOpacityOpaque).toDouble();
    try {
      await _prefs.setDouble(AppConstants.keyNavBarOpacity, next);
    } catch (_) {}
    if (_navOpacity == next) return;
    _navOpacity = next;
    notifyListeners();
  }

  bool _backgroundReady = false;

  /// 背景图是否已问过服务端（避免首屏先铺一层纯色再跳成照片）
  bool get backgroundReady => _backgroundReady;

  // ---- 主题 ----

  /// 读主题：不合法就回出厂默认。
  ///
  /// 旧版存的是「整套主题」的名字（original / sakura / …），那些名字现在都不是
  /// 合法 id 了，于是自动回落到出厂主题 —— 老用户装上新版会看到主题变了，
  /// 这是换色板体系的预期结果，不是丢配置。
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

  /// 切换主题（设置页点一下即生效并落盘）
  Future<void> setThemeId(ThemeId id) async {
    await _saveThemeId(id);
    if (_themeId == id) return;
    _themeId = id;
    notifyListeners();
  }

  // ---- 明暗 ----

  /// 读明暗偏好。出厂「跟随系统」—— 手机到了晚上自己变深色，最不打扰人；
  /// 读不到或读到脏值也一样回它。
  ThemeBrightness _loadBrightness() {
    final raw = _prefs.getString(AppTheme.brightnessKey);
    for (final item in ThemeBrightness.values) {
      if (item.name == raw) return item;
    }
    return ThemeBrightness.system;
  }

  /// 设置页那三个「浅色 / 深色 / 跟随系统」按钮
  Future<void> setBrightness(ThemeBrightness value) async {
    try {
      await _prefs.setString(AppTheme.brightnessKey, value.name);
    } catch (_) {}
    if (_brightness == value) return;
    _brightness = value;
    notifyListeners();
  }

  /// 右上角太阳/月亮按钮：在浅色与深色之间来回切。
  ///
  /// [effectiveDark] 是「现在看上去是不是深色」—— 偏好是「跟随系统」时，
  /// 光看 [_brightness] 判断不出该往哪边切，得由界面把当前实际明暗问出来传进来。
  Future<void> toggleBrightness({required bool effectiveDark}) =>
      setBrightness(effectiveDark ? ThemeBrightness.light : ThemeBrightness.dark);

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
