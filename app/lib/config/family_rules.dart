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
  /// 固定任务表。顺序 = 同组内的渲染顺序（任务区按 [TaskGroup] 分组渲染）。
  ///
  /// 三组的分工（v2.10 起）：
  /// - **日常**：每天做一次的家务与学习，其中 [TaskConfig.mandatory] 的三件
  ///   没做会被服务端日结算扣分；
  /// - **本周**：一周 N 次（洗头 3 次 / 剪指甲 1 次 / 上班 1 天）；
  /// - **特殊加分**：参赛 / 获奖 / 学校奖状，不限次数，不算进「今日进度」。
  ///
  /// ⚠️ 加任务时必须同步 `functions/_lib/rules.ts` 的 `FAMILY_TASK_RULES`：
  /// 服务端拿自己那份判断分值，两边不一致时以服务端为准（客户端只是显示）。
  static const List<TaskConfig> taskRules = <TaskConfig>[
    // ── 日常 ──────────────────────────────────────────────
    TaskConfig(id: 'clean_room', name: '整理房间', type: TaskType.earning, value: 10, dailyLimit: 2),
    TaskConfig(id: 'wash_dishes', name: '洗碗', type: TaskType.earning, value: 5, dailyLimit: 2),
    TaskConfig(id: 'do_laundry', name: '洗衣服', type: TaskType.earning, value: 15, dailyLimit: 1),
    TaskConfig(id: 'take_out_trash', name: '倒垃圾', type: TaskType.earning, value: 5, dailyLimit: 1),
    TaskConfig(
      id: 'finish_homework',
      name: '按时完成作业',
      type: TaskType.earning,
      value: 20,
      dailyLimit: 1,
      mandatory: true,
      missPenalty: -10,
    ),
    TaskConfig(id: 'read_book', name: '课外阅读30分钟', type: TaskType.earning, value: 10, dailyLimit: 2),
    TaskConfig(
      id: 'wash_face',
      name: '洗脸刷牙',
      type: TaskType.earning,
      value: 5,
      dailyLimit: 1,
      mandatory: true,
      missPenalty: -10,
    ),
    TaskConfig(
      id: 'sleep_on_time',
      name: '按时睡觉',
      type: TaskType.earning,
      value: 10,
      dailyLimit: 1,
      window: TaskWindow(start: '19:00', end: '22:00'),
      mandatory: true,
      // 这条没做的罚款由服务端 `sleep_penalty -20` 负责（晚于 22:00），
      // 不再叠加必须任务的 -10 —— 否则「一晚没按时睡」会扣 30。
      missPenalty: -20,
    ),

    // ── 本周（自然周 周一–周日，周日晚 22:00 结算缺的次数）──────
    TaskConfig(
      id: 'wash_hair',
      name: '洗头',
      type: TaskType.earning,
      value: 5,
      dailyLimit: 1,
      group: TaskGroup.weekly,
      weeklyTarget: 3,
      mandatory: true,
      missPenalty: -10,
    ),
    TaskConfig(
      id: 'trim_nails',
      name: '剪指甲（手指甲/脚指甲）',
      type: TaskType.earning,
      value: 10,
      dailyLimit: 1,
      group: TaskGroup.weekly,
      weeklyTarget: 1,
      mandatory: true,
      missPenalty: -10,
    ),
    TaskConfig(
      id: 'work_one_day',
      name: '上班一天',
      type: TaskType.earning,
      value: 500,
      dailyLimit: 1,
      group: TaskGroup.weekly,
      weeklyTarget: 1,
    ),

    // ── 特殊加分（不限次数，不算今日进度）────────────────────
    TaskConfig(id: 'competition', name: '参加比赛', type: TaskType.earning, value: 20, group: TaskGroup.special),
    TaskConfig(id: 'award', name: '获奖', type: TaskType.earning, value: 50, group: TaskGroup.special),
    TaskConfig(id: 'school_cert', name: '学校奖状', type: TaskType.earning, value: 20, group: TaskGroup.special),

    // ── 消费 · 罚款（本次不动）───────────────────────────────
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

  /// 日结算里会**逐件**扣 [mandatoryPenaltyPerTask] 分的必须任务 id。
  ///
  /// 不含 `sleep_on_time`：它没做的罚款由 `sleep_penalty -20` 负责，
  /// 两笔都记就等于一晚扣 30（见 `functions/api/ledger/settle.ts`）。
  /// ⚠️ 必须与 `functions/_lib/rules.ts` 的 `MANDATORY_PENALTY_TASK_IDS` 一致。
  static const List<String> dailyPenaltyTaskIds = <String>['finish_homework', 'wash_face'];

  /// 必须任务没完成时每件扣多少分（正数，实际记账为负）
  static const int mandatoryPenaltyPerTask = 10;

  /// 周任务没完成时每缺一次扣多少分（正数，实际记账为负）
  static const int weeklyMissPenaltyPerVisit = 10;

  /// 按类型筛任务（对应 `getTasksByType`）
  static List<TaskConfig> tasksByType(TaskType type) =>
      taskRules.where((task) => task.type == type).toList(growable: false);

  /// 按分组筛任务（任务区分组渲染用）
  static List<TaskConfig> tasksByGroup(TaskType type, TaskGroup group) => taskRules
      .where((task) => task.type == type && task.group == group)
      .toList(growable: false);

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
