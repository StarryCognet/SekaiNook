// 安卓（以及将来可能的其它 `dart:io` 平台）的实现：把 CSV 落成临时文件，
// 再交给系统分享面板，落点由用户自己挑。
//
// 为什么不写进「下载」目录：`path_provider` 在安卓上给的 Downloads 其实是
// **应用专属**那一份（`Android/data/<包名>/files/Download`），系统文件管理器默认
// 不展示它 —— 按提示去「下载」里翻只会扑空。分享面板把「存哪 / 发给谁」交给用户，
// 这才是家里人拿到这份表格的真实路径（最常用的一条是直接发到电脑上的微信）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'ledger_export_types.dart';

/// Excel 认 BOM：没有它，UTF-8 的中文列会显示成乱码（Web 版同样在拼 Blob 时加）
const String _utf8Bom = '\uFEFF';

/// 写一份 CSV 到临时目录，调起系统分享面板，返回文件名与落点说明。
///
/// 失败（临时目录不可写、磁盘满、没有可分享的应用……）一律抛异常，
/// 交给调用方如实报给用户，这里不吞。
Future<LedgerExportResult> saveLedgerCsv(String csv, {String? fileName}) async {
  final String name = fileName ?? ledgerExportFileName(DateTime.now());
  final Directory dir = await getTemporaryDirectory();
  final File file = File('${dir.path}/$name');
  // BOM 加在最终写出去的内容上，`buildLedgerCsv()` 的返回值保持干净（别处还要引用它）
  await file.writeAsString('$_utf8Bom$csv', encoding: utf8, flush: true);

  // 这个 Future 到用户把分享面板处理完（送出或取消）才 resolve，
  // 所以下面那行删除不会抢在「保存到文件」完成之前把源文件抽走。
  await SharePlus.instance.share(
    ShareParams(
      files: <XFile>[XFile(file.path, mimeType: 'text/csv')],
      subject: name,
    ),
  );

  // 临时文件只是中转（真正那份已经在用户选的地方了），删掉不占地方。
  // 删不掉也无所谓，系统自己会回收临时目录。
  unawaited(file.delete().catchError((Object _) => file));

  return LedgerExportResult(fileName: name, location: '分享', path: file.path);
}

/// 成功提示：安卓上落点由用户在分享面板里挑，所以文案只说清「已经给出去了」
String ledgerExportToastText(int count, LedgerExportResult result) =>
    '已导出 $count 条流水，在分享面板里选个地方存下来吧';
