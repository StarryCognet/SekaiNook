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

  /// 右上角那颗明暗按钮：浅色 → 深色 → 跟随系统 → 浅色，点一下循环一格。
  ///
  /// 为什么要第三档：手机自带「日落自动深色」时，用户想要的是「跟着设备走」，
  /// 而不是被 App 钉死在浅色或深色上。设置在设置页早就有了，顶栏以前只能表达
  /// 两档，所以切不到它。
  Future<void> cycleBrightness() => setBrightness(
        switch (_brightness) {
          ThemeBrightness.light => ThemeBrightness.dark,
          ThemeBrightness.dark => ThemeBrightness.system,
          ThemeBrightness.system => ThemeBrightness.light,
        },
      );

  // ---- 跟随壁纸 ----

  /// 跟随系统壁纸取色（Android 12+）。拿不到动态色时 App 会退回固定种子。
  bool get followWallpaper => _prefs.getBool(AppTheme.followWallpaperKey) ?? false;

  Future<void> setFollowWallpaper(bool value) async {
    // 值没变就别写盘、别 notify（L-1）：拖动/连点会触发整树重建
    if (followWallpaper == value) return;
    try {
      await _prefs.setBool(AppTheme.followWallpaperKey, value);
    } catch (_) {}
    notifyListeners();
  }

  // ---- 纯黑 / 字号 ----

  /// 深色模式下把页面底压到纯黑（AMOLED 省电、黑边更利落）。浅色模式无效。
  bool get pureBlack => _prefs.getBool(AppTheme.pureBlackKey) ?? false;

  Future<void> setPureBlack(bool value) async {
    if (pureBlack == value) return; // L-1 等值早退
    try {
      await _prefs.setBool(AppTheme.pureBlackKey, value);
    } catch (_) {}
    notifyListeners();
  }

  /// 正文字号缩放 0.8 ~ 1.4（1.0 是默认）。
  double get textScale =>
      (_textScalePreview ??
              (_prefs.getDouble(AppTheme.textScaleKey) ?? 1.0))
          .clamp(0.8, 1.4)
          .toDouble();

  /// 拖动字号滑杆时的内存预览值（null = 没有预览，读持久值）。
  ///
  /// P-8：滑杆 onChanged 每帧回调，以前每帧 `await _prefs.setDouble` 一次；
  /// 拖动期间只改内存，松手（onChangeEnd）才走 [setTextScale] 落盘。
  double? _textScalePreview;

  /// 拖动字号滑杆的即时预览：只改内存、不落盘。
  void previewTextScale(double value) {
    final next = value.clamp(0.8, 1.4).toDouble();
    if (textScale == next) return;
    _textScalePreview = next;
    notifyListeners();
  }

  Future<void> setTextScale(double value) async {
    final next = value.clamp(0.8, 1.4).toDouble();
    final current =
        (_prefs.getDouble(AppTheme.textScaleKey) ?? 1.0).clamp(0.8, 1.4).toDouble();
    final hadPreview = _textScalePreview != null;
    _textScalePreview = null;
    if (current == next) {
      // 值没变：可能只是把预览态收回成持久值，也要刷一次
      if (hadPreview) notifyListeners();
      return;
    }
    try {
      await _prefs.setDouble(AppTheme.textScaleKey, next);
    } catch (_) {}
    notifyListeners();
  }

  // ---- 背景图 ----

  /// 打开 App 时问一次服务端有没有设背景图。
  ///
  /// 失败就当没设，不打扰用户 —— 但**不会把 background 清空**，保留旧值。
  Future<void> loadBackground() async {
    // 首帧先把本机缓存的地址挂上（M-11）：以前只写不读，
    // 注释承诺的「刷新时首帧就有背景」其实没实现，得等一次网络往返。
    if (!_backgroundReady && _background.isEmpty) {
      final cached = _prefs.getString(AppConstants.keyBackgroundCache);
      if (cached != null && cached.isNotEmpty) {
        _background = cached;
        _backgroundReady = true;
        notifyListeners();
      }
    }
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
