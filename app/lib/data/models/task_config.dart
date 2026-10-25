/// 任务类型（对应 Web 版 `src/types/family.ts` 的 `TaskType`）。
///
/// `name` 就是接口上的取值（'earning' / 'spending'），不要改成中文。
enum TaskType { earning, spending }

extension TaskTypeX on TaskType {
  /// 传给接口的字符串
  String get wire => name;

  /// 解析接口返回值；不认识的一律当 earning（与 Web 版 `?? 'earning'` 同行为）
  static TaskType parse(Object? value) =>
      value == 'spending' ? TaskType.spending : TaskType.earning;

  String get label => this == TaskType.earning ? '赚积分' : '扣积分';
}

/// 打卡时间窗（24 小时制 "HH:mm"，闭区间，不支持跨零点）。
class TaskWindow {
  const TaskWindow({required this.start, required this.end});

  final String start;
  final String end;

  factory TaskWindow.fromJson(Map<String, dynamic> json) => TaskWindow(
        start: (json['start'] ?? '') as String,
        end: (json['end'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{'start': start, 'end': end};

  /// 拆成「当天第几分钟」，供区间比较
  int get startMinutes => _toMinutes(start);
  int get endMinutes => _toMinutes(end);

  static int _toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return 0;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return h * 60 + m;
  }

  /// 该时刻是否落在窗口内
  bool contains(DateTime now) {
    final minutes = now.hour * 60 + now.minute;
    return minutes >= startMinutes && minutes <= endMinutes;
  }
}

/// 一条任务配置（对应 Web 版 `TaskConfig`）。
class TaskConfig {
  const TaskConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.value,
    this.unit = '积分',
    this.description,
    this.dailyLimit,
    this.window,
    this.requirePhoto,
  });

  final String id;
  final String name;
  final TaskType type;

  /// 分值。earning 为正、spending 为负（规则表里就这么写的）。
  final int value;
  final String unit;
  final String? description;

  /// 每日次数上限；null = 不限次
  final int? dailyLimit;
  final TaskWindow? window;

  /// 提交这条任务是否必须带一张照片（拍照 / 相册）。
  ///
  /// null = 按类型兜底（赚钱类必须，消费 / 罚款不强制），判定统一走
  /// `core/task_rules.dart` 的 `taskRequiresPhoto`；自定义任务由家长在
  /// 「添加任务」里勾选，原样带到这里。
  final bool? requirePhoto;

  factory TaskConfig.fromJson(Map<String, dynamic> json) => TaskConfig(
        id: (json['id'] ?? '') as String,
        name: (json['name'] ?? '') as String,
        type: TaskTypeX.parse(json['type']),
        value: (json['value'] as num?)?.toInt() ?? 0,
        unit: (json['unit'] as String?) ?? '积分',
        description: json['description'] as String?,
        dailyLimit: (json['daily_limit'] as num?)?.toInt() ?? (json['dailyLimit'] as num?)?.toInt(),
        // 用 `is Map` 而不是 `is Map<String, dynamic>`（L-5）：JSON 解码出来也可能是
        // Map<dynamic, dynamic>，过窄的判断会让时间窗静默失效（任务全天可打卡）。
        window: json['window'] is Map
            ? TaskWindow.fromJson(
                Map<String, dynamic>.from(json['window'] as Map),
              )
            : null,
      );

  /// 展示用的正负号文案，如 `+10` / `-10`
  String get signedValue => value >= 0 ? '+$value' : '$value';

  TaskConfig copyWith({
    String? id,
    String? name,
    TaskType? type,
    int? value,
    String? unit,
    String? description,
    int? dailyLimit,
    TaskWindow? window,
    bool? requirePhoto,
  }) =>
      TaskConfig(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        value: value ?? this.value,
        unit: unit ?? this.unit,
        description: description ?? this.description,
        dailyLimit: dailyLimit ?? this.dailyLimit,
        window: window ?? this.window,
        requirePhoto: requirePhoto ?? this.requirePhoto,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'type': type.wire,
        'value': value,
        'unit': unit,
        if (description != null) 'description': description,
        if (dailyLimit != null) 'daily_limit': dailyLimit,
        if (window != null) 'window': window!.toJson(),
      };
}
