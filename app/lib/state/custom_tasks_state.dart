import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_constants.dart';
import '../core/week.dart';
import '../data/models/custom_task.dart';
import '../data/models/ledger_record.dart';
import '../data/models/task_config.dart';

/// 自定义任务列表（对应 Web 版 `src/store/useCustomTasksStore.ts`）。
///
/// **不入账**：这份列表是纯本机存档，线上 D1 没有对应表（没有 migration 执行通道）。
/// 点「添加任务」只写进列表，不写流水；只有打卡完成时才写流水。
///
/// **上报 id 的分流**：非预置任务的打卡流水统一用 [userTaskExecId] 上报
/// （名称与金额由客户端带，`type` 由服务端按 amount 符号覆盖）；未知 `task_id`
/// 服务端一律 403，所以**绝不能自造 id 上报**。
class CustomTasksState extends ChangeNotifier {
  CustomTasksState({required SharedPreferences prefs}) : _prefs = prefs {
    _restore();
  }

  final SharedPreferences _prefs;

  /// 所有非预置任务的统一上报 id
  static const String userTaskExecId = 'user_task_exec';

  /// 两条预置任务：服务端已登记为独立 task_id（各自日限 1、即时到账），
  /// 且不占自定义任务的 50 分额度。
  static const List<String> presetTaskIds = <String>[
    'custom:english_words10',
    'custom:poem2',
  ];

  /// 服务端 `clientAmount` 的夹取上限
  static const int maxTaskValue = 200;

  /// 三条系统流水 —— 统计「今日完成数」时要排除
  static const List<String> systemTaskIds = <String>[
    'seed_welcome_bonus',
    'daily_min_tasks_penalty',
    'sleep_penalty',
  ];

  /// 预置任务定义（`createdBy` 硬编码 parent，这才是它们即时到账的根因）
  ///
  /// `requirePhoto` 默认 true（两条都是学习任务，照规矩要带照片才算完成）。
  static const List<CustomTask> presetTasks = <CustomTask>[
    CustomTask(
      id: 'custom:english_words10',
      name: '十个英语单词',
      value: 10,
      type: TaskType.earning,
      createdBy: TaskCreator.parent,
      createdAt: '',
      kind: CustomTaskKind.preset,
      requirePhoto: true,
    ),
    CustomTask(
      id: 'custom:poem2',
      name: '两首古诗',
      value: 10,
      type: TaskType.earning,
      createdBy: TaskCreator.parent,
      createdAt: '',
      kind: CustomTaskKind.preset,
      requirePhoto: true,
    ),
  ];

  List<CustomTask> _tasks = <CustomTask>[];

  /// 全部任务（含已追加的预置任务）
  List<CustomTask> get tasks => List<CustomTask>.unmodifiable(_tasks);

  /// 只要预置任务
  List<CustomTask> get presetTaskList =>
      _tasks.where((task) => task.kind == CustomTaskKind.preset).toList(growable: false);

  Map<String, String> _doneDate = <String, String>{};

  /// 已删掉的预置任务 id —— 不暴露给 UI，但每次落盘都要写回，
  /// 否则 `ensurePresets` 会把用户删掉的预置任务又加回来（「删除按钮看起来是坏的」）。
  List<String> _removedPresets = <String>[];

  // ---- 持久化 ----

