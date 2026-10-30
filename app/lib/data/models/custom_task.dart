import 'task_config.dart';

/// 自定义任务由谁创建 —— 决定打卡是即时到账还是走待审批
enum TaskCreator {
  parent('parent'),
  child('child');

  const TaskCreator(this.wire);
  final String wire;

  static TaskCreator parse(String? raw) =>
      raw == 'child' ? TaskCreator.child : TaskCreator.parent;
}

/// 预置任务 / 自建任务 —— 决定打卡上报用自带 id 还是统一的 `user_task_exec`
enum CustomTaskKind {
  preset('preset'),
  custom('custom');

  const CustomTaskKind(this.wire);
  final String wire;

  static CustomTaskKind parse(String? raw) =>
      raw == 'preset' ? CustomTaskKind.preset : CustomTaskKind.custom;
}

/// 任务名规范化（与服务端同一套）：trim + 折叠连续空白为单个空格 + 截断 30 字符
String normalizeTaskName(String name) {
  final folded = name.trim().replaceAll(RegExp(r'\s+'), ' ');
  return folded.length > 30 ? folded.substring(0, 30) : folded;
}

/// 存档字段容错读取：只有字符串才透传，其它类型（数字 / 对象 / null）一律当缺省。
///
/// 以前这里写的是 `raw['createdBy'] as String?` —— 存档被手改或旧格式里该字段是
/// 数字时会抛 TypeError，而整条任务的解析没有一个兜底，直接把启动流程炸掉（审计 S-2）。
String? _stringOrNull(dynamic value) => value is String ? value : null;

/// 自定义任务（本地存档，字段名与 Web 版 `CustomTask` 一字不差）
class CustomTask {
  const CustomTask({
    required this.id,
    required this.name,
    required this.value,
    required this.type,
    required this.createdBy,
    required this.createdAt,
    required this.kind,
    this.repeatDaily = true,
    this.requirePhoto = true,
  });

  final String id;
  final String name;

  /// 完成可得（正）/ 需扣（负），符号与 [type] 始终保持一致
  final int value;

  final TaskType type;
  final TaskCreator createdBy;

  /// ISO 字符串；预置任务定义里是空串，落地时填当前时间
  final String createdAt;

  final CustomTaskKind kind;

  /// 默认 true：每天可再打卡一次
  final bool repeatDaily;

  /// 提交这条任务是否必须带一张照片（拍照 / 相册）。
  ///
  /// 家长在「添加任务」里勾选，默认开 —— 孩子交的任务大多得看见东西才算数。
  /// 消费 / 罚款类固定 false（扣分只要写清原因，不要求拍照）。
  /// 最终判定统一走 `core/task_rules.dart` 的 `taskRequiresPhoto`。
  final bool requirePhoto;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'value': value,
        'type': type.wire,
        'createdBy': createdBy.wire,
        'createdAt': createdAt,
        'kind': kind.wire,
        'repeatDaily': repeatDaily,
        'requirePhoto': requirePhoto,
      };

  /// 从存档里还原一条任务；数据被手改得不像样就返回 null（整条丢弃）。
  ///
  /// 规范化规则与 Web 版 `toTask` 完全一致 —— 符号一律按 type 重算，
  /// 免得存档里出现「earning 但是负数」这种自相矛盾的条目。
  static CustomTask? fromStored(dynamic raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final value = raw['value'];
    if (id is! String || id.isEmpty) return null;
    if (name is! String || name.isEmpty) return null;
    if (value is! num || !value.isFinite) return null;

    final type = raw['type'] == 'spending' ? TaskType.spending : TaskType.earning;
    final abs = value.abs().round();
    final signed = type == TaskType.earning ? abs : -abs;
    final createdAt = raw['createdAt'];
    return CustomTask(
      id: id,
      name: name,
      value: signed,
      type: type,
      createdBy: TaskCreator.parse(_stringOrNull(raw['createdBy'])),
      createdAt: createdAt is String ? createdAt : DateTime.now().toUtc().toIso8601String(),
      kind: CustomTaskKind.parse(_stringOrNull(raw['kind'])),
      repeatDaily: raw['repeatDaily'] != false,
      // 老存档里没有这个字段：赚钱类按「要照片」兜底，消费 / 罚款一律不要
      requirePhoto: type == TaskType.earning ? raw['requirePhoto'] != false : false,
    );
  }

  /// 映射成打卡用的 [TaskConfig]。
  ///
  /// 提交 id 的分流规则：预置任务用自带 id（服务端已登记），
  /// 其余一律用统一的 `user_task_exec`（未知 task_id 服务端一律 403）。
  TaskConfig toExecTask({required String userTaskExecId}) {
    return TaskConfig(
      id: kind == CustomTaskKind.preset ? id : userTaskExecId,
      name: name,
      type: type,
      value: value,
      // 家长定的照片要求，原样带进打卡弹窗
      requirePhoto: requirePhoto,
    );
  }
}

/// 新增自定义任务的入参
class CustomTaskInput {
  const CustomTaskInput({
    required this.name,
    required this.value,
    required this.type,
    required this.createdBy,
    this.kind = CustomTaskKind.custom,
    this.repeatDaily = true,
    this.requirePhoto = true,
    this.id,
  });

  final String name;
  final num value;
  final TaskType type;
  final TaskCreator createdBy;
  final CustomTaskKind kind;
  final bool repeatDaily;

  /// 缺省 true（仅赚钱类有效；消费 / 罚款固定不需要照片）
  final bool requirePhoto;
  final String? id;
}
