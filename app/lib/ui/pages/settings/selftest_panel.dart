import 'package:sekainook_app/ui/icons/icons.dart';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sekainook_app/ui/widgets/app_toast.dart';
import 'package:sekainook_app/ui/widgets/app_loading.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_constants.dart';
import '../../../core/api_exception.dart';
import '../../../core/image_compress.dart';
import '../../../data/api/selftest_api.dart';
import '../../../theme/app_shape.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/motion.dart';
import '../../../theme/tokens.dart';
import '../../shell/app_nav_bar.dart';
import '../../shell/app_top_bar.dart';
import '../../widgets/app_card.dart';
import '../../widgets/motion_widgets.dart';
import '../../widgets/state_views.dart';
import '../../widgets/motion/app_buttons.dart';
import '../../widgets/motion/press_scale.dart';

/// 「设置 → 管理员 → 全站自检」面板（对应 Web 版同一块控制台）。
///
/// 契约在 `docs/selftest-console.md`：清单分组渲染、参数区、预设、先跑客户端
/// 再 POST、结果按状态着色并把失败排最前、JSON / Markdown 导出。
///
/// 密码不在这里收：管理员分区已经验证过一次，[password] 直接用那一份。
class SelftestPanel extends StatefulWidget {
  const SelftestPanel({super.key, required this.password, required this.onBack});

  /// 管理员密码（管理员分区解锁时存下来的那一份）
  final String password;

  /// 退回管理员分区
  final VoidCallback onBack;

  @override
  State<SelftestPanel> createState() => _SelftestPanelState();
}

class _SelftestPanelState extends State<SelftestPanel> {
  late final SelftestApi _api = SelftestApi();

  /// 契约里的 7 条路由（`flutter.routes` 逐条对表用）
  static const List<String> _expectedRoutes = <String>[
    '/role',
    '/home',
    '/family',
    '/home/notifications',
    '/family/plan',
    '/garden',
    '/settings',
  ];

  /// 本地存储自检用的探针键（写完立刻删）
  static const String _storageProbeKey = 'sekainook_selftest_probe';

  SelftestManifest? _manifest;
  bool _loading = true;
  String? _loadError;

  /// 勾选了的检查项 id
  final Set<String> _selected = <String>{};

  /// 参数值（bool / int / String），缺键 = 没填
  final Map<String, dynamic> _values = <String, dynamic>{};
  final Map<String, TextEditingController> _controllers = <String, TextEditingController>{};

  /// 折起来的分组（默认全展开：先让人看清有哪些项）
  final Set<String> _collapsedGroups = <String>{};

  /// 当前套用的预设 id（只做高亮，改动参数/勾选后不清空）
  String? _activePreset;

  bool _running = false;
  String _phase = '';
  int _clientDone = 0;
  int _clientTotal = 0;
  SelftestReport? _report;
  Map<String, dynamic>? _sentParams;
  String? _runError;

