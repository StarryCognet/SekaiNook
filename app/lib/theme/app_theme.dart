import 'package:flutter/material.dart';

import 'app_shape.dart';
import 'motion.dart';
import 'tokens.dart';

/// 主题预设 —— 全局生效（对应 Web 版 `src/theme/themes.ts` 的 THEMES）。
///
/// 一套主题 = 一份 [AppPalette]（16 个颜色）+ 是否深色。
/// Web 版的「CSS 变量集 + antd 主题」两半，在 Flutter 里统一由 [AppTheme.build]
/// 组装成 ThemeData + palette 扩展，页面只读 palette，不再各写各的色值。
///
/// 加新主题的步骤：① 下面 [AppTheme.all] 加一条 ② [ThemeId] 加一个枚举值。
enum ThemeId { rose, brown, blue, yellow, grayblue, green, purple }

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

  /// 三级文字：标签、单位、时间戳、空态提示。
  ///
  /// **七套主题的值都按对比度校准过**（`test/palette_contrast_test.dart` 会拦）：
  /// 卡片底 ≥ 4.5:1、页面底 ≥ 4.0:1。改色板时别再凭手感调淡 —— 出厂主题最初
  /// 给的 `#9CA3AF` 在白卡上只有 2.54:1，用户反馈的「字和底撞一起看不清」多半是它。
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

  /// 在一层「有色底」（主色块、深底、渐变、软色块）上取读得清的文字色。
  ///
  /// 底色亮 → 同色系近黑；底色暗 → 近白。凡是「彩色底 + 文字」的地方都必须走它，
  /// 不要直接拿 [text] / [textSecondary] 往上放：原始主题的主色 #1A1A2E 和正文色
  /// 是同一个值，深底上放深字会直接糊成一片（午夜蓝主题的亮蓝底同理）。
  ///
  /// 取色不是拍脑袋定的：先按底色亮度判该用亮字还是暗字（阈值 0.18 来自
  /// 「纯黑字在 L≥0.175 时就能到 4.5:1、纯白字在 L≤0.183 时能到 4.5:1」这两条），
  /// 再在候选里挑**最柔但对比度仍 ≥ 4.5:1** 的那个 —— 中间调底色（森林绿、暖阳橙、
  /// 暗夜红）如果只把白色淡一点是压不住的（实测只有 2.3~3.9:1）。
  Color onColor(Color background) {
    final bool lightText = background.computeLuminance() < 0.18;
    final List<Color> candidates = lightText
        ? <Color>[
            Color.lerp(background, Colors.white, 0.9) ?? Colors.white,
            Color.lerp(background, Colors.white, 0.96) ?? Colors.white,
            Colors.white,
          ]
        : <Color>[
            Color.lerp(background, Colors.black, 0.82) ?? Colors.black,
            Color.lerp(background, Colors.black, 0.92) ?? Colors.black,
            Colors.black,
          ];
    for (final Color candidate in candidates) {
      if (_contrastRatio(candidate, background) >= 4.5) return candidate;
    }
    return lightText ? Colors.white : Colors.black;
  }

  /// 同 [onColor]，但弱一档 —— 副标题、说明文字用（仍有 3.5:1 以上）。
  ///
  /// 用「向底色混一点」而不是降低 alpha：视觉一样，但不会在渐变/背景图/玻璃卡上
  /// 透出后面的东西。
  Color onColorSoft(Color background) {
    final Color strong = onColor(background);
    for (final double t in <double>[0.78, 0.86, 0.93, 1]) {
      final Color candidate = Color.lerp(background, strong, t) ?? strong;
      if (_contrastRatio(candidate, background) >= 3.5) return candidate;
    }
    return strong;
  }

  static double _contrastRatio(Color a, Color b) {
    final double la = a.computeLuminance();
    final double lb = b.computeLuminance();
    final double hi = la > lb ? la : lb;
    final double lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// 把语义色（success / danger / warning / primary）当**文字色**用在某层底上：
  /// 保持色相，只往黑（浅底）或白（深底）压到对比度 ≥ 4.5:1。
  ///
  /// 与 [onColor] 的分工：[onColor] 用在「彩色块」上（丢掉色相换可读性），
  /// 这个用在「中性卡片底上的彩色字」——比如「+10 阳光」「-20 积分」这类数字，
  /// 既要不糊，也要保住红涨绿跌的颜色含义。
  /// 直接拿语义色当字色是不行的：出厂主题的 warning `#F5A623` 落在白卡上只有
  /// 1.7:1（实测），基本读不出来。
  Color ink(Color color, [Color? background]) {
    final Color base = background ?? surface;
    final bool darken = base.computeLuminance() > 0.5;
    for (final double t in <double>[0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]) {
      final Color candidate =
          (darken ? Color.lerp(color, Colors.black, t) : Color.lerp(color, Colors.white, t)) ??
              color;
      if (_contrastRatio(candidate, base) >= 4.5) return candidate;
    }
    return onColor(base);
  }

  Color get primaryInk => ink(primary);
  Color get successInk => ink(success);
  Color get dangerInk => ink(danger);
  Color get warningInk => ink(warning);

  /// 主色块上的文字色。
  Color get onPrimary => onColor(primary);

  /// 次级色块 / 选中底色上的文字色。
  Color get onSoft => onColor(primarySoft);

  /// 从一个种子色推导整套色板 —— Material You 的做法，FlClash 的主题就是这么来的。
  ///
  /// 为什么换掉原来那七份手写色板：每加一套主题都要人工配 17 个色值，还得逐个校对
  /// 对比度（`test/palette_contrast_test.dart` 拦的就是漏配的那几个）。走
  /// [ColorScheme.fromSeed] 之后，给一个种子色，M3 会按 HCT 色轮推出一整组
  /// 对比度达标的色（浅色/深色各一套），再加主题只要加一行种子色。
  ///
  /// 语义色（success / danger / warning）M3 不管，仍是固定色，但会 [harmonize]
  /// 到种子色 —— 否则紫主题里跳出一个正绿，整页看着就脏。
  factory AppPalette.fromSeed(
    Color seed, {
    required bool dark,
    bool pureBlack = false,
  }) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: dark ? Brightness.dark : Brightness.light,
    );
    final AppPalette palette = AppPalette(
      primary: scheme.primary,
      primarySoft: scheme.primaryContainer,
      success: harmonize(const Color(0xFF0F9B6C), seed),
      danger: harmonize(const Color(0xFFE94560), seed),
      warning: harmonize(const Color(0xFFF5A623), seed),
      // M3 里 surface(浅色 tone 98 / 深色 tone 6) 是页面底，
      // surfaceContainerLow 才是卡片底 —— 卡片比页面底低两档，
      // 「白卡浮在白底上」这件事在 Material You 里是靠这个层级表达的。
      bg: scheme.surface,
      surface: scheme.surfaceContainerLow,
      surfaceSoft: scheme.surfaceContainerHigh,
      text: scheme.onSurface,
      textSecondary: scheme.onSurfaceVariant,
      // M3 只有两档文字色（onSurface / onSurfaceVariant），第三档得自己找：
      // outline(tone50) 对 surface 只有 3.96:1 不够，所以取 onSurfaceVariant(tone30)
      // 与 outline 的中点（约 tone40）—— 浅深两色下都落在 5:1 上下。
      textTertiary: Color.lerp(scheme.onSurfaceVariant, scheme.outline, 0.5)!,
      border: scheme.outlineVariant,
      sider: scheme.surfaceContainer,
      siderSelected: scheme.secondaryContainer,
      segmentedSelected: scheme.surfaceContainerHighest,
      surfaceGlass: scheme.surfaceContainerLow.withValues(alpha: 0.82),
      surfaceSoftGlass: scheme.surfaceContainerHigh.withValues(alpha: 0.70),
    );
    return pureBlack ? palette.toPureBlack() : palette;
  }

  /// 纯黑模式：只压「底」，不动「墨」。
  ///
  /// AMOLED 上纯黑像素不发光（省电、黑边更利落），但把文字和主色也一起压暗
  /// 会让对比度塌掉 —— 所以只换 bg / surface / surfaceSoft / sider 这几层底。
  AppPalette toPureBlack() => copyWith(
        bg: const Color(0xFF000000),
        surface: const Color(0xFF0B0B0B),
        surfaceSoft: const Color(0xFF141414),
        sider: const Color(0xFF080808),
        segmentedSelected: const Color(0xFF1C1C1C),
        border: const Color(0xFF262626),
        surfaceGlass: const Color(0x1A000000),
        surfaceSoftGlass: const Color(0x1F0B0B0B),
      );

  /// 把 [target] 的色相往 [source] 的色相上拉一半。
  ///
  /// material_color_utilities 的 HarmonizedColor 只能在 HCT 上算，这里用 HSL 顶上。
  /// **只拉一半**：全拉的话黄主题下的 success 会变成黄绿、紫主题下的 danger 变成紫，
  /// 「绿=好、红=坏」的语义就没了；拉一半既让整页色调统一，又保住那点直觉。
  static Color harmonize(Color target, Color source) {
    final HSLColor t = HSLColor.fromColor(target);
    final HSLColor s = HSLColor.fromColor(source);
    // 最短角差（色相是环，179° 和 -179° 其实差 2°）
    final double delta = ((s.hue - t.hue + 540) % 360) - 180;
    if (delta.abs() < 12) return target;
    double hue = t.hue + delta * 0.5;
    if (hue < 0) hue += 360;
    if (hue >= 360) hue -= 360;
    return t.withHue(hue).toColor();
  }


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

