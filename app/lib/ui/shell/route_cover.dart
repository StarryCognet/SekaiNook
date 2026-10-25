import 'package:flutter/widgets.dart';

/// 当前有没有「压在这一页上面的弹窗」（底部面板、居中确认框、选择列表…）。
///
/// 悬浮的顶栏与胶囊底栏是页面内 z 最高的浮层，弹窗的半透明遮罩压不干净：
/// 玻璃会把底下的颜色透出来，看着仍然是浮在面板上面。所以弹窗一开就让它们
/// 退场 —— 顶栏往上收、底栏往下收，关掉再回来。
///
/// 这条信息只能从 Navigator 拿：`ModalRoute.secondaryAnimation` 不跟
/// [PopupRoute]（实测弹窗打开后它一直是 0），所以挂一个 observer 数一下。
class RouteCoverState extends ChangeNotifier {
  int _popups = 0;

  /// 有弹窗压在页面上。
  bool get covered => _popups > 0;

  /// 注册给 `GoRouter(observers: [...])` 用。同一个状态可以反复取，
  /// observer 本身不持有别的资源。
  NavigatorObserver get observer => _RouteCoverObserver(this);

  void _pushed(Route<dynamic> route) {
    if (route is! PopupRoute) return;
    _popups += 1;
    notifyListeners();
  }

  void _popped(Route<dynamic> route) {
    if (route is! PopupRoute || _popups == 0) return;
    _popups -= 1;
    notifyListeners();
  }
}

class _RouteCoverObserver extends NavigatorObserver {
  _RouteCoverObserver(this._state);

  final RouteCoverState _state;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _state._pushed(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _state._popped(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _state._popped(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _state._popped(oldRoute);
    if (newRoute != null) _state._pushed(newRoute);
  }
}
