import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

/// 保留速度的弹簧驱动器（移植自 FlClash 的 `_Spring`，`navigation_dock.dart:107-168`）。
///
/// 为什么不用 `AnimationController.animateWith`：那个 API 每次重定向都要重启
/// ticker，而 ticker 的第一帧读不到已流逝时间 —— 手指每帧都在动（拖动、连点）时，
/// 值会被「重启」钉在原地不动。这里自己记时间基准：重定向只把起点挪到当前时刻，
/// 值继续从当前位置和当前速度往下走，所以连点、拖拽都不打断手感。
class SpringDriver extends ChangeNotifier implements ValueListenable<double> {
  SpringDriver(TickerProvider vsync, double value) : _value = value {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;
  double _value;
  double _target = 0;
  SpringSimulation? _simulation;
  double _now = 0;
  double _start = 0;

  @override
  double get value => _value;

  /// 正在追的目标（没在跑时就是当前值）
  double get target => _simulation == null ? _value : _target;

  /// 当前速度（像素 / 秒）
  double get velocity => _simulation?.dx(_now - _start) ?? 0;

  bool get isAnimating => _ticker.isActive;

  /// 往 [target] 弹。已经跑着就只换目标，速度接着用。
  void springTo(double target, SpringDescription spring) {
    _simulation = SpringSimulation(spring, _value, target, velocity);
    _target = target;
    if (_ticker.isActive) {
      _start = _now;
      return;
    }
    _now = _start = 0;
    _ticker.start();
  }

  /// 直接落位 —— 无障碍「减少动态效果」打开时用它，别让动画绊住人。
  void jumpTo(double value) {
    _simulation = null;
    _ticker.stop();
    _value = value;
    notifyListeners();
  }

  void _tick(Duration elapsed) {
    _now = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final simulation = _simulation!;
    final time = _now - _start;
    if (simulation.isDone(time)) {
      _value = _target;
      _simulation = null;
      _ticker.stop();
    } else {
      _value = simulation.x(time);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
