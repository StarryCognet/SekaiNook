import '../data/models/task_config.dart';

/// 每周学习计划的模板行（对应 Web 版 `WEEKLY_PLAN_TEMPLATE` 的条目形状）。
class WeeklyPlanTemplate {
  const WeeklyPlanTemplate({
    required this.subject,
    required this.taskName,
    required this.target,
  });

  final String subject;
  final String taskName;
  final int target;
}

/// 家庭任务规则表（对应 Web 版 `src/config/familyRules.ts`，逐条照抄）。
///
/// 这张表是**前端本地规则**：任务清单、分值、日限、时间窗都在这里，
/// 后端不校验这些。所以改分值 = 改这里一处就够，但日限的拦截责任也在客户端。
abstract final class FamilyRules {
  /// 12 条固定任务。顺序与 Web 版一致（账本页按此顺序分组渲染）。
  static const List<TaskConfig> taskRules = <TaskConfig>[
    TaskConfig(id: 'clean_room', name: '整理房间', type: TaskType.earning, value: 10, dailyLimit: 2),
    TaskConfig(id: 'wash_dishes', name: '洗碗', type: TaskType.earning, value: 5, dailyLimit: 2),
    TaskConfig(id: 'do_laundry', name: '洗衣服', type: TaskType.earning, value: 15, dailyLimit: 1),
    TaskConfig(id: 'take_out_trash', name: '倒垃圾', type: TaskType.earning, value: 5, dailyLimit: 1),
    TaskConfig(id: 'finish_homework', name: '按时完成作业', type: TaskType.earning, value: 20, dailyLimit: 1),
    TaskConfig(id: 'read_book', name: '课外阅读30分钟', type: TaskType.earning, value: 10, dailyLimit: 2),
    TaskConfig(
      id: 'sleep_on_time',
      name: '按时睡觉',
      type: TaskType.earning,
      value: 10,
      dailyLimit: 1,
      window: TaskWindow(start: '19:00', end: '22:00'),
    ),
    TaskConfig(id: 'ipad_time', name: '看iPad 30分钟', type: TaskType.spending, value: -10, dailyLimit: 4),
    TaskConfig(id: 'phone_time', name: '玩手机 30分钟', type: TaskType.spending, value: -10, dailyLimit: 4),
    TaskConfig(
      id: 'eye_penalty',
      name: '视力下降1度',
      type: TaskType.spending,
      value: -100,
      description: '保护眼睛',
    ),
    TaskConfig(id: 'sleep_penalty', name: '未按时作息(晚于22:00)', type: TaskType.spending, value: -20, dailyLimit: 1),
    TaskConfig(id: 'homework_incomplete', name: '作业未完成', type: TaskType.spending, value: -50, dailyLimit: 1),
  ];

  /// 按类型筛任务（对应 `getTasksByType`）
  static List<TaskConfig> tasksByType(TaskType type) =>
      taskRules.where((task) => task.type == type).toList(growable: false);

  /// 按 id 找任务；找不到返回 null
  static TaskConfig? taskById(String id) {
    for (final task in taskRules) {
      if (task.id == id) return task;
    }
    return null;
  }

  /// 10 积分 = 1 元
  static const int pointsPerYuan = 10;

  /// 汇率文案，界面上要显示的地方统一读它，别各处手写
  static const String exchangeRateText = '100 积分 = 10 元';

  /// 积分换算成元，保留两位（对应 `pointsToYuan`：四舍五入到分）
  static double pointsToYuan(num points) => (points / pointsPerYuan * 100).round() / 100;

  /// 每周学习计划模板（8 行）
  static const List<WeeklyPlanTemplate> weeklyPlanTemplate = <WeeklyPlanTemplate>[
    WeeklyPlanTemplate(subject: '英语', taskName: '单词背诵', target: 50),
    WeeklyPlanTemplate(subject: '英语', taskName: '小作文', target: 1),
    WeeklyPlanTemplate(subject: '语文', taskName: '课文预习', target: 2),
    WeeklyPlanTemplate(subject: '语文', taskName: '课外阅读', target: 3),
    WeeklyPlanTemplate(subject: '数学', taskName: '口算练习', target: 5),
    WeeklyPlanTemplate(subject: '数学', taskName: '错题订正', target: 10),
    WeeklyPlanTemplate(subject: '日常', taskName: '22:00前睡觉', target: 7),
    WeeklyPlanTemplate(subject: '日常', taskName: '7:00起床', target: 7),
  ];

  /// 学习计划四个分类的展示顺序（做分组标题用）
  static const List<String> planSubjects = <String>['英语', '语文', '数学', '日常'];

  /// 「今日不足 5 个任务扣 10」这条惩罚的阈值 —— 只用于文案解释，判定在后端 settle。
  static const int dailyMinTasks = 5;

  /// 每日结算的默认惩罚/奖励金额（用于文案，实际金额以后端返回为准）
  static const int dailyMinTasksPenalty = -10;
  static const int sleepPenaltyAmount = -20;
  static const int welcomeBonus = 100;
}
