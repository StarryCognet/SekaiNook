import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/app_error.dart';
import 'data/models/ledger_record.dart';
import 'router.dart';
import 'state/custom_tasks_state.dart';
import 'state/family_state.dart';
import 'state/garden_state.dart';
import 'state/local_notify_state.dart';
import 'state/notification_state.dart';
import 'state/settings_state.dart';
import 'state/theme_state.dart';
import 'state/update_state.dart';
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
    required this.localNotify,
    required this.update,
    this.dynamicSeed,
    this.dynamicDarkSeed,
  });

  final FamilyState family;
  final ThemeState theme;
  final SettingsState settings;
  final NotificationState notifications;
  final CustomTasksState customTasks;
  final GardenState garden;
  final LocalNotifyState localNotify;
  final UpdateState update;

  /// 跟随壁纸取到的主色（Android 12+）。为 null 时用用户选的固定种子。
  final Color? dynamicSeed;

  /// 深色模式下的系统壁纸色（拿不到时退回 [dynamicSeed]）
  final Color? dynamicDarkSeed;

  @override
  State<SekaiNookApp> createState() => _SekaiNookAppState();
}

class _SekaiNookAppState extends State<SekaiNookApp> {
  late final GoRouter _router = createRouter(widget.family);

  /// 出错兜底卡片的「重新加载」：递增即重建整棵树，
  /// 对应 Web 版 `ErrorBoundary` 里的 `window.location.reload()`。
  int _generation = 0;

  /// 上一次喂给本地提醒的账本（同一份 List 就不重复排程）
  List<LedgerRecord>? _syncedRecords;

  @override
  void initState() {
    super.initState();
    setReloadHandler(_handleReload);
    widget.family.addListener(_onFamilyChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    widget.family.removeListener(_onFamilyChanged);
    super.dispose();
  }

  /// 账本一刷新就重排本地提醒：任务做完了撤掉，没做完就把「还差几个」改准。
  ///
  /// 监听放在这里而不是 [LocalNotifyState] 里，是为了让状态层不认识 FamilyState ——
  /// 通知只关心「一串流水」，谁给的都一样。
  void _onFamilyChanged() {
    final records = widget.family.records;
    if (identical(records, _syncedRecords)) return;
    _syncedRecords = records;
    unawaited(widget.localNotify.syncFromRecords(records));
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

    // 本地通知：初始化插件、恢复开关状态；点通知跳到首页。
    widget.localNotify.bindTapHandler((payload) => _router.go(payload));
    unawaited(widget.localNotify.init());

    // 静默看一眼有没有新版本：一天最多一次，有新版本才由主壳弹窗（安卓才有）
    unawaited(widget.update.autoCheck());

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
        ChangeNotifierProvider<LocalNotifyState>.value(value: widget.localNotify),
        ChangeNotifierProvider<UpdateState>.value(value: widget.update),
      ],
      child: Consumer<ThemeState>(
        builder: (BuildContext context, ThemeState theme, Widget? child) {
          return MaterialApp.router(
            key: ValueKey<int>(_generation),
            title: 'SekaiNook',
            debugShowCheckedModeBanner: false,
            // 主题（种子色）与明暗分开给：浅色、深色各建一份 ThemeData，
            // 「跟随系统」交给 ThemeMode.system —— 平台亮度由 Flutter 自己解析，
            // 系统一改（比如到了晚上）整个 App 就跟着变，不用我们监听。
            theme: AppTheme.build(
              theme.themeId,
              dark: false,
              hasBackground: theme.hasBackground,
              textScale: theme.textScale,
              // 只有用户明确开了「跟随壁纸」才用系统色。Android 12+ 上
              // 系统色**永远存在**，无条件传下去会把 7 个色板卡全盖掉。
              dynamicSeed: theme.followWallpaper ? widget.dynamicSeed : null,
            ),
            darkTheme: AppTheme.build(
              theme.themeId,
              dark: true,
              hasBackground: theme.hasBackground,
              pureBlack: theme.pureBlack,
              textScale: theme.textScale,
              dynamicSeed: theme.followWallpaper
                  ? (widget.dynamicDarkSeed ?? widget.dynamicSeed)
                  : null,
            ),
            themeMode: switch (theme.brightness) {
              ThemeBrightness.light => ThemeMode.light,
              ThemeBrightness.dark => ThemeMode.dark,
              ThemeBrightness.system => ThemeMode.system,
            },
            // MaterialApp 内部就是 AnimatedTheme：换主题时整个色板慢慢化过去，
            // 而不是"啪"地一下跳。AppPalette 实现了 lerp，所以半透明底也会一起过渡。
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
            // 底图铺在所有页面之下（页面在设了背景图时背景是透明的）
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
