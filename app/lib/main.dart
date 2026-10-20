import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/scheduler.dart' show timeDilation;
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'core/app_error.dart';
import 'core/boot_splash.dart';
import 'core/pin_guard.dart';
import 'data/api/ledger_api.dart';
import 'data/api/notification_api.dart';
import 'data/api/settings_api.dart';
import 'state/custom_tasks_state.dart';
import 'state/family_state.dart';
import 'state/garden_state.dart';
import 'state/local_notify_state.dart';
import 'state/notification_state.dart';
import 'state/settings_state.dart';
import 'state/theme_state.dart';
import 'state/update_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 动效验收辅助：加 --dart-define=SLOW_MO=15 时把全局动画放慢 15 倍，
  // 截图/录屏才抓得到转场与弹层的中间态。默认 1 倍，正式构建不受影响。
  const slowMo = int.fromEnvironment('SLOW_MO');
  if (slowMo > 1) {
    timeDilation = slowMo.toDouble();
    debugPrint('[SekaiNook] 动效放慢 $slowMo 倍（仅验收用）');
  }

  // 出错兜底卡片：渲染期异常不再白屏（对应 Web 版 ErrorBoundary）
  installErrorWidget();

  // 未捕获的异步异常要留痕，否则真机上只是「什么都没发生」
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('[SekaiNook] 未捕获异常：$error\n$stack');
    return true;
  };
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('[SekaiNook] 渲染异常：${details.exceptionAsString()}');
  };

  // 本地存档要先就绪：主题、身份、花园状态都在 store 构造时读它
  final prefs = await SharedPreferences.getInstance();

  final client = ApiClient();
  final ledgerApi = LedgerApi(client);
  final settingsApi = SettingsApi(client);

  // 跟随壁纸：Android 12+ 会把壁纸主色交给 App；拿不到（旧系统 / 桌面 / Web）
  // 时 lightDynamic 是 null，App 里会退回用户选的固定种子。
  runApp(
    DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final Widget app = SekaiNookApp(
      family: FamilyState(
        api: ledgerApi,
        pinGuard: PinGuard(prefs),
        prefs: prefs,
      ),
      theme: ThemeState(prefs: prefs, settingsApi: settingsApi),
      settings: SettingsState(prefs: prefs, api: settingsApi),
      notifications: NotificationState(api: NotificationApi(client)),
      customTasks: CustomTasksState(prefs: prefs),
      garden: GardenState(prefs: prefs, ledgerApi: ledgerApi),
      localNotify: LocalNotifyState(prefs: prefs),
      update: UpdateState(prefs: prefs),
        dynamicSeed: lightDynamic?.primary,
        );
        return app;
      },
    ),
  );

  // 第一帧画好了就撤掉 index.html 里的 HTML 启动动画（Web 专有；其它平台是空实现）。
  // 不撤的话它会在页面上多盖 8 秒 —— index.html 里只有 8 秒兜底。
  WidgetsBinding.instance.addPostFrameCallback((_) => removeHtmlBootSplash());
}
