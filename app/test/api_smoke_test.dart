// 接口层冒烟测试：拿真实后端跑一遍「只读」接口，验证 Dart 侧的解析与契约一致。
//
// 跑法（连本地后端；后端在 Web 版仓库 `npm run dev:api` 起在 8788）：
//   flutter test test/api_smoke_test.dart --dart-define=API_BASE=http://127.0.0.1:8788
//
// 只发 GET，不写库 —— 手工验证「客户端能跑通」时用它，不要拿它改数据。
import 'package:flutter_test/flutter_test.dart';
import 'package:sekainook_app/config/app_constants.dart';
import 'package:sekainook_app/core/api_client.dart';
import 'package:sekainook_app/data/api/ledger_api.dart';
import 'package:sekainook_app/data/api/notification_api.dart';
import 'package:sekainook_app/data/api/plans_api.dart';
import 'package:sekainook_app/data/api/settings_api.dart';
import 'package:sekainook_app/data/models/notification_record.dart';
import 'package:sekainook_app/core/week.dart';

void main() {
  final client = ApiClient();
  final ledgerApi = LedgerApi(client);

  test('base url', () {
    // ignore: avoid_print
    print('API_BASE = ${AppConstants.apiBase}');
  });

  test('GET /api/ledger 能解析成 LedgerRecord 列表', () async {
    final records = await ledgerApi.fetchRecords();
    expect(records, isNotEmpty);
    final first = records.first;
    expect(first.id, isNotEmpty);
    expect(first.taskName, isNotEmpty);
    // ignore: avoid_print
    print('ledger: ${records.length} 条，最新 ${first.taskName} ${first.amount}');
  });

  test('GET /api/ledger?status=pending 能解析', () async {
    final pending = await ledgerApi.fetchPendingRequests();
    // ignore: avoid_print
    print('pending: ${pending.length} 条');
  });

  test('GET /api/ledger/summary 返回两个数字', () async {
    final summary = await ledgerApi.fetchLedgerSummary();
    expect(summary.family, isA<num>());
    expect(summary.sun, isA<num>());
    // ignore: avoid_print
    print('summary: family=${summary.family} sun=${summary.sun}');
  });

  test('GET /api/settings 能解析', () async {
    final settings = await SettingsApi(client).fetchSettings();
    expect(settings.names.momCall, isNotEmpty);
    expect(settings.names.kidCall, isNotEmpty);
    // ignore: avoid_print
    print('settings: background=${settings.background} ready=${settings.ready}');
  });

  test('GET /api/notifications?audience=parent 能解析', () async {
    final box = await NotificationApi(client).fetchNotifications(NotifyAudience.parent);
    expect(box.items, isA<List<NotificationRecord>>());
    // ignore: avoid_print
    print('notifications(parent): ${box.items.length} 条，未读 ${box.unreadCount}，ready=${box.ready}');
  });

  test('GET /api/plans?week= 能解析（当周）', () async {
    final week = WeekUtil.currentWeekLabel();
    final plans = await PlansApi(client).fetchPlans(week);
    // ignore: avoid_print
    print('plans($week): ${plans.length} 条');
  });
}
