import 'package:flutter/material.dart';

import 'motion.dart';
import 'tokens.dart';

/// 主题预设 —— 全局生效（对应 Web 版 `src/theme/themes.ts` 的 THEMES）。
///
/// 一套主题 = 一份 [AppPalette]（16 个颜色）+ 是否深色。
/// Web 版的「CSS 变量集 + antd 主题」两半，在 Flutter 里统一由 [AppTheme.build]
/// 组装成 ThemeData + palette 扩展，页面只读 palette，不再各写各的色值。
///
/// 加新主题的步骤：① 下面 [AppTheme.all] 加一条 ② [ThemeId] 加一个枚举值。
enum ThemeId { original, midnight, sakura, forest, sunset, crimson, graphite }

/// 一套主题的全部颜色。字段与 Web 版 `ThemePalette` 一一对应，不要改名。
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.primary,
    required this.primarySoft,
    required this.success,
    required this.danger,
    required this.warning,
    required this.bg,
    required this.surface,
    required this.surfaceSoft,
    required this.text,
    required this.textSecondary,
    required this.textTertiary,
    required this.border,
    required this.sider,
    required this.siderSelected,
    required this.segmentedSelected,
    required this.surfaceGlass,
    required this.surfaceSoftGlass,
  });

  /// 主色
  final Color primary;

  /// 主色浅一档，用于渐变尾、选中底色
  final Color primarySoft;
  final Color success;
  final Color danger;
  final Color warning;

  /// 页面底色
  final Color bg;

  /// 卡片底
  final Color surface;

  /// 次级底（内嵌区块、输入框）
  final Color surfaceSoft;

  final Color text;
  final Color textSecondary;
  final Color textTertiary;
  final Color border;

  /// PC 侧边栏底
  final Color sider;

  /// 侧边栏选中项底
  final Color siderSelected;

  /// 分段控件选中项底
  final Color segmentedSelected;

  /// 设了自定义背景图时的半透明卡片底（照片透出来）
  final Color surfaceGlass;

  /// 设了自定义背景图时的半透明次级底
  final Color surfaceSoftGlass;

  /// 按「有没有设背景图」取卡片底色 —— 页面一律走它，不要直接读 surface。
  Color cardColor({required bool hasBackground}) => hasBackground ? surfaceGlass : surface;

  /// 背景图之上盖的一层薄纱（对应 Web 版 `--app-bg-veil`）：
  /// 浅色主题白纱 0.34、深色主题暗纱 0.32 —— 照片再花也能看清文字。
  Color get bgVeil => bg.withValues(alpha: bg.computeLuminance() < 0.35 ? 0.32 : 0.35);

  /// 按「有没有设背景图」取次级底色。
  Color softColor({required bool hasBackground}) =>
      hasBackground ? surfaceSoftGlass : surfaceSoft;

  @override
  AppPalette copyWith({
    Color? primary,
    Color? primarySoft,
    Color? success,
    Color? danger,
    Color? warning,
    Color? bg,
    Color? surface,
    Color? surfaceSoft,
    Color? text,
    Color? textSecondary,
    Color? textTertiary,
    Color? border,
    Color? sider,
    Color? siderSelected,
    Color? segmentedSelected,
    Color? surfaceGlass,
    Color? surfaceSoftGlass,
  }) {
    return AppPalette(
      primary: primary ?? this.primary,
      primarySoft: primarySoft ?? this.primarySoft,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceSoft: surfaceSoft ?? this.surfaceSoft,
      text: text ?? this.text,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      border: border ?? this.border,
      sider: sider ?? this.sider,
      siderSelected: siderSelected ?? this.siderSelected,
      segmentedSelected: segmentedSelected ?? this.segmentedSelected,
      surfaceGlass: surfaceGlass ?? this.surfaceGlass,
      surfaceSoftGlass: surfaceSoftGlass ?? this.surfaceSoftGlass,
    );
  }

  /// 切换主题时的颜色过渡（[AppDuration.themeChange] 内插值）
  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return AppPalette(
      primary: mix(primary, other.primary),
      primarySoft: mix(primarySoft, other.primarySoft),
      success: mix(success, other.success),
      danger: mix(danger, other.danger),
      warning: mix(warning, other.warning),
      bg: mix(bg, other.bg),
      surface: mix(surface, other.surface),
      surfaceSoft: mix(surfaceSoft, other.surfaceSoft),
      text: mix(text, other.text),
      textSecondary: mix(textSecondary, other.textSecondary),
      textTertiary: mix(textTertiary, other.textTertiary),
      border: mix(border, other.border),
      sider: mix(sider, other.sider),
      siderSelected: mix(siderSelected, other.siderSelected),
      segmentedSelected: mix(segmentedSelected, other.segmentedSelected),
      surfaceGlass: mix(surfaceGlass, other.surfaceGlass),
      surfaceSoftGlass: mix(surfaceSoftGlass, other.surfaceSoftGlass),
    );
  }
}

