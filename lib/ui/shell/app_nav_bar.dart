import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import '../../theme/tokens.dart';
import '../widgets/motion/spring_driver.dart';

/// 一个底部 Tab 的图标、文案与角标。
class AppNavDestination {
  const AppNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badge = 0,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// > 0 时在图标右上角挂一个角标（未读通知 / 待审批）。
  final int badge;
}

/// 底部导航 —— 参考 FlClash 的 NavigationDock：弹簧透镜（Q 弹）+ 跟手拖动 +
/// 按压缩放，整条以圆角胶囊悬浮在页面之上（两侧留白 + 柔和投影），不再是顶到
/// 屏幕边缘的横杠。
///
/// 与 FlClash 的差异（有意为之）：不做鼠标 hover 磁吸、不做透镜放大镜与着色层
/// （Web 上 `ImageFilter.blur` 太贵，Android 也没有 hover），指针交互只保留
/// 「按下 → 透镜跟手 → 松手落位」这条主线。
///
/// 无障碍：`MediaQuery.disableAnimations` 打开时全部直接落位（不弹）；每个 Tab 都
/// 带 `Semantics(button/selected/label)`，语义上仍可点击。
class AppNavBar extends StatefulWidget {
  const AppNavBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.hasBackground = false,
  });

  final List<AppNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// 用户设了自定义背景图时用半透明卡片底，让照片透出来。
  final bool hasBackground;

  @override
  State<AppNavBar> createState() => _AppNavBarState();
}

class _AppNavBarState extends State<AppNavBar> with TickerProviderStateMixin {
  /// 条内可用高度（不含自身 padding）
  static const double _innerHeight = 58;
  static const double _barPadding = 4;

  /// 与屏幕两侧的留白 —— 让它浮起来，而不是贴住边框
  static const double _edgeMargin = AppSpacing.md;
  static const double _bottomMargin = AppSpacing.sm;

  /// 透镜随速度拉伸（果冻感）的中心速度与最大拉伸比例
  static const double _jellySpeed = 8;
  static const double _jellyStretch = 0.25;

  /// 按下时透镜与外框一起「膨胀」的幅度
  static const double _lensGrowth = 14;
  static const double _pressGrowth = 1 / 8;
  static const double _maxPressGrowth = 16;

  /// 拖到条外时整条被橡皮筋拉动的极限（按条高算）
  static const double _pullLimit = 7 / 32;

  late final SpringDriver _lens;
  late final SpringDriver _lift;
  late final SpringDriver _stretch;
  late final Listenable _motion;

  /// 条内 Row 的宽度（指针坐标系原点固定是 [_barPadding]）
  double _rowWidth = 1;

