/// App 本地提醒的一条「提醒项」。
///
/// 与网站那条 Web Push 是两条独立通道：本地提醒由 App 自己用系统闹钟排程，
/// 不依赖网络、不依赖服务端 —— 代价是文案里的数字是「最后一次打开 App 时」算的。
///
/// 这个文件只管**数据长什么样**（可序列化、可复制），排程与落盘在
/// `state/local_notify_state.dart`，真发通知在 `core/local_notifications.dart`。
library;

/// 消息类型（决定默认文案，也决定 UI 上的标签色）
enum ReminderKind {
  taskProgress('task_progress', '任务提醒', '今天还差几个任务'),
  sleep('sleep', '睡觉提醒', '到点该睡觉了'),
  checkin('checkin', '打卡提醒', '提醒去打今天的卡'),
  custom('custom', '自定义', '想说什么就说什么');

  const ReminderKind(this.wire, this.label, this.hint);

  /// 落盘用的字符串（不要用 enum 名，改名会读不出旧数据）
  final String wire;

  /// UI 上的中文名
  final String label;

  /// UI 上的一句话说明
  final String hint;

  static ReminderKind parse(Object? value) {
    if (value is! String) return ReminderKind.custom;
    for (final kind in values) {
      if (kind.wire == value) return kind;
    }
    return ReminderKind.custom;
  }
}

/// 重复方式
enum ReminderRepeat {
  daily('daily', '每天'),
  weekdays('weekdays', '工作日'),
  once('once', '只提醒一次');

  const ReminderRepeat(this.wire, this.label);

  final String wire;
  final String label;

  static ReminderRepeat parse(Object? value) {
    if (value is! String) return ReminderRepeat.daily;
    for (final repeat in values) {
      if (repeat.wire == value) return repeat;
    }
    return ReminderRepeat.daily;
  }
}

/// 一条提醒「怎么弹」：声音 / 震动 / 悬浮横幅 / 锁屏上显示内容。
///
/// 安卓 8 以后这些属性属于**通知渠道**，而渠道一旦建好就不能改 ——
/// 所以 [channelId] 把四个开关编进 id：改了设置就是一个新渠道，
/// 系统才会按新设置来（这也是「改完设置不生效」这类 bug 的根因）。
class ReminderStyle {
  const ReminderStyle({
    this.sound = true,
    this.vibrate = true,
    this.headsUp = true,
    this.lockscreenVisible = true,
  });

  /// 有提示音
  final bool sound;

  /// 震动
  final bool vibrate;

  /// 悬浮横幅（顶部弹出来那一条）；关掉就只进通知栏
  final bool headsUp;

  /// 锁屏上是否显示内容；关掉只显示「有一条通知」
  final bool lockscreenVisible;

  /// 完全安静（没声没震动也不弹横幅）
  bool get isSilent => !sound && !vibrate && !headsUp;

  /// 通知渠道 id（安卓渠道不可改，所以把表现编进 id）
  String get channelId {
    final buffer = StringBuffer('sekainook_');
    buffer.write(headsUp ? 'banner' : 'quiet');
    if (sound) buffer.write('_sound');
    if (vibrate) buffer.write('_vibrate');
    if (!lockscreenVisible) buffer.write('_private');
    return buffer.toString();
  }

  /// 渠道名（安卓「通知设置」里显示给用户看的）
  String get channelName {
    final parts = <String>[];
    if (headsUp) parts.add('悬浮横幅');
    if (sound) parts.add('声音');
    if (vibrate) parts.add('震动');
    if (parts.isEmpty) parts.add('静默');
    return 'SekaiNook 提醒（${parts.join(' + ')}）';
  }

  String get summary {
    final parts = <String>[
      if (headsUp) '悬浮' else '只进通知栏',
      if (sound) '响铃' else '静音',
      if (vibrate) '震动' else '不震动',
      if (!lockscreenVisible) '锁屏隐藏内容',
    ];
    return parts.join(' · ');
  }