/// 一个主题预设 = 一个种子色。
///
/// 色板不存了 —— 它由 [AppPalette.fromSeed] 现推，深色浅色各推一份。
class AppThemePreset {
  const AppThemePreset({
    required this.id,
    required this.name,
    required this.description,
    required this.seed,
  });

  final ThemeId id;

  /// 设置页显示的名字
  final String name;

  /// 设置页显示的一句话说明
  final String description;

  /// 种子色：整套 17 色都从它推出来
  final Color seed;
}

/// 明暗偏好 —— 与「哪个主题」是两件独立的事。
///
/// 跟着系统走是本机行为（`ThemeMode.system`），所以「跟随系统」只是亮度的一档，
/// 不是第七个主题。
enum ThemeBrightness { light, dark, system }

/// 七个种子色 —— 与 FlClash 的预设主色用的是同一套。
///
/// 主题列表只存种子色，色板现推（[paletteOf]）；推导结果有缓存，
/// `ColorScheme.fromSeed` 要跑一遍 HCT 量化，而主题 × 明暗一共就 14 种。
abstract final class AppTheme {
  static const ThemeId defaultThemeId = ThemeId.rose;

  /// 主题选择存在本机（每台设备各选各的，不跨设备同步）
  static const String storageKey = 'sekainook_theme';

