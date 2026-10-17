import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sekainook_app/core/api_client.dart';
import 'package:sekainook_app/core/day_completion.dart';
import 'package:sekainook_app/data/api/ledger_api.dart';

/// 口径对账：App 本地提醒说的「还差几个」必须与**服务端提醒 Worker** 说的完全一样。
///
/// 两边各自实现了一遍「今天完成了几个任务」（服务端在 `functions/_lib/rules.ts`
/// 的 `countDayCompletions`，App 在 `lib/core/day_completion.dart`），
/// 只要有一边改了口径，孩子手机上就会出现「网站说还差 1 个、App 说还差 3 个」。
///
/// 需要两个本地服务同时起着（否则跳过）：
///   * Pages API：`npx wrangler pages dev public --port 8788`
///   * 提醒 Worker：`npx wrangler dev --test-scheduled --persist-to ../../.wrangler/state --port 8789`
/// 跑法：
///   flutter test --no-pub test/reminder_parity_test.dart \
///     --dart-define=PARITY=true --dart-define=API_BASE=http://127.0.0.1:8788
void main() {
  const bool enabled = bool.fromEnvironment('PARITY');
  const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://127.0.0.1:8788',
  );
  const String workerBase = String.fromEnvironment(
    'WORKER_BASE',
    defaultValue: 'http://127.0.0.1:8789',
  );
  // 本地 workers/reminder/.dev.vars 里的 REMIND_TOKEN
  const String token = String.fromEnvironment('REMIND_TOKEN', defaultValue: 'dev-token');

  test('App 的完成数与 Worker 的完成数一致', () async {
    if (!enabled) {
      // ignore: avoid_print
      print('跳过口径对账（加 --dart-define=PARITY=1 才跑，且需要本地两个服务）');
      return;
    }

    // flutter_test 默认把 HttpClient 换成「一律回 400」的假实现，真实网络要先放行
    HttpOverrides.global = null;

    final records = await LedgerApi(ApiClient()).fetchRecords();

    final dio = Dio();
    final response = await dio.post<dynamic>(
      '$workerBase/trigger?dry=1',
      options: Options(
        headers: <String, String>{'Authorization': 'Bearer $token'},
        validateStatus: (_) => true,
      ),
    );
    expect(response.statusCode, 200, reason: 'Worker 没应答：$workerBase（响应体 ${response.data}）');

    final Map<String, dynamic> body = Map<String, dynamic>.from(response.data as Map);
    final int workerDone = (body['done'] as num).toInt();
    final String workerDay = body['dayKey'] as String;

    final completion = countDayCompletions(records);

    // ignore: avoid_print
    print('对账：App done=${completion.done} dayKey=${completion.dayKey} / '
        'Worker done=$workerDone dayKey=$workerDay（$apiBase 共 ${records.length} 条流水）');

    expect(completion.dayKey, workerDay, reason: '「今天」是哪一天必须一致（东八区）');
    expect(completion.done, workerDone, reason: '今天完成的任务数必须一致');
  });
}
