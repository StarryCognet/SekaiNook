import 'package:sekainook_app/ui/icons/icons.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../state/notification_state.dart';
import '../../state/theme_state.dart';
import '../../theme/app_shape.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import '../../theme/tokens.dart';
import '../widgets/motion/elastic_press.dart';

/// 顶栏左侧那颗胶囊里的「当前页小图标 + 页面名」。
///
/// 手机优先，所以不做 PC 端那条面包屑（`/home / 家庭账本 / …`），只显示脚下这一格。
/// 图标借的是**底部 Tab 那颗**（与 Web 版 `renderIcon(activeNavItem, true)` 同一口径）
/// —— 顶栏和底栏指着同一格，看着才是一套；通知页不是 Tab，就用「首页」那颗。
class AppTopBarPage {
  const AppTopBarPage({required this.label, required this.icon});

  final String label;
  final Glyph icon;

  static const AppTopBarPage home = AppTopBarPage(label: '首页', icon: AppIcons.home);
  static const AppTopBarPage notifications =
      AppTopBarPage(label: '通知', icon: AppIcons.bell);
  static const AppTopBarPage family =
      AppTopBarPage(label: '任务', icon: AppIcons.checklist);
  static const AppTopBarPage plan =
      AppTopBarPage(label: '学习计划', icon: AppIcons.calendar);
  static const AppTopBarPage garden =
      AppTopBarPage(label: '阳光花园', icon: AppIcons.flower);
  static const AppTopBarPage settings =
      AppTopBarPage(label: '设置', icon: AppIcons.settings);

  /// 按当前 location 推页面名与图标（路由表见 `app/lib/router.dart`）。
  ///
  /// 判断顺序要紧：`/home/notifications` 必须先于 `/home`、`/family/plan` 先于
  /// `/family` —— 跟 `MainShell._indexForLocation` 是同一个先例坑。
  static AppTopBarPage of(String location) {
    if (location.startsWith('/home/notifications')) return notifications;
    if (location.startsWith('/family/plan')) return plan;
    if (location.startsWith('/family')) return family;
    if (location.startsWith('/garden')) return garden;
    if (location.startsWith('/settings')) return settings;
    return home;
  }
}

