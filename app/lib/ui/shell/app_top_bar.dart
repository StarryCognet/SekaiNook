import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../state/notification_state.dart';
import '../../state/theme_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import '../../theme/tokens.dart';
import '../widgets/motion/press_scale.dart';

/// 顶栏左侧那颗胶囊里的「当前页小图标 + 页面名」。
///
/// 手机优先，所以不做 PC 端那条面包屑（`/home / 家庭账本 / …`），只显示脚下这一格。
/// 图标借的是**底部 Tab 那颗**（与 Web 版 `renderIcon(activeNavItem, true)` 同一口径）
/// —— 顶栏和底栏指着同一格，看着才是一套；通知页不是 Tab，就用「首页」那颗。
class AppTopBarPage {
  const AppTopBarPage({required this.label, required this.icon});

  final String label;
  final IconData icon;

  static const AppTopBarPage home = AppTopBarPage(label: '首页', icon: Icons.home_outlined);
  static const AppTopBarPage notifications =
      AppTopBarPage(label: '通知', icon: Icons.notifications_outlined);
  static const AppTopBarPage family =
      AppTopBarPage(label: '家庭账本', icon: Icons.receipt_long_outlined);
  static const AppTopBarPage plan =
      AppTopBarPage(label: '学习计划', icon: Icons.calendar_month_outlined);
  static const AppTopBarPage garden =
      AppTopBarPage(label: '阳光花园', icon: Icons.local_florist_outlined);
  static const AppTopBarPage settings =
      AppTopBarPage(label: '设置', icon: Icons.settings_outlined);

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
/// 左边：一颗「当前页小图标 + 页面名」的胶囊（手机优先，不做 PC 端的面包屑）；
/// 右边两件：通知铃铛（带未读角标，点进 `/home/notifications`）与太阳/月亮两段式
/// 深浅开关 —— 点哪一档就切到「上次用过的那一档深浅」，与设置页那颗按钮共用同一份
/// 记忆（见 [ThemeState.toggleBrightness]）。PC 端那颗「余额/积分小胶囊」不做：
/// 手机端首页与账本本来就有更大的余额卡，顶栏再塞会把页面名挤没。
///
/// 形态与 [AppNavBar] 同一套语言：整条是浮在页面之上的圆角胶囊（两侧留白 + 柔和
/// 落影），不是顶到屏幕边缘的横杠。**不透明、没有毛玻璃** —— 1.31.6 试过卡片模糊，
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
    this.onNotifications,
    this.onToggleBrightness,
  });

  /// 左边胶囊里显示的页面名与图标
  final AppTopBarPage page;

  /// 未读通知数，> 0 时在铃铛右上角挂角标
  final int unread;

  /// 用户设了自定义背景图时用半透明玻璃底，让照片透出来
  final bool hasBackground;

  final VoidCallback? onNotifications;

  /// 点「另一档」深浅时调一次（点当前这一档不动）—— 由外壳接到
  /// [ThemeState.toggleBrightness]
  final VoidCallback? onToggleBrightness;

  // ---- 几何（跟 AppNavBar 一样公开：外壳与测试要拿它算高度） ----

  /// 条内可用高度（不含上下留白）
  static const double innerHeight = 52;

  /// 与屏幕两侧 / 状态栏下方的留白 —— 让它浮起来，而不是贴住边框
  static const double edgeMargin = AppSpacing.md;
  static const double topMargin = AppSpacing.sm;

  /// 胶囊内壁留白
  static const double barPadding = 6;

  /// 右边小件的点按区域
  static const double chipHeight = 40;
  static const double chipWidth = 40;

  /// 页码块（`primarySoft` 小方块）与它里面那颗图标
  static const double pageIconSize = 28;
  static const double pageIconGlyph = 16;

  /// 条内图标（铃铛）的大小
  static const double glyph = 20;

  /// 条自身高度（**不含**状态栏那一截）—— 顶栏与外壳共用这一份，
  /// 两处各写一遍的话迟早写歪（写歪了就是溢出或留白）。
  static const Size preferredBarSize = Size.fromHeight(innerHeight + topMargin);

  @override
  Size get preferredSize => preferredBarSize;

  /// 胶囊落影 —— 数值与 [AppNavBar] 里那份一致（那边是私有的，借不过来），
  /// 让上下两条悬浮胶囊看着是一套东西。颜色取自 `colorScheme.shadow`（主题里是黑），
  /// 不写字面量。
  static List<BoxShadow> _shadows(BuildContext context) {
    final Color shadow = Theme.of(context).colorScheme.shadow;
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return <BoxShadow>[
      BoxShadow(
        color: shadow.withValues(alpha: dark ? 0.34 : 0.10),
        blurRadius: 20,
        spreadRadius: -2,
        offset: const Offset(0, 6),
      ),
      BoxShadow(
        color: shadow.withValues(alpha: dark ? 0.22 : 0.05),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // 「当前是哪一档」直接看真实主题，不看 store：两处万一差一帧，也宁可跟画面对齐。
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final bool reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    // 挂在 `Scaffold.appBar` 上时高度由 preferredSize 给（不含状态栏），
    // 状态栏那一条由这里自己让 —— 这样参数里不用再传 MediaQuery.padding。
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(edgeMargin, topMargin, edgeMargin, 0),
        child: SizedBox(
          height: innerHeight,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: palette.cardColor(hasBackground: hasBackground),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              shadows: _shadows(context),
            ),
            child: Padding(
              padding: const EdgeInsets.all(barPadding),
              child: Row(
                children: <Widget>[
                  Expanded(child: _PageChip(page: page)),
                  const SizedBox(width: AppSpacing.sm),
                  _BellChip(unread: unread, onTap: onNotifications),
                  const SizedBox(width: AppSpacing.xs),
                  _BrightnessSwitch(
                    dark: dark,
                    reduceMotion: reduceMotion,
                    onToggle: onToggleBrightness,
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

/// 左边那颗胶囊：页码块 + 页面名。纯展示，不可点。
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
          Container(
            width: AppTopBar.pageIconSize,
            height: AppTopBar.pageIconSize,
            decoration: BoxDecoration(
              // 与底栏选中项同一个色（底栏选中是 primarySoft 底 + onSoft 前景）
              color: palette.primarySoft,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              page.icon,
              size: AppTopBar.pageIconGlyph,
              color: palette.onSoft,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              page.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppFontSize.sm,
                fontWeight: FontWeight.w600,
                color: palette.text,
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
    final Icon icon = Icon(
      Icons.notifications_outlined,
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
        child: PressInkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.full),
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

/// 太阳 / 月亮两段式深浅开关（对应 Web 版的 `brightnessSwitch`）。
///
/// 滑块托着**当前这一档**，点另一档才切 —— 与 `ThemeState.toggleBrightness` 的
/// 语义一致：切到「上次用过的那一档深浅」，所以点当前这一档什么也不会发生。
class _BrightnessSwitch extends StatelessWidget {
  const _BrightnessSwitch({
    required this.dark,
    required this.reduceMotion,
    required this.onToggle,
  });

  final bool dark;
  final bool reduceMotion;
  final VoidCallback? onToggle;

  /// 一档的边长（滑块与图标槽同宽，滑块才能正好坐满一格）
  static const double optionSize = 32;

  /// 轨道内壁留白
  static const double trackPadding = 3;

  static const double glyph = 18;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(trackPadding),
        decoration: BoxDecoration(
          // 与底栏选中项同一个底：深色主题下是蓝，浅色主题下是「深蓝主色」
          color: palette.primarySoft,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: SizedBox(
          width: optionSize * 2,
          height: optionSize,
          child: Stack(
            children: <Widget>[
              // 滑块：托着当前这一档，带一点过冲滑过去（跟手但不弹飞）
              AnimatedAlign(
                alignment: dark ? Alignment.centerRight : Alignment.centerLeft,
                duration: reduceMotion ? Duration.zero : AppMotion.normal,
                curve: AppMotion.overshoot,
                child: Container(
                  width: optionSize,
                  height: optionSize,
                  decoration: BoxDecoration(
                    // 滑块就是「分段控件选中项底」那一档颜色：不透明，压住轨道 ——
                    // 半透明的话轨道会透上来，压在上面的图标就没对比度了
                    color: palette.segmentedSelected,
                    shape: BoxShape.circle,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Theme.of(context)
                            .colorScheme
                            .shadow
                            .withValues(alpha: dark ? 0.34 : 0.10),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  _BrightnessOption(
                    icon: Icons.light_mode_outlined,
                    label: '切到浅色主题',
                    hint: '浅色',
                    current: !dark,
                    // 已经在浅色就别再切一次（否则会把用户弹回深色）
                    onTap: dark ? onToggle : null,
                  ),
                  _BrightnessOption(
                    icon: Icons.dark_mode_outlined,
                    label: '切到深色主题',
                    hint: '深色',
                    current: dark,
                    onTap: dark ? null : onToggle,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 深浅开关里的一档：图标 + 语义 + tooltip，点它 = 切到这一档。
class _BrightnessOption extends StatelessWidget {
  const _BrightnessOption({
    required this.icon,
    required this.label,
    required this.hint,
    required this.current,
    required this.onTap,
  });

  final IconData icon;

  /// 读屏念的完整说法（「切到浅色主题」）
  final String label;

  /// 长按浮出来的短语（「浅色」）
  final String hint;

  /// 是不是当前这一档
  final bool current;

  /// 为空 = 已经在这一档，点了不动
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      selected: current,
      label: label,
      onTap: onTap,
      child: Tooltip(
        message: hint,
        excludeFromSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: _BrightnessSwitch.optionSize,
            height: _BrightnessSwitch.optionSize,
            // 当前这一档压在滑块（分段选中底）上 → 用它自己的合规前景色；
            // 另一档压在轨道（primarySoft）上 → 用 `onSoft`（就是 `onColor(primarySoft)`）。
            // 两档各取自己背景的合规前景色，不靠调透明度凑对比 ——
            // 这两组都在 `test/palette_contrast_test.dart` 的射程里。
            child: Icon(
              icon,
              size: _BrightnessSwitch.glyph,
              color: current ? palette.onColor(palette.segmentedSelected) : palette.onSoft,
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
  const AppTopBarHost({super.key, required this.location});

  /// 当前 location（`GoRouterState.of(context).uri.toString()`），页面名与图标按它推
  final String location;

  @override
  Size get preferredSize => AppTopBar.preferredBarSize;

  @override
  Widget build(BuildContext context) {
    final unread = context.select<NotificationState, int>((state) => state.unreadCount);
    final hasBackground = context.select<ThemeState, bool>(
      (ThemeState state) => state.background.isNotEmpty,
    );
    return AppTopBar(
      page: AppTopBarPage.of(location),
      unread: unread,
      hasBackground: hasBackground,
      onNotifications: () => context.go('/home/notifications'),
      onToggleBrightness: () => unawaited(context.read<ThemeState>().toggleBrightness()),
    );
  }
}
