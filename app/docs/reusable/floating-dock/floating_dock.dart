import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'spring_utils.dart';

/// 悬浮式底部导航（FlClash `NavigationDock` 风格）—— 复制即用，零项目依赖。
///
/// 交互主线（三条，缺一条就不「Q 弹」了）：
/// 1. 按下 → 透镜（选中高亮）跳到该格并放大，整条轻微膨胀；
/// 2. 拖动 → 透镜**保留速度**地跟手，拖到条外整条被橡皮筋拽动，每换一格震一下；
/// 3. 松手 → 落到最近格（带过冲回弹）、轻震、回调 [FloatingDock.onSelected]。
///
/// 三条实现约定（改之前先读 README 的「坑」一节）：
/// - 整条只有一个 [Listener] 提交选中；格子本身**不要**再挂 `GestureDetector`/
///   `InkWell`，否则一次点击会提交两次，也会把透镜的起手拖慢；
/// - 透镜位置用 [SpringDriver]（保留速度的弹簧），不用 `AnimationController`；
/// - `MediaQuery.disableAnimations` 打开时全部直接落位。
///
/// 需要 Flutter 3.27+（用到 `Color.withValues` 与 `ColorScheme.surfaceContainer`；
/// 要兼容更老的版本就把 `withValues(alpha: x)` 换成 `withOpacity(x)`，
/// 把 `surfaceContainer` 换成 `surfaceVariant`）。
class FloatingDock extends StatefulWidget {
  const FloatingDock({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.style = const DockStyle(),
  });

  final List<DockDestination> destinations;
  final int selectedIndex;

  /// 选中某一格时回调（只在真的换了格时触发一次）。
  final ValueChanged<int> onSelected;

  final DockStyle style;

  /// 悬浮条会遮住内容多少高度 —— 用 `Scaffold(extendBody: true)` 让内容穿到
  /// 条下面时，把它加到列表底部留白里，否则最后一条会被压住。
  static double reservedHeight(BuildContext context, {DockStyle style = const DockStyle()}) {
    final double inset = style.handleSystemInset ? MediaQuery.paddingOf(context).bottom : 0;
    return style.height + style.barPadding * 2 + style.bottomMargin + inset;
  }

  @override
  State<FloatingDock> createState() => _FloatingDockState();
}

/// 一个 Tab 的图标、文案与角标。
@immutable
class DockDestination {
  const DockDestination({
    required this.icon,
    IconData? selectedIcon,
    required this.label,
    this.badge = 0,
  }) : selectedIcon = selectedIcon ?? icon;

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// > 0 时在图标右上角挂一个角标（未读通知 / 待审批）。
  final int badge;
}

/// 观感参数。颜色留 `null` 时按当前 `ThemeData.colorScheme` 取，所以大多数项目
/// 只要写 `FloatingDock(...)` 就够了。
@immutable
class DockStyle {
  const DockStyle({
    this.background,
    this.indicatorColor,
    this.selectedForeground,
    this.idleForeground,
    this.badgeColor,
    this.badgeTextColor,
    this.height = 58,
    this.barPadding = 4,
    this.edgeMargin = 16,
    this.bottomMargin = 8,
    this.iconSize = 24,
    this.labelSize = 12,
    this.showLabels = true,
    this.showShadow = true,
    this.haptics = true,
    this.handleSystemInset = true,
  });

  /// 条的底色。默认 `colorScheme.surfaceContainer`；页面有自定义背景图、想让
  /// 照片透出来时传半透明色（`surface.withValues(alpha: 0.82)`）。
  final Color? background;

  /// 透镜（选中高亮）底色。默认 `colorScheme.secondaryContainer`。
  final Color? indicatorColor;

  /// 选中格的图标与文字色。默认 `colorScheme.onSecondaryContainer`
  /// —— 它跟 [indicatorColor] 是一对，别拿中性灰去配彩色底。
  final Color? selectedForeground;

  /// 未选中格的图标与文字色。默认 `colorScheme.onSurfaceVariant`。
  final Color? idleForeground;

  /// 角标底色 / 字色。默认 `colorScheme.error` / 按底色算出的可读色。
  final Color? badgeColor;
  final Color? badgeTextColor;

  /// 条内高度（不含 [barPadding]）。
  final double height;
  final double barPadding;

  /// 与屏幕两侧的留白 —— 让它浮起来，而不是贴住边框。
  final double edgeMargin;

