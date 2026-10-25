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
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;

  /// 弹层：对话框、底部弹层的顶部圆角（M3 里弹层比卡片更圆）
  static const double xxl = 28;

  /// 胶囊（导航选中项、标签、按钮）。用 `BorderRadius.circular(AppRadius.full)` 时
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

/// 组件尺寸 —— 图标块 / 圆形底座 / 触控区这类**方形边长**。
///
/// 只收「多处同构、且不属于字号」的尺寸（以前散落着 32/36/40/44/48 一堆字面量，
/// 同一页里 6 处 44×44 圆角块各写各的）。间距仍走 [AppSpacing]，字号仍走
/// [AppFontSize] —— 别拿字号当图标尺寸用。
abstract final class AppSize {
  /// 统计卡左上角的图标块（32×32，圆角矩形）
  static const double iconTile = 32;

  /// 列表行里的图标块 / 勋章图标（36×36，圆角矩形）
  static const double iconBadge = 36;

  /// 圆形图标底座（44×44，头像框 / 植物 / 装饰）
  static const double iconCircle = 44;

  /// 大圆底（48×48，奖励页顶部那颗）
  static const double iconCircleLg = 48;

  /// 勾选钮这类小触控区（40×40）
  static const double touchTarget = 40;

  /// 行内小图标（14，跟 [AppFontSize.xs] 的正文对齐）
  static const double glyphXs = 14;
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
