import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// 动效令牌 —— 全站动画参数的**唯一来源**。
///
/// 铁律：动画的时长与曲线一律从这里取，不要在组件里散写
/// `Duration(milliseconds: 300)` / `Curves.easeInOut`。
/// 参数统一，整站才会「动得像同一个东西」。
///
/// 数值对齐 Material 3 的 motion 规范（short / medium / long 三档 + emphasized 曲线族），
/// 弹簧参数参考 FlClash（`common/motion.dart`）。
abstract final class AppMotion {
  // ------------------------------------------------------------------
  // 时长
  // ------------------------------------------------------------------

  /// 90ms：按压回弹、图标切换这类「必须立刻有反馈」的动作
  static const Duration instant = Duration(milliseconds: 90);

  /// 160ms：高亮、小范围展开、Tooltip
  static const Duration fast = Duration(milliseconds: 160);

  /// 240ms：**默认档** —— 卡片入场、内容切换、列表错峰
  static const Duration normal = Duration(milliseconds: 240);

  /// 360ms：页面转场、弹层、抽屉
  static const Duration slow = Duration(milliseconds: 360);

  /// 520ms：强调型 —— 数字滚动、主题切换
  static const Duration slower = Duration(milliseconds: 520);

  /// 900ms：庆祝类一次性动画（打卡对勾 + 光环扩散）
  static const Duration celebrate = Duration(milliseconds: 900);

  /// 骨架屏一次呼吸的周期
  static const Duration skeleton = Duration(milliseconds: 1600);

  // ------------------------------------------------------------------
  // 曲线（只吃 `Curve` 的 API 用这些）
  // ------------------------------------------------------------------

  /// 标准曲线：绝大多数过渡
  static const Curve standard = Cubic(0.2, 0, 0, 1);

  /// 减速进入：新内容进场（页面转场、弹层出现）
  static const Curve decelerate = Cubic(0.05, 0.7, 0.1, 1);

  /// 加速离开：旧内容退场
  static const Curve accelerate = Cubic(0.3, 0, 0.8, 0.15);

  /// Material 3 的「强调」曲线族里最常用的一支，用于对称型过渡
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;

  /// 收尾带一点过冲（1.0 → 1.1 → 1.0）。**只能喂给 scale / offset，不能喂 Opacity**
  static const Curve overshoot = Curves.easeOutBack;

  /// 匀速：无限循环
  static const Curve linear = Curves.linear;

  // ------------------------------------------------------------------
  // 弹簧（喂给 scale / offset —— 会越过 1，别拿去插值透明度）
  // ------------------------------------------------------------------

  /// 默认弹簧：跟手、收得快
  static final Curve spring = SpringCurve();

  /// 软弹簧：大幅位移用（弹层、抽屉）
  static final Curve springSoft = SpringCurve(stiffness: 340, damping: 26);

  // ------------------------------------------------------------------
  // 弹簧（喂给 SpringDriver —— 需要「保留速度」的原生模拟）
  // ------------------------------------------------------------------
  //
  // 参数取自 FlClash（`widgets/navigation_dock.dart:62-79`），用「时长 + 回弹」
  // 描述弹簧，比手调 mass/stiffness/damping 直观。

