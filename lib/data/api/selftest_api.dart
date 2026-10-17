import 'dart:convert';

import 'package:dio/dio.dart';

import '../../config/app_constants.dart';
import '../../core/api_client.dart';
import '../../core/api_exception.dart';

/// 全站自检（`/api/admin/selftest`）的接口层。
///
/// 契约见 `docs/selftest-console.md`（Web 版同一份），三条必须照抄：
/// - GET 清单**不需要密码**，POST 才要；
/// - 整轮预算是 45 秒、单项 10 秒，比 [AppConstants.requestTimeout] 的 12 秒长得多，
///   所以这里单独造一个只调大接收超时的 `Dio`，仍然套 [ApiClient] 那套
///   「先读 body 里的 error 当文案 / 可重试状态码 / 超时文案」逻辑，不另写一份；
/// - `params` 在清单里是**数组**、在结果里是**回显的 map**，两者不能混着解析。
class SelftestApi {
  SelftestApi({ApiClient? api}) : _api = api ?? ApiClient(dio: _buildDio());

  final ApiClient _api;

  static const String path = '/api/admin/selftest';

  /// 整轮预算 45 秒 + 一点余量：短于服务端预算就会把「还在跑」误判成本地超时。
  static const Duration runTimeout = Duration(seconds: 60);

  static Dio _buildDio() => Dio(
        BaseOptions(
          baseUrl: AppConstants.apiBase,
          connectTimeout: AppConstants.requestTimeout,
          receiveTimeout: runTimeout,
          sendTimeout: AppConstants.requestTimeout,
          responseType: ResponseType.json,
          headers: const <String, dynamic>{'Accept': 'application/json'},
          validateStatus: (_) => true,
        ),
      );

  /// 读清单（免密）。面板进来先调这个，之后所有勾选项/参数都从这里出。
  Future<SelftestManifest> fetchManifest() async {
    final raw = await _api.getJson<Map<String, dynamic>>(path);
    if (raw == null) throw const ApiException('自检清单没有返回内容', 0);
    return SelftestManifest.fromJson(raw);
  }

  /// 跑一轮。
  ///
  /// [clientResults] 是本地已经跑完的客户端检查项（`side == 'client'`）；
  /// 服务端不会替客户端跑，没回传的会被标成 `skip: client-side`。
  /// [items] 为空表示「服务端自己按 groups 挑」，所以这里只在非空时才带上。
  Future<SelftestReport> run({
    required String password,
    List<String>? items,
    List<String>? groups,
    Map<String, dynamic>? params,
    List<SelftestClientResult>? clientResults,
    bool? includeClient,
  }) async {
    final raw = await _api.postJson<Map<String, dynamic>>(
      path,
      data: <String, dynamic>{
        'password': password,
        if (items != null && items.isNotEmpty) 'items': items,
        if (groups != null && groups.isNotEmpty) 'groups': groups,
        if (params != null && params.isNotEmpty) 'params': params,
        'clientResults': ?_encodeClientResults(clientResults),
        'includeClient': ?includeClient,
      },
    );
    if (raw == null) throw const ApiException('自检没有返回内容', 0);
    return SelftestReport.fromJson(raw);
  }

  /// 客户端结果进 body 前摊平成契约要的 `[{id, status, detail, data?}]`。
  List<Map<String, dynamic>>? _encodeClientResults(List<SelftestClientResult>? results) {
    if (results == null) return null;
    return <Map<String, dynamic>>[
      for (final SelftestClientResult result in results) result.toJson(),
    ];
  }
}

// ------------------------------------------------------------------ 清单模型

/// 清单里的参数类型（`params[].type`）。
enum SelftestParamType {
  flag('bool'),
  integer('int'),
  text('string'),
  choice('enum');

  const SelftestParamType(this.raw);

  final String raw;

  static SelftestParamType parse(Object? value) {
    for (final SelftestParamType type in SelftestParamType.values) {
      if (type.raw == value) return type;
    }
    return SelftestParamType.text;
  }
}

/// 检查项 / 单个结果的状态（`pass|fail|warn|skip`）。
enum SelftestStatus {
  pass('pass', '通过', '✅'),
  fail('fail', '失败', '❌'),
  warn('warn', '警告', '⚠️'),
  skip('skip', '跳过', '⏭️');

  const SelftestStatus(this.raw, this.label, this.mark);

  final String raw;
  final String label;

  /// 报告表格里的图标（Markdown 导出用）
  final String mark;

