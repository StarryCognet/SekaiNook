import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sekainook_app/ui/widgets/app_toast.dart';
import 'package:sekainook_app/ui/widgets/app_loading.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_constants.dart';
import '../../../config/changelog.dart';
import '../../../core/api_client.dart';
import '../../../core/api_exception.dart';
import '../../../core/image_compress.dart';
import '../../../data/api/admin_api.dart';
import '../../../data/api/changelog_api.dart';
import '../../../data/api/maintenance_api.dart';
import '../../../data/api/upload_api.dart';
import '../../../data/models/family_names.dart';
import '../../../state/family_state.dart';
import '../../../state/settings_state.dart';
import '../../../state/theme_state.dart';
import '../../../theme/app_shape.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/motion.dart';
import '../../../theme/tokens.dart';
import '../../widgets/app_card.dart';
import '../../widgets/motion_widgets.dart';
import '../../widgets/update_dialog.dart';
import '../../shell/app_nav_bar.dart';
import '../../shell/app_top_bar.dart';
import '../../shell/back_intent.dart';
import 'push_section.dart';
import 'selftest_panel.dart';
import '../../widgets/motion/app_buttons.dart';
import '../../widgets/motion/press_scale.dart';

/// 家长口令长度（与 Web 版一致：4-8 位）。
const int _pinMinLength = 4;
const int _pinMaxLength = 8;

