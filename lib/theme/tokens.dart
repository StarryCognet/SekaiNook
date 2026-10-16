import 'dart:ui' show FontFeature;

/// 设计令牌 —— 唯一数据源（对应 Web 版 `src/theme/tokens.ts`）。
///
/// 铁律：所有颜色 / 间距 / 圆角 / 阴影 / 字号必须从此处读取，禁止在组件里硬编码。
/// 颜色不在这里（颜色随主题变，见 `theme/app_theme.dart` 的 AppPalette）。
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

abstract final class AppRadius {
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 16;

  /// 胶囊（导航选中项、标签）。用 `BorderRadius.circular(AppRadius.full)` 时
  /// 半径超过高度一半会自动退化成胶囊，所以给一个足够大的数即可。
  static const double full = 999;
}

abstract final class AppFontSize {
  static const double xs = 12;
  static const double sm = 14;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;

  /// 余额大数字
  static const double num = 48;
}

abstract final class AppDuration {
  /// 页面切换淡入上滑
  static const Duration pageTransition = Duration(milliseconds: 260);

  /// 主题切换后的过渡
  static const Duration themeChange = Duration(milliseconds: 250);
}

/// 数字展示统一用等宽数字（对应 Web 版 `.num` 的 `tabular-nums`）。
///
/// 余额、积分、时间这类会跳动的数字如果不等宽，刷新时整行会左右抖。
const List<FontFeature> kTabularNumbers = <FontFeature>[FontFeature.tabularFigures()];
