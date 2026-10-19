/// 应用内更新的清单条目 —— 对应 R2 上那份 `latest.json`（由 `tool/publish_apk.ps1` 写出）。
///
/// 清单是**外部文件**：可能被手改坏、可能只写了一半、可能被中间人换了。
/// 所以 [fromJson] 走字段级容错 —— 缺字段/类型不对就整条作废（返回 null），
/// 绝不让一份坏清单把 App 拦在启动里。
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.url,
    required this.sha256,
    required this.size,
    this.changelog,
  });

  /// 给人看的版本号（如 `1.31.1`）
  final String versionName;

  /// 安卓 versionCode，比大小的**唯一**依据。
  ///
  /// 不拿 versionName 比：字符串比较会得出 `1.31.10 < 1.31.9` 这种反结论。
  final int versionCode;

  /// APK 直链
  final String url;

  /// APK 的 sha256（十六进制，统一存小写）
  final String sha256;

  /// APK 字节数，弹窗里写「大约 xx MB」用
  final int size;

  /// 这次更新改了什么（可选；发布脚本会从网页版那套版本日志里取）
  final String? changelog;

  /// 解析清单。任何一个必需字段坏掉都返回 null —— 调用方按「没有新版本」处理。
  static AppUpdateInfo? fromJson(dynamic raw) {
    if (raw is! Map) return null;

    final String? versionName = _string(raw['versionName']);
    final String? url = _string(raw['url']);
    final String? sha256 = _string(raw['sha256']);
    final int? versionCode = _int(raw['versionCode']);
    final int? size = _int(raw['size']);
    if (versionName == null ||
        url == null ||
        sha256 == null ||
        versionCode == null ||
        size == null) {
      return null;
    }

    // 只认 https：更新包是从公网静态存储下来的可执行文件，
    // 明文那条路一旦被中间人插一手，装上去的就是别人的包（sha256 那时也一起被换掉了）
    if (!url.startsWith('https://')) return null;
    // sha256 必须是完整的 64 位十六进制；不是就说明清单是手写/被截断的
    if (versionCode <= 0 || sha256.length != 64 || size <= 0) return null;

    return AppUpdateInfo(
      versionName: versionName,
      versionCode: versionCode,
      url: url,
      sha256: sha256.toLowerCase(),
      size: size,
      changelog: _string(raw['changelog']),
    );
  }

  /// 比本机新才提示。相等（同一版本重发）不算更新。
  bool isNewerThan(int currentVersionCode) => versionCode > currentVersionCode;

  /// 「大约 58.6 MB」里的那个数字
  String get sizeText => '${(size / 1024 / 1024).toStringAsFixed(1)} MB';

  /// 落盘用的文件名。**带版本号**：不带的话新旧包同名，残留的旧包会让 sha256 校验必挂。
  String get fileName => 'SekaiNook-$versionName.apk';

  static String? _string(dynamic value) {
    if (value is! String) return null;
    final String text = value.trim();
    return text.isEmpty ? null : text;
  }

  static int? _int(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}
