import '../../config/changelog.dart';
import '../../core/api_client.dart';

/// `GET /api/changelog` 的返回（对应 Web 版 `src/api/changelog.ts` 的 `ChangelogResponse`）。
///
/// 日志的真源在服务端 D1（`changelog` 表）：网页版和 App 读同一份，改一处两端都看得见 ——
/// 以前两端各存一份代码常量，App 这边常常慢好几个版本（这次接上时它还停在 1.30.6，
/// 网页版已经到 1.30.8）。
///
/// 兜底分工：服务端读不到内容时回 `ready:false`，此时本机那份 `config/changelog.dart`
/// 顶上（表没迁移 / 还没同步 / 断网三种情况都算）。
class ChangelogPayload {
  const ChangelogPayload({
    required this.version,
    required this.entries,
    required this.ready,
  });

  /// 最新一条的版本号；服务端没有内容时为 null
  final String? version;

  /// 版本日志，最新在前
  final List<ChangelogEntry> entries;

  /// [entries] 能不能用。服务端明确回 `false`、或者条目全被解析丢掉时都是 false
  final bool ready;

  static ChangelogPayload fromJson(dynamic raw) {
    if (raw is! Map) {
      return const ChangelogPayload(
        version: null,
        entries: <ChangelogEntry>[],
        ready: false,
      );
    }

    final List<ChangelogEntry> entries = <ChangelogEntry>[];
    final dynamic rawEntries = raw['entries'];
    if (rawEntries is List) {
      for (final dynamic item in rawEntries) {
        final ChangelogEntry? entry = _parseEntry(item);
        if (entry != null) entries.add(entry);
      }
    }

    final dynamic version = raw['version'];
    return ChangelogPayload(
      version: version is String && version.isNotEmpty ? version : null,
      entries: entries,
      // 空表一律按「不可用」处理：调用方据此退回本机那份，而不是渲染一片空白
      ready: raw['ready'] == true && entries.isNotEmpty,
    );
  }

  /// 解析一条日志。字段不全就当这行是坏的丢掉 —— 与服务端
  /// `functions/_lib/changelog.ts` 的 `readChangelog` 同一个口径：日志是给人看的历史，
  /// 一行坏了不值得让整个列表消失。
  static ChangelogEntry? _parseEntry(dynamic raw) {
    if (raw is! Map) return null;

    final dynamic rawVersion = raw['version'];
    final String version = rawVersion is String ? rawVersion.trim() : '';
    if (version.isEmpty) return null;

    final List<String> changes = <String>[];
    final dynamic rawChanges = raw['changes'];
    if (rawChanges is List) {
      for (final dynamic change in rawChanges) {
        if (change is String && change.trim().isNotEmpty) {
          changes.add(change.trim());
        }
      }
    }

    final dynamic rawDate = raw['date'];
    final dynamic rawTitle = raw['title'];
    return ChangelogEntry(
      version: version,
      date: rawDate is String ? rawDate.trim() : '',
      title: rawTitle is String ? rawTitle.trim() : '',
      changes: changes,
    );
  }
}

/// 版本日志接口（`GET /api/changelog`）。
class ChangelogApi {
  ChangelogApi(this._client);

  final ApiClient _client;

  /// 读云端版本日志。调用方要吞异常：读不到就继续用本机 `config/changelog.dart` 那份兜底，
  /// 别让日志问题拦住「关于」这一块。
  Future<ChangelogPayload> fetchChangelog() async {
    final raw = await _client.getJson<dynamic>('/api/changelog');
    return ChangelogPayload.fromJson(raw);
  }
}