  static SelftestStatus parse(Object? value) {
    for (final SelftestStatus status in SelftestStatus.values) {
      if (status.raw == value) return status;
    }
    return SelftestStatus.skip;
  }

  /// 需要用户处理的状态（结果列表把它们排在最前）
  bool get isProblem => this == fail || this == warn;
}

/// 一条可调参数。
class SelftestParam {
  const SelftestParam({
    required this.name,
    required this.label,
    required this.type,
    required this.desc,
    this.defaultValue,
    this.options = const <String>[],
  });

  final String name;
  final String label;
  final SelftestParamType type;
  final String desc;

  /// 清单里可能没有 `default`（比如 `now`、`title`），此时是 null。
  final Object? defaultValue;

  /// `type == enum` 时的候选值
  final List<String> options;

  factory SelftestParam.fromJson(Map<String, dynamic> json) {
    final options = json['options'];
    return SelftestParam(
      name: (json['name'] as String?) ?? '',
      label: (json['label'] as String?) ?? (json['name'] as String?) ?? '',
      type: SelftestParamType.parse(json['type']),
      desc: (json['desc'] as String?) ?? '',
      defaultValue: json['default'],
      options: options is List ? options.whereType<String>().toList() : const <String>[],
    );
  }
}

/// 一个检查项。
class SelftestItem {
  const SelftestItem({
    required this.id,
    required this.name,
    required this.desc,
    required this.side,
    required this.mutates,
    required this.danger,
    required this.params,
    required this.estMs,
  });

  final String id;
  final String name;
  final String desc;

  /// `server` / `client`
  final String side;

  /// 会不会写库
  final bool mutates;

  /// 清单里的危险级别：`safe` / `write` …（不是布尔，别拿 `as bool` 解）
  final String danger;

  /// 这一项会读哪些参数（对应清单 `params[].name`）
  final List<String> params;

  /// 服务端估的耗时（毫秒）
  final int estMs;

  /// 由客户端本地跑（服务端不碰）
  bool get isClient => side == 'client';

  /// 会动数据：默认不勾，跑之前要二次确认
  bool get isWrite => mutates || danger != 'safe';

  factory SelftestItem.fromJson(Map<String, dynamic> json) {
    final params = json['params'];
    return SelftestItem(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      desc: (json['desc'] as String?) ?? '',
      side: (json['side'] as String?) ?? 'server',
      mutates: json['mutates'] == true,
      danger: (json['danger'] as String?) ?? 'safe',
      params: params is List ? params.whereType<String>().toList() : const <String>[],
      estMs: (json['estMs'] as num?)?.round() ?? 0,
    );
  }
}

/// 一组检查项。
class SelftestGroup {
  const SelftestGroup({
    required this.id,
    required this.name,
    required this.desc,
    required this.items,
  });

  final String id;
  final String name;
  final String desc;
  final List<SelftestItem> items;

  factory SelftestGroup.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    return SelftestGroup(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      desc: (json['desc'] as String?) ?? '',
      items: items is List
          ? <SelftestItem>[
              for (final item in items)
                if (item is Map) SelftestItem.fromJson(item.cast<String, dynamic>()),
            ]
          : const <SelftestItem>[],
    );
  }
}

/// 一键套用的预设。
class SelftestPreset {
  const SelftestPreset({
    required this.id,
    required this.name,
    required this.desc,
    required this.params,
    required this.itemIds,
    required this.skipMutating,
  });

  final String id;
  final String name;
  final String desc;

  /// 套用时覆盖的参数（没列出的参数保持用户当前值）
  final Map<String, dynamic> params;

  /// 只勾这些检查项（**空表示按 [skipMutating] 或「全选」推**）
  final List<String> itemIds;

  /// 只跑不写库的项（`readonly` 预设用）
  final bool skipMutating;

  factory SelftestPreset.fromJson(Map<String, dynamic> json) {
    final params = json['params'];
    final itemIds = json['itemIds'];
    return SelftestPreset(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      desc: (json['desc'] as String?) ?? '',
      params: params is Map
          ? params.map((key, value) => MapEntry(key.toString(), value))
          : const <String, dynamic>{},
      itemIds: itemIds is List ? itemIds.whereType<String>().toList() : const <String>[],
      skipMutating: json['skipMutating'] == true,
    );
  }
}