  /// 读存档。**老版本直接存数组**是唯一的迁移形态（没有版本号字段）。
  void _restore() {
    final raw = _prefs.getString(AppConstants.keyCustomTasks);
    if (raw == null || raw.isEmpty) return;

    dynamic parsed;
    try {
      parsed = jsonDecode(raw);
    } catch (_) {
      return;
    }

    List<dynamic> rawTasks = <dynamic>[];
    if (parsed is List) {
      // 最早版本直接存任务数组
      rawTasks = parsed;
    } else if (parsed is Map) {
      final tasks = parsed['tasks'];
      if (tasks is List) rawTasks = tasks;
      final doneDate = parsed['doneDate'];
      if (doneDate is Map) {
        _doneDate = <String, String>{
          for (final entry in doneDate.entries)
            if (entry.value is String) entry.key.toString(): entry.value as String,
        };
      }
      final removed = parsed['removedPresets'];
      if (removed is List) {
        _removedPresets = removed.whereType<String>().toList();
      }
    }

    // 单条坏数据不该让整份存档作废，更不该在 App 启动时抛异常 —— 逐条兜底（审计 S-2）。
    _tasks = rawTasks
        .map((item) {
          try {
            return CustomTask.fromStored(item);
          } catch (_) {
            return null;
          }
        })
        .whereType<CustomTask>()
        .toList();
  }

  void _persist() {
    final payload = <String, dynamic>{
      'tasks': _tasks.map((task) => task.toJson()).toList(),
      'doneDate': _doneDate,
      'removedPresets': _removedPresets,
    };
    try {
      // 写盘是异步的：接住 future 才不会让「隐私模式 / 配额满」变成未捕获异步
      // 异常（L-15）；存不下就退化成只在内存里生效。
      unawaited(
        _prefs
            .setString(AppConstants.keyCustomTasks, jsonEncode(payload))
            .catchError((Object _) => false),
      );
    } catch (_) {
      // 本机存储不可用：退化成只在内存里生效
    }
  }

  // ---- 动作 ----

  /// 新增任务并返回它。本方法不抛（存档写入失败已在 [_persist] 内吞掉）。
  CustomTask addTask(CustomTaskInput input) {
    final type = input.type;
    var abs = input.value.isFinite ? input.value.abs().round() : 0;
    if (abs == 0) abs = 1; // 0 / NaN 归 1
    if (abs < 1) abs = 1;
    if (abs > maxTaskValue) abs = maxTaskValue;

    final id = input.id ?? _nextTaskId(input.createdBy, _tasks);
    final name = normalizeTaskName(input.name);
    final created = CustomTask(
      id: id,
      name: name.isEmpty ? '未命名任务' : name,
      value: type == TaskType.earning ? abs : -abs,
      type: type,
      createdBy: input.createdBy,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      kind: input.kind,
      repeatDaily: input.repeatDaily,
      // 家长勾的「必须添加照片」只在赚钱类上生效；扣分类不需要照片
      requirePhoto: type == TaskType.earning ? input.requirePhoto : false,
    );

    // 同 id 覆盖且挪到末尾
    _tasks = <CustomTask>[
      ..._tasks.where((task) => task.id != created.id),
      created,
    ];
    _persist();
    notifyListeners();
    return created;
  }

  /// 删除任务。**完全不动服务端流水** —— 历史照旧显示在流水列表里
  /// （任务名存在流水的 `task_name` 上，所以删任务不会让历史失去可读性）。
  void removeTask(String id) {
    final target = _taskById(id);
    if (target != null &&
        target.kind == CustomTaskKind.preset &&
        !_removedPresets.contains(id)) {
      _removedPresets = <String>[..._removedPresets, id];
    }
    _tasks = _tasks.where((task) => task.id != id).toList();
    final nextDone = Map<String, String>.from(_doneDate)..remove(id);
    _doneDate = nextDone;
    _persist();
    notifyListeners();
  }

  /// 把两条预置任务追加进列表（页面挂载时调）。**没有变更就完全不写盘、不通知**。
  void ensurePresets() {
    final next = List<CustomTask>.from(_tasks);
    var changed = false;
    for (final preset in presetTasks) {
      if (_removedPresets.contains(preset.id)) continue;
      if (next.any((task) => task.id == preset.id)) continue;
      next.add(CustomTask(
        id: preset.id,
        name: preset.name,
        value: preset.value,
        type: preset.type,
        createdBy: preset.createdBy,
        createdAt: DateTime.now().toUtc().toIso8601String(),
        kind: preset.kind,
        repeatDaily: preset.repeatDaily,
        requirePhoto: preset.requirePhoto,
      ));
      changed = true;
    }
    if (!changed) return;
    _tasks = next;
    _persist();
    notifyListeners();
  }

