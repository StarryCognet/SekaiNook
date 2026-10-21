import 'package:flutter/material.dart';
import 'package:sekainook_app/fl_ui/l10n.dart';

/// lib/fl_ui（FlClash v0.9.1 UI 库）的中文本地化。
///
/// `lib/ui` 的组件只通过 [UiLocalizations] 取文案（14 个 getter），
/// 不依赖 Flutter 自带的 MaterialLocalizations。注册方式：
///
/// ```dart
/// MaterialApp(
///   localizationsDelegates: const <LocalizationsDelegate<Object>>[
///     FlUiZhDelegate(),
///     GlobalMaterialLocalizations.delegate,
///     GlobalWidgetsLocalizations.delegate,
///     GlobalCupertinoLocalizations.delegate,
///   ],
///   supportedLocales: const <Locale>[Locale('zh')],
/// )
/// ```
class FlUiZhLocalizations extends UiLocalizations {
  FlUiZhLocalizations();

  @override
  String get back => '返回';
  @override
  String get cancel => '取消';
  @override
  String get clearSearch => '清除';
  @override
  String get close => '关闭';
  @override
  String get hidePassword => '隐藏密码';
  @override
  String get more => '更多';
  @override
  String get noSearchResults => '没有搜索结果';
  @override
  String get reset => '重置';
  @override
  String get search => '搜索';
  @override
  String get showLess => '收起';
  @override
  String get showMore => '展开';
  @override
  String get showPassword => '显示密码';
  @override
  String get sort => '排序';
  @override
  String get submit => '确定';
}

/// 注册 [FlUiZhLocalizations] 的委托（SekaiNook 只支持中文，直接 always load）。
class FlUiZhDelegate extends LocalizationsDelegate<UiLocalizations> {
  const FlUiZhDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<UiLocalizations> load(Locale locale) async => FlUiZhLocalizations();

  @override
  bool shouldReload(FlUiZhDelegate old) => false;
}
