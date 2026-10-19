import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_constants.dart';
import '../data/api/settings_api.dart';
import '../data/models/family_names.dart';

/// 家庭称呼（对应 Web 版 `src/store/useSettingsStore.ts`）。
///
/// 权威数据在服务端（D1 settings 表），本机存储只当缓存：
/// 打开 App 先用缓存渲染，再去服务端对一次，这样两个人换手机也能看到同一套称呼。
///
/// **同步方向（谁覆盖谁）**：
/// - 启动：`names` 初值 = 本机缓存或默认值，立即可渲染；随后 [load] 拉服务端并
///   **用服务端值覆盖本地缓存与 state**。
/// - 保存：[save] 是**只提交自己那一半**的 PATCH，成功后用**服务端返回的完整 names**
///   覆盖 state 与缓存 —— 不是本地乐观值。因此不存在本地写入先行的乐观更新，
///   `save` 必须先成功返回。
class SettingsState extends ChangeNotifier {
  SettingsState({
    required SharedPreferences prefs,
    required SettingsApi api,
  })  : _prefs = prefs,
        _api = api {
    _names = _loadCache();
  }

  final SharedPreferences _prefs;
  final SettingsApi _api;

  late FamilyNames _names;

  /// 当前称呼（缓存或服务端值）
  FamilyNames get names => _names;

  bool _loading = false;
  bool get loading => _loading;

  bool _ready = false;

  /// false = 服务端还没就绪（表没迁移 / 请求失败），当前用缓存或默认值
  bool get ready => _ready;

  /// 妈妈显示名（昵称优先 → 称呼 → 出厂默认）
  String get momName => _names.displayName(FamilyWho.mom);

  /// 女儿显示名
  String get kidName => _names.displayName(FamilyWho.kid);

  /// 读本机缓存，**字段级容错**：坏数据一律回默认值，不让设置问题拦住首页。
  ///
  /// 逐字段规则：`momCall` / `kidCall` 要求是**非空字符串**，否则回中文默认；
  /// `momNickname` / `kidNickname` 只要是字符串就收（允许空串）。
  FamilyNames _loadCache() {
    final raw = _prefs.getString(AppConstants.keyFamilyNames);
    if (raw == null || raw.isEmpty) return FamilyNames.defaults;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map) return FamilyNames.defaults;
      final momCall = parsed['momCall'];
      final kidCall = parsed['kidCall'];
      final momNickname = parsed['momNickname'];
      final kidNickname = parsed['kidNickname'];
      return FamilyNames(
        momCall: momCall is String && momCall.isNotEmpty ? momCall : FamilyNames.defaults.momCall,
        momNickname: momNickname is String ? momNickname : '',
        kidCall: kidCall is String && kidCall.isNotEmpty ? kidCall : FamilyNames.defaults.kidCall,
        kidNickname: kidNickname is String ? kidNickname : '',
      );
    } catch (_) {
      return FamilyNames.defaults;
    }
  }

  Future<void> _saveCache(FamilyNames names) async {
    try {
      await _prefs.setString(AppConstants.keyFamilyNames, jsonEncode(names.toJson()));
    } catch (_) {
      // 存储不可用 / 存储满：拿不到缓存也不影响本次使用
    }
  }

  /// 拉服务端设置并覆盖本地（失败保留当前值，不打扰用户）。
  ///
  /// 并发去重：正在加载时重复调用直接返回，不报错不排队。
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      final payload = await _api.fetchSettings();
      _names = payload.names;
      await _saveCache(payload.names);
      // ready 用「不是显式 false」判定：服务端没回这个字段就算 true（老部署兼容）
      _ready = payload.ready;
      _loading = false;
      notifyListeners();
    } catch (_) {
      // 失败保留当前值（缓存/默认），但 ready 被显式置回 false
      _loading = false;
      _ready = false;
      notifyListeners();
    }
  }

  /// 保存设置。失败**不吞**，异常直接抛给调用方提示。
  Future<FamilyNames> save(Map<String, dynamic> patch) async {
    final payload = await _api.saveSettings(patch);
    _names = payload.names;
    await _saveCache(payload.names);
    _ready = true;
    notifyListeners();
    return payload.names;
  }
}
