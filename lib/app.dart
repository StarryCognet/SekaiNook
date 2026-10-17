import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/app_error.dart';
import 'router.dart';
import 'state/custom_tasks_state.dart';
import 'state/family_state.dart';
import 'state/garden_state.dart';
import 'state/notification_state.dart';
import 'state/settings_state.dart';
import 'state/theme_state.dart';
import 'theme/app_theme.dart';
import 'theme/motion.dart';
import 'ui/shell/main_shell.dart';
import 'ui/widgets/app_background.dart';

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

  /// 出错兜底卡片的「重新加载」：递增即重建整棵树，
  /// 对应 Web 版 `ErrorBoundary` 里的 `window.location.reload()`。
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    setReloadHandler(_handleReload);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  void _handleReload() {
    if (!mounted) return;
    setState(() => _generation += 1);
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
            key: ValueKey<int>(_generation),
            title: 'SekaiNook',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(theme.themeId, hasBackground: theme.hasBackground),
            // MaterialApp 内部就是 AnimatedTheme：换主题时整个色板慢慢化过去，
            // 而不是"啪"地一下跳。AppPalette 实现了 lerp，所以玻璃底也会一起过渡。
            themeAnimationDuration: AppMotion.slower,
            themeAnimationCurve: AppMotion.emphasized,
            routerConfig: _router,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const <Locale>[Locale('zh', 'CN'), Locale('en')],
            localizationsDelegates: const <LocalizationsDelegate<Object>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            // 全局背景图铺在所有页面之下（页面在设了背景图时背景是透明的）
            builder: (BuildContext context, Widget? child) => Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (theme.hasBackground)
                  AppBackgroundLayer(
                    url: theme.background,
                    veil: context.palette.bgVeil,
                  ),
                child ?? const SizedBox.shrink(),
              ],
            ),
          );
        },
      ),
    );
  }
}