  /// 展开了 data 的结果 id
  final Set<String> _expandedData = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final TextEditingController controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------------ 数据

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final SelftestManifest manifest = await _api.fetchManifest();
      if (!mounted) return;
      _seed(manifest);
      setState(() {
        _manifest = manifest;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error is ApiException ? error.message : '清单读取失败，请重试';
      });
    }
  }

  /// 清单到手后的初值：参数取 default，勾选「不写库的服务端项 + Flutter 客户端项」。
  ///
  /// 写库项默认不勾（契约 §6：危险项默认不跑），`web.*` 也不勾 —— 那些是浏览器端
  /// 的检查项，Flutter 里跑只会得到一条 skip。
  void _seed(SelftestManifest manifest) {
    _selected
      ..clear()
      ..addAll(_defaultSelection(manifest));
    _values
      ..clear()
      ..addAll(manifest.defaults);
    for (final TextEditingController controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    for (final SelftestParam param in manifest.params) {
      if (param.type == SelftestParamType.flag || param.type == SelftestParamType.choice) continue;
      _controllers[param.name] = TextEditingController(text: _values[param.name]?.toString() ?? '');
    }
    _activePreset = null;
  }

  Set<String> _defaultSelection(SelftestManifest manifest) {
    final Set<String> ids = <String>{};
    for (final SelftestItem item in manifest.items) {
      if (item.isWrite) continue;
      if (item.isClient && !manifest.flutterChecks.contains(item.id)) continue;
      ids.add(item.id);
    }
    return ids;
  }

  /// 预设里 `itemIds` 支持 `前缀.*` 通配（`client.web` 就是 `web.*`）
  bool _matchesItemId(String pattern, String id) {
    if (pattern.endsWith('*')) return id.startsWith(pattern.substring(0, pattern.length - 1));
    return pattern == id;
  }

  void _applyPreset(SelftestPreset preset) {
    final SelftestManifest? manifest = _manifest;
    if (manifest == null) return;
    setState(() {
      _activePreset = preset.id;
      _values.addAll(preset.params);
      _syncControllers();

      final Set<String> next = <String>{};
      if (preset.itemIds.isNotEmpty) {
        for (final SelftestItem item in manifest.items) {
          for (final String pattern in preset.itemIds) {
            if (_matchesItemId(pattern, item.id)) {
              next.add(item.id);
              break;
            }
          }
        }
      } else if (preset.skipMutating) {
        for (final SelftestItem item in manifest.items) {
          if (item.isWrite) continue;
          if (item.isClient && !manifest.flutterChecks.contains(item.id)) continue;
          next.add(item.id);
        }
      } else {
        // 「全量检查」：服务端项全要 + Flutter 客户端项；`web.*` 跑不了，跳过
        for (final SelftestItem item in manifest.items) {
          if (item.isClient && !manifest.flutterChecks.contains(item.id)) continue;
          next.add(item.id);
        }
      }
      _selected
        ..clear()
        ..addAll(next);
    });
  }

  void _syncControllers() {
    for (final MapEntry<String, TextEditingController> entry in _controllers.entries) {
      final String text = _values[entry.key]?.toString() ?? '';
      if (entry.value.text != text) entry.value.text = text;
    }
  }

  /// 只把「有值的参数」发给服务端：空文本框不该覆盖服务端的默认口径。
  Map<String, dynamic> _collectedParams(SelftestManifest manifest) {
    final Map<String, dynamic> result = <String, dynamic>{};
    for (final SelftestParam param in manifest.params) {
      final Object? value = _values[param.name];
      if (value == null) continue;
      if (value is String && value.trim().isEmpty) continue;
      result[param.name] = value;
    }
    return result;
  }

  // ------------------------------------------------------------------ 动作

  Future<void> _run() async {
    final SelftestManifest? manifest = _manifest;
    if (manifest == null || _running) return;
    final List<SelftestItem> picked = <SelftestItem>[
      for (final SelftestItem item in manifest.items)
        if (_selected.contains(item.id)) item,
    ];
    if (picked.isEmpty) {
      _toast('先勾几个检查项', error: true);
      return;
    }

    final bool dryRun = _values['dryRun'] != false;
    final List<SelftestItem> writes = <SelftestItem>[
      for (final SelftestItem item in picked)
        if (!item.isClient && item.isWrite) item,
    ];
    // 写库项只在「dryRun 关掉」时才真写；那时必须再问一次（契约 §6）
    if (writes.isNotEmpty && !dryRun) {
      final bool ok = await _confirm(
        title: '确认跑 ${writes.length} 个写库项？',
        description: 'dryRun 是关的，下面这些会真的写库 / 真发通知（跑完会自清理）：\n'
            '${writes.map((SelftestItem item) => item.name).join('、')}',
        okText: '照跑',
        danger: true,
      );
      if (!ok || !mounted) return;
    }

    final List<SelftestItem> clientItems = <SelftestItem>[
      for (final SelftestItem item in picked)
        if (item.isClient) item,
    ];

    setState(() {
      _running = true;
      _runError = null;
      _report = null;
      _sentParams = null;
      _expandedData.clear();
      _clientDone = 0;
      _clientTotal = clientItems.length;
      _phase = clientItems.isEmpty ? '准备中…' : '客户端自检 0/${clientItems.length}';
    });

    try {
      final List<SelftestClientResult> clientResults = await _runClientChecks(clientItems);
      if (!mounted) return;
      setState(() => _phase = '服务端运行中（整轮预算 45 秒）…');

      final Map<String, dynamic> params = _collectedParams(manifest);
      final SelftestReport report = await _api.run(
        password: widget.password,
        items: <String>[for (final SelftestItem item in picked) item.id],
        params: params,
        clientResults: clientResults,
      );
      if (!mounted) return;
      setState(() {
        _running = false;
        _phase = '';
        _report = report;
        _sentParams = params;
      });
      if (report.summary.failed == 0) showBurst(context);
      _toast(report.summary.allGreen ? '自检跑完，全绿' : '自检跑完，${report.summary.failed} 项失败');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _phase = '';
        _runError = error is ApiException ? error.message : '自检没跑起来，请重试';
      });
      _toast(_runError!, error: true);
    }
  }

  /// 只跑失败项：把上次 fail/warn 的项重新勾上再跑
  Future<void> _runFailed() async {
    final SelftestReport? report = _report;
    final SelftestManifest? manifest = _manifest;
    if (report == null || manifest == null || _running) return;
    final Set<String> ids = <String>{
      for (final SelftestResult result in report.results)
        if (result.status.isProblem && manifest.itemById(result.id) != null) result.id,
    };
    if (ids.isEmpty) {
      _toast('上一轮没有失败项');
      return;
    }
    setState(() {
      _selected
        ..clear()
        ..addAll(ids);
    });
    await _run();
  }

  /// 全部跑一遍：服务端项（含写库）+ Flutter 客户端项
  Future<void> _runAll() async {
    final SelftestManifest? manifest = _manifest;
    if (manifest == null || _running) return;
    setState(() {
      _selected
        ..clear()
        ..addAll(<String>[
          for (final SelftestItem item in manifest.items)
            if (!item.isClient || manifest.flutterChecks.contains(item.id)) item.id,
        ]);
    });
    await _run();
  }

  /// 只跑写库项（dryRun 默认开着，真写要手动关）
  Future<void> _runWrites() async {
    final SelftestManifest? manifest = _manifest;
    if (manifest == null || _running) return;
    final Set<String> ids = <String>{
      for (final SelftestItem item in manifest.items)
        if (!item.isClient && item.isWrite) item.id,
    };
    if (ids.isEmpty) {
      _toast('清单里没有写库项');
      return;
    }
    setState(() {
      _selected
        ..clear()
        ..addAll(ids);
    });
    await _run();
  }

  Future<void> _copyJson() async {
    final SelftestReport? report = _report;
    if (report == null) return;
    await Clipboard.setData(ClipboardData(text: buildSelftestJson(report)));
    if (!mounted) return;
    _toast('JSON 已复制到剪贴板');
  }

  Future<void> _copyMarkdown() async {
    final SelftestReport? report = _report;
    if (report == null) return;
    final String markdown = buildSelftestMarkdown(report, sentParams: _sentParams);
    await Clipboard.setData(ClipboardData(text: markdown));
    if (!mounted) return;
    _toast('Markdown 已复制到剪贴板');
  }

  void _toggleGroup(String id) {
    setState(() {
      if (!_collapsedGroups.remove(id)) _collapsedGroups.add(id);
    });
  }

  void _toggleItem(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _toggleGroupSelection(SelftestGroup group) {
    final int picked = group.items.where((SelftestItem item) => _selected.contains(item.id)).length;
    setState(() {
      if (picked == group.items.length) {
        for (final SelftestItem item in group.items) {
          _selected.remove(item.id);
        }
      } else {
        for (final SelftestItem item in group.items) {
          _selected.add(item.id);
        }
      }
    });
  }

  void _toggleAll(bool selectAll) {
    final SelftestManifest? manifest = _manifest;
    if (manifest == null) return;
    setState(() {
      _selected.clear();
      if (selectAll) _selected.addAll(manifest.items.map((SelftestItem item) => item.id));
    });
  }

  // -------------------------------------------------------------- 客户端自检

  /// 逐项跑客户端检查；每一项都回一条 [SelftestClientResult]。
  Future<List<SelftestClientResult>> _runClientChecks(List<SelftestItem> items) async {
    final List<SelftestClientResult> results = <SelftestClientResult>[];
    for (final SelftestItem item in items) {
      if (!mounted) break;
      setState(() {
        _clientDone = results.length;
        _phase = '客户端自检 ${results.length + 1}/${items.length}：${item.name}';
      });
      results.add(await _runClientCheck(item));
      // 让出一帧：图片压缩这种同步重活之前，先把「正在跑哪一项」画出来
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    return results;
  }

  Future<SelftestClientResult> _runClientCheck(SelftestItem item) async {
    switch (item.id) {
      case 'flutter.routes':
        return _checkRoutes(item.id);
      case 'flutter.theme':
        return _checkTheme(item.id);
      case 'flutter.storage':
        return _checkStorage(item.id);
      case 'flutter.image':
        return _checkImage(item.id);
      case 'flutter.notify.permission':
      case 'flutter.notify.schedule':
      case 'flutter.notify.cancel':
        // 本仓库没引本地通知插件，也不为自检去加依赖 —— 如实 skip
        return SelftestClientResult(
          id: item.id,
          status: SelftestStatus.skip,
          detail: '本地通知尚未接入（需 flutter_local_notifications）',
        );
    }
    if (item.id.startsWith('web.')) {
      return SelftestClientResult(
        id: item.id,
        status: SelftestStatus.skip,
        detail: '这是 Web 端检查项（${item.id}），Flutter 客户端跑不了',
      );
    }
    return SelftestClientResult(
      id: item.id,
      status: SelftestStatus.skip,
      detail: 'Flutter 端没有实现这一项（${item.id}）',
    );
  }

  /// 路由表 + 当前 location。
  ///
  /// go_router 没有公开的 routes 列表，但它挂在 RouterConfig 上的
  /// [GoRouteInformationParser] 公开了 `configuration.routes` —— 从这里把
  /// 路由表摊平对表。**不逐条 go**：那会离开设置页、把面板状态冲掉。
  SelftestClientResult _checkRoutes(String id) {
    try {
      final GoRouter router = GoRouter.of(context);
      final String location = router.routerDelegate.currentConfiguration.uri.toString();
      final RouteInformationParser<Object?> parser = router.routeInformationParser;
      if (parser is! GoRouteInformationParser) {
        return SelftestClientResult(
          id: id,
          status: SelftestStatus.skip,
          detail: '读不到 go_router 路由表（解析器是 ${parser.runtimeType}），只确认了当前 location=$location',
        );
      }
      final List<String> paths = <String>[];
      void walk(List<RouteBase> routes, String prefix) {
        for (final RouteBase route in routes) {
          if (route is GoRoute) {
            final String path = _joinRoutePath(prefix, route.path);
            paths.add(path);
            walk(route.routes, path);
          } else if (route is StatefulShellRoute) {
            for (final StatefulShellBranch branch in route.branches) {
              walk(branch.routes, prefix);
            }
          } else {
            walk(route.routes, prefix);
          }
        }
      }

      walk(parser.configuration.routes, '');
      final List<String> missing = <String>[
        for (final String path in _expectedRoutes)
          if (!paths.contains(path)) path,
      ];
      final bool locationKnown = paths.contains(_stripQuery(location));
      final Map<String, dynamic> data = <String, dynamic>{
        'location': location,
        'routes': paths,
        'expected': _expectedRoutes,
      };
      if (missing.isNotEmpty) {
        return SelftestClientResult(
          id: id,
          status: SelftestStatus.fail,
          detail: '路由表缺 ${missing.join('、')}（现有 ${paths.length} 条）',
          data: data,
        );
      }
      if (!locationKnown) {
        return SelftestClientResult(
          id: id,
          status: SelftestStatus.warn,
          detail: '当前 location「$location」不在路由表里',
          data: data,
        );
      }
      return SelftestClientResult(
        id: id,
        status: SelftestStatus.pass,
        detail: '当前 $location；7 条路由都在表里（未逐条 go：会离开设置页、冲掉面板状态）',
        data: data,
      );
    } catch (error) {
      return SelftestClientResult(
        id: id,
        status: SelftestStatus.fail,
        detail: '读路由表出错：$error',
      );
    }
  }

  /// 主题：存的键是否合法 + 7 个种子（明暗各一遍）能不能构建 + 色板对比度。
  Future<SelftestClientResult> _checkTheme(String id) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? current = prefs.getString(AppTheme.storageKey);

    bool knownId(String? value) =>
        value != null && AppTheme.all.any((AppThemePreset preset) => preset.id.name == value);
    final List<String> broken = <String>[];
    final Map<String, double> ratios = <String, double>{};
    double worst = double.infinity;
    String worstWhere = '';

    for (final AppThemePreset preset in AppTheme.all) {
      final String name = preset.id.name; // ignore: unnecessary_string_interpolations
      try {
        AppTheme.build(preset.id, dark: false);
        AppTheme.build(preset.id, dark: true);
      } catch (error) {
        broken.add('$name 构建失败：$error');
        continue;
      }
      final AppPalette palette = AppTheme.paletteOf(preset.id, dark: false);
      // 阈值与 test/palette_contrast_test.dart 一致（正文 4.5 / 次要 3.5）
      final List<_ContrastPair> pairs = <_ContrastPair>[
        _ContrastPair('text / surface', palette.text, palette.surface, 4.5),
        _ContrastPair('textSecondary / surface', palette.textSecondary, palette.surface, 3.5),
        _ContrastPair('textTertiary / surface', palette.textTertiary, palette.surface, 4.5),
        _ContrastPair('onPrimary / primary', palette.onPrimary, palette.primary, 4.5),
        _ContrastPair('onSoft / primarySoft', palette.onSoft, palette.primarySoft, 4.5),
        _ContrastPair('onColor / success', palette.onColor(palette.success), palette.success, 4.5),
        _ContrastPair('onColor / danger', palette.onColor(palette.danger), palette.danger, 4.5),
        _ContrastPair('onColor / warning', palette.onColor(palette.warning), palette.warning, 3.5),
      ];
      double presetWorst = double.infinity;
      for (final _ContrastPair pair in pairs) {
        final double ratio = _contrastRatio(pair.foreground, pair.background);
        if (ratio < pair.min) {
          broken.add('$name ${pair.what} 只有 ${ratio.toStringAsFixed(2)}:1（要求 ≥ ${pair.min}）');
        }
        if (ratio < presetWorst) presetWorst = ratio;
        if (ratio < worst) {
          worst = ratio;
          worstWhere = '$name ${pair.what}';
        }
      }
      if (presetWorst.isFinite) ratios[name] = presetWorst;
    }

    final List<String> invalid = <String>[
      if (current != null && !knownId(current)) '${AppTheme.storageKey}=$current',
    ];
    final List<String> missing = <String>[
      if (current == null) AppTheme.storageKey,
    ];
    final Map<String, dynamic> data = <String, dynamic>{
      'current': current,
      'brightness': prefs.getString(AppTheme.brightnessKey),
      'minContrast': ratios,
      'broken': broken,
    };
    final String worstText =
        worst.isFinite ? '最低对比度 ${worst.toStringAsFixed(2)}:1（$worstWhere）' : '对比度未测';

    if (broken.isNotEmpty || invalid.isNotEmpty) {
      return SelftestClientResult(
        id: id,
        status: SelftestStatus.fail,
        detail: <String>[
          if (broken.isNotEmpty) broken.join('；'),
          if (invalid.isNotEmpty) '存的值不合法：${invalid.join('、')}（会回落到出厂主题）',
        ].join('；'),
        data: data,
      );
    }
    if (missing.isNotEmpty) {
      return SelftestClientResult(
        id: id,
        status: SelftestStatus.warn,
        detail: '还没存过 ${missing.join('、')}；7 套主题都能构建，$worstText',
        data: data,
      );
    }
    return SelftestClientResult(
      id: id,
      status: SelftestStatus.pass,
      detail: '主题=$current · 明暗=${prefs.getString(AppTheme.brightnessKey) ?? "未存"}；7 套都能构建，$worstText',
      data: data,
    );
  }

  /// 关键存储键可读写：探针键写 → 读 → 删，再列一遍 `sekainook_*` 键。
  Future<SelftestClientResult> _checkStorage(String id) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String probe = DateTime.now().toIso8601String();
    try {
      await prefs.setString(_storageProbeKey, probe);
      final String? readBack = prefs.getString(_storageProbeKey);
      await prefs.remove(_storageProbeKey);
      final String? afterRemove = prefs.getString(_storageProbeKey);
      final List<String> keys = prefs.getKeys().where((String key) => key.startsWith('sekainook_')).toList()
        ..sort();
      final Map<String, dynamic> data = <String, dynamic>{'keys': keys, 'probe': probe};
      if (readBack != probe) {
        return SelftestClientResult(
          id: id,
          status: SelftestStatus.fail,
          detail: '写入后读回的不一样（写 $probe，读到 $readBack）',
          data: data,
        );
      }
      if (afterRemove != null) {
        return SelftestClientResult(
          id: id,
          status: SelftestStatus.fail,
          detail: '删除后还能读到（$afterRemove）',
          data: data,
        );
      }
      return SelftestClientResult(
        id: id,
        status: SelftestStatus.pass,
        detail: '读写删都正常；本机有 ${keys.length} 个 sekainook_* 键',
        data: data,
      );
    } catch (error) {
      return SelftestClientResult(
        id: id,
        status: SelftestStatus.fail,
        detail: 'SharedPreferences 读写失败：$error',
      );
    }
  }

  /// 图片压缩：造一张 1800×1200 的噪点图（纯色图 PNG 比 JPEG 还小，测不出来），
  /// 走一遍 [compressImage]，断言长边 ≤ [maxImageSide] 且体积变小。
  SelftestClientResult _checkImage(String id) {
    const int width = 1800;
    const int height = 1200;
    final Stopwatch watch = Stopwatch()..start();
    try {
      final img.Image source = img.Image(width: width, height: height);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int noise = (x * 73856093) ^ (y * 19349663);
          source.setPixelRgb(x, y, noise & 0xFF, (noise >> 8) & 0xFF, (noise >> 16) & 0xFF);
        }
      }
      final List<int> png = img.encodePng(source);
      final Uint8List? compressed = compressImage(png);
      if (compressed == null) {
        return SelftestClientResult(
          id: id,
          status: SelftestStatus.fail,
          detail: 'compressImage 返回 null（这张 PNG 解不开？）',
        );
      }
      final img.Image? decoded = img.decodeImage(compressed);
      if (decoded == null) {
        return SelftestClientResult(
          id: id,
          status: SelftestStatus.fail,
          detail: '压缩结果不是可解码的图片（${compressed.length} 字节）',
        );
      }
      watch.stop();
      final int longSide = math.max(decoded.width, decoded.height);
      final Map<String, dynamic> data = <String, dynamic>{
        'source': '${width}x$height PNG ${png.length} 字节',
        'output': '${decoded.width}x${decoded.height} JPEG ${compressed.length} 字节',
        'ms': watch.elapsedMilliseconds,
      };
      if (longSide > maxImageSide) {
        return SelftestClientResult(
          id: id,
          status: SelftestStatus.fail,
          detail: '长边 $longSide 超过 $maxImageSide',
          data: data,
        );
      }
      if (compressed.length >= png.length) {
        return SelftestClientResult(
          id: id,
          status: SelftestStatus.fail,
          detail: '压缩后反而变大：${png.length} → ${compressed.length} 字节',
          data: data,
        );
      }
      return SelftestClientResult(
        id: id,
        status: SelftestStatus.pass,
        detail: '$width×$height → ${decoded.width}×${decoded.height}；'
            '${png.length} → ${compressed.length} 字节（${watch.elapsedMilliseconds}ms）',
        data: data,
      );
    } catch (error) {
      return SelftestClientResult(
        id: id,
        status: SelftestStatus.fail,
        detail: '图片压缩自检出错：$error',
      );
    }
  }

  // ------------------------------------------------------------------ 小工具

  void _toast(String message, {bool error = false}) {
    AppToast.show(
      context,
      message,
      tone: error ? AppToastTone.error : AppToastTone.neutral,
    );
  }

  Future<bool> _confirm({
    required String title,
    required String description,
    required String okText,
    bool danger = false,
  }) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final AppPalette palette = dialogContext.palette;
        return AlertDialog(
          backgroundColor: palette.surface,
          title: Text(
            title,
            style: TextStyle(
              fontSize: AppFontSize.md,
              fontWeight: FontWeight.w600,
              color: palette.text,
            ),
          ),
          content: Text(
            description,
            style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
          ),
          actions: <Widget>[
            AppTextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            AppFilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: danger ? palette.danger : palette.primary,
                foregroundColor: palette.onColor(danger ? palette.danger : palette.primary),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(okText),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  // ------------------------------------------------------------------ 渲染

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final SelftestManifest? manifest = _manifest;

    if (_loading) {
      return ListView(
        padding: _pagePadding(context),
        children: <Widget>[
          _header(palette),
          const SizedBox(height: AppSpacing.md),
          const AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SkeletonLine(height: 18, widthFactor: 0.4),
                SizedBox(height: AppSpacing.sm),
                SkeletonLine(height: 14, widthFactor: 0.8),
                SizedBox(height: AppSpacing.sm),
                SkeletonLine(height: 14, widthFactor: 0.6),
              ],
            ),
          ),
        ],
      );
    }

    if (manifest == null) {
      return ListView(
        padding: _pagePadding(context),
        children: <Widget>[
          _header(palette),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: ErrorView(message: _loadError ?? '清单没读到', onRetry: _load),
          ),
        ],
      );
    }

    return ListView(
      padding: _pagePadding(context),
      children: <Widget>[
        _header(palette),
        const SizedBox(height: AppSpacing.xs),
        SectionHeader(
          title: '全站自检',
          subtitle: '逐项跑一遍后端与客户端 · 清单 v${manifest.version}',
        ),
        _buildEnvCard(palette, manifest),
        _buildParamsCard(palette, manifest),
        _buildItemsCard(palette, manifest),
        _buildRunCard(palette, manifest),
        if (_runError != null) _buildErrorCard(palette),
        if (_report != null) _buildReportCard(palette, manifest, _report!),
      ],
    );
  }

  Widget _header(AppPalette palette) {
    return Row(
      children: <Widget>[
        AppIconButton(
          onPressed: widget.onBack,
          tooltip: '返回管理员',
          icon: GlyphIcon(AppIcons.arrowBack, color: palette.text),
        ),
        Text(
          '管理员',
          style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text('/', style: TextStyle(fontSize: AppFontSize.sm, color: palette.textTertiary)),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            '全站自检',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppFontSize.sm,
              fontWeight: FontWeight.w600,
              color: palette.text,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEnvCard(AppPalette palette, SelftestManifest manifest) {
    final int paramCount = manifest.params.length;
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _CardHead(
            title: '跑之前先看一眼',
            description: '清单免密可读；点「运行」才会把密码和勾选项发出去。'
                '参数留空的服务端按自己的口径算',
          ),
          const SizedBox(height: AppSpacing.sm),
          _InfoRow(label: '接口', value: '${AppConstants.apiBase}${SelftestApi.path}'),
          _InfoRow(label: '清单版本', value: manifest.version.isEmpty ? '未知' : manifest.version),
          _InfoRow(
            label: '生成于',
            value: _formatStamp(DateTime.tryParse(manifest.generatedAt)),
          ),
          _InfoRow(label: '检查项', value: '${manifest.groups.length} 组 / ${manifest.items.length} 项'),
          _InfoRow(label: '参数', value: '$paramCount 个'),
          _InfoRow(label: '管理员密码', value: widget.password.isEmpty ? '没拿到' : '已解锁'),
        ],
      ),
    );
  }

  Widget _buildParamsCard(AppPalette palette, SelftestManifest manifest) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _CardHead(
            title: '参数',
            description: '先套预设，再按需改；留空的不会发给服务端',
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              for (final SelftestPreset preset in manifest.presets)
                _PresetChip(
                  preset: preset,
                  active: _activePreset == preset.id,
                  onTap: _running ? null : () => _applyPreset(preset),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final SelftestParam param in manifest.params)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _buildParamField(palette, param),
            ),
        ],
      ),
    );
  }

  Widget _buildParamField(AppPalette palette, SelftestParam param) {
    final String label = param.label.isEmpty ? param.name : param.label;
    switch (param.type) {
      case SelftestParamType.flag:
        return Row(
          children: <Widget>[
            Expanded(
              child: _ParamLabel(label: label, desc: param.desc),
            ),
            Switch.adaptive(
              value: _values[param.name] == true,
              onChanged: _running
                  ? null
                  : (bool value) => setState(() => _values[param.name] = value),
            ),
          ],
        );
      case SelftestParamType.choice:
        final String? current = _values[param.name] as String?;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _ParamLabel(label: label, desc: param.desc),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                for (final String option in param.options)
                  _OptionChip(
                    label: option,
                    selected: current == option,
                    onTap: _running
                        ? null
                        : () => setState(() => _values[param.name] = option),
                  ),
              ],
            ),
          ],
        );
      case SelftestParamType.integer:
      case SelftestParamType.text:
        final TextEditingController? controller = _controllers[param.name];
        return _ParamLabeledField(
          label: label,
          desc: param.desc,
          child: _panelField(
            context,
            controller: controller ?? TextEditingController(text: _values[param.name]?.toString() ?? ''),
            hint: param.type == SelftestParamType.integer ? '整数' : '留空 = 不传',
            keyboardType: param.type == SelftestParamType.integer
                ? const TextInputType.numberWithOptions(signed: true)
                : TextInputType.text,
            onChanged: _running
                ? null
                : (String text) {
                    final String trimmed = text.trim();
                    if (trimmed.isEmpty) {
                      _values.remove(param.name);
                    } else if (param.type == SelftestParamType.integer) {
                      final int? parsed = int.tryParse(trimmed);
                      if (parsed == null) return;
                      _values[param.name] = parsed;
                    } else {
                      _values[param.name] = text;
                    }
                  },
          ),
        );
    }
  }

  Widget _buildItemsCard(AppPalette palette, SelftestManifest manifest) {
    final int total = manifest.items.length;
    final int picked = _selected.length;
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Checkbox(
                value: picked == 0 ? false : (picked == total ? true : null),
                tristate: true,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: _running ? null : (bool? value) => _toggleAll(value == true),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  '全选（已选 $picked / $total 项）',
                  style: TextStyle(
                    fontSize: AppFontSize.sm,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
              ),
              AppTextButton(
                onPressed: _running ? null : () => _toggleAll(false),
                child: const Text('全不选'),
              ),
            ],
          ),
          Text(
            '写库项默认不勾（契约：危险项要手动勾，dryRun 关掉时还会再确认一次）；'
            '「客户端自检」由本机跑完再把结果随请求发出去',
            style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final SelftestGroup group in manifest.groups) _buildGroup(palette, group),
        ],
      ),
    );
  }

  Widget _buildGroup(AppPalette palette, SelftestGroup group) {
    final bool collapsed = _collapsedGroups.contains(group.id);
    final int picked = group.items.where((SelftestItem item) => _selected.contains(item.id)).length;
    final bool? value = picked == 0
        ? false
        : (picked == group.items.length ? true : null);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: ShapeDecoration(
        color: palette.surfaceSoft,
        shape: AppShape.all(AppRadius.md, side: BorderSide(color: palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () => _toggleGroup(group.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: <Widget>[
                  Checkbox(
                    value: value,
                    tristate: true,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: _running
                        ? null
                        : (bool? checked) => _toggleGroupSelection(group),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${group.name}（$picked/${group.items.length}）',
                          style: TextStyle(
                            fontSize: AppFontSize.sm,
                            fontWeight: FontWeight.w600,
                            color: palette.text,
                          ),
                        ),
                        if (group.desc.isNotEmpty)
                          Text(
                            group.desc,
                            style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                          ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: collapsed ? 0 : 0.5,
                    duration: AppMotion.fast,
                    curve: AppMotion.standard,
                    child: GlyphIcon(AppIcons.chevronDown, size: 20, color: palette.textTertiary),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: AppMotion.fast,
            firstCurve: AppMotion.standard,
            secondCurve: AppMotion.standard,
            crossFadeState: collapsed ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                0,
                AppSpacing.sm,
                AppSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final SelftestItem item in group.items) _buildItem(palette, item),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(AppPalette palette, SelftestItem item) {
    final bool selected = _selected.contains(item.id);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: _running ? null : () => _toggleItem(item.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Checkbox(
              value: selected,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: _running ? null : (bool? checked) => _toggleItem(item.id),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text(
                        item.name,
                        style: TextStyle(
                          fontSize: AppFontSize.sm,
                          fontWeight: FontWeight.w600,
                          color: palette.text,
                        ),
                      ),
                      if (item.isClient) const _MiniTag(text: '客户端自检'),
                      if (item.isWrite) const _MiniTag(text: '写库'),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    item.desc,
                    style: TextStyle(
                      fontSize: AppFontSize.xs,
                      color: palette.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    <String>[
                      '${item.estMs}ms',
                      'id ${item.id}',
                      if (item.params.isNotEmpty) '参数 ${item.params.join('、')}',
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: AppFontSize.xs,
                      color: palette.textTertiary,
                      fontFeatures: kTabularNumbers,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRunCard(AppPalette palette, SelftestManifest manifest) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _CardHead(title: '运行', description: '先跑客户端检查项，再把结果和勾选项一起交给后端'),
          const SizedBox(height: AppSpacing.sm),
          if (_running) ...<Widget>[
            Row(
              children: <Widget>[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: AppLoading(size: 20, color: palette.primary),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _phase.isEmpty ? '运行中…' : _phase,
                    style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
                  ),
                ),
                if (_clientTotal > 0)
                  Text(
                    '$_clientDone/$_clientTotal',
                    style: TextStyle(
                      fontSize: AppFontSize.xs,
                      color: palette.textTertiary,
                      fontFeatures: kTabularNumbers,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              AppFilledButton.icon(
                onPressed: _running ? null : _run,
                icon: const GlyphIcon(AppIcons.play, size: 18),
                label: Text(_running ? '跑着…' : '运行所选（${_selected.length}）'),
              ),
              AppOutlinedButton(
                onPressed: _running ? null : _runAll,
                child: const Text('全部跑一遍'),
              ),
              AppOutlinedButton(
                onPressed: _running || _report == null ? null : _runFailed,
                child: const Text('只跑失败项'),
              ),
              AppOutlinedButton(
                onPressed: _running ? null : _runWrites,
                child: const Text('只跑写库项'),
              ),
            ],
          ),
          if (_report != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                AppOutlinedButton.icon(
                  onPressed: _copyJson,
                  icon: const GlyphIcon(AppIcons.copy, size: 18),
                  label: const Text('复制 JSON'),
                ),
                AppOutlinedButton.icon(
                  onPressed: _copyMarkdown,
                  icon: const GlyphIcon(AppIcons.file, size: 18),
                  label: const Text('导出 Markdown'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorCard(AppPalette palette) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          GlyphIcon(AppIcons.error, size: 18, color: palette.dangerInk),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              _runError ?? '',
              style: TextStyle(fontSize: AppFontSize.sm, color: palette.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(AppPalette palette, SelftestManifest manifest, SelftestReport report) {
    final SelftestSummary summary = report.summary;
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _CardHead(
                  title: '结果',
                  description: '${_formatStamp(DateTime.tryParse(report.ranAt)?.toLocal())}'
                      ' · 用时 ${report.durationMs}ms',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              _CountChip(label: '共', value: summary.total, color: palette.text),
              _CountChip(label: '通过', value: summary.passed, color: palette.successInk),
              _CountChip(label: '失败', value: summary.failed, color: palette.dangerInk),
              _CountChip(label: '警告', value: summary.warned, color: palette.warningInk),
              _CountChip(label: '跳过', value: summary.skipped, color: palette.textSecondary),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _InfoRow(
            label: '环境',
            value: '${report.env.origin} · Worker ${report.env.worker}',
          ),
          if (report.notes.isNotEmpty) _InfoRow(label: '备注', value: report.notes.join('；')),
          if (report.clientMissing.isNotEmpty)
            _InfoRow(label: '客户端缺项', value: report.clientMissing.join('、')),
          const SizedBox(height: AppSpacing.sm),
          for (final SelftestResult result in report.sortedResults)
            _buildResult(palette, manifest, result),
        ],
      ),
    );
  }

  Widget _buildResult(AppPalette palette, SelftestManifest manifest, SelftestResult result) {
    final Color color = _statusColor(palette, result.status);
    final bool expanded = _expandedData.contains(result.id);
    final SelftestGroup? group = _groupById(manifest, result.group);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              GlyphIcon(_statusIcon(result.status), size: 16, color: color),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(
                      result.name,
                      style: TextStyle(
                        fontSize: AppFontSize.sm,
                        fontWeight: FontWeight.w600,
                        color: palette.text,
                      ),
                    ),
                    if (group != null)
                      Text(
                        group.name,
                        style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                      ),
                    if (result.side == 'client') const _MiniTag(text: '客户端自检'),
                    if (result.mutates) const _MiniTag(text: '写库'),
                  ],
                ),
              ),
              Text(
                '${result.ms}ms',
                style: TextStyle(
                  fontSize: AppFontSize.xs,
                  color: palette.textTertiary,
                  fontFeatures: kTabularNumbers,
                ),
              ),
            ],
          ),
          if (result.detail.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              result.detail,
              style: TextStyle(
                fontSize: AppFontSize.xs,
                color: palette.textSecondary,
                height: 1.5,
              ),
            ),
          ],
          if (result.hint != null && result.hint!.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '建议：${result.hint}',
              style: TextStyle(fontSize: AppFontSize.xs, color: palette.warningInk, height: 1.5),
            ),
          ],
          if (result.hasData) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.xs),
              onTap: () {
                setState(() {
                  if (!_expandedData.remove(result.id)) _expandedData.add(result.id);
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      expanded ? '收起 data' : '展开 data',
                      style: TextStyle(
                        fontSize: AppFontSize.xs,
                        fontWeight: FontWeight.w600,
                        color: palette.primaryInk,
                      ),
                    ),
                    GlyphIcon(
                      expanded ? AppIcons.chevronUp : AppIcons.chevronDown,
                      size: 16,
                      color: palette.primaryInk,
                    ),
                  ],
                ),
              ),
            ),
            if (expanded) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: ShapeDecoration(
                  color: palette.surfaceSoft,
                  shape: AppShape.all(AppRadius.sm, side: BorderSide(color: palette.border)),
                ),
                child: SelectableText(
                  _prettyJson(result.data),
                  style: TextStyle(
                    fontSize: AppFontSize.xs,
                    color: palette.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  SelftestGroup? _groupById(SelftestManifest manifest, String id) {
    for (final SelftestGroup group in manifest.groups) {
      if (group.id == id) return group;
    }
    return null;
  }

  Color _statusColor(AppPalette palette, SelftestStatus status) {
    switch (status) {
      case SelftestStatus.pass:
        return palette.success;
      case SelftestStatus.fail:
        return palette.danger;
      case SelftestStatus.warn:
        return palette.warning;
      case SelftestStatus.skip:
        return palette.textTertiary;
    }
  }

  Glyph _statusIcon(SelftestStatus status) {
    switch (status) {
      case SelftestStatus.pass:
        return AppIcons.checkCircle;
      case SelftestStatus.fail:
        return AppIcons.close;
      case SelftestStatus.warn:
        return AppIcons.warning;
      case SelftestStatus.skip:
        return AppIcons.removeCircle;
    }
  }
}

// -------------------------------------------------------------------- 小零件

EdgeInsets _pagePadding(BuildContext context) => EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.sm + AppTopBar.contentInset(context),
      AppSpacing.md,
      AppSpacing.xl + AppNavBar.contentInset(context),
    );

/// 卡片标题（与设置页里那几个卡片的标题同款）
class _CardHead extends StatelessWidget {
  const _CardHead({required this.title, this.description});

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            fontSize: AppFontSize.md,
            fontWeight: FontWeight.w600,
            color: palette.text,
          ),
        ),
        if (description != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            description!,
            style: TextStyle(
              fontSize: AppFontSize.xs,
              color: palette.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}

/// 一行「标签：值」
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// 参数名 + 说明
class _ParamLabel extends StatelessWidget {
  const _ParamLabel({required this.label, required this.desc});

  final String label;
  final String desc;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontSize: AppFontSize.sm,
            fontWeight: FontWeight.w600,
            color: palette.text,
          ),
        ),
        if (desc.isNotEmpty)
          Text(
            desc,
            style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary, height: 1.5),
          ),
      ],
    );
  }
}

