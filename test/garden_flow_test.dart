// 花园阳光链路端到端测试：本地状态 → pending 队列 → 真实后端 → 余额回读。
//
// 覆盖的是花园页真正调用的那一层（GardenState + LedgerApi），不是 mock。
// 用法：
//   flutter test --no-pub test/garden_flow_test.dart --dart-define=API_BASE=http://127.0.0.1:8788
//
// 注意：会真实写库（跑完会把自己写的那条删掉）。默认不要指向生产环境。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sekainook_app/core/api_client.dart';
import 'package:sekainook_app/core/ledger_ids.dart';
import 'package:sekainook_app/data/api/ledger_api.dart';
import 'package:sekainook_app/data/models/ledger_record.dart';
import 'package:sekainook_app/state/garden_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient client;
  late LedgerApi ledger;
  late GardenState garden;
  late SharedPreferences prefs;

  setUp(() async {
    // flutter_test 默认把 HttpClient 替换成「一律回 400」的假实现，这里放行。
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    client = ApiClient();
    ledger = LedgerApi(client);
    garden = GardenState(prefs: prefs, ledgerApi: ledger);
  });

  /// 清理本次测试写进去的花园流水（按 id 删）。
  Future<void> cleanup(Iterable<String> ids) async {
    for (final String id in ids) {
      try {
        await ledger.deleteLedgerRecord(id);
      } catch (_) {
        // 清理是尽力而为
      }
    }
  }

  test('背古诗 → pending 出队 → 后端阳光 +10 → 清理后复原', () async {
    garden.init(); // 同步返回，内部的 flushPending / refreshLedger 是 fire-and-forget
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await garden.refreshLedger();

    final num before = (await ledger.fetchLedgerSummary()).sun;
    // 记下现有流水 id，清理时只删「本次新增」的那条，别误伤历史记录。
    final Set<String> beforeIds = (await ledger.fetchRecords())
        .map((LedgerRecord r) => r.id)
        .toSet();

    // 背一首今天还没背过的古诗（本地状态是全新的，所以必定可背）
    final bool ok = garden.recitePoem('jingyesi');
    expect(ok, isTrue, reason: '静夜思今天应该还能背');
    expect(garden.todayPoemIds, contains('jingyesi'));

    // 队列推给后端
    await garden.flushPending();

    final num after = (await ledger.fetchLedgerSummary()).sun;
    expect(after, before + 10, reason: '背一首古诗应入账 +10 阳光');

    // 本地账也刷新到了
    await garden.refreshLedger();
    expect(garden.balance, before + 10);

    // 清理：把本次写的 garden:poem 流水删掉，阳光回到起点
    final List<LedgerRecord> records = await ledger.fetchRecords();
    final List<String> mine = records
        .where((LedgerRecord r) =>
            r.taskId == 'garden:poem' && !beforeIds.contains(r.id))
        .map((LedgerRecord r) => r.id)
        .toList();
    expect(mine, isNotEmpty, reason: '应该能在流水里找到刚写的那条');
    await cleanup(mine);

    final num restored = (await ledger.fetchLedgerSummary()).sun;
    expect(restored, before, reason: '删掉后阳光应回到起点');
  });
}