/// 一个主题预设：id + 名字 + 说明 + 预览三色 + 深色标记 + 完整调色板。
class AppThemePreset {
  const AppThemePreset({
    required this.id,
    required this.name,
    required this.description,
    required this.swatch,
    required this.dark,
    required this.palette,
  });

  final ThemeId id;

  /// 设置页显示的名字
  final String name;

  /// 设置页显示的一句话说明
  final String description;

  /// 预览小块的三个色（底 / 卡片 / 强调）
  final List<Color> swatch;

  /// 是否深色主题
  final bool dark;

  final AppPalette palette;
}

/// 深色与浅色主题共用的半透明玻璃底（对应 Web 版的 GLASS_LIGHT / GLASS_SOFT_LIGHT）
const Color _glassLight = Color(0xD1FFFFFF); // rgba(255,255,255,0.82)
const Color _glassSoftLight = Color(0xB3FFFFFF); // rgba(255,255,255,0.7)

/// 七套主题（顺序与 Web 版一致，设置页按此顺序展示）。
abstract final class AppTheme {
  static const ThemeId defaultThemeId = ThemeId.original;

  /// 主题选择存在本机（每台设备各选各的，不跨设备同步）
  static const String storageKey = 'sekainook_theme';

  static const List<AppThemePreset> all = <AppThemePreset>[
    AppThemePreset(
      id: ThemeId.original,
      name: '原始',
      description: '浅色卡片 + 深蓝主色，出厂默认',
      swatch: <Color>[Color(0xFFF5F6FA), Color(0xFFFFFFFF), Color(0xFF1A1A2E)],
      dark: false,
      palette: AppPalette(
        primary: Color(0xFF1A1A2E),
        primarySoft: Color(0xFF2A2A4A),
        success: Color(0xFF0F9B6C),
        danger: Color(0xFFE94560),
        warning: Color(0xFFF5A623),
        bg: Color(0xFFF5F6FA),
        surface: Color(0xFFFFFFFF),
        surfaceSoft: Color(0xFFF9FAFB),
        text: Color(0xFF1A1A2E),
        textSecondary: Color(0xFF6B7280),
        textTertiary: Color(0xFF9CA3AF),
        border: Color(0xFFE5E7EB),
        sider: Color(0xFF1A1A2E),
        siderSelected: Color(0xFF2A2A4A),
        segmentedSelected: Color(0xFFFFFFFF),
        surfaceGlass: _glassLight,
        surfaceSoftGlass: _glassSoftLight,
      ),
    ),
    AppThemePreset(
      id: ThemeId.midnight,
      name: '午夜蓝',
      description: '午夜蓝墨底 + 青蓝高光，晚上看不刺眼',
      swatch: <Color>[Color(0xFF060C1C), Color(0xFF0E1A33), Color(0xFF2B7FE0)],
      dark: true,
      palette: AppPalette(
        primary: Color(0xFF2B7FE0),
        primarySoft: Color(0xFF1B4A8F),
        success: Color(0xFF34D399),
        danger: Color(0xFFFF6B81),
        warning: Color(0xFFF7B955),
        bg: Color(0xFF060C1C),
        surface: Color(0xFF0E1A33),
        surfaceSoft: Color(0xFF132241),
        text: Color(0xFFE8F1FF),
        textSecondary: Color(0xFF92A8C9),
        textTertiary: Color(0xFF6C82A5),
        border: Color(0xFF22355A),
        sider: Color(0xFF04091A),
        siderSelected: Color(0xFF152A52),
        segmentedSelected: Color(0xFF1D3160),
        surfaceGlass: Color(0xD10E1A33),
        surfaceSoftGlass: Color(0xB3132241),
      ),
    ),
    AppThemePreset(
      id: ThemeId.sakura,
      name: '樱花粉',
      description: '奶粉底 + 樱花主色，软软的一天',
      swatch: <Color>[Color(0xFFFFF5F8), Color(0xFFFFFFFF), Color(0xFFE8628F)],
      dark: false,
      palette: AppPalette(
        primary: Color(0xFFE8628F),
        primarySoft: Color(0xFFF6A8C4),
        success: Color(0xFF2FAE86),
        danger: Color(0xFFE8455F),
        warning: Color(0xFFE9A13A),
        bg: Color(0xFFFFF5F8),
        surface: Color(0xFFFFFFFF),
        surfaceSoft: Color(0xFFFDF1F5),
        text: Color(0xFF3B2430),
        textSecondary: Color(0xFF8B6B78),
        textTertiary: Color(0xFFB39AA4),
        border: Color(0xFFF6DBE5),
        sider: Color(0xFFE8628F),
        siderSelected: Color(0xFFC9426E),
        segmentedSelected: Color(0xFFFFFFFF),
        surfaceGlass: _glassLight,
        surfaceSoftGlass: _glassSoftLight,
      ),
    ),
    AppThemePreset(
      id: ThemeId.forest,
      name: '森林绿',
      description: '薄荷底 + 森林绿，清清爽爽像早上',
      swatch: <Color>[Color(0xFFF2F9F5), Color(0xFFFFFFFF), Color(0xFF2F9E6E)],
      dark: false,
      palette: AppPalette(
        primary: Color(0xFF2F9E6E),
        primarySoft: Color(0xFF8FD3B4),
        success: Color(0xFF2F9E6E),
        danger: Color(0xFFE0603F),
        warning: Color(0xFFDFA03A),
        bg: Color(0xFFF2F9F5),
        surface: Color(0xFFFFFFFF),
        surfaceSoft: Color(0xFFEEF7F1),
        text: Color(0xFF1E3B2F),
        textSecondary: Color(0xFF5F7D6F),
        textTertiary: Color(0xFF93AB9F),
        border: Color(0xFFDCEBE2),
        sider: Color(0xFF1F6F4D),
        siderSelected: Color(0xFF2F9E6E),
        segmentedSelected: Color(0xFFFFFFFF),
        surfaceGlass: _glassLight,
        surfaceSoftGlass: _glassSoftLight,
      ),
    ),
    AppThemePreset(
      id: ThemeId.sunset,
      name: '暖阳橙',
      description: '米白底 + 暖橙主色，像傍晚的客厅',
      swatch: <Color>[Color(0xFFFFF8F1), Color(0xFFFFFFFF), Color(0xFFE07B39)],
      dark: false,
      palette: AppPalette(
        primary: Color(0xFFE07B39),
        primarySoft: Color(0xFFF5B183),
        success: Color(0xFF3D9E6D),
        danger: Color(0xFFD8452F),
        warning: Color(0xFFDD9A2A),
        bg: Color(0xFFFFF8F1),
        surface: Color(0xFFFFFFFF),
        surfaceSoft: Color(0xFFFDF3E9),
        text: Color(0xFF3F2A1B),
        textSecondary: Color(0xFF8A6C55),
        textTertiary: Color(0xFFB39B86),
        border: Color(0xFFF4E0CC),
        sider: Color(0xFFC25F22),
        siderSelected: Color(0xFFE07B39),
        segmentedSelected: Color(0xFFFFFFFF),
        surfaceGlass: _glassLight,
        surfaceSoftGlass: _glassSoftLight,
      ),
    ),
    AppThemePreset(
      id: ThemeId.crimson,
      name: '暗夜红',
      description: '墨红底 + 霓虹红，像游戏界面（夜里护眼）',
      swatch: <Color>[Color(0xFF140609), Color(0xFF1F0C11), Color(0xFFF04A5A)],
      dark: true,
      palette: AppPalette(
        primary: Color(0xFFF04A5A),
        primarySoft: Color(0xFF8C1F2D),
        success: Color(0xFF3DDC97),
        danger: Color(0xFFFF7B7B),
        warning: Color(0xFFF2B44C),
        bg: Color(0xFF140609),
        surface: Color(0xFF1F0C11),
        surfaceSoft: Color(0xFF2A1218),
        text: Color(0xFFF8ECEF),
        textSecondary: Color(0xFFC99AA5),
        textTertiary: Color(0xFF9C7079),
        border: Color(0xFF3D2027),
        sider: Color(0xFF0D0406),
        siderSelected: Color(0xFF3A1620),
        segmentedSelected: Color(0xFF3A1620),
        surfaceGlass: Color(0xD11F0C11),
        surfaceSoftGlass: Color(0xB32A1218),
      ),
    ),
    AppThemePreset(
      id: ThemeId.graphite,
      name: '石墨黑',
      description: '近黑底 + 白墨 + 玻璃胶囊，笔记工具风（夜里最安静）',
      swatch: <Color>[Color(0xFF141414), Color(0xFF242424), Color(0xFF0F77F0)],
      dark: true,
      palette: AppPalette(
        primary: Color(0xFF0F77F0),
        primarySoft: Color(0xFF0A4F9E),
        success: Color(0xFF3DDC97),
        danger: Color(0xFFFF4538),
        warning: Color(0xFFFFDD55),
        bg: Color(0xFF141414),
        surface: Color(0xFF1F1F1F),
        surfaceSoft: Color(0xFF242424),
        text: Color(0xFFFFFFFF),
        textSecondary: Color(0xFFB4B4B4),
        textTertiary: Color(0xFF808080),
        border: Color(0xFF383838),
        sider: Color(0xFF0D0D0D),
        siderSelected: Color(0xFF2A2A2A),
        segmentedSelected: Color(0xFF3F3F3F),
        surfaceGlass: Color(0xD11F1F1F),
        surfaceSoftGlass: Color(0xB3242424),
      ),
    ),
  ];

