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

/// 任务在「赚积分」区里的展示分组（纯前端概念，服务端不关心）。
///
/// 为什么要有它：任务区原来只有「赚钱 / 消费」一刀切，12 条任务平铺成一张清单。
/// 加了「每天必须完成」「每周 N 次」「参赛获奖」之后，平铺会把「今天不做要扣分的事」
/// 和「一周只发生一次的事」混在同一个音量上，所以按频率分三组。
enum TaskGroup {
  /// 每天要做（含必须任务）
  daily,

  /// 每周 N 次（洗头 3 次、剪指甲 1 次、上班 1 天）
  weekly,

  /// 特殊加分：参赛 / 获奖 / 学校奖状，不限次数、不算进「今日进度」
  special,
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
    this.group = TaskGroup.daily,
    this.mandatory = false,
    this.weeklyTarget,
    this.missPenalty,
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

  /// 展示分组（见 [TaskGroup]）
  final TaskGroup group;

  /// 必须完成：当天/本周没做要扣 [missPenalty] 分。
  ///
  /// 目前只有「今天必须完成」那几件与周任务挂它 —— 消费罚款类永远 false，
  /// 它们本身就是「已经发生的事」，不存在「没做」。
  final bool mandatory;

  /// 每周目标次数（[TaskGroup.weekly] 用）：洗头 3、剪指甲 1、上班 1。
  final int? weeklyTarget;

  /// 没完成时扣多少分（负数，如 -10）；null = 不扣分。
  ///
  /// 前端只拿它做文案（「未做 −10」），真正扣分由服务端日结算执行。
  final int? missPenalty;

  /// 这条任务是不是「按周结算」的（周任务用自然周，日任务按天）
  bool get isWeekly => group == TaskGroup.weekly;

  /// 每周要做满几次；非周任务返回 null
  int? get weeklyGoal => isWeekly ? (weeklyTarget ?? 1) : null;

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
    TaskGroup? group,
    bool? mandatory,
    int? weeklyTarget,
    int? missPenalty,
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
        group: group ?? this.group,
        mandatory: mandatory ?? this.mandatory,
        weeklyTarget: weeklyTarget ?? this.weeklyTarget,
        missPenalty: missPenalty ?? this.missPenalty,
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