/// 上面是说明、下面是输入框
class _ParamLabeledField extends StatelessWidget {
  const _ParamLabeledField({required this.label, required this.desc, required this.child});

  final String label;
  final String desc;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ParamLabel(label: label, desc: desc),
        const SizedBox(height: AppSpacing.xs),
        child,
      ],
    );
  }
}

/// 输入框：颜色 / 圆角 / 字号一律走主题与令牌
Widget _panelField(
  BuildContext context, {
  required TextEditingController controller,
  String? hint,
  TextInputType? keyboardType,
  ValueChanged<String>? onChanged,
}) {
  final AppPalette palette = context.palette;
  return TextField(
    controller: controller,
    keyboardType: keyboardType,
    onChanged: onChanged,
    style: TextStyle(fontSize: AppFontSize.sm, color: palette.text),
    decoration: InputDecoration(
      hintText: hint,
      isDense: true,
      hintStyle: TextStyle(fontSize: AppFontSize.sm, color: palette.textTertiary),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: palette.primary),
      ),
    ),
  );
}

/// 预设按钮
class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.preset, required this.active, required this.onTap});

  final SelftestPreset preset;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Material(
          color: active ? palette.segmentedSelected : palette.surfaceSoft,
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: PressInkWell(
            borderRadius: BorderRadius.circular(AppRadius.full),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: ShapeDecoration(
                  shape: AppShape.all(AppRadius.full, side: BorderSide(color: active ? palette.primary : palette.border)),
              ),
              child: Text(
                preset.name,
                style: TextStyle(
                  fontSize: AppFontSize.xs,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? palette.onColor(palette.segmentedSelected) : palette.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 单选胶囊（参数 `type == enum` 用）
class _OptionChip extends StatelessWidget {
  const _OptionChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final Color background = selected ? palette.segmentedSelected : palette.surfaceSoft;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: PressInkWell(
        borderRadius: BorderRadius.circular(AppRadius.full),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          decoration: ShapeDecoration(
              shape: AppShape.all(AppRadius.full, side: BorderSide(color: selected ? palette.primary : palette.border)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppFontSize.xs,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? palette.onColor(background) : palette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// 小标签（客户端自检 / 写库）
class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 1),
      decoration: ShapeDecoration(
        color: palette.primarySoft,
        shape: AppShape.all(AppRadius.xs),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppFontSize.xs,
          fontWeight: FontWeight.w600,
          color: palette.onSoft,
        ),
      ),
    );
  }
}

/// 汇总里的一个数字
class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
        ),
        const SizedBox(width: 2),
        Text(
          '$value',
          style: TextStyle(
            fontSize: AppFontSize.md,
            fontWeight: FontWeight.w700,
            color: color,
            fontFeatures: kTabularNumbers,
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------- 纯函数

/// `fg` 压在 `bg` 上的对比度（WCAG 口径，1~21），半透明前景先合成。
double _contrastRatio(Color foreground, Color background) {
  final Color solid = _composite(foreground, background);
  final double fg = solid.computeLuminance();
  final double bg = background.computeLuminance();
  final double hi = math.max(fg, bg);
  final double lo = math.min(fg, bg);
  return (hi + 0.05) / (lo + 0.05);
}

Color _composite(Color foreground, Color background) {
  final double alpha = foreground.a;
  if (alpha >= 1) return foreground;
  return Color.from(
    alpha: 1,
    red: foreground.r * alpha + background.r * (1 - alpha),
    green: foreground.g * alpha + background.g * (1 - alpha),
    blue: foreground.b * alpha + background.b * (1 - alpha),
  );
}

class _ContrastPair {
  const _ContrastPair(this.what, this.foreground, this.background, this.min);

  final String what;
  final Color foreground;
  final Color background;
  final double min;
}

/// go_router 里父子路径拼成一条（子路由可以是相对路径）
String _joinRoutePath(String prefix, String path) {
  if (path.startsWith('/')) return path;
  if (prefix.isEmpty) return '/$path';
  return '$prefix/$path';
}

/// `/home?x=1` → `/home`
String _stripQuery(String location) {
  final int index = location.indexOf('?');
  return index < 0 ? location : location.substring(0, index);
}

/// 结果 `data` 展开后的样子
String _prettyJson(Object? data) {
  try {
    return const JsonEncoder.withIndent('  ').convert(data);
  } catch (_) {
    return data.toString();
  }
}

/// `2026-10-17 18:00:01`（本地时间；解析不了就写「时间未知」）
String _formatStamp(DateTime? time) {
  if (time == null) return '时间未知';
  final DateTime local = time.toLocal();
  final String month = local.month.toString().padLeft(2, '0');
  final String day = local.day.toString().padLeft(2, '0');
  final String hour = local.hour.toString().padLeft(2, '0');
  final String minute = local.minute.toString().padLeft(2, '0');
  final String second = local.second.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute:$second';
}
