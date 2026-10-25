import 'dart:async';

import 'package:flutter/material.dart';

/// 每秒自更新的时钟文本。
///
/// 页面里别为了「秒在走」整页 `setState` —— 那会把整棵子树（重列表、统计循环、
/// 图表……）每秒重建一遍。用这个独立 widget，只重建它自己那个 Text。
class AppLiveClock extends StatefulWidget {
  const AppLiveClock({
    super.key,
    required this.style,
    this.withSeconds = true,
  });

  /// 文字样式（颜色随主题走，由调用方给）
  final TextStyle style;

  /// 是否带秒（`HH:mm:ss`）；不带就是 `HH:mm`
  final bool withSeconds;

  @override
  State<AppLiveClock> createState() => _AppLiveClockState();
}

class _AppLiveClockState extends State<AppLiveClock> with WidgetsBindingObserver {
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 切到后台就别再每秒叫醒自己：回来时补一次当前时间再重启。
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() => _now = DateTime.now());
      _start();
    } else {
      _stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  void _start() {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Widget build(BuildContext context) {
    final String hh = _now.hour.toString().padLeft(2, '0');
    final String mm = _now.minute.toString().padLeft(2, '0');
    if (!widget.withSeconds) return Text('$hh:$mm', style: widget.style);
    final String ss = _now.second.toString().padLeft(2, '0');
    return Text('$hh:$mm:$ss', style: widget.style);
  }
}