/// 自检清单（`GET /api/admin/selftest`）。
class SelftestManifest {
  const SelftestManifest({
    required this.version,
    required this.generatedAt,
    required this.groups,
    required this.params,
    required this.presets,
    required this.webChecks,
    required this.flutterChecks,
  });

  final String version;
  final String generatedAt;
  final List<SelftestGroup> groups;
  final List<SelftestParam> params;
  final List<SelftestPreset> presets;

  /// `clientChecks.web`：浏览器端本地跑的检查项 id
  final List<String> webChecks;

  /// `clientChecks.flutter`：Flutter 端本地跑的检查项 id
  final List<String> flutterChecks;

  /// 全部检查项（按清单顺序摊平）
  List<SelftestItem> get items => <SelftestItem>[
        for (final SelftestGroup group in groups) ...group.items,
      ];

  SelftestItem? itemById(String id) {
    for (final SelftestGroup group in groups) {
      for (final SelftestItem item in group.items) {
        if (item.id == id) return item;
      }
    }
    return null;
  }

  SelftestParam? paramByName(String name) {
    for (final SelftestParam param in params) {
      if (param.name == name) return param;
    }
    return null;
  }

  /// 清单给的默认值（`default` 缺省的参数**不出现**在 map 里）
  Map<String, dynamic> get defaults => <String, dynamic>{
        for (final SelftestParam param in params)
          if (param.defaultValue != null) param.name: param.defaultValue,
      };

  factory SelftestManifest.fromJson(Map<String, dynamic> json) {
    final groups = json['groups'];
    final params = json['params'];
    final presets = json['presets'];
    final clientChecks = json['clientChecks'];
    final web = clientChecks is Map ? clientChecks['web'] : null;
    final flutter = clientChecks is Map ? clientChecks['flutter'] : null;
    return SelftestManifest(
      // 清单版本号是数字（比如 1），别当字符串硬转
      version: json['version']?.toString() ?? '',
      generatedAt: (json['generatedAt'] as String?) ?? '',
      groups: groups is List
          ? <SelftestGroup>[
              for (final group in groups)
                if (group is Map) SelftestGroup.fromJson(group.cast<String, dynamic>()),
            ]
          : const <SelftestGroup>[],
      params: params is List
          ? <SelftestParam>[
              for (final param in params)
                if (param is Map) SelftestParam.fromJson(param.cast<String, dynamic>()),
            ]
          : const <SelftestParam>[],
      presets: presets is List
          ? <SelftestPreset>[
              for (final preset in presets)
                if (preset is Map) SelftestPreset.fromJson(preset.cast<String, dynamic>()),
            ]
          : const <SelftestPreset>[],
      webChecks: web is List ? web.whereType<String>().toList() : const <String>[],
      flutterChecks: flutter is List ? flutter.whereType<String>().toList() : const <String>[],
    );
  }
}

// ------------------------------------------------------------------ 结果模型

/// 客户端本地跑完的一项检查，随 POST 回传给服务端。
class SelftestClientResult {
  const SelftestClientResult({
    required this.id,
    required this.status,
    required this.detail,
    this.data,
  });

  final String id;
  final SelftestStatus status;
  final String detail;

  /// 需要展开看的细节（路由表、色板对比度这些）
  final Object? data;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'status': status.raw,
        'detail': detail,
        if (data != null) 'data': data,
      };
}

/// 跑这一轮时的环境（服务端回显）。
class SelftestEnv {
  const SelftestEnv({
    required this.db,
    required this.origin,
    required this.now,
    required this.worker,
  });

  final String db;
  final String origin;
  final String now;
  final String worker;