  int? _pressedIndex;
  bool _dragging = false;
  double _pressX = 0;
  bool _reduceMotion = false;

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
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  @override
  void didUpdateWidget(covariant AppNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _springLens(widget.selectedIndex.toDouble(), AppMotion.springSettle);
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

  // ------------------------------------------------------------------
  // 指针几何
  // ------------------------------------------------------------------

  double get _extent => _rowWidth / math.max(1, widget.destinations.length);

  /// 指针的 x 坐标 → 透镜位置（0 = 第一格中心，1 = 第二格中心 …）
  double _positionAt(double dx) {
    final raw = (dx - _barPadding) / _extent - 0.5;
    final last = widget.destinations.length - 1;
    return raw.clamp(0, math.max(0, last).toDouble());
  }

  int _indexAt(double position) =>
      position.round().clamp(0, math.max(0, widget.destinations.length - 1));

  /// 拖到条外时的橡皮筋阻力：越拖越沉，永远拉不出无限量。
  static double _rubberBand(double overshoot, double limit) {
    if (overshoot == 0 || limit <= 0) return 0;
    final pull = 1 - 1 / (overshoot.abs() * 0.55 / limit + 1);
    return limit * pull * overshoot.sign;
  }

  // ------------------------------------------------------------------
  // 手势：按下 → 透镜跟手 → 松手落位
  // ------------------------------------------------------------------

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.destinations.isEmpty) return;
    final index = _indexAt(_positionAt(event.localPosition.dx));
    _pressedIndex = index;
    _pressX = event.localPosition.dx;
    _dragging = false;
    _spring(_lift, 1, AppMotion.springPress);
    _springLens(index.toDouble(), AppMotion.springSettle);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_pressedIndex == null) return;
    final dx = event.localPosition.dx;
    if (!_dragging) {
      if ((dx - _pressX).abs() < kTouchSlop) return;
      _dragging = true;
    }
    // 手指跑到条外 → 整条被橡皮筋拽一下（Row 之外的都算溢出）
    final overshoot = dx - dx.clamp(_barPadding, _barPadding + _rowWidth);
    _spring(
      _stretch,
      _rubberBand(overshoot, _innerHeight * _pullLimit),
      AppMotion.springTrack,
    );
    final position = _positionAt(dx);
    _springLens(position, AppMotion.springTrack);
    final index = _indexAt(position);
    if (index != _pressedIndex) {
      if (!_reduceMotion) HapticFeedback.selectionClick();
      _pressedIndex = index;
    }
  }

  void _handlePointerEnd(PointerEvent event) {
    final index = _pressedIndex;
    if (index == null) return;
    _pressedIndex = null;
    _dragging = false;
    _spring(_lift, 0, AppMotion.springSettle);
    _spring(_stretch, 0, AppMotion.springTrack);
    _springLens(index.toDouble(), AppMotion.springSettle);
    if (index != widget.selectedIndex) {
      if (!_reduceMotion) HapticFeedback.lightImpact();
      widget.onSelected(index);
    }
  }

  // ------------------------------------------------------------------

  List<BoxShadow> _shadows(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
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
    final palette = context.palette;
    final count = widget.destinations.length;
    // 条越宽，「按下膨胀」的绝对量要越小 —— 观感才一致
    final longestSide = MediaQuery.sizeOf(context).width - _edgeMargin * 2;

    return Padding(
      padding: const EdgeInsets.fromLTRB(_edgeMargin, 0, _edgeMargin, _bottomMargin),
      child: AnimatedBuilder(
        animation: _motion,
        builder: (BuildContext context, Widget? child) {
          // 按下：整条轻微膨胀；拖到条外：整条被拽走一点点
          final swell =
              _lift.value * math.min(_maxPressGrowth / longestSide, _pressGrowth);
          return Transform.translate(
            offset: Offset(_stretch.value, 0),
            child: Transform.scale(scale: 1 + swell, child: child),
          );
        },
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: palette.cardColor(hasBackground: widget.hasBackground),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            shadows: _shadows(context),
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
                padding: const EdgeInsets.all(_barPadding),
                child: SizedBox(
                  height: _innerHeight,
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints constraints) {
                      _rowWidth = constraints.maxWidth;
                      final extent = _extent;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: <Widget>[
                          AnimatedBuilder(
                            animation: _lens,
                            builder: (BuildContext context, Widget? child) {
                              // 速度越快拉得越长、压得越扁 —— 果冻的来源
                              final stretch = (_lens.velocity.abs() / _jellySpeed)
                                      .clamp(0.0, 1.0) *
                                  _jellyStretch;
                              final growth = _lensGrowth * 2 * _lift.value;
                              final width = (extent + growth) * (1 + stretch);
                              final height =
                                  (_innerHeight + growth) * (1 - stretch / 2);
                              return Positioned(
                                left: (_lens.value + 0.5) * extent - width / 2,
                                top: (_innerHeight - height) / 2,
                                width: width,
                                height: height,
                                child: DecoratedBox(
                                  decoration: ShapeDecoration(
                                    color: palette.primarySoft,
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(AppRadius.full),
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
                                  child: _NavItem(
                                    destination: widget.destinations[i],
                                    selected: i == widget.selectedIndex,
                                    reduceMotion: _reduceMotion,
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

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.reduceMotion,
    required this.onTap,
  });

  final AppNavDestination destination;
  final bool selected;
  final bool reduceMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      container: true,
      // 图标与文字只是画出来的，语义由这里统一给（免得「首页 首页」念两遍，角标也能念出来）
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
        duration: reduceMotion ? Duration.zero : AppMotion.normal,
        curve: AppMotion.spring,
        builder: (BuildContext context, double t, Widget? child) {
          return Transform.translate(
            offset: Offset(0, -1.5 * t),
            child: Transform.scale(scale: 1 + 0.14 * t, child: child),
          );
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _NavIcon(
              destination: destination,
              selected: selected,
              color: selected ? palette.onSoft : palette.textSecondary,
              danger: palette.danger,
            ),
            const SizedBox(height: 2),
            Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppFontSize.xs,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? palette.onSoft : palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({
    required this.destination,
    required this.selected,
    required this.color,
    required this.danger,
  });

  final AppNavDestination destination;
  final bool selected;
  final Color color;
  final Color danger;

  @override
  Widget build(BuildContext context) {
    final Icon icon = Icon(
      selected ? destination.selectedIcon : destination.icon,
      size: 24,
      color: color,
    );
    if (destination.badge <= 0) return icon;
    return Badge(
      backgroundColor: danger,
      textColor: context.palette.onColor(danger),
      label: Text(
        destination.badge > 99 ? '99+' : '${destination.badge}',
        style: const TextStyle(fontSize: 10),
      ),
      child: icon,
    );
  }
}
