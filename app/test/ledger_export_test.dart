import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sekainook_app/core/ledger_csv.dart';
import 'package:sekainook_app/core/ledger_export.dart';
import 'package:sekainook_app/data/models/ledger_record.dart';

/// 这两个 mock 通道就是插件在安卓上真正走的那条路
/// （`path_provider` / `share_plus` 各自的 method channel）。
/// 用它们而不是 `setMockPathProviderPlatform()` 之类的平台接口桩：不用往
/// dev_dependencies 里塞两个间接依赖，而且测的是「真的调到了插件」。
const MethodChannel _pathProvider = MethodChannel('plugins.flutter.io/path_provider');
const MethodChannel _shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  bool shareCalled = false;
  List<Object?> sharedPaths = <Object?>[];
  List<int> bytesWhenShared = <int>[];

  setUp(() {
    root = Directory.systemTemp.createTempSync('ledger_export');
    shareCalled = false;
    sharedPaths = <Object?>[];
    bytesWhenShared = <int>[];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _pathProvider,
      (MethodCall call) async => call.method == 'getTemporaryDirectory' ? root.path : null,
    );

    // 假分享面板：不弹系统 UI，只记下「分享那一刻文件长什么样」。
    // 最常用的一条用法是直接发到电脑上的微信，所以这里就是家里人拿到表格的路径。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _shareChannel,
      (MethodCall call) async {
        shareCalled = true;
        final Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
        sharedPaths = args['paths']! as List<Object?>;
        // 真机上分享面板开着等用户操作（可能几十秒）。停 50 ms 再回来，是把
        // 「清理临时文件」的竞态逼出来：谁改成不等分享结束就删，这里会当场红。
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final File shared = File(sharedPaths.single! as String);
        if (shared.existsSync()) bytesWhenShared = shared.readAsBytesSync();
        return 'ok';
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_shareChannel, null);
    root.deleteSync(recursive: true);
  });

  // 文件名的日期取自本机时区：晚上 8 点以后导出，文件名不该写着「明天」
  test('文件名用本地日期，格式 sekainook-流水-YYYY-MM-DD.csv', () {
    expect(
      ledgerExportFileName(DateTime(2026, 10, 19, 21, 10)),
      'sekainook-流水-2026-10-19.csv',
    );
    expect(
      ledgerExportFileName(DateTime(2026, 1, 5, 0, 0)),
      'sekainook-流水-2026-01-05.csv',
    );
  });

  test('导出：写成带 BOM 的真 CSV，再交给分享面板', () async {
    const String csv = '时间,类型\r\n2026-10-19 14:32,收入\r\n';
    const String name = 'sekainook-流水-2026-10-19.csv';
    final LedgerExportResult result = await saveLedgerCsv(csv, fileName: name);

    expect(shareCalled, isTrue);
    expect(sharedPaths.single, endsWith('/$name'));
    expect(result.fileName, name);

    // 分享那一刻文件还在、且内容完整（临时文件必须活到用户把它存下来）
    expect(bytesWhenShared, isNotEmpty);
    // BOM 是给 Excel 认 UTF-8 的：少了它中文列在 Windows 上就是乱码
    expect(bytesWhenShared.sublist(0, 3), <int>[0xEF, 0xBB, 0xBF]);
    expect(bytesWhenShared.sublist(3), utf8.encode(csv));

    // 而 buildLedgerCsv 的返回值本身不带 BOM（别处还要引用这份文本）
    expect(buildLedgerCsv(<LedgerRecord>[]), isNot(startsWith('\uFEFF')));
  });

  test('分享结束后清掉临时文件（真正那份已经在用户选的地方）', () async {
    final LedgerExportResult result = await saveLedgerCsv('a,b\r\n', fileName: 'x.csv');
    // 删除是 unawaited 的：让出事件循环，等那次真实 IO 落下去
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(File(result.path!).existsSync(), isFalse);
  });
}
