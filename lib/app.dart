import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'router.dart';
import 'state/custom_tasks_state.dart';
import 'state/family_state.dart';
import 'state/garden_state.dart';
import 'state/notification_state.dart';
import 'state/settings_state.dart';
import 'state/theme_state.dart';
import 'theme/app_theme.dart';
import 'ui/shell/main_shell.dart';

/// 应用根（对应 Web 版 `src/App.tsx`）。
///
/// 依赖注入：所有全局 store 在 `main.dart` 里构造一次，这里挂上 Provider。
/// 主题由 [ThemeState] 驱动 —— 切换主题是纯本地行为，不重新拉数据。
class SekaiNookApp extends StatefulWidget {
  const SekaiNookApp({
    super.key,
    required this.family,
    required this.theme,
    required this.settings,
    required this.notifications,
    required this.customTasks,
    required this.garden,
  });

  final FamilyState family;
  final ThemeState theme;
  final SettingsState settings;
  final NotificationState notifications;
  final CustomTasksState customTasks;
  final GardenState garden;

  @override
  State<SekaiNookApp> createState() => _SekaiNookAppState();
}

class _SekaiNookAppState extends State<SekaiNookApp> {
  late final GoRouter _router = createRouter(widget.family);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  /// 启动时的一次性加载。
  ///
  /// 都是「尽力而为」：某一个接口挂了不该让整个应用起不来，
  /// 所以每个都单独 catch，页面自己会显示重试入口。
  Future<void> _bootstrap() async {
    unawaited(widget.theme.loadBackground());
    unawaited(widget.settings.load());
    widget.customTasks.ensurePresets();
    widget.garden.init();

    final role = widget.family.role;
    if (role != null) {
      unawaited(widget.family.loadLedger());
      unawaited(widget.notifications.load(audienceOf(role)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<FamilyState>.value(value: widget.family),
        ChangeNotifierProvider<ThemeState>.value(value: widget.theme),
        ChangeNotifierProvider<SettingsState>.value(value: widget.settings),
        ChangeNotifierProvider<NotificationState>.value(value: widget.notifications),
        ChangeNotifierProvider<CustomTasksState>.value(value: widget.customTasks),
        ChangeNotifierProvider<GardenState>.value(value: widget.garden),
      ],
      child: Consumer<ThemeState>(
        builder: (BuildContext context, ThemeState theme, Widget? child) {
          return MaterialApp.router(
            title: 'SekaiNook',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(theme.themeId, hasBackground: theme.hasBackground),
            routerConfig: _router,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const <Locale>[Locale('zh', 'CN'), Locale('en')],
            localizationsDelegates: const <LocalizationsDelegate<Object>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
          );
        },
      ),
    );
  }
}