  /// 明暗偏好（浅色 / 深色 / 跟随系统）同样存本机
  static const String brightnessKey = 'sekainook_theme_brightness';
  /// 纯黑模式（只深色有效）：把页面底压到 0 tone。
  static const String pureBlackKey = 'theme_pure_black';

  /// 正文字号缩放，0.8 ~ 1.4。
  static const String textScaleKey = 'theme_text_scale';

  /// 是否跟随壁纸主色（Android 12+ 的 Material You）。
  static const String followWallpaperKey = 'theme_follow_wallpaper';

  static const List<AppThemePreset> all = <AppThemePreset>[
    AppThemePreset(
      id: ThemeId.rose,
      name: '玫瑰粉',
      description: '柔和灰玫瑰，出厂默认',
      seed: Color(0xFFD8C0C3),
    ),
    AppThemePreset(
      id: ThemeId.brown,
      name: '暖棕',
      description: '木质褐，安静耐看',
      seed: Color(0xFF795548),
    ),
    AppThemePreset(
      id: ThemeId.blue,
      name: '晴空蓝',
      description: '清澈的天蓝',
      seed: Color(0xFF03A9F4),
    ),
    AppThemePreset(
      id: ThemeId.yellow,
      name: '柠檬黄',
      description: '明亮的黄，白天看着精神',
      seed: Color(0xFFFFFF00),
    ),
    AppThemePreset(
      id: ThemeId.grayblue,
      name: '雾灰蓝',
      description: '低饱和灰蓝，不抢眼',
      seed: Color(0xFFBBC9CC),
    ),
    AppThemePreset(
      id: ThemeId.green,
      name: '抹茶绿',
      description: '清淡的草绿',
      seed: Color(0xFFABD397),
    ),
    AppThemePreset(
      id: ThemeId.purple,
      name: '藤紫',
      description: '灰调紫，晚上看不刺眼',
      seed: Color(0xFF665390),
    ),
  ];

