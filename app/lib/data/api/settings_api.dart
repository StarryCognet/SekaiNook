import '../../core/api_client.dart';
import '../models/family_names.dart';

/// `GET/PATCH /api/settings` 的返回（对应 Web 版 `api/settings.ts` 的 `SettingsResponse`）
class SettingsPayload {
  const SettingsPayload({
    required this.names,
    required this.background,
    required this.ready,
  });

  final FamilyNames names;

  /// 全局背景图地址，`''` = 没设
  final String background;

  /// 服务端设置表是否就绪。**注意**：`GET /api/settings` 的 ready 实际上恒为 true
  /// （读取 helper 内部各自吞异常回默认值，外层 catch 几乎不可达），
  /// 真正可达的 `ready:false` 在通知接口那边。这里仍按「没回字段就算 true」处理。
  final bool ready;

  static SettingsPayload fromJson(dynamic raw) {
    if (raw is! Map) {
      return SettingsPayload(
        names: FamilyNames.defaults,
        background: '',
        ready: true,
      );
    }
    FamilyNames names;
    try {
      names = FamilyNames.fromJson(raw['names']);
    } catch (_) {
      names = FamilyNames.defaults;
    }
    final background = raw['background'];
    return SettingsPayload(
      names: names,
      background: background is String ? background : '',
      ready: raw['ready'] != false,
    );
  }
}

/// 设置接口（称呼 + 全局背景图）。
///
/// 权威数据在服务端 D1 settings 表，本机只当缓存：打开 App 先用缓存渲染，
/// 再去服务端对一次，这样两个人换手机也能看到同一套称呼。
class SettingsApi {
  SettingsApi(this._client);

  final ApiClient _client;

  /// 启动时 theme（要背景图）与 settings（要称呼）会各请求一次设置，
  /// 内容完全一样 —— 让并发调用共享同一个在途请求，启动少打一次接口。
  Future<SettingsPayload>? _inflight;

  /// 读设置（`GET /api/settings`）。调用方要吞异常，别让设置问题拦住首页。
  Future<SettingsPayload> fetchSettings() {
    final existing = _inflight;
    if (existing != null) return existing;
    final future = _client
        .getJson<dynamic>('/api/settings')
        .then(SettingsPayload.fromJson)
        .whenComplete(() => _inflight = null);
    _inflight = future;
    return future;
  }

  /// 保存设置（`PATCH /api/settings`，写请求**不带 retry**）。
  ///
  /// [patch] 只含要改的字段，例如 `{'kidCall': '妹妹', 'kidNickname': ''}` 或 `{'background': url}`。
  /// 传 `{'background': ''}` 表示移除背景图。返回服务端**完整**的设置。
  Future<SettingsPayload> saveSettings(Map<String, dynamic> patch) async {
    final raw = await _client.patchJson<dynamic>('/api/settings', data: patch);
    return SettingsPayload.fromJson(raw);
  }
}