  ReminderStyle copyWith({
    bool? sound,
    bool? vibrate,
    bool? headsUp,
    bool? lockscreenVisible,
  }) {
    return ReminderStyle(
      sound: sound ?? this.sound,
      vibrate: vibrate ?? this.vibrate,
      headsUp: headsUp ?? this.headsUp,
      lockscreenVisible: lockscreenVisible ?? this.lockscreenVisible,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'sound': sound,
        'vibrate': vibrate,
        'headsUp': headsUp,
        'lockscreenVisible': lockscreenVisible,
      };

  factory ReminderStyle.fromJson(Object? json) {
    if (json is! Map) return const ReminderStyle();
    bool read(String key, bool fallback) {
      final value = json[key];
      return value is bool ? value : fallback;
    }

    return ReminderStyle(
      sound: read('sound', true),
      vibrate: read('vibrate', true),
      headsUp: read('headsUp', true),
      lockscreenVisible: read('lockscreenVisible', true),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReminderStyle &&
      other.sound == sound &&
      other.vibrate == vibrate &&
      other.headsUp == headsUp &&
      other.lockscreenVisible == lockscreenVisible;

  @override
  int get hashCode => Object.hash(sound, vibrate, headsUp, lockscreenVisible);
}

/// 一条提醒项
class LocalReminder {
  const LocalReminder({
    required this.slot,
    required this.id,
    required this.name,
    required this.kind,
    required this.hour,
    required this.minute,
    this.repeat = ReminderRepeat.daily,
    this.enabled = true,
    required this.title,
    required this.body,
    this.style = const ReminderStyle(),
    this.onceDay,
    this.builtin = false,
  });

  /// 排程用的槽位（1..99）。通知 id = `2100 + slot * 10`（工作日再 +1..+5），
  /// 落盘保存是为了重启后还能撤掉上一次排的通知。
  final int slot;

  /// 稳定标识（内置项是固定字符串，自定义项是 `custom-<时间戳>`）
  final String id;

  /// 名字（列表里显示）
  final String name;

  /// 消息类型
  final ReminderKind kind;

  /// 几点几分（北京墙钟时间：字段即所见）
  final int hour;
  final int minute;

  /// 重复方式
  final ReminderRepeat repeat;

  /// 这条开不开
  final bool enabled;

  /// 标题模板，支持 `{done}` `{remaining}` `{total}` 占位符
  final String title;

  /// 正文模板，同上
  final String body;

  /// 通知表现
  final ReminderStyle style;

  /// [ReminderRepeat.once] 时的日期（东八区日期键，形如 `2026-10-18`）
  final String? onceDay;

  /// 内置项不可删除（可以改时间/文案/停用）
  final bool builtin;

  /// 内置：任务提醒（默认 21:30，与服务端 Worker 的 cron 同一时刻）
  static const String taskProgressId = 'task_progress';

  /// 内置：睡觉提醒（默认 22:00，与服务端 `SLEEP_DEADLINE` 同一时刻）
  static const String sleepId = 'sleep';

  /// 通知 id（工作日会在此基础上 +1..+5）
  int get notificationId => 2100 + slot * 10;

  /// 这条提醒会占用哪些通知 id
  List<int> get notificationIds {
    switch (repeat) {
      case ReminderRepeat.weekdays:
        return <int>[for (var i = 1; i <= 5; i++) notificationId + i];
      case ReminderRepeat.daily:
      case ReminderRepeat.once:
        return <int>[notificationId];
    }
  }

  /// 时刻文案 `21:30`
  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// 列表副标题：`每天 21:30 · 任务提醒 · 悬浮 · 响铃 · 震动`
  String get scheduleLabel => '${repeat.label} $timeLabel';

  LocalReminder copyWith({
    int? slot,
    String? id,
    String? name,
    ReminderKind? kind,
    int? hour,
    int? minute,
    ReminderRepeat? repeat,
    bool? enabled,
    String? title,
    String? body,
    ReminderStyle? style,
    String? onceDay,
    bool? builtin,
    bool clearOnceDay = false,
  }) {
    return LocalReminder(
      slot: slot ?? this.slot,
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      repeat: repeat ?? this.repeat,
      enabled: enabled ?? this.enabled,
      title: title ?? this.title,
      body: body ?? this.body,
      style: style ?? this.style,
      onceDay: clearOnceDay ? null : (onceDay ?? this.onceDay),
      builtin: builtin ?? this.builtin,
    );
  }

  /// 把 `{done}` / `{remaining}` / `{total}` 填进模板
  String renderTitle(Map<String, String> vars) => _render(title, vars);

  /// 同上，正文版
  String renderBody(Map<String, String> vars) => _render(body, vars);

  static String _render(String template, Map<String, String> vars) {
    var text = template;
    for (final entry in vars.entries) {
      text = text.replaceAll('{${entry.key}}', entry.value);
    }
    return text;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'slot': slot,
        'id': id,
        'name': name,
        'kind': kind.wire,
        'hour': hour,
        'minute': minute,
        'repeat': repeat.wire,
        'enabled': enabled,
        'title': title,
        'body': body,
        'style': style.toJson(),
        if (onceDay != null) 'onceDay': onceDay,
        if (builtin) 'builtin': true,
      };

  factory LocalReminder.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('提醒项不是对象');
    int readInt(String key, int fallback) {
      final value = json[key];
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? fallback;
      return fallback;
    }

    String readString(String key, String fallback) {
      final value = json[key];
      return value is String && value.isNotEmpty ? value : fallback;
    }

    return LocalReminder(
      slot: readInt('slot', 1).clamp(1, 99),
      id: readString('id', 'custom'),
      name: readString('name', '提醒'),
      kind: ReminderKind.parse(json['kind']),
      hour: readInt('hour', 21).clamp(0, 23),
      minute: readInt('minute', 30).clamp(0, 59),
      repeat: ReminderRepeat.parse(json['repeat']),
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      title: readString('title', 'SekaiNook 提醒'),
      body: readString('body', ''),
      style: ReminderStyle.fromJson(json['style']),
      onceDay: json['onceDay'] is String ? json['onceDay'] as String : null,
      builtin: json['builtin'] == true,
    );
  }

  /// 出厂默认的三条：任务提醒 + 睡觉提醒（内置），再留一条自定义的空位给用户自己加
  static List<LocalReminder> defaults() => const <LocalReminder>[
        LocalReminder(
          slot: 1,
          id: taskProgressId,
          name: '今天还差几个任务',
          kind: ReminderKind.taskProgress,
          hour: 21,
          minute: 30,
          title: '今天还差 {remaining} 个任务',
          body: '已完成 {done}/{total} —— 22:00 前做完，不然扣 10 分。\n'
              '睡觉卡也别忘了：晚于 22:00 打卡要扣 20 分。',
          builtin: true,
        ),
        LocalReminder(
          slot: 2,
          id: sleepId,
          name: '该睡觉啦',
          kind: ReminderKind.sleep,
          hour: 22,
          minute: 0,
          title: '该睡觉啦',
          body: '22:00 前打个睡觉卡，不然要扣 20 分。',
          builtin: true,
        ),
      ];
}