  static AppThemePreset preset(ThemeId id) {
    for (final AppThemePreset item in all) {
      if (item.id == id) return item;
    }
    return all.first;
  }

  static final Map<String, AppPalette> _palettes = <String, AppPalette>{};

  /// 某个主题 + 某个明暗下的一整套色（带缓存）
  static AppPalette paletteOf(
    ThemeId id, {
    required bool dark,
    bool pureBlack = false,
    Color? dynamicSeed,
  }) =>
      _palettes.putIfAbsent(
        '${id.name}-$dark-$pureBlack-${dynamicSeed?.hashCode}',
        () => AppPalette.fromSeed(
          dynamicSeed ?? preset(id).seed,
          dark: dark,
          pureBlack: pureBlack,
        ),
      );

  /// 设置页色板卡的三块颜色（浅色版推导出的 底 / 卡片 / 主色）。
  /// 手写会和推导公式漂移，所以现算。
  static List<Color> swatchOf(ThemeId id) {
    final AppPalette light = paletteOf(id, dark: false);
    return <Color>[light.bg, light.surface, light.primary];
  }

  static ThemeData build(
    ThemeId id, {
    required bool dark,
    bool hasBackground = false,
    bool pureBlack = false,
    double textScale = 1,
    Color? dynamicSeed,
  }) {
    final p = paletteOf(id, dark: dark, pureBlack: pureBlack, dynamicSeed: dynamicSeed);
    final Brightness brightness = dark ? Brightness.dark : Brightness.light;

    // 种子用**原始**种子色而不是 p.primary —— p.primary 本身就是推出来的，
    // 拿它当种子再推一次会把色相又挪一点（推两次 ≠ 推一次）。
    final scheme = ColorScheme.fromSeed(
      seedColor: preset(id).seed,
      brightness: brightness,
    ).copyWith(
      // ColorScheme.fromSeed 只会按种子色推出整套容器色，与 palette 里的色值、
      // 尤其是「哪个字配哪个底」无关。这里把容器色与 on* 全部按 palette 收口，
      // 否则 Chip / SegmentedButton / NavigationBar 指示器等组件会拿到一套
      // 和页面底色打架的配色（就是「字和背景糊在一起」的来源）。
      primary: p.primary,
      onPrimary: p.onPrimary,
      primaryContainer: p.primarySoft,
      onPrimaryContainer: p.onSoft,
      secondary: p.primary,
      onSecondary: p.onPrimary,
      secondaryContainer: p.primarySoft,
      onSecondaryContainer: p.onSoft,
      tertiary: p.success,
      onTertiary: p.onColor(p.success),
      tertiaryContainer: p.softColor(hasBackground: hasBackground),
      onTertiaryContainer: p.text,
      error: p.danger,
      onError: p.onColor(p.danger),
      errorContainer: p.softColor(hasBackground: hasBackground),
      onErrorContainer: p.danger,
      surface: p.cardColor(hasBackground: hasBackground),
      onSurface: p.text,
      surfaceContainerLowest: p.cardColor(hasBackground: hasBackground),
      surfaceContainerLow: p.cardColor(hasBackground: hasBackground),
      surfaceContainer: p.cardColor(hasBackground: hasBackground),
      surfaceContainerHigh: p.softColor(hasBackground: hasBackground),
      surfaceContainerHighest: p.segmentedSelected,
      onSurfaceVariant: p.textSecondary,
      outline: p.border,
      outlineVariant: p.border,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: p.text,
      onInverseSurface: p.bg,
      inversePrimary: p.primarySoft,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: hasBackground ? Colors.transparent : p.bg,
      canvasColor: p.cardColor(hasBackground: hasBackground),
      dividerColor: p.border,
      // 全站去水波纹：点击反馈交给按压缩放（motion/press_scale.dart）。
      // FlClash 也是这么做的 —— 水波纹与缩放叠加会显得脏，二选一时选形变。
      splashFactory: NoSplash.splashFactory,
    );

    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[p],
      // 字号缩放走 MediaQuery.textScaler（见 app.dart 的 builder）：
      // 只乘文字、不乘尺寸，全站所有 `fontSize: AppFontSize.*` 的裸文字也一起生效。
      // 这里绝不能再用 `textTheme.apply(fontSizeFactor:)` —— 两套一起开会双倍放大，
      // 且 textTheme 外的硬编码字号不受它影响（旧实现的实际问题）。
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
        shape: AppShape.card(p.border),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.cardColor(hasBackground: hasBackground),
        surfaceTintColor: Colors.transparent,
        shape: AppShape.sheet(),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.cardColor(hasBackground: hasBackground),
        surfaceTintColor: Colors.transparent,
        shape: AppShape.dialog(),
      ),
      // 输入框也走超椭圆：InputBorder 得自己实现（见 app_shape.dart 的 AppInputBorder）
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.softColor(hasBackground: hasBackground),
        border: AppInputBorder(borderSide: BorderSide(color: p.border)),
        enabledBorder: AppInputBorder(borderSide: BorderSide(color: p.border)),
        focusedBorder: AppInputBorder(borderSide: BorderSide(color: p.primary, width: 1.5)),
        hintStyle: TextStyle(color: p.textTertiary),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? p.surfaceSoft : const Color(0xFF303030),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: AppFontSize.sm),
        behavior: SnackBarBehavior.floating,
        shape: AppShape.all(AppRadius.md),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.primary,
        linearTrackColor: p.softColor(hasBackground: hasBackground),
        circularTrackColor: p.softColor(hasBackground: hasBackground),
      ),
      // 下面这些组件的默认配色来自 ColorScheme.fromSeed，会和 palette 撞色；
      // 一律显式收口到 palette + onColor。
      chipTheme: ChipThemeData(
        backgroundColor: p.softColor(hasBackground: hasBackground),
        selectedColor: p.primarySoft,
        secondarySelectedColor: p.primarySoft,
        labelStyle: TextStyle(color: p.text, fontSize: AppFontSize.sm),
        secondaryLabelStyle: TextStyle(color: p.onSoft, fontSize: AppFontSize.sm),
        side: BorderSide(color: p.border),
        shape: AppShape.all(AppRadius.sm),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? p.onSoft : p.textSecondary,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? p.primarySoft : Colors.transparent,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: p.border)),
          shape: WidgetStatePropertyAll<OutlinedBorder>(AppShape.all(AppRadius.sm)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          disabledBackgroundColor: p.softColor(hasBackground: hasBackground),
          disabledForegroundColor: p.textTertiary,
          shape: AppShape.pill(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.primary,
          side: BorderSide(color: p.border),
          shape: AppShape.pill(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.primary,
          shape: AppShape.pill(),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        shape: AppShape.all(AppRadius.lg),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.cardColor(hasBackground: hasBackground),
        textStyle: TextStyle(color: p.text, fontSize: AppFontSize.sm),
        shape: AppShape.all(AppRadius.lg),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: ShapeDecoration(
          color: p.text,
          shape: AppShape.all(AppRadius.sm),
        ),
        textStyle: TextStyle(color: p.bg, fontSize: AppFontSize.xs),
      ),
      listTileTheme: ListTileThemeData(textColor: p.text, iconColor: p.textSecondary),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.cardColor(hasBackground: hasBackground),
        indicatorColor: p.primarySoft,
        surfaceTintColor: Colors.transparent,
        indicatorShape: AppShape.pill(),
      ),
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
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppTheme.paletteOf(AppTheme.defaultThemeId, dark: false);
}