/// [fg] 压在 [bg] 上的对比度（WCAG 口径，1~21）。
double _contrastRatio(Color fg, Color bg) {
  final double a = fg.computeLuminance();
  final double b = bg.computeLuminance();
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

/// warning / danger 这类强调色当正文或图标色用时的可读版本：衬不住卡片底就朝
/// 「底色的对色」方向压一档（金色 → 深金），色相留着 —— 只动前景色，不动底色。
Color _readableAccent(AppPalette palette, Color accent, {double minRatio = 4.5}) {
  final Color surface = palette.surface;
  if (_contrastRatio(accent, surface) >= minRatio) return accent;
  final Color target = palette.onColor(surface);
  Color best = accent;
  for (double t = 0.25; t <= 1.0001; t += 0.25) {
    best = Color.lerp(accent, target, t)!;
    if (_contrastRatio(best, surface) >= minRatio) return best;
  }
  return best;
}

/// 设置页（对应 Web 版 `src/views/settings/SettingsPage.tsx`）。
///
/// 两级结构：第一层只列大类入口（外观 / 家庭 / 家长管理 / 管理员 / 关于），
/// 点进去才是具体的主题、称呼、口令、清理、积分数这些小卡片。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

enum _SettingsSection { appearance, family, push, parent, admin }

class _SettingsPageState extends State<SettingsPage> {
  /// 版本日志收起时只留最近几条
  static const int _recentLogCount = 3;

  /// 「最近改过什么」最多列多少条
  static const int _adjustmentLogLimit = 20;

  final ApiClient _client = ApiClient();
  late final AdminApi _adminApi = AdminApi(_client);
  late final ChangelogApi _changelogApi = ChangelogApi(_client);
  late final MaintenanceApi _maintenanceApi = MaintenanceApi(_client);

  _SettingsSection? _section;

  // 外观：背景图（相册上传 + 图片地址两条路）
  final TextEditingController _backgroundCtrl = TextEditingController();
  bool _savingBackground = false;
  bool _uploadingBackground = false;

  // 家庭：称呼（妈妈/女儿的称呼与昵称）
  final TextEditingController _callCtrl = TextEditingController();
  final TextEditingController _nicknameCtrl = TextEditingController();
  bool _namesInitialized = false;
  bool _namesTouched = false;
  bool _syncingNames = false;
  bool _savingNames = false;

  /// 本机存着的称呼草稿（改了一半、还没保存的那半截）。
  /// 服务端那份到位时**草稿优先** —— 对应 Web 版的 `readNameDraft(nameTarget)`。
  ({String call, String nickname})? _nameDraft;

  // 家长管理：闲置照片清理
  bool _scanning = false;
  bool _cleaning = false;
  int _orphanCount = 0;
  String? _scanSummary;

  // 管理员
  String? _adminPassword;
  bool _adminUnlocked = false;
  final TextEditingController _familyTargetCtrl = TextEditingController();
  final TextEditingController _sunTargetCtrl = TextEditingController();
  bool _savingPoints = false;
  final TextEditingController _newAdminPasswordCtrl = TextEditingController();
  final TextEditingController _confirmAdminPasswordCtrl = TextEditingController();
  bool _changingAdminPassword = false;
  List<AdminAdjustment> _adjustments = const <AdminAdjustment>[];
  bool _loadingAdjustments = false;
  String? _revokingId;

  /// 管理员分区里又钻了一层「全站自检」；返回时只关这一层，不动 [_section]
  bool _selftestOpen = false;

  // 关于：版本日志展开 / 收起
  bool _logExpanded = false;

  /// 要展示的版本日志：先摆上本机那份（立刻有内容，不用等网络），
  /// 云端那份读到了再整体替换 —— 真源在服务端 D1，网页版和 App 看的才是同一份。
  List<ChangelogEntry> _logEntries = changelog;

  /// [_logEntries] 是不是云端来的；false = 正在用本机内置的那份兜底
  bool _logFromCloud = false;

  int _pinLockSeconds = 0;
  Timer? _lockTimer;

  @override
  void initState() {
    super.initState();
    _callCtrl.addListener(_onNameInputChanged);
    _nicknameCtrl.addListener(_onNameInputChanged);
    unawaited(_loadNameDraft());
    // 版本日志以云端为准（D1 那张表网页版和 App 共用）；读不到就继续用本机那份，不阻塞渲染
    unawaited(_loadChangelog());
    // 口令锁定时每秒把倒计时刷出来（和引导页同一套口径）
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final seconds = context.read<FamilyState>().pinLockRemaining.inSeconds;
      if (seconds != _pinLockSeconds) setState(() => _pinLockSeconds = seconds);
    });
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    _backgroundCtrl.dispose();
    _callCtrl.dispose();
    _nicknameCtrl.dispose();
    _familyTargetCtrl.dispose();
    _sunTargetCtrl.dispose();
    _newAdminPasswordCtrl.dispose();
    _confirmAdminPasswordCtrl.dispose();
    super.dispose();
  }

  void _onNameInputChanged() {
    if (_syncingNames) return;
    if (!mounted) return;
    setState(() => _namesTouched = true);
    unawaited(_writeNameDraft());
  }

  /// 草稿记在谁名下：家长编辑的是**孩子**的称呼，孩子编辑的是**妈妈**的
  /// （与 Web 版 `nameTarget` 同口径）。
  String get _nameDraftKey {
    final bool isParent = context.read<FamilyState>().role == FamilyRole.parent;
    return '${AppConstants.keyNameDraftPrefix}:${isParent ? 'kid' : 'mom'}';
  }

  /// 读本机草稿。读不出来 / 格式坏了都当没草稿，不影响页面。
  Future<void> _loadNameDraft() async {
    if (!mounted) return;
    ({String call, String nickname})? draft;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_nameDraftKey);
      if (raw != null) {
        final Object? parsed = jsonDecode(raw);
        if (parsed is Map) {
          final Object? call = parsed['call'];
          final Object? nickname = parsed['nickname'];
          if (call is String && nickname is String) {
            draft = (call: call, nickname: nickname);
          }
        }
      }
    } catch (_) {
      // 当没草稿
    }
    if (!mounted) return;
    _nameDraft = draft;
    // 草稿到了就填进输入框：服务端那份可能已经先填过一次，这里以草稿为准
    if (draft != null && !_namesTouched) {
      _syncingNames = true;
      _callCtrl.text = draft.call;
      _nicknameCtrl.text = draft.nickname;
      _syncingNames = false;
      _namesInitialized = true;
    }
  }

  /// 有改动就自动留一份草稿（对应 Web 版 `writeNameDraft`）。
  /// 存不下就算了，绝不拦着用户输入。
  Future<void> _writeNameDraft() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _nameDraftKey,
        jsonEncode(<String, String>{'call': _callCtrl.text, 'nickname': _nicknameCtrl.text}),
      );
      _nameDraft = (call: _callCtrl.text, nickname: _nicknameCtrl.text);
    } catch (_) {}
  }

  /// 已经进服务端了，草稿退休（对应 Web 版 `clearNameDraft`）。
  Future<void> _clearNameDraft() async {
    _nameDraft = null;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(_nameDraftKey);
    } catch (_) {}
  }

  /// 读云端版本日志（`GET /api/changelog`）。
  ///
  /// 读不到就静默继续用本机那份兜底 —— 表没迁移 / 还没同步 / 断网都会走到这儿。
  /// 日志是次要信息，不弹提示打扰用户；卡片底部那行小字会说清当前看的是哪一份。
  Future<void> _loadChangelog() async {
    try {
      final ChangelogPayload payload = await _changelogApi.fetchChangelog();
      if (!mounted || !payload.ready || payload.entries.isEmpty) return;
      setState(() {
        _logEntries = payload.entries;
        _logFromCloud = true;
      });
    } catch (_) {
      // 故意吞掉：ApiClient 抛 ApiException、JSON 形状不对抛别的类型，这里都不用区分
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = context.read<SettingsState>();
    // 云端称呼到了就填进输入框；用户已经动过手就不再覆盖。
    // 本机草稿优先于服务端那份（改了一半就走开也不丢，与 Web 版同口径）。
    if (settings.ready && !_namesTouched) {
      final ({String call, String nickname})? draft = _nameDraft;
      if (draft != null) {
        if (!_namesInitialized) {
          _namesInitialized = true;
          _syncingNames = true;
          _callCtrl.text = draft.call;
          _nicknameCtrl.text = draft.nickname;
          _syncingNames = false;
        }
        return;
      }
      if (!_namesInitialized || !_sameAsInputs(settings.names)) {
        _namesInitialized = true;
        _fillNameInputs(settings.names);
      }
    }
  }

  bool _sameAsInputs(FamilyNames names) {
    final isParent = context.read<FamilyState>().role == FamilyRole.parent;
    final call = isParent ? names.kidCall : names.momCall;
    final nickname = isParent ? names.kidNickname : names.momNickname;
    return _callCtrl.text == call && _nicknameCtrl.text == nickname;
  }

  void _fillNameInputs(FamilyNames names) {
    final isParent = context.read<FamilyState>().role == FamilyRole.parent;
    _syncingNames = true;
    _callCtrl.text = isParent ? names.kidCall : names.momCall;
    _nicknameCtrl.text = isParent ? names.kidNickname : names.momNickname;
    _syncingNames = false;
  }

  void _resetNameInputs() {
    _namesTouched = false;
    _namesInitialized = false;
    _fillNameInputs(context.read<SettingsState>().names);
  }

  // ---------------------------------------------------------------- 通用动作

  void _toast(String message, {bool error = false}) {
    AppToast.show(
      context,
      message,
      tone: error ? AppToastTone.error : AppToastTone.neutral,
    );
  }

  // ------------------------------------------------------------------ 主题

  Future<void> _pickTheme(AppThemePreset preset) async {
    final theme = context.read<ThemeState>();
    try {
      await theme.setThemeId(preset.id);
    } catch (error) {
      if (!mounted) return;
      _toast(error is ApiException ? error.message : '主题没换成功，请重试', error: true);
      return;
    }
    if (!mounted) return;
    _toast('已切换到「${preset.name}」主题');
  }

  /// 设置页那三档「浅色 / 深色 / 跟随系统」
  Future<void> _setBrightness(ThemeBrightness value) async {
    try {
      await context.read<ThemeState>().setBrightness(value);
    } catch (_) {
      if (!mounted) return;
      _toast('明暗没切成功，请重试', error: true);
    }
  }

  /// 从相册选一张照片 → 纯 Dart 压到长边 1600px → 传 R2 → 把地址存进服务端设置。
  /// 与 Web 版 `SettingsPage.tsx` 的背景图链路一致（image_picker + 压缩 + `/api/upload`）。
  Future<void> _uploadBackground() async {
    // 先取好依赖：await 之后就不该再碰 context 了
    final theme = context.read<ThemeState>();
    final uploadApi = UploadApi(_client);
    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    } catch (_) {
      if (!mounted) return;
      _toast('打不开相册，检查一下相册权限', error: true);
      return;
    }
    if (picked == null) return;
    setState(() => _uploadingBackground = true);
    try {
      final bytes = await picked.readAsBytes();
      final compressed = compressImage(bytes) ?? Uint8List.fromList(bytes);
      final result = await uploadApi.upload(compressed);
      await theme.saveBackground(result.url);
      if (!mounted) return;
      setState(() => _uploadingBackground = false);
      _toast('背景图已换好，另一台手机打开也是这张');
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploadingBackground = false);
      _toast(error is ApiException ? error.message : '上传失败，请重试', error: true);
    }
  }

  Future<void> _saveBackgroundUrl() async {
    final url = _backgroundCtrl.text.trim();
    if (url.isEmpty) {
      _toast('先粘一个图片地址，或者从相册选一张', error: true);
      return;
    }
    final theme = context.read<ThemeState>();
    setState(() => _savingBackground = true);
    try {
      await theme.saveBackground(url);
      if (!mounted) return;
      setState(() {
        _savingBackground = false;
        _backgroundCtrl.clear();
      });
      _toast('背景图已换好，另一台手机打开也是这张');
    } catch (error) {
      if (!mounted) return;
      setState(() => _savingBackground = false);
      _toast(error is ApiException ? error.message : '保存失败，请重试', error: true);
    }
  }

  Future<void> _removeBackground() async {
    final ok = await _confirmDialog(
      context,
      title: '移除背景图？',
      description: '移除后恢复主题自带的纯色底，照片会在下次清理闲置照片时从云端删掉',
      okText: '移除',
      danger: true,
    );
    if (!ok || !mounted) return;
    final theme = context.read<ThemeState>();
    setState(() => _savingBackground = true);
    try {
      await theme.saveBackground('');
      if (!mounted) return;
      setState(() => _savingBackground = false);
      _toast('已移除背景图');
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingBackground = false);
      _toast('移除失败，请重试', error: true);
    }
  }

  // ------------------------------------------------------------------ 家庭

  Future<void> _changeRole(FamilyRole next) async {
    final family = context.read<FamilyState>();
    if (next == FamilyRole.parent && family.role != FamilyRole.parent) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => _ParentPinDialog(family: family),
      );
      if (ok != true || !mounted) return;
    }
    try {
      await family.setRole(next);
    } catch (error) {
      if (!mounted) return;
      _toast(error is ApiException ? error.message : '身份没切成功，请重试', error: true);
      return;
    }
    if (!mounted) return;
    showBurst(context);
    setState(_resetNameInputs);
    _toast(next == FamilyRole.parent ? '已切换为家长' : '已切换为小孩');
  }

  Future<void> _changeParentPin() async {
    final family = context.read<FamilyState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ChangePinDialog(family: family),
    );
    if (ok != true || !mounted) return;
    showBurst(context);
    _toast('家长口令已更新');
  }

  Future<void> _saveNames() async {
    final settings = context.read<SettingsState>();
    final isParent = context.read<FamilyState>().role == FamilyRole.parent;
    final call = _callCtrl.text.trim();
    final nickname = _nicknameCtrl.text.trim();

    final callError = FamilyNames.validateName(call);
    final nicknameError = FamilyNames.validateName(nickname);
    if (callError != null || nicknameError != null) {
      _toast(callError ?? nicknameError!, error: true);
      return;
    }
    if (call.isEmpty && nickname.isEmpty) {
      _toast('称呼和昵称至少要填一个', error: true);
      return;
    }

    final patch = <String, dynamic>{};
    if (isParent) {
      patch['kidCall'] = call.isEmpty ? FamilyNames.defaultKidCall : call;
      patch['kidNickname'] = nickname;
    } else {
      patch['momCall'] = call.isEmpty ? FamilyNames.defaultMomCall : call;
      patch['momNickname'] = nickname;
    }

    setState(() => _savingNames = true);
    try {
      final saved = await settings.save(patch);
      if (!mounted) return;
      final who = isParent ? FamilyWho.kid : FamilyWho.mom;
      unawaited(_clearNameDraft()); // 已经进服务端了，草稿退休
      setState(() {
        _savingNames = false;
        _namesTouched = false;
        _namesInitialized = false;
        _fillNameInputs(saved);
      });
      _toast('已保存，界面上会显示「${saved.displayName(who)}」');
    } catch (error) {
      if (!mounted) return;
      setState(() => _savingNames = false);
      _toast(error is ApiException ? error.message : '保存失败，请重试', error: true);
    }
  }

  // -------------------------------------------------------------- 家长管理

  Future<void> _scanOrphans() async {
    setState(() => _scanning = true);
    try {
      final result = await _maintenanceApi.scan();
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _orphanCount = result.orphans;
        _scanSummary = result.orphans > 0
            ? '共 ${result.total} 张打卡照片，${result.referenced} 张还在用，有 ${result.orphans} 张闲置照片可以清理'
            : '共 ${result.total} 张打卡照片，全部还在用，没有需要清理的';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _scanning = false);
      _toast(error is ApiException ? error.message : '扫描失败，请重试', error: true);
    }
  }

  Future<void> _cleanOrphans() async {
    final ok = await _confirmDialog(
      context,
      title: '确认清理这 $_orphanCount 张闲置照片？',
      description: '照片将从云端永久删除，且不可恢复',
      okText: '清理',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _cleaning = true);
    try {
      final result = await _maintenanceApi.clean();
      if (!mounted) return;
      setState(() {
        _cleaning = false;
        _orphanCount = 0;
        _scanSummary = result.failed > 0
            ? '已清理 ${result.deleted} 张闲置照片，${result.failed} 张没清掉'
            : '已清理 ${result.deleted} 张闲置照片';
      });
      showBurst(context);
      _toast('已清理 ${result.deleted} 张闲置照片');
    } catch (error) {
      if (!mounted) return;
      setState(() => _cleaning = false);
      _toast(error is ApiException ? error.message : '清理失败，请重试', error: true);
    }
  }

  // ---------------------------------------------------------------- 管理员

  Future<void> _openAdmin() async {
    if (_adminUnlocked) {
      setState(() {
        _section = _SettingsSection.admin;
        _selftestOpen = false;
      });
      unawaited(_refreshAdjustments());
      return;
    }
    final api = _adminApi;
    final password = await showDialog<String>(
      context: context,
      builder: (_) => _AdminPasswordDialog(api: api),
    );
    if (password == null || !mounted) return;
    setState(() {
      _adminPassword = password;
      _adminUnlocked = true;
      _section = _SettingsSection.admin;
      _selftestOpen = false;
    });
    showBurst(context);
    _toast('已进入管理员');
    unawaited(_refreshBalances());
    unawaited(_refreshAdjustments());
  }

  Future<void> _refreshBalances() async {
    final family = context.read<FamilyState>();
    try {
      await family.loadLedger();
    } catch (_) {
      // 余额拉不到不挡面板，下面的输入框照样能用
    }
  }

  Future<void> _refreshAdjustments() async {
    final password = _adminPassword;
    if (password == null) return;
    setState(() => _loadingAdjustments = true);
    try {
      final list = await _adminApi.fetchAdjustments(password);
      if (!mounted) return;
      setState(() {
        _adjustments = list.adjustments;
        _loadingAdjustments = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _adjustments = const <AdminAdjustment>[];
        _loadingAdjustments = false;
      });
    }
  }

  Future<void> _savePoints() async {
    final familyRaw = _familyTargetCtrl.text.trim();
    final sunRaw = _sunTargetCtrl.text.trim();
    if (familyRaw.isEmpty && sunRaw.isEmpty) {
      _toast('先填一个想改的积分数');
      return;
    }
    final familyValue = familyRaw.isEmpty ? null : num.tryParse(familyRaw);
    final sunValue = sunRaw.isEmpty ? null : num.tryParse(sunRaw);
    if ((familyRaw.isNotEmpty && familyValue == null) || (sunRaw.isNotEmpty && sunValue == null)) {
      _toast('积分数只能填数字', error: true);
      return;
    }
    if ((familyValue != null && familyValue.abs() > AdminApi.maxAdjustAbs) ||
        (sunValue != null && sunValue.abs() > AdminApi.maxAdjustAbs)) {
      _toast('一次最多改 ${AdminApi.maxAdjustAbs}', error: true);
      return;
    }
    final password = _adminPassword;
    if (password == null) return;
    final family = context.read<FamilyState>();

    setState(() => _savingPoints = true);
    try {
      final result = await _adminApi.adjust(password, family: familyValue, sun: sunValue);
      if (!mounted) return;
      setState(() {
        _savingPoints = false;
        _familyTargetCtrl.clear();
        _sunTargetCtrl.clear();
      });
      try {
        await family.loadLedger();
      } catch (_) {
        // 余额刷新失败不影响「已经改成功」这个事实
      }
      await _refreshAdjustments();
      if (!mounted) return;
      _toast(result.changed.isEmpty ? '已保存' : '已修改：${result.changed.join('，')}');
    } catch (error) {
      if (!mounted) return;
      setState(() => _savingPoints = false);
      _toast(error is ApiException ? _adminErrorMessage(error) : '保存失败，请重试', error: true);
    }
  }

  Future<void> _clearLedger({required bool sun}) async {
    final password = _adminPassword;
    if (password == null) return;
    final family = context.read<FamilyState>();
    final label = sun ? '花园阳光' : '家庭积分';
    final current = sun ? family.sunBalance : family.balance;
    final ok = await _confirmDialog(
      context,
      title: '把$label从 ${_formatNum(current)} 清零？',
      description: '会记一条「管理员调整」流水，撤销入口就在下面',
      okText: '清零',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      final result = await _adminApi.adjust(
        password,
        family: sun ? null : 0,
        sun: sun ? 0 : null,
      );
      if (!mounted) return;
      try {
        await family.loadLedger();
      } catch (_) {
        // 同上
      }
      await _refreshAdjustments();
      if (!mounted) return;
      showBurst(context);
      _toast(result.changed.isEmpty ? '本来就是 0，没有改动' : '已清零：${result.changed.join('，')}');
    } catch (error) {
      if (!mounted) return;
      _toast(error is ApiException ? _adminErrorMessage(error) : '清零失败，请重试', error: true);
    }
  }

  Future<void> _revokeAdjustment(AdminAdjustment item) async {
    final family = context.read<FamilyState>();
    final ok = await _confirmDialog(
      context,
      title: '撤销这条调整？',
      description: '会删掉这条流水，余额回到改之前',
      okText: '撤销',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _revokingId = item.id);
    try {
      await family.removeRecord(item.id);
      await _refreshAdjustments();
      if (!mounted) return;
      _toast('已撤销，余额回到改之前');
    } catch (_) {
      if (!mounted) return;
      _toast('撤销失败，请重试', error: true);
    } finally {
      if (mounted) setState(() => _revokingId = null);
    }
  }

  Future<void> _changeAdminPassword() async {
    final password = _adminPassword;
    if (password == null) return;
    final next = _newAdminPasswordCtrl.text;
    if (next != _confirmAdminPasswordCtrl.text) {
      _toast('两次输入的新密码不一致', error: true);
      return;
    }
    if (next.length < AdminApi.passwordMinLength || next.length > AdminApi.passwordMaxLength) {
      _toast(
        '新密码需为 ${AdminApi.passwordMinLength}-${AdminApi.passwordMaxLength} 位',
        error: true,
      );
      return;
    }
    setState(() => _changingAdminPassword = true);
    try {
      await _adminApi.changePassword(password, next);
      if (!mounted) return;
      setState(() {
        _changingAdminPassword = false;
        _adminPassword = next;
        _newAdminPasswordCtrl.clear();
        _confirmAdminPasswordCtrl.clear();
      });
      showBurst(context);
      _toast('管理员密码已更新');
    } catch (error) {
      if (!mounted) return;
      setState(() => _changingAdminPassword = false);
      _toast(error is ApiException ? _adminErrorMessage(error) : '改密码失败，请重试', error: true);
    }
  }

  // ---------------------------------------------------------------- 退出身份

  Future<void> _signOut() async {
    final ok = await _confirmDialog(
      context,
      title: '退出当前身份？',
      description: '清掉这台手机记的身份，下次打开需要重新选「妈妈」或「女儿」',
      okText: '退出',
      danger: true,
    );
    if (!ok || !mounted) return;
    _toast('已清掉本机身份记录，下次打开需要重新选择');
    // clearRole() 会 notifyListeners，router 的 refreshListenable 随即把页面带回 /role
    await context.read<FamilyState>().clearRole();
  }

  // ------------------------------------------------------------------ 渲染

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final section = _section;
    // 系统返回键：先退一级（自检 → 分区 → 设置首页），设置首页上再按才交给外壳
    return BackIntentHandler(
      onBack: () {
        if (_selftestOpen) {
          setState(() => _selftestOpen = false);
          return true;
        }
        if (_section != null) {
          setState(() => _section = null);
          return true;
        }
        return false;
      },
      child: Scaffold(
        body: SafeArea(
          // 两级钻取：入口页和子页之间做一次横向滑淡切换
          child: SlideFadeSwitcher(
            childKey: ValueKey<_SettingsSection?>(section),
            child: section == null ? _buildIndex(palette) : _buildSection(palette, section),
          ),
        ),
      ),
    );
  }

  Widget _buildIndex(AppPalette palette) {
    final theme = context.watch<ThemeState>();
    final family = context.watch<FamilyState>();
    final isParent = family.role == FamilyRole.parent;

    return ListView(
      // 底部让出底栏胶囊的高度（`MainShell` 开了 extendBody，它是浮在内容上的）
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md + AppTopBar.contentInset(context),
        AppSpacing.md,
        AppSpacing.xl + AppNavBar.contentInset(context),
      ),
      children: <Widget>[
        Text(
          '设置',
          style: TextStyle(
            fontSize: AppFontSize.xl,
            fontWeight: FontWeight.w700,
            color: palette.text,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        EnterBox(
          index: 0,
          child: AppCard(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            onTap: () => setState(() => _section = _SettingsSection.appearance),
            child: _EntryRow(
              icon: Icons.palette_outlined,
              title: '外观',
              description:
                  '主题与背景图 · 现在是「${theme.preset.name}」主题${theme.hasBackground ? ' · 已设背景图' : ''}',
            ),
          ),
        ),
        EnterBox(
          index: 1,
          child: AppCard(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            onTap: () => setState(() => _section = _SettingsSection.family),
            child: _EntryRow(
              icon: Icons.family_restroom_outlined,
              title: '家庭',
              description: '身份与称呼 · 现在用的是${isParent ? '家长' : '小孩'}身份',
            ),
          ),
        ),
        EnterBox(
          index: 2,
          child: AppCard(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            onTap: () => setState(() => _section = _SettingsSection.push),
            child: const _EntryRow(
              icon: Icons.notifications_active_outlined,
              title: '手机提醒',
              description: '任务快到期时手机收提醒 · 可以发一条测试通知',
            ),
          ),
        ),
        if (isParent)
          EnterBox(
            index: 3,
            child: AppCard(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              onTap: () => setState(() => _section = _SettingsSection.parent),
              child: const _EntryRow(
                icon: Icons.lock_outline,
                title: '家长管理',
                description: '家长口令、打卡照片清理',
              ),
            ),
          ),
        EnterBox(
          index: 4,
          child: AppCard(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            onTap: _openAdmin,
            child: const _EntryRow(
              icon: Icons.tune_outlined,
              title: '管理员',
              description: '修改积分数 · 需要管理员密码',
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const SectionHeader(title: '关于', subtitle: '这是什么版本、改过什么'),
        EnterBox(
          index: 5,
          child: AppCard(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            AppConstants.appName,
                            style: TextStyle(
                              fontSize: AppFontSize.md,
                              fontWeight: FontWeight.w600,
                              color: palette.text,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '家庭财务与行为管理',
                            style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Text(
                          '当前版本',
                          style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        _Tag(text: 'v$appVersion'),
                      ],
                    ),
                  ],
                ),
                // 安卓才有这两行：装上就能自己更新；网页版刷新即最新，不摆这个入口
                const UpdateCheckTile(),
                const UpdateAutoCheckTile(),
              ],
            ),
          ),
        ),
        EnterBox(
          index: 6,
          child: AppCard(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _buildChangelog(palette),
          ),
        ),
        EnterBox(
          index: 7,
          child: AppCard(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            onTap: _signOut,
            child: const _EntryRow(
              icon: Icons.logout,
              title: '退出当前身份',
              description: '清掉本机记的身份，下次打开重新选（妈妈 / 女儿）',
              danger: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChangelog(AppPalette palette) {
    final entries = _logExpanded
        ? _logEntries
        : _logEntries.take(_recentLogCount).toList(growable: false);
    final more = _logEntries.length - _recentLogCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _CardHead(title: '版本日志'),
        const SizedBox(height: AppSpacing.sm),
        // 展开 / 收起时高度平滑过渡，不做会一跳一跳的裸 if
        AnimatedSize(
          duration: AppMotion.slow,
          curve: AppMotion.emphasized,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (int index = 0; index < entries.length; index++)
                _changelogEntry(palette, entries[index], isFirst: index == 0),
            ],
          ),
        ),
        if (more > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: AppTextButton(
              onPressed: () => setState(() => _logExpanded = !_logExpanded),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _logExpanded
                    ? '收起，只看最近 $_recentLogCount 个版本'
                    : '展开全部（共 ${_logEntries.length} 个版本）',
              ),
            ),
          ),
        if (more > 0)
          AnimatedSize(
            duration: AppMotion.fast,
            curve: AppMotion.emphasized,
            alignment: Alignment.topCenter,
            child: _logExpanded
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      '收起时只显示最近 $_recentLogCount 个版本，还有 $more 个更早的在里面',
                      style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                    ),
                  ),
          ),
        // 数据来源说明：日志存在云端 D1 里，网页版和 Flutter 版读的是同一份
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(
            _logFromCloud
                ? '已与云端同步：网页版和 Flutter 版看的是同一份日志'
                : '暂时读不到云端，显示的是本机内置的那一份',
            style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
          ),
        ),
      ],
    );
  }

  Widget _changelogEntry(AppPalette palette, ChangelogEntry entry, {required bool isFirst}) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: isFirst ? palette.primary : palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'v${entry.version}',
                style: TextStyle(
                  fontSize: AppFontSize.sm,
                  fontWeight: FontWeight.w600,
                  color: isFirst ? palette.primary : palette.text,
                  fontFeatures: kTabularNumbers,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  entry.date,
                  style: TextStyle(
                    fontSize: AppFontSize.xs,
                    color: palette.textTertiary,
                    fontFeatures: kTabularNumbers,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            entry.title,
            style: TextStyle(
              fontSize: AppFontSize.sm,
              fontWeight: FontWeight.w600,
              color: palette.text,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final change in entry.changes)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('· ', style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary)),
                  Expanded(
                    child: Text(
                      change,
                      style: TextStyle(
                        fontSize: AppFontSize.xs,
                        color: palette.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSection(AppPalette palette, _SettingsSection section) {
    switch (section) {
      case _SettingsSection.appearance:
        return _buildAppearance(palette);
      case _SettingsSection.family:
        return _buildFamily(palette);
      case _SettingsSection.push:
        return _buildPush(palette);
      case _SettingsSection.parent:
        return _buildParentTools(palette);
      case _SettingsSection.admin:
        return _buildAdmin(palette);
    }
  }

  Widget _buildAppearance(AppPalette palette) {
    final theme = context.watch<ThemeState>();
    return ListView(
      padding: _pagePadding(context),
      children: <Widget>[
        _subPageHeader(palette, '外观'),
        const SectionHeader(title: '外观', subtitle: '主题和背景图，改完这台手机立刻变'),
        AppCard(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const _CardHead(
                title: '主题',
                description:
                    '七种颜色，每种只要一个种子色 —— 整套色板由 Material You 推出来。只改这台手机，另一台自己选',
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  for (int index = 0; index < AppTheme.all.length; index++)
                    EnterBox(
                      index: index,
                      child: _themeTile(palette, AppTheme.all[index], theme.themeId),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Divider(height: 1, color: palette.border),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: <Widget>[
                  Text(
                    '明暗',
                    style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
                  ),
                  const Spacer(),
                  SegmentedButton<ThemeBrightness>(
                    segments: const <ButtonSegment<ThemeBrightness>>[
                      ButtonSegment<ThemeBrightness>(
                        value: ThemeBrightness.light,
                        label: Text('浅色'),
                      ),
                      ButtonSegment<ThemeBrightness>(
                        value: ThemeBrightness.dark,
                        label: Text('深色'),
                      ),
                      ButtonSegment<ThemeBrightness>(
                        value: ThemeBrightness.system,
                        label: Text('跟随系统'),
                      ),
                    ],
                    selected: <ThemeBrightness>{theme.brightness},
                    showSelectedIcon: false,
                    onSelectionChanged: (Set<ThemeBrightness> value) => _setBrightness(value.first),
                  ),
                ],
              ),
              // 纯黑只在深色下有意义，浅色下不给这个开关（点了也不会变）
              if (Theme.of(context).brightness == Brightness.dark) ...<Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '纯黑背景',
                            style: TextStyle(fontSize: AppFontSize.sm, color: palette.text),
                          ),
                          Text(
                            'OLED 屏上黑色像素不发光，能省一点电',
                            style: TextStyle(
                              fontSize: AppFontSize.xs,
                              color: palette.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: theme.pureBlack,
                      onChanged: (bool value) => theme.setPureBlack(value),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '跟随壁纸取色',
                          style: TextStyle(fontSize: AppFontSize.sm, color: palette.text),
                        ),
                        Text(
                          'Android 12+ 从壁纸里取主色，其它系统会自动退回上面选的色',
                          style: TextStyle(
                            fontSize: AppFontSize.xs,
                            color: palette.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: theme.followWallpaper,
                    onChanged: (bool value) => theme.setFollowWallpaper(value),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              const _CardHead(
                title: '字号',
                description: '整体放大或缩小正文；图标、间距不跟着变',
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Slider(
                      value: theme.textScale,
                      min: 0.8,
                      max: 1.4,
                      divisions: 12,
                      onChanged: (double value) => theme.setTextScale(value),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${(theme.textScale * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: AppFontSize.sm,
                        fontWeight: FontWeight.w600,
                        color: palette.text,
                        fontFeatures: kTabularNumbers,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              const _CardHead(
                title: '底栏不透明度',
                description:
                    '底部那颗胶囊。调低一点能看见从它后面滚过去的内容；默认不透明，觉得字看不清就调回 100%',
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Slider(
                      value: theme.navBarOpacity,
                      min: ThemeState.navOpacityMin,
                      max: ThemeState.navOpacityOpaque,
                      divisions: 10,
                      onChanged: theme.setNavBarOpacity,
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${(theme.navBarOpacity * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: AppFontSize.sm,
                        fontWeight: FontWeight.w600,
                        color: palette.text,
                        fontFeatures: kTabularNumbers,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        AppCard(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const _CardHead(title: '全局背景图', description: '换一张全家福当底色，两台手机会同步'),
              const SizedBox(height: AppSpacing.sm),
              if (!theme.backgroundReady)
                // 正在读服务端背景图：先用骨架占位，别让这一块空着不动
                const SkeletonBox(width: double.infinity, height: 140)
              else ...<Widget>[
                // 设了图 / 换了图时淡入，高度也一起平滑（不会把下面的按钮顶一下）
                AnimatedSize(
                  duration: AppMotion.slow,
                  curve: AppMotion.emphasized,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: AppMotion.slow,
                    switchInCurve: AppMotion.decelerate,
                    switchOutCurve: AppMotion.accelerate,
                    child: theme.hasBackground
                        ? ClipRRect(
                            key: ValueKey<String>(theme.background),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            child: Image.network(
                              theme.background,
                              height: 140,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                height: 140,
                                alignment: Alignment.center,
                                decoration: ShapeDecoration(
                                  color: palette.surfaceSoft,
                                  shape: AppShape.all(AppRadius.md),
                                ),
                                child: Text(
                                  '这张图打不开了，换一张吧',
                                  style: TextStyle(
                                    fontSize: AppFontSize.xs,
                                    color: palette.textTertiary,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey<String>('')),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  theme.hasBackground ? '现在用的就是这张，两台手机一样' : '还没设置背景图，现在用主题自带的纯色底',
                  style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              _inputField(
                context,
                controller: _backgroundCtrl,
                hint: '图片地址，例如 https://…/family.jpg',
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  AppFilledButton(
                    onPressed:
                        _savingBackground || _uploadingBackground ? null : _uploadBackground,
                    child: _uploadingBackground
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: AppLoading(size: 20),
                          )
                        : const Text('从相册选照片'),
                  ),
                  AppOutlinedButton(
                    onPressed:
                        _savingBackground || _uploadingBackground ? null : _saveBackgroundUrl,
                    child: _savingBackground
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: AppLoading(size: 20),
                          )
                        : const Text('用这个地址'),
                  ),
                  if (theme.hasBackground)
                    AppOutlinedButton(
                      onPressed:
                          _savingBackground || _uploadingBackground ? null : _removeBackground,
                      child: const Text('移除背景图'),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '建议用横图；上传前会自动压到长边 1600px，两台手机会同步',
                style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 一张主题色板卡：48px 圆切三块 —— 整圆是**页面底**、右上四分之一是**卡片底**、
  /// 右下四分之一是**主色**。
  ///
  /// 三个色是当场从种子色推出来的（[AppTheme.swatchOf]），所以色卡上看到的就是
  /// 选中之后整页的样子 —— 手写预览色迟早会和推导公式漂移。
  Widget _themeTile(AppPalette palette, AppThemePreset preset, ThemeId current) {
    final bool selected = preset.id == current;
    final List<Color> swatch = AppTheme.swatchOf(preset.id);
    return PressScale(
      scale: 0.94,
      onTap: () => _pickTheme(preset),
      child: SizedBox(
        width: 62,
        child: Column(
          children: <Widget>[
            AnimatedContainer(
              duration: AppMotion.fast,
              curve: AppMotion.standard,
              padding: const EdgeInsets.all(3),
              decoration: ShapeDecoration(
                shape: AppShape.all(
                  AppRadius.full,
                  side: BorderSide(
                    color: selected ? palette.primary : palette.border,
                    width: selected ? 2 : 1,
                  ),
                ),
              ),
              child: ClipOval(
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(child: ColoredBox(color: swatch[0])),
                      Positioned(
                        right: 0,
                        top: 0,
                        width: 22,
                        height: 22,
                        child: ColoredBox(color: swatch[1]),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        width: 22,
                        height: 22,
                        child: ColoredBox(color: swatch[2]),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              preset.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppFontSize.xs,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? palette.primary : palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFamily(AppPalette palette) {
    final family = context.watch<FamilyState>();
    final settings = context.watch<SettingsState>();
    final isParent = family.role == FamilyRole.parent;
    final serverCall = isParent ? settings.names.kidCall : settings.names.momCall;
    final serverNickname = isParent ? settings.names.kidNickname : settings.names.momNickname;

    final call = _callCtrl.text.trim();
    final nickname = _nicknameCtrl.text.trim();
    final dirty = settings.ready && (call != serverCall || nickname != serverNickname);
    final preview = nickname.isNotEmpty ? nickname : (call.isNotEmpty ? call : serverCall);

    return ListView(
      padding: _pagePadding(context),
      children: <Widget>[
        _subPageHeader(palette, '家庭'),
        const SectionHeader(title: '家庭', subtitle: '身份和称呼，两个人在各自手机上各管一半'),
        AppCard(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _CardHead(
                title: '当前身份',
                description: isParent ? '家长：可审批小孩的打卡申请' : '小孩：打卡后需家长审批',
              ),
              const SizedBox(height: AppSpacing.sm),
              _ChoiceRow(
                options: const <String>['家长', '小孩'],
                selectedIndex: isParent ? 0 : 1,
                onChanged: (index) => _changeRole(index == 0 ? FamilyRole.parent : FamilyRole.child),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                isParent ? '切回小孩无需口令，随时可切' : '切换为家长需输入家长口令',
                style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
              ),
            ],
          ),
        ),
        AppCard(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _CardHead(
                title: '称呼设置',
                description: isParent
                    ? '你的界面里，女儿叫什么（昵称优先，留空就显示称呼）'
                    : '你的界面里，妈妈叫什么（昵称优先，留空就显示称呼）',
              ),
              const SizedBox(height: AppSpacing.sm),
              _LabeledField(
                label: isParent ? '女儿的称呼' : '妈妈的称呼',
                child: _inputField(
                  context,
                  controller: _callCtrl,
                  hint: isParent ? '例如：女儿' : '例如：妈妈',
                  maxLength: FamilyNames.maxNameLength,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _LabeledField(
                label: isParent ? '女儿的昵称' : '妈妈的昵称',
                child: _inputField(
                  context,
                  controller: _nicknameCtrl,
                  hint: isParent ? '例如：宝贝' : '例如：老妈',
                  maxLength: FamilyNames.maxNameLength,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '现在会显示「$preview」（${isParent ? '女儿' : '妈妈'}自己手机上打开也是这个名字）',
                style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: <Widget>[
                  AppFilledButton(
                    onPressed: _savingNames ? null : _saveNames,
                    child: _savingNames
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: AppLoading(size: 20),
                          )
                        : const Text('保存称呼'),
                  ),
                ],
              ),
              if (dirty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    '有改动还没保存：先帮你留在这台手机上，切走再回来还能接着改',
                    style: TextStyle(
                      fontSize: AppFontSize.xs,
                      color: _readableAccent(palette, palette.warning),
                    ),
                  ),
                ),
              if (!settings.ready)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    '还没连上云端称呼表（本地库需要执行 0004 迁移），当前显示的是本机缓存',
                    style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 手机提醒：整块 UI 在 `push_section.dart`，这里只给子页外壳和提示方式。
  Widget _buildPush(AppPalette palette) {
    return ListView(
      padding: _pagePadding(context),
      children: <Widget>[
        _subPageHeader(palette, '手机提醒'),
        PushSection(
          onToast: (String message, bool error) => _toast(message, error: error),
        ),
      ],
    );
  }

  Widget _buildParentTools(AppPalette palette) {
    final family = context.watch<FamilyState>();
    final hasCustom = family.hasCustomParentPin;
    final lockLeft = _pinLockSeconds > 0 ? _pinLockSeconds : family.pinLockRemaining.inSeconds;

    return ListView(
      padding: _pagePadding(context),
      children: <Widget>[
        _subPageHeader(palette, '家长管理'),
        const SectionHeader(title: '家长管理', subtitle: '口令和打卡照片，只有家长身份看得到'),
        AppCard(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _CardHead(
                title: '家长口令',
                description: hasCustom
                    ? '切到家长身份要输它；已经改成你自己的口令了（忘了只能清掉这台手机的数据重来）'
                    : '切到家长身份要输它；现在还是出厂口令 1234，建议改成只有你知道的',
              ),
              const SizedBox(height: AppSpacing.sm),
              if (lockLeft > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    '口令锁定中，请等 $lockLeft 秒再试',
                    style: TextStyle(
                      fontSize: AppFontSize.xs,
                      color: _readableAccent(palette, palette.danger),
                      fontFeatures: kTabularNumbers,
                    ),
                  ),
                ),
              AppOutlinedButton(
                onPressed: _changeParentPin,
                child: const Text('修改家长口令'),
              ),
            ],
          ),
        ),
        AppCard(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const _CardHead(
                title: '打卡照片清理',
                description:
                    '删除记录时照片会自动一起删掉；这里清理以前遗留下来、已经没人用的闲置照片（正在用的背景图不会被清掉）',
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_scanSummary != null) ...<Widget>[
                Text(
                  _scanSummary!,
                  style: TextStyle(
                    fontSize: AppFontSize.xs,
                    color: palette.textSecondary,
                    fontFeatures: kTabularNumbers,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Row(
                children: <Widget>[
                  AppOutlinedButton(
                    onPressed: _scanning || _cleaning ? null : _scanOrphans,
                    child: _scanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: AppLoading(size: 20),
                          )
                        : const Text('扫描闲置照片'),
                  ),
                  if (_orphanCount > 0) ...<Widget>[
                    const SizedBox(width: AppSpacing.sm),
                    AppFilledButton(
                      onPressed: _cleaning ? null : _cleanOrphans,
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.danger,
                        // 底被换成了 danger：字色跟着这层底走（主题的 onPrimary 是按主色算的）
                        foregroundColor: palette.onColor(palette.danger),
                      ),
                      child: _cleaning
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: AppLoading(size: 20),
                            )
                          : Text.rich(
                              TextSpan(
                                children: <InlineSpan>[
                                  const TextSpan(text: '清理 '),
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.baseline,
                                    baseline: TextBaseline.alphabetic,
                                    child: AnimatedCount(value: _orphanCount),
                                  ),
                                  const TextSpan(text: ' 张'),
                                ],
                              ),
                            ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAdmin(AppPalette palette) {
    // 「全站自检」是管理员分区里的一层子页：密码沿用上面解锁时输入的那一份
    if (_selftestOpen) {
      return SelftestPanel(
        password: _adminPassword ?? '',
        onBack: () => setState(() => _selftestOpen = false),
      );
    }

    final family = context.watch<FamilyState>();
    final entries = _adjustments.take(_adjustmentLogLimit).toList(growable: false);

    return ListView(
      padding: _pagePadding(context),
      children: <Widget>[
        _subPageHeader(palette, '管理员'),
        const SectionHeader(title: '管理员', subtitle: '直接校准积分数，改完立刻生效'),
        AppCard(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          onTap: () => setState(() => _selftestOpen = true),
          child: const _EntryRow(
            icon: Icons.fact_check_outlined,
            title: '全站自检',
            description: '把后端整条链路逐项跑一遍 · 按组勾选、套预设、导出 JSON / Markdown',
          ),
        ),
        AppCard(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const _CardHead(
                title: '修改积分数',
                description:
                    '填的是「改成多少」而不是「加多少」；只填想改的那一项，留空的不会动。改完账本里会多一条「管理员调整」，想退回就去账本里删掉它',
              ),
              const SizedBox(height: AppSpacing.sm),
              _LabeledField(
                label: '家庭积分（现在是 ${_formatNum(family.balance)}）',
                child: _inputField(
                  context,
                  controller: _familyTargetCtrl,
                  hint: '留空 = 不改',
                  keyboardType: const TextInputType.numberWithOptions(signed: true),
                  formatters: _numberFormatters,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _LabeledField(
                label: '花园阳光（现在是 ${_formatNum(family.sunBalance)}）',
                child: _inputField(
                  context,
                  controller: _sunTargetCtrl,
                  hint: '留空 = 不改',
                  keyboardType: const TextInputType.numberWithOptions(signed: true),
                  formatters: _numberFormatters,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppFilledButton(
                onPressed: _savingPoints ? null : _savePoints,
                child: _savingPoints
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: AppLoading(size: 20),
                      )
                    : const Text('保存修改'),
              ),
            ],
          ),
        ),
        AppCard(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const _CardHead(
                title: '一键清零',
                description: '把某一本账直接归零；同样会记一条「管理员调整」，改错了在下面撤销',
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: <Widget>[
                  AppOutlinedButton(
                    onPressed: family.balance == 0 ? null : () => _clearLedger(sun: false),
                    child: const Text('家庭积分清零'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AppOutlinedButton(
                    onPressed: family.sunBalance == 0 ? null : () => _clearLedger(sun: true),
                    child: const Text('花园阳光清零'),
                  ),
                ],
              ),
            ],
          ),
        ),
        AppCard(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _CardHead(
                title: '最近改过什么',
                description: '最近 $_adjustmentLogLimit 条调整；点「撤销」会删掉那条流水，余额回到改之前',
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_loadingAdjustments && entries.isEmpty)
                // 正在读调整记录：先铺三行骨架，别让卡片里空着一行「正在读取…」
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (int index = 0; index < 3; index++)
                      Padding(
                        padding: EdgeInsets.only(top: index == 0 ? 0 : AppSpacing.sm),
                        child: const SkeletonLine(height: 14, widthFactor: 0.55),
                      ),
                  ],
                )
              else if (entries.isEmpty)
                Text(
                  '还没改过积分数',
                  style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                )
              else
                for (final item in entries) _adjustmentRow(palette, item),
            ],
          ),
        ),
        AppCard(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const _CardHead(
                title: '管理员密码',
                description: '换成只有你知道的密码，家里每台手机都用新密码',
              ),
              const SizedBox(height: AppSpacing.sm),
              _LabeledField(
                label: '新密码',
                child: _inputField(
                  context,
                  controller: _newAdminPasswordCtrl,
                  hint: '${AdminApi.passwordMinLength}-${AdminApi.passwordMaxLength} 位',
                  obscure: true,
                  maxLength: AdminApi.passwordMaxLength,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _LabeledField(
                label: '再输一遍',
                child: _inputField(
                  context,
                  controller: _confirmAdminPasswordCtrl,
                  hint: '确认新密码',
                  obscure: true,
                  maxLength: AdminApi.passwordMaxLength,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppOutlinedButton(
                onPressed: _changingAdminPassword ? null : _changeAdminPassword,
                child: _changingAdminPassword
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: AppLoading(size: 20),
                      )
                    : const Text('改密码'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _adjustmentRow(AppPalette palette, AdminAdjustment item) {
    final amount = item.amount;
    final amountText = amount > 0 ? '+${_formatNum(amount)}' : _formatNum(amount);
    final busy = _revokingId == item.id;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: item.isSun ? palette.warning : palette.primary)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${item.isSun ? '花园阳光' : '家庭积分'} $amountText',
                  style: TextStyle(
                    fontSize: AppFontSize.sm,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                    fontFeatures: kTabularNumbers,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${item.note} · ${_formatAdjustTime(item.createdAt)}',
                  style: TextStyle(
                    fontSize: AppFontSize.xs,
                    color: palette.textSecondary,
                    fontFeatures: kTabularNumbers,
                  ),
                ),
              ],
            ),
          ),
          AppTextButton(
            onPressed: busy ? null : () => _revokeAdjustment(item),
            child: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: AppLoading(size: 20),
                  )
                : const Text('撤销'),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- 小零件

  /// 子页统一的滚动内边距。
  ///
  /// 底部额外让出 [AppNavBar.contentInset] —— `MainShell` 开了 `extendBody`，
  /// 底栏是浮在内容之上的，不让位的话滚到底会被胶囊压住最后一条。
  static EdgeInsets _pagePadding(BuildContext context) => EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm + AppTopBar.contentInset(context),
        AppSpacing.md,
        AppSpacing.xl + AppNavBar.contentInset(context),
      );

  static final List<TextInputFormatter> _numberFormatters = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
  ];

  Widget _subPageHeader(AppPalette palette, String title) {
    return Row(
      children: <Widget>[
        AppIconButton(
          onPressed: () => setState(() => _section = null),
          tooltip: '返回设置',
          icon: Icon(Icons.arrow_back, color: palette.text),
        ),
        Text(
          '设置',
          style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          '/',
          style: TextStyle(fontSize: AppFontSize.sm, color: palette.textTertiary),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          title,
          style: TextStyle(
            fontSize: AppFontSize.sm,
            fontWeight: FontWeight.w600,
            color: palette.text,
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------- 通用件

String _formatNum(num value) =>
    value == value.roundToDouble() ? value.round().toString() : value.toString();

String _formatAdjustTime(DateTime? time) {
  if (time == null) return '时间未知';
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$month-$day $hour:$minute';
}

/// 管理员接口的报错文案：`e.message` 之外，把服务端给的锁定/剩余次数也说出来。
String _adminErrorMessage(ApiException error) {
  final body = error.body;
  final lockMs = (body?['lockRemainingMs'] as num?)?.toInt();
  if (lockMs != null && lockMs > 0) {
    return '${error.message}（试错太多次，请等 ${(lockMs / 1000).ceil()} 秒再试）';
  }
  final attemptsLeft = (body?['attemptsLeft'] as num?)?.toInt();
  if (attemptsLeft != null) return '${error.message}（还可以试 $attemptsLeft 次）';
  return error.message;
}

EdgeInsetsGeometry _fieldPadding() => const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.sm,
    );

/// 输入框：颜色 / 圆角 / 字号一律走主题与令牌。
Widget _inputField(
  BuildContext context, {
  required TextEditingController controller,
  String? hint,
  bool obscure = false,
  int? maxLength,
  TextInputType? keyboardType,
  List<TextInputFormatter>? formatters,
}) {
  final palette = context.palette;
  return TextField(
    controller: controller,
    obscureText: obscure,
    keyboardType: keyboardType,
    maxLength: maxLength,
    inputFormatters: formatters,
    style: TextStyle(fontSize: AppFontSize.sm, color: palette.text),
    decoration: InputDecoration(
      counterText: '',
      hintText: hint,
      isDense: true,
      hintStyle: TextStyle(fontSize: AppFontSize.sm, color: palette.textTertiary),
      contentPadding: _fieldPadding(),
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

Future<bool> _confirmDialog(
  BuildContext context, {
  required String title,
  required String description,
  required String okText,
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final palette = dialogContext.palette;
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
              // danger 底的按钮：字色按这层底取
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

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.icon,
    required this.title,
    required this.description,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // 退出这类破坏性入口：图标坐在自己的 12% 淡色块上、标题压在卡片底上，
    // 都按底色算过对比度再上前景色（红线在浅色主题里只有 ~3.5:1）
    final Color accent = _readableAccent(palette, danger ? palette.danger : palette.primary);
    return Row(
      children: <Widget>[
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: accent.withValues(alpha: 0.12),
            shape: AppShape.all(AppRadius.md),
          ),
          child: Icon(icon, size: 18, color: accent),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  fontSize: AppFontSize.sm,
                  fontWeight: FontWeight.w600,
                  color: danger ? accent : palette.text,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                description,
                style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right, size: 18, color: palette.textTertiary),
      ],
    );
  }
}

class _CardHead extends StatelessWidget {
  const _CardHead({required this.title, this.description});

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
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

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Text(
            label,
            style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
          ),
        ),
        child,
      ],
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: <Widget>[
        for (int index = 0; index < options.length; index++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: index == options.length - 1 ? 0 : AppSpacing.sm,
              ),
              child: AnimatedContainer(
                duration: AppMotion.fast,
                curve: AppMotion.standard,
                decoration: ShapeDecoration(
                  color: index == selectedIndex ? palette.segmentedSelected : palette.surfaceSoft,
                  shape: AppShape.all(AppRadius.md, side: BorderSide(color: index == selectedIndex ? palette.primary : palette.border)),
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: PressInkWell(
                    onTap: () => onChanged(index),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: SizedBox(
                      height: 40,
                      child: Center(
                        child: Text(
                          options[index],
                          style: TextStyle(
                            fontSize: AppFontSize.sm,
                            fontWeight: index == selectedIndex ? FontWeight.w600 : FontWeight.w400,
                            color: index == selectedIndex
                                // 选中段的底是 segmentedSelected：字色按这层底取
                                ? palette.onColor(palette.segmentedSelected)
                                : palette.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: ShapeDecoration(
        color: palette.primarySoft,
        shape: AppShape.all(AppRadius.full),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppFontSize.xs,
          fontWeight: FontWeight.w600,
          // 版本号胶囊的底是 primarySoft：字色按这层底取
          color: palette.onSoft,
          fontFeatures: kTabularNumbers,
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- 弹窗

/// 切换为家长：输一次家长口令。
class _ParentPinDialog extends StatefulWidget {
  const _ParentPinDialog({required this.family});

  final FamilyState family;

  @override
  State<_ParentPinDialog> createState() => _ParentPinDialogState();
}

class _ParentPinDialogState extends State<_ParentPinDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _controller.text.trim();
    if (pin.isEmpty) {
      setState(() => _error = '请输入家长口令');
      return;
    }
    final lock = widget.family.pinLockRemaining;
    if (lock > Duration.zero) {
      setState(() => _error = '口令锁定中，请等 ${lock.inSeconds} 秒再试');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.family.verifyParentPin(pin);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    final remain = widget.family.pinLockRemaining;
    final attemptsLeft = widget.family.pinAttemptsLeft;
    setState(() {
      _busy = false;
      _error = remain > Duration.zero
          ? '口令错得太多次，请等 ${remain.inSeconds} 秒再试'
          : '口令不对，还可以试 $attemptsLeft 次';
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      backgroundColor: palette.surface,
      title: Text(
        '切换为家长',
        style: TextStyle(
          fontSize: AppFontSize.md,
          fontWeight: FontWeight.w600,
          color: palette.text,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _LabeledField(
            label: '请输入家长口令',
            child: _inputField(
              context,
              controller: _controller,
              hint: '$_pinMinLength-$_pinMaxLength 位口令',
              obscure: true,
              maxLength: _pinMaxLength,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _error ?? '口令不正确将无法切换到家长模式',
            style: TextStyle(
              fontSize: AppFontSize.xs,
              color: _error == null ? palette.textTertiary : palette.danger,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        AppTextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        AppFilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: AppLoading(size: 20),
                )
              : const Text('确认'),
        ),
      ],
    );
  }
}

/// 修改家长口令：先验原口令，再写新口令。
class _ChangePinDialog extends StatefulWidget {
  const _ChangePinDialog({required this.family});

  final FamilyState family;

  @override
  State<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<_ChangePinDialog> {
  final TextEditingController _oldCtrl = TextEditingController();
  final TextEditingController _newCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final oldPin = _oldCtrl.text.trim();
    if (oldPin.isEmpty) {
      setState(() => _error = '请输入原口令');
      return;
    }
    final lock = widget.family.pinLockRemaining;
    if (lock > Duration.zero) {
      setState(() => _error = '口令锁定中，请等 ${lock.inSeconds} 秒再试');
      return;
    }
    final next = _newCtrl.text.trim();
    if (next.length < _pinMinLength || next.length > _pinMaxLength) {
      setState(() => _error = '新口令需为 $_pinMinLength-$_pinMaxLength 位');
      return;
    }
    if (next != _confirmCtrl.text.trim()) {
      setState(() => _error = '两次输入的新口令不一致');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.family.verifyParentPin(oldPin);
    if (!mounted) return;
    if (!ok) {
      final remain = widget.family.pinLockRemaining;
      final attemptsLeft = widget.family.pinAttemptsLeft;
      setState(() {
        _busy = false;
        _error = remain > Duration.zero
            ? '原口令错得太多次，请等 ${remain.inSeconds} 秒再试'
            : '原口令不对，还可以试 $attemptsLeft 次';
      });
      return;
    }
    try {
      await widget.family.setParentPin(next);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '新口令没保存成功，请重试';
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      backgroundColor: palette.surface,
      title: Text(
        '修改家长口令',
        style: TextStyle(
          fontSize: AppFontSize.md,
          fontWeight: FontWeight.w600,
          color: palette.text,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _LabeledField(
              label: '原口令',
              child: _inputField(
                context,
                controller: _oldCtrl,
                hint: '当前口令',
                obscure: true,
                maxLength: _pinMaxLength,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _LabeledField(
              label: '新口令',
              child: _inputField(
                context,
                controller: _newCtrl,
                hint: '$_pinMinLength-$_pinMaxLength 位新口令',
                obscure: true,
                maxLength: _pinMaxLength,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _LabeledField(
              label: '确认新口令',
              child: _inputField(
                context,
                controller: _confirmCtrl,
                hint: '再次输入新口令',
                obscure: true,
                maxLength: _pinMaxLength,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error ?? '出厂口令为 1234，请尽快修改',
              style: TextStyle(
                fontSize: AppFontSize.xs,
                color: _error == null ? palette.textTertiary : palette.danger,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        AppTextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        AppFilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: AppLoading(size: 20),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
}

/// 管理员密码：验过才让进面板，密码不给对就把锁定/剩余次数写在弹窗里。
class _AdminPasswordDialog extends StatefulWidget {
  const _AdminPasswordDialog({required this.api});

  final AdminApi api;

  @override
  State<_AdminPasswordDialog> createState() => _AdminPasswordDialogState();
}

class _AdminPasswordDialogState extends State<_AdminPasswordDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _controller.text;
    if (password.isEmpty) {
      setState(() => _error = '请输入管理员密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.verify(password);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error is ApiException ? _adminErrorMessage(error) : '管理员密码验证失败，请重试';
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      backgroundColor: palette.surface,
      title: Text(
        '管理员密码',
        style: TextStyle(
          fontSize: AppFontSize.md,
          fontWeight: FontWeight.w600,
          color: palette.text,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _LabeledField(
            label: '管理员密码',
            child: _inputField(
              context,
              controller: _controller,
              hint: '请输入管理员密码',
              obscure: true,
              maxLength: AdminApi.passwordMaxLength,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _error ?? '进去之后可以直接改积分数，也能在面板里换掉这个密码',
            style: TextStyle(
              fontSize: AppFontSize.xs,
              color: _error == null ? palette.textTertiary : palette.danger,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        AppTextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        AppFilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: AppLoading(size: 20),
                )
              : const Text('进入'),
        ),
      ],
    );
  }
}