  /// 与屏幕底部的留白（会再加上系统手势条的安全区）。
  final double bottomMargin;

  final double iconSize;
  final double labelSize;
  final bool showLabels;
  final bool showShadow;

  /// 轻震动反馈（换格 `selectionClick`、落位 `lightImpact`）。桌面/Web 上是空操作。
  final bool haptics;

  /// 是否自己处理系统底部安全区。如果你在 `Scaffold` 外面已经套了 `SafeArea`，
  /// 设成 `false` 免得留白算两遍。
  final bool handleSystemInset;
}

/// 弹簧与果冻参数 —— 数值取自 FlClash，改之前先想清楚「手感」会怎么变。
abstract final class DockMotion {
  /// 选中图标弹一下的时长（配合 [popCurve]）。
  static const Duration itemPop = Duration(milliseconds: 240);

  /// 跟手：快到几乎无延迟、不过冲（bounce 0）。
  static final SpringDescription track =
      SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 120), bounce: 0);

  /// 按下：有明显回弹。
  static final SpringDescription press =
      SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 280), bounce: 0.2);

  /// 松手落位：Q 弹的主角。
  static final SpringDescription settle =
      SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 500), bounce: 0.32);

  /// 桌面 hover 用（本实现没接 hover，留着给需要的人）。
  static final SpringDescription hover =
      SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 260), bounce: 0.18);

  /// 给 `Curve` 槽位用的弹簧（自带过冲）。
  static final Curve popCurve = SpringCurve(stiffness: 500, damping: 28);

  /// 透镜随速度拉伸：达到该速度（px/s）就拉满 [jellyStretch]。
  static const double jellySpeed = 8;
  static const double jellyStretch = 0.25;

  /// 按下时透镜与外框一起「膨胀」的绝对幅度与上限比例。
  static const double lensGrowth = 14;
  static const double pressGrowth = 1 / 8;
  static const double maxPressGrowth = 16;

  /// 拖到条外时整条被橡皮筋拉动的极限（按条高算）。
  static const double pullLimit = 7 / 32;
}

class _FloatingDockState extends State<FloatingDock> with TickerProviderStateMixin {
  late final SpringDriver _lens;
  late final SpringDriver _lift;
  late final SpringDriver _stretch;
  late final Listenable _motion;

  /// 条内 Row 的宽度（指针坐标系原点固定是 [DockStyle.barPadding]）
  double _rowWidth = 1;

  int? _pressedIndex;
  bool _dragging = false;
  double _pressX = 0;
  bool _reduceMotion = false;

  double get _innerHeight => widget.style.height;
  double get _barPadding => widget.style.barPadding;
  double get _edgeMargin => widget.style.edgeMargin;

