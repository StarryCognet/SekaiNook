// 端到端流程测试：对着真实后端跑一遍完整业务闭环 ——
// 「孩子打卡 → 家长在待审批里看到 → 通过 → 余额增加 → 删除 → 余额复原」。
//
// 覆盖的是页面真正调用的那一层（state + api），不是 mock。
// 用法：
//   flutter test test/e2e_flow_test.dart --dart-define=API_BASE=http://127.0.0.1:8788
//
// 注意：会真实写库（跑完会把自己写的那条删掉）。默认不要指向生产环境。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sekainook_app/config/app_constants.dart';
import 'package:sekainook_app/core/api_client.dart';
import 'package:sekainook_app/core/pin_guard.dart';
import 'package:sekainook_app/data/api/ledger_api.dart';
import 'package:sekainook_app/data/models/ledger_record.dart';
import 'package:sekainook_app/data/models/task_config.dart';
import 'package:sekainook_app/state/family_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient client;
  late LedgerApi ledger;
  late FamilyState family;
  late SharedPreferences prefs;

  setUp(() async {
    // flutter_test 默认把 HttpClient 全局替换成「一律回 400」的假实现，
    // 这里放行，让测试真的打本地后端。
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    client = ApiClient();
    ledger = LedgerApi(client);
    family = FamilyState(api: ledger, pinGuard: PinGuard(prefs), prefs: prefs);
  });

  test('打卡 -> 待审批 -> 审批 -> 余额 -> 删除 -> 余额复原', () async {
    // ignore: avoid_print
    print('API base = ${AppConstants.apiBase}');
    final String requestId = 'e2e-${DateTime.now().millisecondsSinceEpoch}';
    // 服务端会拒绝它不认识的任务（403 未知任务，不能记账），所以用一条真实任务；
    // 变量部分只放在幂等键 requestId 上。
    final TaskConfig task = TaskConfig(
      id: 'clean_room',
      name: '整理房间',
      type: TaskType.earning,
      value: 10,
    );

    await family.loadLedger();
    final num before = family.balance;
    final int pendingBefore = family.pendingCount;

    // 1) 孩子打卡：写一条待审批流水
    final String id = await ledger.addLedgerRecord(
      task,
      requestId: requestId,
      autoApprove: false,
    );
    expect(id, requestId);

    // 2) 幂等：同一个 id 再提交一次不会重复记账
    final LedgerWriteResult again = await ledger.postLedgerRecord(
      task.id,
      requestId: requestId,
      amount: 10,
      name: task.name,
      type: TaskType.earning,
    );
    expect(again.duplicate, isTrue, reason: '同 id 重发应命中幂等');

    // 3) 家长视角：待审批多一条，余额还没动（未审批不计入）
    await family.loadLedger();
    expect(family.pendingCount, pendingBefore + 1);
    expect(family.balance, before, reason: '待审批不该影响余额');

    // 4) 审批通过：余额 +10，待审批回到原样
    await family.approve(requestId);
    expect(family.balance, before + 10);
    expect(family.pendingCount, pendingBefore);

    // 5) 删除这条流水：余额复原
    await family.removeRecord(requestId);
    expect(family.balance, before, reason: '删掉后余额应回到起点');
  });
}
