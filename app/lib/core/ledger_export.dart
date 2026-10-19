// 「导出流水」落成真文件的外壳。
//
// Web 版是 `src/utils/exportLedger.ts` 里的浏览器下载：把 CSV 包成 Blob，挂一个临时
// `<a download>` 点一下。Flutter 侧分两条腿（桌面端谈不上，走兜底）：
//
// - 安卓/iOS：写一份 CSV 到临时目录，再交给系统分享面板，落点由用户自己挑
//   （最常用的一条是直接发到电脑上的微信）—— 见 `ledger_export_io.dart`；
// - Web：同样触发一次真下载 —— 见 `ledger_export_web.dart`。
//
// 平台分支走条件导入，和 `apk_installer.dart` / `boot_splash.dart` 同一套写法。
// 这么绕一下不只是风格问题：`dart:io` 一旦进了 Web 构建，`flutter build web` 直接编不过。
//
// 结果类型与文件名拼法在 `ledger_export_types.dart`（三个分支共用），这里一并转出去，
// 调用方只认这一个 import。
import 'ledger_export_stub.dart'
    if (dart.library.io) 'ledger_export_io.dart'
    if (dart.library.js_interop) 'ledger_export_web.dart' as impl;
import 'ledger_export_types.dart';

export 'ledger_export_types.dart' show LedgerExportResult, ledgerExportFileName;

/// 把一份 CSV 导出成真文件。
///
/// [csv] 传 `buildLedgerCsv()` 的返回值即可 —— BOM 由各平台实现补在**最终写出去的内容**
/// 里（Excel 打开中文才不乱码），不会污染 `buildLedgerCsv()` 本身的返回值。
///
/// [fileName] 只给测试用；不给就按 [ledgerExportFileName] 的
/// `sekainook-流水-YYYY-MM-DD.csv`。
///
/// 失败一律抛异常（磁盘满、没有可用目录、浏览器不给下载……），由调用方如实弹给用户，
/// 这里不吞。返回值说明文件最后落在哪，供调用方组织提示文案。
Future<LedgerExportResult> saveLedgerCsv(String csv, {String? fileName}) =>
    impl.saveLedgerCsv(csv, fileName: fileName);

/// 「导出成功」的统一反馈文案：两个入口说同一句话。
///
/// 平台不同，能说的话也不同（安卓说得出目录，Web 只说得出文件名），
/// 所以真正的措辞在各自的平台分支里。
String ledgerExportToastText(int count, LedgerExportResult result) =>
    impl.ledgerExportToastText(count, result);
