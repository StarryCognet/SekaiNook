// Web 的实现：触发浏览器下载真文件（对应 Web 版 `src/utils/exportLedger.ts`）。
//
// 只用 `dart:js_interop`（和 `boot_splash_web.dart` 一样），不走已经弃用的 `dart:html`；
// 也不引 `package:web` —— 它在本项目里只是传递依赖，为一个 Blob 添一个直接依赖不划算。
//
// `href` / `download` / `click()` 这些成员名没法静态检查，只能靠 `dart:js_interop_unsafe`
// 动态读写。**这个分支在本机跑不了**（要真浏览器），改动务必在 `flutter build web`
// 与网页端上各验一次。

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'ledger_export_types.dart';

/// Excel 认 BOM：没有它，UTF-8 的中文列会显示成乱码（Web 版同样在拼 Blob 时加）
const String _utf8Bom = '\uFEFF';

/// `new Blob(parts, {type})`
@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external _Blob(JSArray<JSAny> parts, JSObject options);
}

/// 把 CSV 包成 Blob，挂一个临时 `<a download>` 点一下。
///
/// 落点由浏览器的下载设置决定，Dart 侧看不见，所以返回值里不带路径。
Future<LedgerExportResult> saveLedgerCsv(String csv, {String? fileName}) async {
  final String name = fileName ?? ledgerExportFileName(DateTime.now());
  // 对应 Web 版的 `new Blob([`\uFEFF${csv}`], {type: 'text/csv;charset=utf-8'})`
  final _Blob blob = _Blob(
    <JSAny>['$_utf8Bom$csv'.toJS].toJS,
    <String, String>{'type': 'text/csv;charset=utf-8'}.jsify()! as JSObject,
  );
  final JSObject url = globalContext.getProperty<JSObject>('URL'.toJS);
  final String href = url.callMethod<JSString>('createObjectURL'.toJS, blob).toDart;

  final JSObject document = globalContext.getProperty<JSObject>('document'.toJS);
  final JSObject link = document.callMethod<JSObject>('createElement'.toJS, 'a'.toJS);
  link.setProperty('href'.toJS, href.toJS);
  // download 属性就是「另存为时用这个文件名」
  link.setProperty('download'.toJS, name.toJS);
  // 挂进文档再点、点完摘掉：Firefox 对「没进 DOM 的 a」不触发下载
  final JSObject head = document.getProperty<JSObject>('head'.toJS);
  head.callMethod<JSAny?>('appendChild'.toJS, link);
  link.callMethod<JSAny?>('click'.toJS);
  head.callMethod<JSAny?>('removeChild'.toJS, link);
  // 这里**不**立刻 revokeObjectURL：部分浏览器会在下载真正开始前把它掐断。
  // 代价是每点一次导出多留一份 Blob（几十 KB），比「偶尔下载出个坏文件」划算。

  return LedgerExportResult(fileName: name);
}

/// 成功提示：Web 上说不出落点（下载目录由浏览器设置决定），只报文件名
String ledgerExportToastText(int count, LedgerExportResult result) =>
    '已开始下载 ${result.fileName}（$count 条流水）';