  factory SelftestEnv.fromJson(Map<String, dynamic> json) => SelftestEnv(
        db: (json['db'] as String?) ?? '',
        origin: (json['origin'] as String?) ?? '',
        now: (json['now'] as String?) ?? '',
        worker: (json['worker'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'db': db,
        'origin': origin,
        'now': now,
        'worker': worker,
      };
}

/// 汇总。
class SelftestSummary {
  const SelftestSummary({
    required this.total,
    required this.passed,
    required this.failed,
    required this.skipped,
    required this.warned,
  });

  final int total;
  final int passed;
  final int failed;
  final int skipped;
  final int warned;

  /// 全过（没有失败也不算警告）
  bool get allGreen => failed == 0 && warned == 0;

  factory SelftestSummary.fromJson(Map<String, dynamic> json) => SelftestSummary(
        total: (json['total'] as num?)?.round() ?? 0,
        passed: (json['passed'] as num?)?.round() ?? 0,
        failed: (json['failed'] as num?)?.round() ?? 0,
        skipped: (json['skipped'] as num?)?.round() ?? 0,
        warned: (json['warned'] as num?)?.round() ?? 0,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'total': total,
        'passed': passed,
        'failed': failed,
        'skipped': skipped,
        'warned': warned,
      };
}

/// 单个检查项的结果。
class SelftestResult {
  const SelftestResult({
    required this.id,
    required this.group,
    required this.name,
    required this.side,
    required this.mutates,
    required this.ms,
    required this.status,
    required this.detail,
    this.data,
    this.hint,
  });

  final String id;
  final String group;
  final String name;
  final String side;
  final bool mutates;
  final int ms;
  final SelftestStatus status;
  final String detail;

  /// 结构化细节（成功时也常带，比如对账的双方数字）
  final Object? data;

  /// 失败时的下一步提示
  final String? hint;

  bool get hasData => data != null;

  factory SelftestResult.fromJson(Map<String, dynamic> json) => SelftestResult(
        id: (json['id'] as String?) ?? '',
        group: (json['group'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        side: (json['side'] as String?) ?? 'server',
        mutates: json['mutates'] == true,
        ms: (json['ms'] as num?)?.round() ?? 0,
        status: SelftestStatus.parse(json['status']),
        detail: (json['detail'] as String?) ?? '',
        data: json['data'],
        hint: json['hint']?.toString(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'group': group,
        'name': name,
        'side': side,
        'mutates': mutates,
        'ms': ms,
        'status': status.raw,
        'detail': detail,
        if (data != null) 'data': data,
        if (hint != null) 'hint': hint,
      };
}

/// 一轮自检的完整结果（`POST /api/admin/selftest`）。
class SelftestReport {
  const SelftestReport({
    required this.ranAt,
    required this.durationMs,
    required this.env,
    required this.params,
    required this.summary,
    required this.results,
    required this.notes,
    this.version,
    this.clientMissing = const <String>[],
  });

  final String ranAt;
  final int durationMs;
  final SelftestEnv env;

  /// 服务端回显的「这一轮实际用的参数」（没填的也在，值是 null）
  final Map<String, dynamic> params;
  final SelftestSummary summary;
  final List<SelftestResult> results;

  /// 服务端给整轮的备注（通常是「真发了一条通知」这类副作用说明）
  final List<String> notes;

  /// 新版后端才回；老版本没有就算了
  final String? version;

  /// 客户端检查项里没回传、被服务端标成 skip 的 id（新版后端才回）
  final List<String> clientMissing;

  /// 结果列表的展示顺序：失败最前、警告其次，然后跳过，最后通过。
  List<SelftestResult> get sortedResults {
    final List<SelftestResult> sorted = List<SelftestResult>.of(results);
    sorted.sort((SelftestResult a, SelftestResult b) {
      final int byStatus = _statusRank(a.status).compareTo(_statusRank(b.status));
      if (byStatus != 0) return byStatus;
      return a.id.compareTo(b.id);
    });
    return sorted;
  }

  static int _statusRank(SelftestStatus status) {
    switch (status) {
      case SelftestStatus.fail:
        return 0;
      case SelftestStatus.warn:
        return 1;
      case SelftestStatus.skip:
        return 2;
      case SelftestStatus.pass:
        return 3;
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (version != null) 'version': version,
        'ranAt': ranAt,
        'durationMs': durationMs,
        'env': env.toJson(),
        'params': params,
        'summary': summary.toJson(),
        'results': <Map<String, dynamic>>[
          for (final SelftestResult result in results) result.toJson(),
        ],
        'notes': notes,
        if (clientMissing.isNotEmpty) 'clientMissing': clientMissing,
      };

  factory SelftestReport.fromJson(Map<String, dynamic> json) {
    final env = json['env'];
    final summary = json['summary'];
    final results = json['results'];
    final notes = json['notes'];
    final params = json['params'];
    final clientMissing = json['clientMissing'];
    final resultsList = <SelftestResult>[
      for (final result in results is List ? results : const <Object?>[])
        if (result is Map) SelftestResult.fromJson(result.cast<String, dynamic>()),
    ];
    return SelftestReport(
      ranAt: (json['ranAt'] as String?) ?? '',
      durationMs: (json['durationMs'] as num?)?.round() ?? 0,
      env: env is Map ? SelftestEnv.fromJson(env.cast<String, dynamic>()) : const SelftestEnv(
        db: '',
        origin: '',
        now: '',
        worker: '',
      ),
      params: params is Map
          ? params.map((key, value) => MapEntry(key.toString(), value))
          : const <String, dynamic>{},
      summary: summary is Map
          ? SelftestSummary.fromJson(summary.cast<String, dynamic>())
          : const SelftestSummary(total: 0, passed: 0, failed: 0, skipped: 0, warned: 0),
      results: resultsList,
      notes: notes is List ? notes.map((value) => value.toString()).toList() : const <String>[],
      version: json['version']?.toString(),
      clientMissing: clientMissing is List ? clientMissing.whereType<String>().toList() : const <String>[],
    );
  }
}

// -------------------------------------------------------------------- 导出

/// 生成 Markdown 报告（格式与契约 §5 一致：表头、四行元信息、结果表格）。
///
/// [sentParams] 是这一轮**实际提交**的参数；不传就用服务端回显里非空的那部分。
String buildSelftestMarkdown(SelftestReport report, {Map<String, dynamic>? sentParams}) {
  final DateTime? ranAt = DateTime.tryParse(report.ranAt)?.toLocal();
  final Map<String, dynamic> params = sentParams ??
      <String, dynamic>{
        for (final entry in report.params.entries)
          if (entry.value != null) entry.key: entry.value,
      };
  final SelftestSummary summary = report.summary;

  final StringBuffer buffer = StringBuffer()
    ..writeln('# SekaiNook 自检报告')
    ..writeln('- 时间：${_formatMarkdownStamp(ranAt ?? DateTime.now())}')
    ..writeln(
      '- 环境：${report.env.origin.isEmpty ? '未知' : report.env.origin}'
      ' · Worker ${report.env.worker.isEmpty ? '未知' : report.env.worker}',
    )
    ..writeln(
      '- 参数：${params.isEmpty ? '（全部默认）' : params.entries.map((entry) => '${entry.key}=${_formatParamValue(entry.value)}').join(', ')}',
    );

  final List<String> counts = <String>[
    '${summary.total} 项',
    '通过 ${summary.passed}',
    '失败 ${summary.failed}',
  ];
  if (summary.warned > 0) counts.add('警告 ${summary.warned}');
  if (summary.skipped > 0) counts.add('跳过 ${summary.skipped}');
  buffer
    ..writeln('- 结果：${counts.join(' · ')}')
    ..writeln()
    ..writeln('| 结果 | 分组 | 检查项 | 耗时 | 详情 |')
    ..writeln('| --- | --- | --- | --- | --- |');

  for (final SelftestResult result in report.sortedResults) {
    buffer.writeln(
      '| ${result.status.mark} | ${_escapeCell(result.group)} | ${_escapeCell(result.name)} '
      '| ${result.ms}ms | ${_escapeCell(result.detail)}${result.hint == null ? '' : '（建议：${_escapeCell(result.hint!)}）'} |',
    );
  }

  return buffer.toString();
}

/// 把结果序列化成便于阅读的 JSON（「复制 JSON」用）。
String buildSelftestJson(SelftestReport report) =>
    const JsonEncoder.withIndent('  ').convert(report.toJson());

String _formatMarkdownStamp(DateTime time) {
  final Duration offset = time.timeZoneOffset;
  final String sign = offset.isNegative ? '-' : '+';
  final Duration absolute = offset.abs();
  final String hours = absolute.inHours.toString().padLeft(2, '0');
  final String minutes = (absolute.inMinutes % 60).toString().padLeft(2, '0');
  final String month = time.month.toString().padLeft(2, '0');
  final String day = time.day.toString().padLeft(2, '0');
  final String hour = time.hour.toString().padLeft(2, '0');
  final String minute = time.minute.toString().padLeft(2, '0');
  final String second = time.second.toString().padLeft(2, '0');
  return '${time.year}-$month-$day $hour:$minute:$second ($sign$hours:$minutes)';
}

/// 参数值进 Markdown 前压成一行：布尔写 `true/false`，其余 `toString`。
String _formatParamValue(Object? value) {
  if (value == null) return '（空）';
  if (value is String) return value.isEmpty ? '（空）' : value;
  return value.toString();
}

/// 表格单元里的 `|` 与换行会把表格撑破，先转义掉。
String _escapeCell(String raw) => raw.replaceAll('\r', ' ').replaceAll('\n', ' ').replaceAll('|', r'\|');
