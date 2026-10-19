import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_constants.dart';
import '../config/changelog.dart';
import '../core/api_client.dart';
import '../core/apk_installer.dart';
import '../data/api/app_update_api.dart';
import '../data/api/changelog_api.dart';
import '../data/models/app_update.dart';

/// 「检查更新」的结果。
///
/// 分开表达「有没有新版本」和「清单读没读到」：断网时说「已经是最新版本」是在骗人，
/// 用户下次发现没更新就更不信这个按钮了。
class UpdateCheckResult {
  const UpdateCheckResult({this.update, required this.reachable});

  /// 有值 = 服务端上有个比本机新的版本
  final AppUpdateInfo? update;

  /// 清单有没有读到（false = 断网 / 域名不通 / 还没发布第一版）
  final bool reachable;
}

/// 一次「下载 + 安装」的结果
enum UpdateInstallResult {
  /// 系统安装器已经拉起，接下来是系统界面上的事
  launched,

  /// 少了「安装未知应用」权限，已经把他送到系统授权页；安装包留着，回来再点一次即可
  needPermission,

  /// 下载 / 校验 / 拉起失败，原因见 [UpdateState.lastError]
  failed,
}

/// 应用内更新的状态机（安卓专用）。
///
/// 三条路径：
/// * [autoCheck]：**每次打开 App** 静默看一眼，有新版本就交给主壳弹窗
///   （点过「以后再说」的那个版本不再弹；设置里关掉自动检测就整个不发请求）
/// * [checkNow]：用户点「检查更新」——「已是最新」也要明确回一句，不然像点坏了
/// * [downloadAndInstall]：下载 → 校验 sha256 → 交给系统安装器
///
/// 弹窗里那一段说明优先用云端版本日志里跟新版本对上的那条（[pendingLog]：
/// 标题 + 改动列表），读不到再退回清单里的单行 [AppUpdateInfo.changelog]。
///
/// 网页版与桌面端 [supported] 为 false，界面上不出现这个入口（网页刷新就是最新版）。
class UpdateState extends ChangeNotifier {
  UpdateState({
    required SharedPreferences prefs,
    AppUpdateApi? api,
    ChangelogApi? changelogApi,
    Future<int> Function()? currentVersionCode,
  })  : _prefs = prefs,
        _api = api ?? AppUpdateApi(),
        _changelogApi = changelogApi ?? ChangelogApi(ApiClient()),
        _readVersionCode = currentVersionCode ?? _readPackageVersionCode;

  final SharedPreferences _prefs;
  final AppUpdateApi _api;
  final ChangelogApi _changelogApi;
  final Future<int> Function() _readVersionCode;

  AppUpdateInfo? _pending;
  ChangelogEntry? _pendingLog;
  bool _checking = false;
  bool _downloading = false;
  double _progress = 0;
  String? _lastError;
  int? _currentVersionCode;

  /// 这台设备支不支持应用内更新
  bool get supported => canInstallAppUpdate;

  /// 服务端上比本机新的那个版本（还没装）。null = 没有 / 已经拒绝过
  AppUpdateInfo? get pending => _pending;

  /// [pending] 那一版在云端日志里的原文，用来铺满弹窗；没有就是 null
  ChangelogEntry? get pendingLog => _pendingLog;

  /// 设置里那个开关。没写过就是开 —— 默认每次打开都检查一次。
  bool get autoCheckEnabled =>
      _prefs.getBool(AppConstants.keyAutoCheckUpdate) ?? true;

  bool get checking => _checking;
  bool get downloading => _downloading;

  /// 下载进度 0~1
  double get progress => _progress;

  String? get lastError => _lastError;

  /// 本机 versionCode（装了哪个包就是哪个）
  int? get currentVersionCode => _currentVersionCode;

  /// 开关变动。顺手立刻查一次，用户不用等到下次打开才看到效果。
  Future<void> setAutoCheckEnabled(bool value) async {
    await _prefs.setBool(AppConstants.keyAutoCheckUpdate, value);
    notifyListeners();
    if (value) await autoCheck();
  }

