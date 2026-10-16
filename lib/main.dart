import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'core/pin_guard.dart';
import 'data/api/ledger_api.dart';
import 'data/api/notification_api.dart';
import 'data/api/settings_api.dart';
import 'state/custom_tasks_state.dart';
import 'state/family_state.dart';
import 'state/garden_state.dart';
import 'state/notification_state.dart';
import 'state/settings_state.dart';
import 'state/theme_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 本地存档要先就绪：主题、身份、花园状态都在 store 构造时读它
  final prefs = await SharedPreferences.getInstance();

  final client = ApiClient();
  final ledgerApi = LedgerApi(client);
  final settingsApi = SettingsApi(client);

  runApp(
    SekaiNookApp(
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
    ),
  );
}