  @override
  void initState() {
    super.initState();
    _lens = SpringDriver(this, widget.selectedIndex.toDouble());
    _lift = SpringDriver(this, 0);
    _stretch = SpringDriver(this, 0);
    _motion = Listenable.merge(<Listenable>[_lens, _lift, _stretch]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 注意：不能在 initState 里读 MediaQuery（会断言失败），必须在这里。
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  @override
  void didUpdateWidget(covariant FloatingDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _springLens(widget.selectedIndex.toDouble(), DockMotion.settle);
    }
  }

  @override
  void dispose() {
    _lens.dispose();
    _lift.dispose();
    _stretch.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // 弹簧：开了「减少动态效果」就直接落位
  // ------------------------------------------------------------------

  void _springLens(double target, SpringDescription spring) {
    if (_reduceMotion) {
      _lens.jumpTo(target);
    } else {
      _lens.springTo(target, spring);
    }
  }

  void _spring(SpringDriver driver, double target, SpringDescription spring) {
    if (_reduceMotion) {
      driver.jumpTo(target);
    } else {
      driver.springTo(target, spring);
    }
  }

  void _haptic(VoidCallback feedback) {
    if (widget.style.haptics && !_reduceMotion) feedback();
  }

  // ------------------------------------------------------------------
  // 指针几何
  // ------------------------------------------------------------------

  double get _extent => _rowWidth / math.max(1, widget.destinations.length);

  /// 指针的 x 坐标 → 透镜位置（0 = 第一格中心，1 = 第二格中心 …）
  double _positionAt(double dx) {
    final double raw = (dx - _barPadding) / _extent - 0.5;
    final int last = widget.destinations.length - 1;
    return raw.clamp(0, math.max(0, last).toDouble());
  }

  int _indexAt(double position) =>
      position.round().clamp(0, math.max(0, widget.destinations.length - 1));

  /// 拖到条外时的橡皮筋阻力：越拖越沉，永远拉不出无限量。
  static double _rubberBand(double overshoot, double limit) {
    if (overshoot == 0 || limit <= 0) return 0;
    final double pull = 1 - 1 / (overshoot.abs() * 0.55 / limit + 1);
    return limit * pull * overshoot.sign;
  }

  // ------------------------------------------------------------------
  // 手势：按下 → 透镜跟手 → 松手落位
  // ------------------------------------------------------------------

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.destinations.isEmpty) return;
    final int index = _indexAt(_positionAt(event.localPosition.dx));
    _pressedIndex = index;
    _pressX = event.localPosition.dx;
    _dragging = false;
    _spring(_lift, 1, DockMotion.press);
    _springLens(index.toDouble(), DockMotion.settle);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_pressedIndex == null) return;
    final double dx = event.localPosition.dx;
    if (!_dragging) {
      // 过不了 kTouchSlop 就不算拖 —— 否则「点一下」也会被当成轻微拖动
      if ((dx - _pressX).abs() < kTouchSlop) return;
      _dragging = true;
    }
    // 手指跑到条外 → 整条被橡皮筋拽一下（Row 之外的都算溢出）
    final double overshoot = dx - dx.clamp(_barPadding, _barPadding + _rowWidth);
    _spring(_stretch, _rubberBand(overshoot, _innerHeight * DockMotion.pullLimit), DockMotion.track);
    final double position = _positionAt(dx);
    _springLens(position, DockMotion.track);
    final int index = _indexAt(position);
    if (index != _pressedIndex) {
      _haptic(HapticFeedback.selectionClick);
      _pressedIndex = index;
    }
  }

  void _handlePointerEnd(PointerEvent event) {
    final int? index = _pressedIndex;
    if (index == null) return;
    _pressedIndex = null;
    _dragging = false;
    _spring(_lift, 0, DockMotion.settle);
    _spring(_stretch, 0, DockMotion.track);
    _springLens(index.toDouble(), DockMotion.settle);
    if (index != widget.selectedIndex) {
      _haptic(HapticFeedback.lightImpact);
      widget.onSelected(index);
    }
  }

  // ------------------------------------------------------------------

  List<BoxShadow> _shadows() {
    if (!widget.style.showShadow) return const <BoxShadow>[];
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.34 : 0.10),
        blurRadius: 20,
        spreadRadius: -2,
        offset: const Offset(0, 6),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.22 : 0.05),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final DockStyle style = widget.style;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color background = style.background ?? scheme.surfaceContainer;
    final Color indicator = style.indicatorColor ?? scheme.secondaryContainer;
    final Color selectedForeground = style.selectedForeground ?? scheme.onSecondaryContainer;
    final Color idleForeground = style.idleForeground ?? scheme.onSurfaceVariant;
    final Color badgeColor = style.badgeColor ?? scheme.error;
    final Color badgeTextColor = style.badgeTextColor ?? readableOn(badgeColor);

    final int count = widget.destinations.length;
    // 条越宽，「按下膨胀」的绝对量要越小 —— 观感才一致
    final double longestSide = MediaQuery.sizeOf(context).width - _edgeMargin * 2;
    final double inset =
        style.handleSystemInset ? MediaQuery.paddingOf(context).bottom : 0;

    return Padding(
      padding: EdgeInsets.fromLTRB(_edgeMargin, 0, _edgeMargin, style.bottomMargin + inset),
      child: AnimatedBuilder(
        animation: _motion,
        builder: (BuildContext context, Widget? child) {
          // 按下：整条轻微膨胀；拖到条外：整条被拽走一点点
          final double swell =
              _lift.value * math.min(DockMotion.maxPressGrowth / longestSide, DockMotion.pressGrowth);
          return Transform.translate(
            offset: Offset(_stretch.value, 0),
            child: Transform.scale(scale: 1 + swell, child: child),
          );
        },
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: background,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            shadows: _shadows(),
          ),
          child: Material(
            color: Colors.transparent,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _handlePointerDown,
              onPointerMove: _handlePointerMove,
              onPointerUp: _handlePointerEnd,
              onPointerCancel: _handlePointerEnd,
              child: Padding(
                padding: EdgeInsets.all(_barPadding),
                child: SizedBox(
                  height: _innerHeight,
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints constraints) {
                      _rowWidth = constraints.maxWidth;
                      final double extent = _extent;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: <Widget>[
                          AnimatedBuilder(
                            animation: _lens,
                            builder: (BuildContext context, Widget? child) {
                              // 速度越快拉得越长、压得越扁 —— 果冻的来源
                              final double stretch =
                                  (_lens.velocity.abs() / DockMotion.jellySpeed).clamp(0.0, 1.0) *
                                      DockMotion.jellyStretch;
                              final double growth = DockMotion.lensGrowth * 2 * _lift.value;
                              final double width = (extent + growth) * (1 + stretch);
                              final double height = (_innerHeight + growth) * (1 - stretch / 2);
                              return Positioned(
                                left: (_lens.value + 0.5) * extent - width / 2,
                                top: (_innerHeight - height) / 2,
                                width: width,
                                height: height,
                                child: DecoratedBox(
                                  decoration: ShapeDecoration(
                                    color: indicator,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          Row(
                            children: <Widget>[
                              for (int i = 0; i < count; i++)
                                Expanded(
                                  child: _DockItem(
                                    destination: widget.destinations[i],
                                    selected: i == widget.selectedIndex,
                                    reduceMotion: _reduceMotion,
                                    iconSize: style.iconSize,
                                    labelSize: style.labelSize,
                                    showLabel: style.showLabels,
                                    foreground: i == widget.selectedIndex
                                        ? selectedForeground
                                        : idleForeground,
                                    badgeColor: badgeColor,
                                    badgeTextColor: badgeTextColor,
                                    onTap: () => widget.onSelected(i),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      );
                    },
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

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.destination,
    required this.selected,
    required this.reduceMotion,
    required this.iconSize,
    required this.labelSize,
    required this.showLabel,
    required this.foreground,
    required this.badgeColor,
    required this.badgeTextColor,
    required this.onTap,
  });

  final DockDestination destination;
  final bool selected;
  final bool reduceMotion;
  final double iconSize;
  final double labelSize;
  final bool showLabel;
  final Color foreground;
  final Color badgeColor;
  final Color badgeTextColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      // 图标与文字只是画出来的，语义由这里统一给（免得「首页 首页」念两遍，
      // 角标也能念出来）。`onTap` 让读屏用户也能激活。
      excludeSemantics: true,
      button: true,
      selected: selected,
      label: destination.badge > 0
          ? '${destination.label}，${destination.badge} 条未读'
          : destination.label,
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        // 选中 = 图标弹一下并微微上浮
        tween: Tween<double>(begin: 0, end: selected ? 1 : 0),
        duration: reduceMotion ? Duration.zero : DockMotion.itemPop,
        curve: DockMotion.popCurve,
        builder: (BuildContext context, double t, Widget? child) {
          return Transform.translate(
            offset: Offset(0, -1.5 * t),
            child: Transform.scale(scale: 1 + 0.14 * t, child: child),
          );
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _DockIcon(
              destination: destination,
              selected: selected,
              color: foreground,
              badgeColor: badgeColor,
              badgeTextColor: badgeTextColor,
              size: iconSize,
            ),
            if (showLabel) ...<Widget>[
              const SizedBox(height: 2),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: labelSize,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: foreground,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DockIcon extends StatelessWidget {
  const _DockIcon({
    required this.destination,
    required this.selected,
    required this.color,
    required this.badgeColor,
    required this.badgeTextColor,
    required this.size,
  });

  final DockDestination destination;
  final bool selected;
  final Color color;
  final Color badgeColor;
  final Color badgeTextColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Icon icon = Icon(
      selected ? destination.selectedIcon : destination.icon,
      size: size,
      color: color,
    );
    if (destination.badge <= 0) return icon;
    return Badge(
      backgroundColor: badgeColor,
      textColor: badgeTextColor,
      label: Text(
        destination.badge > 99 ? '99+' : '${destination.badge}',
        style: const TextStyle(fontSize: 10),
      ),
      child: icon,
    );
  }
}

/// 在任意底色上取一个看得清的前景色（浅底给深字、深底给亮字）。
///
/// 用在角标、彩色胶囊这类「底色是别人给的」场景；如果颜色来自你的主题，
/// 优先直接用主题里成对的 `onXxx` 色。
Color readableOn(Color background) {
  return background.computeLuminance() > 0.42
      ? Color.lerp(background, Colors.black, 0.86)!
      : Color.lerp(background, Colors.white, 0.92)!;
}
