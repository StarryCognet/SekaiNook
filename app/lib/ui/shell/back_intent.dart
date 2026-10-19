import 'package:flutter/widgets.dart';

/// 系统返回键的分发器：外壳只挂一个 `PopScope`，页面自己声明「我还有一层要关」。
///
/// 为什么要它：`ModalRoute` 在返回被拦下时会把事件发给**所有**已注册的
/// `PopScope`（`routes.dart` 里 `onPopInvokedWithResult` 是遍历 `_popEntries`），
/// 所以外壳和设置页各挂一个会同时触发 —— 既关分区又跳走。这里改成登记制：
/// 页面把「关一层」的办法交上来，外壳按后注册（更内层）优先的顺序问一遍，
/// 谁先应下来这次返回就归谁，都没应才轮到外壳退回上一页 / 退出。
class BackIntentDispatcher {
  final List<bool Function()> _handlers = <bool Function()>[];

  void add(bool Function() handler) => _handlers.add(handler);

  void remove(bool Function() handler) => _handlers.remove(handler);

  /// 从最内层开始问，返回 true 表示这次返回已经被消化
  bool dispatch() {
    for (final bool Function() handler in _handlers.reversed) {
      if (handler()) return true;
    }
    return false;
  }
}

/// 把分发器递给页面（外壳建，页面用）
class BackIntentScope extends InheritedWidget {
  const BackIntentScope({super.key, required this.dispatcher, required super.child});

  final BackIntentDispatcher dispatcher;

  static BackIntentDispatcher? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BackIntentScope>()?.dispatcher;

  @override
  bool updateShouldNotify(BackIntentScope oldWidget) => dispatcher != oldWidget.dispatcher;
}

/// 页面上登记一层：「返回键来了先关我这一层」。
///
/// `onBack` 关掉一层返回 true；已经没有可关的层（比如设置首页）返回 false，
/// 这次返回就交给外壳继续处理。
class BackIntentHandler extends StatefulWidget {
  const BackIntentHandler({super.key, required this.onBack, required this.child});

  final bool Function() onBack;

  final Widget child;

  @override
  State<BackIntentHandler> createState() => _BackIntentHandlerState();
}

class _BackIntentHandlerState extends State<BackIntentHandler> {
  BackIntentDispatcher? _dispatcher;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final BackIntentDispatcher? next = BackIntentScope.maybeOf(context);
    if (identical(next, _dispatcher)) return;
    _dispatcher?.remove(_handle);
    _dispatcher = next;
    _dispatcher?.add(_handle);
  }

  @override
  void dispose() {
    _dispatcher?.remove(_handle);
    super.dispose();
  }

  bool _handle() => widget.onBack();

  @override
  Widget build(BuildContext context) => widget.child;
}
