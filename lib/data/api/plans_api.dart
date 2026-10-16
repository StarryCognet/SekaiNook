import '../../core/api_client.dart';
import '../models/weekly_plan.dart';

/// 新建计划时的种子项（服务端只认 subject / task_name / target 三个字段）
class PlanSeed {
  const PlanSeed({required this.subject, required this.taskName, required this.target});

  final String subject;
  final String taskName;
  final int target;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'subject': subject,
        'task_name': taskName,
        'target': target,
      };
}

/// 每周学习计划接口（对应 Web 版 `src/api/familyTasks.ts`）。
class PlansApi {
  PlansApi(this._api);

  final ApiClient _api;

  static const String _path = '/api/plans';

  /// 拉某周的计划。**参数名是 `week`**。
  Future<List<WeeklyPlan>> fetchPlans(String week) async {
    final raw = await _api.getJson<List<dynamic>>(_path, query: <String, dynamic>{'week': week});
    return _parseList(raw);
  }

  /// 幂等初始化某周。**参数名是 `week_label`**（与 GET 不同）。
  ///
  /// 服务端用 `INSERT OR IGNORE` + `UNIQUE(week_label, task_name)` 去重，
  /// 成功返回 201 + 该周完整计划，**不需要再 GET 一次**。
  Future<List<WeeklyPlan>> createPlans(String weekLabel, List<PlanSeed> items) async {
    final raw = await _api.postJson<List<dynamic>>(_path, data: <String, dynamic>{
      'week_label': weekLabel,
      'items': items.map((item) => item.toJson()).toList(),
    });
    return _parseList(raw);
  }

  /// 更新进度，返回**服务端夹取后的真实值**。
  ///
  /// 必须用返回值回写本地 state：界面写 60 / 目标 50 时服务端会夹成 50，
  /// 不回写就会出现「界面 60、库里 50」的错位。
  /// 另外 `current` 不是有限数字时服务端**不写库也不报错**，原样回显。
  Future<int> updateCurrent(String id, int current) async {
    final path = '$_path/${Uri.encodeComponent(id)}';
    final raw = await _api.patchJson<Map<String, dynamic>>(path, data: <String, dynamic>{
      'current': current,
    });
    final value = raw?['current'];
    return value is num ? value.round() : current;
  }

  List<WeeklyPlan> _parseList(List<dynamic>? raw) {
    if (raw == null) return <WeeklyPlan>[];
    final result = <WeeklyPlan>[];
    for (final item in raw) {
      if (item is Map) {
        result.add(WeeklyPlan.fromJson(item.map((key, value) => MapEntry(key.toString(), value))));
      }
    }
    return result;
  }
}