  /// 记「今天已完成」。**无条件覆盖**，不检查是否已打卡。
  ///
  /// 调用时机：打卡**成功之后**；以及「账已记上但立即审批失败」时也要调 ——
  /// 本地也要算今天已完成，不然孩子再点一次只会撞上服务端的同名日限。
  void markDone(String id) {
    _doneDate = <String, String>{..._doneDate, id: WeekUtil.beijingDayKey()};
    _persist();
    notifyListeners();
  }

  /// 今天这条任务是不是已经完成过。
  ///
  /// 一次性任务（`repeatDaily == false`）完成过就一直算完成，跨天也 true。
  bool isDoneToday(String id) {
    final day = _doneDate[id];
    if (day == null) return false;
    final task = _taskById(id);
    if (task != null && !task.repeatDaily) return true;
    return day == WeekUtil.beijingDayKey();
  }

  CustomTask? _taskById(String id) {
    for (final task in _tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  /// 家长 `custom_<ms>`、孩子 `wish_<ms>`；同一毫秒撞了往后挪。
  /// **撞检查只在同前缀内做**（两个序列各自独立）。
  static String _nextTaskId(TaskCreator createdBy, List<CustomTask> tasks) {
    final prefix = createdBy == TaskCreator.child ? 'wish_' : 'custom_';
    var stamp = DateTime.now().millisecondsSinceEpoch;
    while (tasks.any((task) => task.id == '$prefix$stamp')) {
      stamp += 1;
    }
    return '$prefix$stamp';
  }
}

/// 今日完成数 —— 与**服务端 `daily_min_tasks_penalty` 口径完全一致**。
///
/// 逐条流水满足全部条件才算数：
/// 1. 无状态视为已审批（兼容存量数据），只有显式非 approved 才跳过；
/// 2. 必须是 `earning` 且 amount > 0（花钱 / 罚款不算完成）；
/// 3. 排除三条系统流水；
/// 4. 按**东八区天**过滤（不是本机 `toDateString`）；
/// 5. 按 `task_id` 去重 —— 一天背三首诗只算 1 个任务。
int countDoneToday(List<LedgerRecord> records, {DateTime? now}) {
  final day = WeekUtil.beijingDayKey(now);
  final done = <String>{};
  for (final record in records) {
    final status = record.status;
    if (status != null && status != LedgerStatus.approved) continue;
    if (record.type != TaskType.earning || record.amount <= 0) continue;
    if (CustomTasksState.systemTaskIds.contains(record.taskId)) continue;
    final at = record.createdAt.toUtc();
    if (WeekUtil.beijingDayKey(at) != day) continue;
    done.add(record.taskId);
  }
  return done.length;
}

/// 今天这条任务是否已经有流水（按钮置灰用）。
///
/// ⚠️ 这只是省一次白跑的请求，**正确性在服务端**（同名当日第二次会 409）。
///
/// 口径注意：按**东八区天**过滤，与 [countDoneToday] 和服务端一致（L-9）。
/// 以前这里用本机时区的日历天 —— 非东八区设备上「今天」会和统计/日结算打架。
bool isRecordedToday(CustomTask task, List<LedgerRecord> records, {DateTime? now}) {
  final day = WeekUtil.beijingDayKey(now);
  for (final record in records) {
    if (record.status == LedgerStatus.rejected) continue;
    if (WeekUtil.beijingDayKey(record.createdAt) != day) continue;
    if (task.kind == CustomTaskKind.preset) {
      if (record.taskId == task.id) return true;
    } else {
      // 自定义任务全部写 user_task_exec，服务端按任务名判重，本地也只能按规范化名字认
      if (record.taskId == CustomTasksState.userTaskExecId &&
          normalizeTaskName(record.taskName) == normalizeTaskName(task.name)) {
        return true;
      }
    }
  }
  return false;
}