  /// 跟手：追指针，不回弹（不能有回弹，否则跟手会抖）
  static final SpringDescription springTrack =
      SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 120));

  /// 按下：轻微回弹，Q 感的来源之一
  static final SpringDescription springPress = SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 280),
    bounce: 0.2,
  );

  /// 落位：明显回弹一下 —— 底部 Tab 透镜滑动「Q 弹」主要靠它
  static final SpringDescription springSettle = SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 500),
    bounce: 0.32,
  );

  /// 次级落位：比落位快一点、弹得少一点
  static final SpringDescription springHover = SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 260),
    bounce: 0.18,
  );

  /// 硬弹簧：小控件用（按钮回弹、指示器）
  static final Curve springSnappy = SpringCurve(stiffness: 720, damping: 32);

  // ------------------------------------------------------------------
  // 常用量
  // ------------------------------------------------------------------

  /// 入场时自下而上的位移（px）。FlClash 的 `FadeSlideEnterBox` 用 24，
  /// 我们列表更密，取一半。
  static const double enterOffset = 14;

  /// 按压膨胀的上限 —— 56px 的小控件封顶 25%（FlClash ElasticPress 同值）
  static const double pressGrowCap = 0.25;

  /// 按压时「每边长出多少像素」的预算：`grow = min(cap, room / 长边)`。
  ///
  /// 用固定像素而不是固定百分比，是为了让 56px 的圆钮和 300px 的卡片
  /// 看起来一样「鼓」—— 百分比对两者是差 5 倍的观感。
  static const double pressGrowRoom = 16;

  /// 拿不到约束时的兜底膨胀量
  static const double pressGrow = 0.02;

  /// 旧语义（按下缩到某个比例）已废弃；现在按压一律是**放大**。
  static const double pressScale = 1.02;

  /// 按压「膨胀」的最大幅度（长边归一化，大卡片不会夸张地胀起来）
  static const double pressLift = 0.02;

  /// 页面转场时新页的起始缩放（Material 3 的 fade-through 取 0.92）
  static const double pageEnterScale = 0.92;

  /// 页面转场时旧页的退出缩放
  static const double pageExitScale = 1.05;

  // ------------------------------------------------------------------
  // 列表错峰入场
  // ------------------------------------------------------------------

  /// 相邻两项的入场间隔
  static const Duration staggerStep = Duration(milliseconds: 42);

  /// 错峰上限：第 10 项之后不再叠加延迟，否则长列表末尾要等好几秒
  static const int staggerMax = 10;

  /// 第 [index] 项的入场延迟。超出 [staggerMax] 的按上限算。
  static Duration stagger(int index) {
    final int i = index < 0 ? 0 : (index > staggerMax ? staggerMax : index);
    return Duration(microseconds: staggerStep.inMicroseconds * i);
  }

  // ------------------------------------------------------------------
  // 页面转场
  // ------------------------------------------------------------------

  /// 全平台统一的 **shared axis（水平）** 页面转场 —— 与 FlClash 的选择一致：
  /// 新页从右侧滑入并淡入、旧页同时向左滑出并淡出，两层共享同一条水平轴，
  /// 所以「进下一层」与「回上一层」的动线方向相反、眼睛能预判。
  ///
  /// `fillColor` 必须显式给 `Colors.transparent`：它默认取
  /// `ThemeData.canvasColor`，会在过渡期间给新页铺一层不透明底把旧页整个盖住，
  /// 表现出来就是「每翻一页闪一下底色」。
  ///
  /// 目标是 Android 手机与 Web，不做平台差异化（也就放弃 iOS 的侧滑返回手感）。
  static const PageTransitionsTheme pageTransitionsTheme = PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: SharedAxisPageTransitionsBuilder(),
      TargetPlatform.iOS: SharedAxisPageTransitionsBuilder(),
      TargetPlatform.macOS: SharedAxisPageTransitionsBuilder(),
      TargetPlatform.windows: SharedAxisPageTransitionsBuilder(),
      TargetPlatform.linux: SharedAxisPageTransitionsBuilder(),
      TargetPlatform.fuchsia: SharedAxisPageTransitionsBuilder(),
    },
  );
}

/// [AppMotion.pageTransitionsTheme] 用的转场构造器：
/// 官方 `animations` 包的 [SharedAxisTransition]，水平轴 + 透明填充。
class SharedAxisPageTransitionsBuilder extends PageTransitionsBuilder {
  const SharedAxisPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return SharedAxisTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      transitionType: SharedAxisTransitionType.horizontal,
      fillColor: Colors.transparent,
      child: child,
    );
  }
}

/// 把物理弹簧塞进只吃 [Curve] 的 API。
///
/// 做法：先用一次 [SpringSimulation] 探出它「静止」需要多久（settle time），
/// 之后把归一化进度 t 映射成真实秒数再求位移。
/// 于是 `CurvedAnimation(curve: AppMotion.spring)` 就能得到一个真弹簧。
///
/// ⚠️ 弹簧会越过 1 再回落，只能插值 scale / offset / position。
class SpringCurve extends Curve {
  SpringCurve({
    this.mass = 1,
    this.stiffness = 500,
    this.damping = 28,
    this.settleThreshold = 0.001,
  }) : settleSeconds = _settleSecondsOf(mass, stiffness, damping, settleThreshold),
       _simulation = SpringSimulation(
         SpringDescription(mass: mass, stiffness: stiffness, damping: damping),
         0,
         1,
         0,
       );

  final double mass;
  final double stiffness;
  final double damping;

  /// 判定「已静止」的位移与速度阈值
  final double settleThreshold;

  /// 弹簧从 0 出发到 1 并静止所需的时间（秒）
  final double settleSeconds;

  final SpringSimulation _simulation;

  /// `Simulation.x(time)` 是纯函数，同一个 simulation 可以反复求值。
  static double _settleSecondsOf(double mass, double stiffness, double damping, double threshold) {
    final SpringSimulation sim = SpringSimulation(
      SpringDescription(mass: mass, stiffness: stiffness, damping: damping),
      0,
      1,
      0,
    );
    double t = 0;
    const double step = 1 / 240;
    while (t < 5) {
      if ((sim.x(t) - 1).abs() < threshold && sim.dx(t).abs() < threshold) break;
      t += step;
    }
    return t;
  }

  @override
  double transformInternal(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    return _simulation.x(t * settleSeconds);
  }

  @override
  String toString() => 'SpringCurve(mass: $mass, stiffness: $stiffness, damping: $damping)';
}