  /// 按 id 取预设；id 非法时回退出厂默认（与 Web 版 themePreset 同行为）。
  static AppThemePreset preset(ThemeId id) {
    for (final item in all) {
      if (item.id == id) return item;
    }
    return all.first;
  }

  /// 按存储字符串取预设；不认识就回退默认。
  static AppThemePreset presetFromName(String? name) {
    for (final item in all) {
      if (item.id.name == name) return item;
    }
    return all.first;
  }

  /// 组装 Flutter 主题。颜色一律取自 palette，这里不出现任何写死的色值。
  ///
  /// [hasBackground] = 用户设了自定义背景图：页面底要透明（照片在底下铺着），
  /// 卡片改用半透明底。玻璃底由调用方通过 [AppPalette.cardColor] 取。
  static ThemeData build(ThemeId id, {bool hasBackground = false}) {
    final themePreset = preset(id);
    final p = themePreset.palette;

    final scheme = ColorScheme.fromSeed(
      seedColor: p.primary,
      brightness: themePreset.dark ? Brightness.dark : Brightness.light,
    ).copyWith(
      primary: p.primary,
      secondary: p.primarySoft,
      error: p.danger,
      surface: p.cardColor(hasBackground: hasBackground),
      onSurface: p.text,
      outline: p.border,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: themePreset.dark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: hasBackground ? Colors.transparent : p.bg,
      canvasColor: p.cardColor(hasBackground: hasBackground),
      dividerColor: p.border,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[p],
      textTheme: base.textTheme.apply(
        bodyColor: p.text,
        displayColor: p.text,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.cardColor(hasBackground: hasBackground),
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: p.text,
          fontSize: AppFontSize.md,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: p.cardColor(hasBackground: hasBackground),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: p.border),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.cardColor(hasBackground: hasBackground),
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.cardColor(hasBackground: hasBackground),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xxl),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.softColor(hasBackground: hasBackground),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: p.primary, width: 1.5),
        ),
        hintStyle: TextStyle(color: p.textTertiary),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: themePreset.dark ? p.surfaceSoft : const Color(0xFF303030),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: AppFontSize.sm),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.primary),
      tabBarTheme: TabBarThemeData(
        labelColor: p.primary,
        unselectedLabelColor: p.textSecondary,
        indicatorColor: p.primary,
        dividerColor: p.border,
      ),
      // 页面转场统一走动效令牌（全平台 FadeForwards），见 theme/motion.dart
      pageTransitionsTheme: AppMotion.pageTransitionsTheme,
    );
  }
}

/// 页面里取调色板的快捷方式：`context.palette.primary`
extension AppPaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>() ?? AppTheme.all.first.palette;
}