  /// 打开 App 之后的静默检查。返回要提示的那个新版本（不该提示时返回 null）。
  ///
  /// 每次启动都会问一次服务端：清单文件只有一个、带 60 秒缓存，比每天一次的
  /// 「时间戳 + 猜用户明天会不会打开」简单，也不会有「今天已经查过了」这种假结论。
  Future<AppUpdateInfo?> autoCheck() async {
    if (!supported || !autoCheckEnabled) return null;

    final AppUpdateInfo? info = await _fetch();
    if (info == null) return null;

    if (!info.isNewerThan(await _currentCode())) {
      // 上一轮记下的「有新版本」可能已经过期（比如用户从别处装上了），顺手清掉
      if (_pending != null) {
        _pending = null;
        _pendingLog = null;
        notifyListeners();
      }
      return null;
    }
    // 用户对「这个版本」说过以后再说 —— 同一个版本不再打扰；
    // 等他手动点「检查更新」时照样能看到（那时不看这个键）
    if (_prefs.getString(AppConstants.keySkipUpdateVersion) == info.versionName) {
      return null;
    }

    _pending = info;
    _pendingLog = await _loadLog(info.versionName);
    notifyListeners();
    return info;
  }

  /// 用户主动点「检查更新」。任何时候都真的发一次请求。
  Future<UpdateCheckResult> checkNow() async {
    if (!supported) return const UpdateCheckResult(reachable: false);

    _lastError = null;
    final AppUpdateInfo? info = await _fetch();
    if (info == null) return const UpdateCheckResult(reachable: false);

    if (!info.isNewerThan(await _currentCode())) {
      _pending = null;
      _pendingLog = null;
      notifyListeners();
      return const UpdateCheckResult(reachable: true);
    }
    _pending = info;
    _pendingLog = await _loadLog(info.versionName);
    notifyListeners();
    return UpdateCheckResult(update: info, reachable: true);
  }

  /// 用户点了「以后再说」：记下版本号，自动检查不再弹它。手动检查不受影响。
  Future<void> skipPending() async {
    final AppUpdateInfo? info = _pending;
    if (info == null) return;
    await _prefs.setString(AppConstants.keySkipUpdateVersion, info.versionName);
    _pending = null;
    _pendingLog = null;
    notifyListeners();
  }

  /// 下载 → 校验 → 调起安装器。
  ///
  /// 已经是第二次点（包还在）时直接装，不重新下 60MB —— 缺「安装未知应用」权限
  /// 的那一趟正是靠这个：用户去系统设置里允许完，回来再点一次就装上了。
  Future<UpdateInstallResult> downloadAndInstall() async {
    final AppUpdateInfo? info = _pending;
    if (info == null) return UpdateInstallResult.failed;

    _lastError = null;
    _downloading = true;
    _progress = 0;
    notifyListeners();

    String? path = _downloadedPath;
    try {
      path ??= await ApkInstaller.download(
        info,
        onProgress: (double value) {
          _progress = value;
          notifyListeners();
        },
      );
      _downloadedPath = path;

      final bool launched = await ApkInstaller.startInstall(path);
      if (!launched) {
        // 包留着：等用户从系统设置页回来，再点一次直接装
        return UpdateInstallResult.needPermission;
      }
      return UpdateInstallResult.launched;
    } on FormatException catch (error) {
      // 校验不过：实现已经把这个文件删了，下次从头下
      _downloadedPath = null;
      _lastError = error.message;
      return UpdateInstallResult.failed;
    } catch (error) {
      _downloadedPath = null;
      _lastError = '下载失败：$error';
      return UpdateInstallResult.failed;
    } finally {
      _downloading = false;
      notifyListeners();
    }
  }

  /// 拉清单。失败返回 null，不抛 —— 调用方按「没有新版本」处理。
  Future<AppUpdateInfo?> _fetch() async {
    _checking = true;
    notifyListeners();
    try {
      return await _api.fetchLatest();
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  /// 去云端日志里找 [version] 那一条。读不到就是 null（调用方退回清单里的单行说明）。
  Future<ChangelogEntry?> _loadLog(String version) async {
    try {
      final ChangelogPayload payload = await _changelogApi.fetchChangelog();
      for (final ChangelogEntry entry in payload.entries) {
        if (entry.version == version) return entry;
      }
    } catch (_) {
      // 日志读不到不该连累更新：弹窗还剩清单里那行说明可讲
    }
    return null;
  }

  /// 本机 versionCode。安卓里它就是 pubspec 的 `+` 后面那个数
  /// （拆 ABI 的包会被 Flutter 加上 1000×ABI 偏移，比较时用的仍然是同一口径）。
  Future<int> _currentCode() async =>
      _currentVersionCode ??= await _readVersionCode();

  static Future<int> _readPackageVersionCode() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  /// 下载好的安装包路径（第二次点「下载安装」时复用）
  String? _downloadedPath;
}
