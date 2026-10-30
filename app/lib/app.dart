import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/app_error.dart';
import 'data/models/ledger_record.dart';
import 'fl_ui/liquid_glass.dart';
import 'fl_ui/measure.dart';
import 'fl_ui/view_scope.dart';
import 'fl_ui_zh.dart';
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
import 'ui/shell/route_cover.dart';
import 'ui/widgets/app_background.dart';
import 'ui/widgets/p5r_texture.dart';

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
  /// 只把「身份变化」喂给 GoRouter：FamilyState 还会因为账本刷新 notify，
  /// 那些不该让路由重跑 redirect（每次都要重建整张路由表，还会连带重建当前页）。
  /// 由 State 持有，dispose 时连同 GoRouter 一起释放（L-4）。
  late final ValueNotifier<FamilyRole?> _roleRefresh = ValueNotifier<FamilyRole?>(widget.family.role);

  /// 弹窗开合状态：MainShell 用它让悬浮顶栏 / 底栏在弹窗打开时退场。
  final RouteCoverState _routeCover = RouteCoverState();

  late final GoRouter _router = createRouter(widget.family, _roleRefresh, _routeCover);

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
    _roleRefresh.dispose();
    _router.dispose();
    _routeCover.dispose();
    super.dispose();
  }

  /// 账本一刷新就重排本地提醒：任务做完了撤掉，没做完就把「还差几个」改准。
  ///
  /// 监听放在这里而不是 [LocalNotifyState] 里，是为了让状态层不认识 FamilyState ——
  /// 通知只关心「一串流水」，谁给的都一样。
  void _onFamilyChanged() {
    // 身份变了才触发路由重算；账本/余额变化一律不碰 GoRouter
    if (_roleRefresh.value != widget.family.role) {
      _roleRefresh.value = widget.family.role;
    }
    final records = widget.family.records;
    if (identical(records, _syncedRecords)) return;
    _syncedRecords = records;
    unawaited(widget.localNotify.syncFromRecords(records));
  }

  void _handleReload() {
    if (!mounted) return;
    // 整树重建会丢弃 Navigator 里的弹窗，observer 收不到 didPop，
    // 弹窗计数会卡住让顶栏/底栏永久退场（U-2）—— 重建前清一次。
    _routeCover.reset();
    setState(() => _generation += 1);
  }

  /// 启动时的一次性加载。
  ///
  /// 都是「尽力而为」：某一个接口挂了不该让整个应用起不来，
  /// 所以每个都单独 catch，页面自己会显示重试入口。
  Future<void> _bootstrap() async {
    unawaited(widget.theme.loadBackground());
    unawaited(widget.settings.load());
    // 这两步会读本地存档并立刻落盘：一条坏数据不能让整个 App 起不来（S-4）
    try {
      widget.customTasks.ensurePresets();
    } catch (error, stack) {
      debugPrint('[SekaiNook] 自定义任务预设读取失败：$error\n$stack');
    }
    try {
      widget.garden.init();
    } catch (error, stack) {
      debugPrint('[SekaiNook] 花园存档读取失败（按空存档继续）：$error\n$stack');
    }

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
        ChangeNotifierProvider<RouteCoverState>.value(value: _routeCover),
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
              FlUiZhDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            // 底图铺在所有页面之下（页面在设了背景图时背景是透明的）
            // 外面再套 FlClash lib/ui 需要的三层作用域（批 1：液态玻璃默认关）：
            // MeasureScope 供文字量高用、ViewScope 供响应式断点用、
            // LiquidGlassScope/Host 是液态玻璃的总开关（关掉时组件走普通绘制）。
            builder: (BuildContext context, Widget? child) {
              final MediaQueryData media = MediaQuery.of(context);
              // 字号缩放**只有这一个入口**：用户设置（0.8–1.4）× 系统字体缩放。
              // 用 MediaQuery.textScaler 而不是 textTheme.apply(fontSizeFactor:)，
              // 这样全站 `fontSize: AppFontSize.*` 的 392 处裸文字也一起生效；
              // 不需要动的（纯图标尺寸、间距）本来就取 AppFontSize 的数值但不当文字，
              // 缩放只乘进 Text 的排版，不会把卡片/按钮的固定高度撑破。
              // 夹到 [0.8, 1.5]：系统 2.0 × 用户 1.4 会把布局撑爆。
              final double effectiveTextScale =
                  (media.textScaler.scale(1) * theme.textScale).clamp(0.8, 1.5);
              final TextScaler textScaler = TextScaler.linear(effectiveTextScale);
              const bool glass = false;
              return MediaQuery(
                data: media.copyWith(textScaler: textScaler),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (theme.hasBackground)
                      AppBackgroundLayer(
                        url: theme.background,
                        veil: context.palette.bgVeil,
                      ),
                    // P5R 的印刷网点：非 P5R 主题时是空壳，不影响其它主题。
                    const P5rTexture(),
                    LiquidGlassHost(
                      enabled: glass,
                      child: LiquidGlassScope(
                        enabled: glass,
                        child: MeasureScope(
                          measure: Measure.of(context, effectiveTextScale),
                          child: ViewScope(
                            size: media.size,
                            isMobile: media.size.width < 700,
                            child: child ?? const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