/// 全局顶栏 —— 对应 Web 版 `src/layouts/MainLayout.tsx:579-653` 的 Header。
///
/// 左边：页面图标 + 页面名（2.9.6 起不再衬色块，图标直接用主色）；
/// 右边两件：通知铃铛（带未读角标，点进 `/home/notifications`）与一颗**明暗单按钮**
/// —— 浅色 → 深色 → 跟随设备 循环，与设置页那三颗按钮共用同一份记忆
/// （见 [ThemeState.cycleBrightness]）。PC 端那颗「余额/积分小胶囊」不做：
/// 手机端首页与账本本来就有更大的余额卡，顶栏再塞会把页面名挤没。
///
/// 形态与 [AppNavBar] 同一套语言：整条是浮在页面之上的圆角胶囊（两侧留白 + 柔和
/// 落影），不是顶到屏幕边缘的横杠。**但不透明、没有毛玻璃** —— 1.31.6 试过卡片模糊，
/// 真机实测太卡、1.31.8 已整体回滚，这里不再引入 `BackdropFilter`；用户设了自定义
/// 背景图时底色走 [AppPalette.cardColor]（半透明玻璃底），与卡片、底栏一个口径。
/// 设置页的「底栏不透明度」只管底栏，顶栏不跟它变。
///
/// 纯展示组件：**不读 Provider**（接线在 [AppTopBarHost]）—— 这样它能在没有
/// Provider 的裸 pump 测试里跑。
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    required this.page,
    this.unread = 0,
    this.hasBackground = false,
    this.elevated = false,
    this.brightness = ThemeBrightness.system,
    this.onNotifications,
    this.onToggleBrightness,
  });

  /// 左边胶囊里显示的页面名与图标
  final AppTopBarPage page;

  /// 未读通知数，> 0 时在铃铛右上角挂角标
  final int unread;

  /// 用户设了自定义背景图时用半透明玻璃底，让照片透出来
  final bool hasBackground;

  /// 内容是否已经滚到顶栏下面。
  ///
  /// `false`（首屏）= 没有胶囊底、没有落影，页名直接浮在页面底色上；
  /// `true` = 淡入胶囊底与落影，内容和顶栏重新分开。由外壳监听页面滚动决定，
  /// 过渡交给 [AnimatedContainer]（[AppMotion.normal]）。设了背景图时始终为真
  /// —— 照片从底下过会把文字吃掉。
  final bool elevated;

  /// 当前明暗偏好（浅色 / 深色 / 跟随系统）—— 那颗单按钮按它决定画哪个图标、
  /// 以及点下去该切到哪一档。纯展示，取值与循环逻辑都在 [ThemeState]。
  final ThemeBrightness brightness;

  final VoidCallback? onNotifications;

  /// 点「明暗」那颗按钮时调一次：浅色 → 深色 → 跟随系统 → 浅色。
  /// 由外壳接到 [ThemeState.cycleBrightness]
  final VoidCallback? onToggleBrightness;

  // ---- 几何（跟 AppNavBar 一样公开：外壳与测试要拿它算高度） ----

  /// 条内可用高度（不含上下留白）。
  ///
  /// 2.9.7 定稿 48：2.9.6 试过收到 42，真机上太窄 —— 胶囊矮了一截、内容又贴着
  /// 屏幕边，看着不像一颗胶囊而像一条色带。48 高 + 18 的内壁，内容离屏幕边
  /// 正好 34dp（16 外边距 + 18 内壁），和「C 宽松」那版验证稿一致。
  static const double innerHeight = 48;

  /// 与屏幕两侧 / 状态栏下方的留白 —— 让它浮起来，而不是贴住边框
  static const double edgeMargin = AppSpacing.md;
  static const double topMargin = AppSpacing.sm;

  /// 胶囊内壁留白。48 - 2×6 = 36，正好是一个小件的点按区。
  static const double barPadding = 6;

  /// 胶囊内壁的左右留白 —— 比上下多一点，让「任务」两个字不贴胶囊边。
  ///
  /// 内容离屏幕边 = [edgeMargin] 16 + 这 18 = 34dp（2.9.6 是 16+3=19，太贴边）。
  static const double barHorizontalPadding = 18;

  /// 右边小件的点按区域
  static const double chipHeight = 36;
  static const double chipWidth = 36;

  /// 页面图标：不再垫 `primarySoft` 色块，图标直接用主色画，所以给到 19
  static const double pageIconGlyph = 19;

  /// 条内图标（铃铛 / 明暗）的大小
  static const double glyph = 19;

  /// 条自身高度（**不含**状态栏那一截）—— 顶栏与外壳共用这一份，
  /// 两处各写一遍的话迟早写歪（写歪了就是溢出或留白）。
  static const Size preferredBarSize = Size.fromHeight(innerHeight + topMargin);

  @override
  Size get preferredSize => preferredBarSize;

  /// 页面顶部要为悬浮顶栏让出的高度 —— 与 [AppNavBar.contentInset] 对称。
  ///
  /// 顶栏是浮在内容之上的一层（不再占 `Scaffold.appBar` 槽），内容从屏幕顶铺下来，
  /// 不让位的话首屏第一条会被胶囊压住。用 `viewPadding` 而不是 `padding`：
  /// 外壳会把 body 的 `padding.top` 抹掉（跟底栏那侧同一个道理），
  /// 只有 `viewPadding` 始终是屏幕自己的安全区原值。
  static double contentInset(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).top + topMargin + innerHeight + AppSpacing.sm;

  /// 胶囊落影 —— **只一层**。
  ///
  /// 以前叠了两层（blur 20 + blur 4），浅色底上会糊出一圈灰雾，看着发脏；
  /// 现在整条在「首屏透明 → 滚动浮现」之间切换，阴影跟着一起淡入淡出，
  /// 一层就够把胶囊从内容里托起来了。
  static List<BoxShadow> _shadows(BuildContext context) {
    final Color shadow = Theme.of(context).colorScheme.shadow;
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return <BoxShadow>[
      BoxShadow(
        color: shadow.withValues(alpha: dark ? 0.30 : 0.09),
        blurRadius: 10,
        spreadRadius: -2,
        offset: const Offset(0, 3),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bool reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    // 首屏不给底：页名直接浮在页面底色上，只有内容滚到顶栏下面时才淡入胶囊底。
    // 用户滚动时外壳把 [elevated] 置 true，动画由 AnimatedContainer 负责。
    final bool lifted = elevated || hasBackground;

    // 挂在 `Scaffold.appBar` 上时高度由 preferredSize 给（不含状态栏），
    // 状态栏那一条由这里自己让 —— 这样参数里不用再传 MediaQuery.padding。
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(edgeMargin, topMargin, edgeMargin, 0),
        child: SizedBox(
          height: innerHeight,
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : AppMotion.normal,
            curve: AppMotion.standard,
            decoration: ShapeDecoration(
              color: lifted
                  ? palette.cardColor(hasBackground: hasBackground)
                  : Colors.transparent,
              shape: AppShape.pill(),
              shadows: lifted ? _shadows(context) : const <BoxShadow>[],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: barHorizontalPadding,
                vertical: barPadding,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(child: _PageChip(page: page)),
                  const SizedBox(width: AppSpacing.sm),
                  _BellChip(unread: unread, onTap: onNotifications),
                  const SizedBox(width: AppSpacing.xs),
                  _BrightnessButton(
                    mode: brightness,
                    reduceMotion: reduceMotion,
                    onTap: onToggleBrightness,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 左边那颗胶囊：页面图标 + 页面名。纯展示，不可点。
///
/// 2.9.6 去掉了图标底下那块 28dp 的 `primarySoft` 方块 —— 它比文字还重，
/// 视线先落在方块上而不是页名。现在图标直接用主色画，和文字左对齐。
class _PageChip extends StatelessWidget {
  const _PageChip({required this.page});

  final AppTopBarPage page;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      container: true,
      // 图标与文字都只是画出来的，语义在这里一次给全（免得读屏念两遍）
      excludeSemantics: true,
      label: '当前页面：${page.label}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          GlyphIcon(
            page.icon,
            size: AppTopBar.pageIconGlyph,
            color: palette.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              page.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppFontSize.md,
                fontWeight: FontWeight.w600,
                color: palette.text,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 通知铃铛：未读时右上角挂角标，整块可点。
class _BellChip extends StatelessWidget {
  const _BellChip({required this.unread, required this.onTap});

  final int unread;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final Widget icon = GlyphIcon(
      AppIcons.bell,
      size: AppTopBar.glyph,
      color: palette.textSecondary,
    );
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: unread > 0 ? '通知，$unread 条未读' : '通知',
      onTap: onTap,
      child: Tooltip(
        message: '通知',
        // 语义已经由外面那条给了，别再念一遍
        excludeFromSemantics: true,
        child: ElasticPress(
          onTap: onTap,
          child: SizedBox(
            width: AppTopBar.chipWidth,
            height: AppTopBar.chipHeight,
            child: Center(
              child: unread > 0
                  ? Badge(
                      backgroundColor: palette.danger,
                      textColor: palette.onColor(palette.danger),
                      label: Text(
                        unread > 99 ? '99+' : '$unread',
                        style: const TextStyle(fontSize: 10),
                      ),
                      child: icon,
                    )
                  : icon,
            ),
          ),
        ),
      ),
    );
  }
}

/// 明暗**单按钮**：浅色 → 深色 → 跟随系统 → 浅色，点一下循环一格。
///
/// 2.9.6 之前是太阳 / 月亮两段式滑块：占了 68×38，顶栏右边挤，而且只能表达两档
/// —— 「跟随设备（系统）」这一档在设置页里有、顶栏却切不到。现在收成一颗 36dp
/// 的按钮，图标本身就是当前档：☀ 浅色 / ☾ 深色 / 📱 跟随设备；换档时图标带
/// 淡入 + 轻微旋转，看得出「切过去了」。
class _BrightnessButton extends StatelessWidget {
  const _BrightnessButton({
    required this.mode,
    required this.reduceMotion,
    required this.onTap,
  });

  final ThemeBrightness mode;
  final bool reduceMotion;
  final VoidCallback? onTap;

  static const double size = AppTopBar.chipWidth;

  /// 当前档位画哪个图标
  static Glyph iconOf(ThemeBrightness mode) => switch (mode) {
        ThemeBrightness.light => AppIcons.sun,
        ThemeBrightness.dark => AppIcons.moon,
        ThemeBrightness.system => AppIcons.devices,
      };

  /// 长按浮出来的短语
  static String hintOf(ThemeBrightness mode) => switch (mode) {
        ThemeBrightness.light => '浅色',
        ThemeBrightness.dark => '深色',
        ThemeBrightness.system => '跟随设备',
      };

  /// 读屏念的完整说法：告诉用户「现在是什么」+「点了会变成什么」
  static String labelOf(ThemeBrightness mode) => switch (mode) {
        ThemeBrightness.light => '当前浅色主题，点一下切到深色',
        ThemeBrightness.dark => '当前深色主题，点一下改为跟随设备',
        ThemeBrightness.system => '当前跟随设备，点一下切到浅色',
      };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: labelOf(mode),
      onTap: onTap,
      child: Tooltip(
        message: hintOf(mode),
        excludeFromSemantics: true,
        child: ElasticPress(
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              // 换档时旧图标淡出、新图标淡入并从一个角度转正 —— 三档之间切换
              // 只有 240ms，但足够把「变了」这件事说清楚。
              child: AnimatedSwitcher(
                duration: reduceMotion ? Duration.zero : AppMotion.normal,
                switchInCurve: AppMotion.decelerate,
                switchOutCurve: AppMotion.accelerate,
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: RotationTransition(
                      turns: Tween<double>(begin: -0.18, end: 0).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey<ThemeBrightness>(mode),
                  child: GlyphIcon(
                    iconOf(mode),
                    size: AppTopBar.glyph,
                    color: palette.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 把顶栏接上路由与两个 store 的那一层 —— 给 `MainShell` 用。
///
/// 分工和底栏一样：bar 自己只画、不读 Provider（那样它能裸 pump 起来测试），
/// Provider 与 go_router 的接线集中放在这里。
class AppTopBarHost extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBarHost({super.key, required this.location, this.elevated = false});

  /// 当前 location（`GoRouterState.of(context).uri.toString()`），页面名与图标按它推
  final String location;

  /// 页面内容是否已经滚到顶栏下面（由外壳监听滚动决定）。
  /// 为真时顶栏淡入胶囊底与落影；为假（首屏）时完全透明。
  final bool elevated;

  @override
  Size get preferredSize => AppTopBar.preferredBarSize;

  @override
  Widget build(BuildContext context) {
    final unread = context.select<NotificationState, int>((state) => state.unreadCount);
    final hasBackground = context.select<ThemeState, bool>(
      (ThemeState state) => state.background.isNotEmpty,
    );
    final brightness = context.select<ThemeState, ThemeBrightness>(
      (ThemeState state) => state.brightness,
    );
    return AppTopBar(
      page: AppTopBarPage.of(location),
      unread: unread,
      hasBackground: hasBackground,
      elevated: elevated,
      brightness: brightness,
      onNotifications: () => context.go('/home/notifications'),
      onToggleBrightness: () => unawaited(context.read<ThemeState>().cycleBrightness()),
    );
  }
}
