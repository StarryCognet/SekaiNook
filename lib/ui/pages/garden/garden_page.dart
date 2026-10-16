import 'dart:math' as math;

// Material 也有一个 Badge（小红点角标），花园的勋章模型重名，藏掉 Material 那个
import 'package:flutter/material.dart' hide Badge;
import 'package:provider/provider.dart';

import '../../../config/garden_config.dart';
import '../../../data/models/garden.dart';
import '../../../data/models/ledger_record.dart';
import '../../../state/garden_state.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tokens.dart';
import '../../widgets/app_card.dart';
import '../../widgets/state_views.dart';

/// 花园里养着的植物（照抄 Web 版 `src/views/garden/GardenPage.tsx` 的 `PLANTS`）
class _Plant {
  const _Plant({required this.name, required this.desc, required this.icon});

  final String name;
  final String desc;
  final IconData icon;
}

const List<_Plant> _plants = <_Plant>[
  _Plant(name: '向日葵', desc: '阳光越足，长得越高', icon: Icons.wb_sunny_outlined),
  _Plant(name: '小玫瑰', desc: '需要细心照顾', icon: Icons.local_florist_outlined),
  _Plant(name: '仙人掌', desc: '坚强的小植物', icon: Icons.eco_outlined),
];

/// 图标 key → Material 图标。
///
/// key 与 Web 版 `src/components/garden/GardenIcon.tsx` 的 `ICON_MAP` 一一对应
/// （`flower` → SmileOutlined、`leaf` → EnvironmentOutlined 那两个在 Material 里
/// 取语义更近的花/叶图标），未知 key 回退星形，与 Web 版一致。
IconData _gardenIcon(String key) => switch (key) {
      'book' => Icons.menu_book_outlined,
      'read' => Icons.chrome_reader_mode_outlined,
      'book-open' => Icons.chrome_reader_mode_outlined,
      'calc' => Icons.calculate_outlined,
      'pen' => Icons.edit_outlined,
      'feather' => Icons.edit_outlined,
      'eye' => Icons.visibility_outlined,
      'sport' => Icons.bolt_outlined,
      'home' => Icons.home_outlined,
      'sun' => Icons.wb_sunny_outlined,
      'flower' => Icons.local_florist_outlined,
      'leaf' => Icons.eco_outlined,
      'calendar' => Icons.calendar_today_outlined,
      'trophy' => Icons.emoji_events_outlined,
      'coin' => Icons.monetization_on_outlined,
      'dashboard' => Icons.dashboard_outlined,
      'check' => Icons.check_circle_outline,
      'shop' => Icons.storefront_outlined,
      'history' => Icons.history,
      'star' => Icons.star_outline,
      _ => Icons.star_outline,
    };

/// 阳光花园儿童工作台（对应 Web 版 `src/views/garden/` 下的 8 个页面）。
///
/// 8 个菜单：学习总览 / 今日任务 / 古诗背诵 / 语文预习 / 阳光花园 / 阳光商城 /
/// 我的奖励 / 学习记录。Web 版把菜单挂在 URL 上（`/garden?tab=poem`），
/// Flutter 侧没有 URL 承载菜单，就用本页 state 保存当前 key，`setState` 切换。
///
/// 数据只来自 [GardenState]：阳光余额 = 显示余额（权威值 + 未同步增量），
/// 今日进度 / 完成率都由 `tasks` 与 `completedCount` 同口径派生。
class GardenPage extends StatefulWidget {
  const GardenPage({super.key});

  @override
  State<GardenPage> createState() => _GardenPageState();
}

class _GardenPageState extends State<GardenPage> {
  /// 当前菜单 key（只在 `GardenConfig.isMenuKey` 通过时切换，未知 key 不渲染空白）
  String _menu = GardenConfig.defaultMenu;

  /// 展开了全文的古诗 id（12 首全文一屏铺开太长，默认收一行显示）
  final Set<String> _expandedPoems = <String>{};

  /// 儿童向大按钮的最小高度（48 = xl + md，不写尺寸字面量）
  static const Size _buttonSize = Size(0, AppSpacing.xl + AppSpacing.md);

  static const Widget _gapSm = SizedBox(height: AppSpacing.sm);
  static const Widget _gapMd = SizedBox(height: AppSpacing.md);

  /// 商城分类展示顺序（对应 Web 版 `ShopPage.tsx` 的 `CATEGORY_ORDER`）
  static const List<GardenShopCategory> _categoryOrder = <GardenShopCategory>[
    GardenShopCategory.avatar,
    GardenShopCategory.title,
    GardenShopCategory.decor,
  ];

  @override
  void initState() {
    super.initState();
    // 进花园就初始化（对应 Web 版 GardenLayout 挂载时的 init()，可重复调用）。
    // 放到首帧之后：init() 会同步 notifyListeners，在 build 阶段喊醒别的监听者会报错。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<GardenState>().init();
    });
  }

  // ---- 本页派生值 ----

  /// 今日任务完成百分比（分子分母同口径：都来自 `tasks`，并夹到 0~100）
  int _percent(GardenState garden) {
    final int total = garden.tasks.length;
    if (total == 0) return 0;
    return math.min(100, math.max(0, (garden.completedCount / total * 100).round()));
  }

  /// 今日实际到手的阳光（存档里的日期不是今天时一律按 0 算）
  int _earnedToday(GardenState garden) =>
      garden.todayEarnedDate == todayKey() ? garden.todayEarned : 0;

  /// 时刻文案（HH:mm，`LedgerRecord.createdAt` 已转本机时区）
  String _timeLabel(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  /// 流水标题：服务端写的是规则名（如「背一首古诗」）；万一拿到的是裸 task_id，
  /// 就翻回本地名字，别把 `garden:poem` 这种串丢给孩子看。
  String _recordTitle(LedgerRecord record) {
    final String name = record.taskName;
    if (name.isNotEmpty && !name.startsWith('garden')) return name;
    final String raw = name.isNotEmpty ? name : record.taskId;
    if (raw == 'garden_legacy') return '花园阳光迁移';
    for (final GardenTask task in GardenConfig.tasks) {
      if (raw == 'garden:${task.id}') return task.name;
    }
    for (final GardenChinesePractice practice in GardenConfig.chinesePractices) {
      if (raw == 'garden:${practice.id}') return practice.title;
    }
    for (final GardenShopItem item in GardenConfig.shopItems) {
      if (raw == 'garden_shop:${item.id}') return item.name;
    }
    return raw;
  }

  // ---- 轻提示与动作 ----

  /// 统一的轻提示（对应 Web 版的 antd `message`）
  void _toast(String message, {bool success = false, bool error = false}) {
    final AppPalette palette = context.palette;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: error
            ? palette.danger
            : success
                ? palette.success
                : null,
      ),
    );
  }

  void _switchMenu(String key) {
    if (key == _menu) return;
    if (!GardenConfig.isMenuKey(key)) return;
    setState(() => _menu = key);
  }

  void _togglePoem(String poemId) {
    setState(() {
      if (!_expandedPoems.remove(poemId)) _expandedPoems.add(poemId);
    });
  }

  /// 完成今日任务。store 会挡下「今天已经做过」的重复打卡（含连点两次），
  /// 这时不能再报喜 —— 否则孩子以为又赚了一份阳光，刷新后数字却没变。
  void _completeTask(GardenTask task) {
    final GardenState garden = context.read<GardenState>();
    if (task.done) {
      _toast('「${task.name}」今天已经完成过啦');
      return;
    }
    garden.completeTask(task.id);
    final bool done = garden.tasks.any((GardenTask item) => item.id == task.id && item.done);
    if (!done) {
      _toast('「${task.name}」今天已经完成过啦');
      return;
    }
    _toast('+${task.reward} 阳光！${task.name}完成啦', success: true);
  }

  void _recite(GardenPoem poem) {
    final GardenState garden = context.read<GardenState>();
    if (!garden.recitePoem(poem.id)) {
      _toast('《${poem.title}》今天已经背过啦，明天再来复习吧');
      return;
    }
    _toast('《${poem.title}》背诵成功！+${poem.reward} 阳光', success: true);
  }

  void _practice(GardenChinesePractice practice, int current) {
    final GardenState garden = context.read<GardenState>();
    if (!garden.completeChineseStep(practice.id)) {
      _toast('${practice.title}今天已经练完啦，明天继续加油');
      return;
    }
    final bool isLast = current + 1 >= practice.timesPerDay;
    _toast(
      isLast ? '${practice.title}完成啦！+${practice.reward} 阳光' : '打卡成功！+${practice.reward} 阳光',
      success: true,
    );
  }

  void _care() {
    final GardenState garden = context.read<GardenState>();
    if (garden.careForGarden()) {
      _toast('照顾成功！植物们精神多啦', success: true);
      return;
    }
    _toast('今天的花园已经照顾过啦，明天再来吧');
  }

  // ---- 页面骨架 ----

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final GardenState garden = context.watch<GardenState>();

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: garden.tasks.isEmpty
            ? const LoadingView(message: '正在打开花园…')
            : Column(
                children: <Widget>[
                  if (garden.pending.isNotEmpty) _buildPendingBanner(garden, palette),
                  _buildHeader(garden, palette),
                  _buildMenuBar(),
                  Expanded(child: _buildMenuContent(garden, palette)),
                ],
              ),
      ),
    );
  }

  /// 离线队列提示：还没同步的打卡 / 兑换，点一下立刻重试
  Widget _buildPendingBanner(GardenState garden, AppPalette palette) {
    final int delta = garden.pendingDelta;
    final String deltaText = delta == 0 ? '' : '（未同步阳光 ${delta > 0 ? '+' : ''}$delta）';
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
      child: AppCard(
        highlight: true,
        onTap: () => garden.flushPending(),
        child: Row(
          children: <Widget>[
            Icon(Icons.cloud_upload_outlined, color: palette.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${garden.pending.length} 条记录待同步',
                    style: TextStyle(
                      fontSize: AppFontSize.sm,
                      fontWeight: FontWeight.w600,
                      color: palette.text,
                      fontFeatures: kTabularNumbers,
                    ),
                  ),
                  Text(
                    '点一下马上重试$deltaText',
                    style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
                  ),
                ],
              ),
            ),
            Text(
              '重试',
              style: TextStyle(
                fontSize: AppFontSize.sm,
                fontWeight: FontWeight.w700,
                color: palette.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部常驻三件套：阳光余额 / 连续天数 / 今日进度（孩子第一眼要看到的）
  Widget _buildHeader(GardenState garden, AppPalette palette) {
    final int percent = _percent(garden);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: StatBlock(
                    label: '阳光余额',
                    value: '${garden.balance}',
                    unit: '阳光',
                    color: palette.warning,
                    icon: Icons.wb_sunny_outlined,
                  ),
                ),
                Expanded(
                  child: StatBlock(
                    label: '连续学习',
                    value: '${garden.streakDays}',
                    unit: '天',
                    color: palette.danger,
                    icon: Icons.local_fire_department_outlined,
                  ),
                ),
                Expanded(
                  child: StatBlock(
                    label: '今日任务',
                    value: '${garden.completedCount}/${garden.tasks.length}',
                    unit: '个',
                    color: palette.primary,
                    icon: Icons.check_circle_outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _ProgressBar(value: percent / 100, color: palette.primary, track: palette.surfaceSoft),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '今天已经赚到 ${_earnedToday(garden)} 阳光，任务完成 $percent%',
              style: TextStyle(
                fontSize: AppFontSize.xs,
                color: palette.textSecondary,
                fontFeatures: kTabularNumbers,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 横向 Tab 条：8 个菜单（375px 下横向滚动，不做换行挤压）
  Widget _buildMenuBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: <Widget>[
          for (final GardenMenu menu in GardenConfig.menus)
            _MenuChip(
              menu: menu,
              selected: menu.key == _menu,
              onTap: () => _switchMenu(menu.key),
            ),
        ],
      ),
    );
  }

  Widget _buildMenuContent(GardenState garden, AppPalette palette) {
    switch (_menu) {
      case 'overview':
        return _buildOverview(garden, palette);
      case 'tasks':
        return _buildTasks(garden, palette);
      case 'poem':
        return _buildPoems(garden, palette);
      case 'chinese':
        return _buildChinese(garden, palette);
      case 'garden':
        return _buildGarden(garden, palette);
      case 'shop':
        return _buildShop(garden, palette);
      case 'rewards':
        return _buildRewards(garden, palette);
      case 'records':
        return _buildRecords(garden, palette);
      default:
        return _buildTasks(garden, palette);
    }
  }

  Widget _pageList(List<Widget> children) => ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: children,
      );

  // ---- 1. 学习总览（Web 版 OverviewPage.tsx）----

  Widget _buildOverview(GardenState garden, AppPalette palette) {
    final int percent = _percent(garden);
    final int earnedBadges = garden.badges.where((Badge badge) => badge.earned).length;
    final List<GardenShopItem> decorItems = GardenConfig.shopItems
        .where((GardenShopItem item) =>
            item.category == GardenShopCategory.decor && garden.equippedDecor.contains(item.id))
        .toList();

    return _pageList(<Widget>[
      const SectionHeader(title: '学习总览'),
      Row(
        children: <Widget>[
          Expanded(
            child: _statTile(
              label: '阳光余额',
              value: '${garden.balance}',
              unit: '阳光',
              icon: Icons.wb_sunny_outlined,
              color: palette.warning,
            ),
          ),
          _gapSm,
          Expanded(
            child: _statTile(
              label: '连续学习',
              value: '${garden.streakDays}',
              unit: '天',
              icon: Icons.local_fire_department_outlined,
              color: palette.danger,
            ),
          ),
          _gapSm,
          Expanded(
            child: _statTile(
              label: '已获勋章',
              value: '$earnedBadges',
              unit: '枚',
              icon: Icons.emoji_events_outlined,
              color: palette.success,
            ),
          ),
        ],
      ),
      _gapMd,
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '今日学习进度',
              style: TextStyle(
                fontSize: AppFontSize.md,
                fontWeight: FontWeight.w600,
                color: palette.text,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _ProgressBar(value: percent / 100, color: palette.primary, track: palette.surfaceSoft),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${garden.completedCount}/${garden.tasks.length} 个任务',
              style: TextStyle(
                fontSize: AppFontSize.sm,
                color: palette.textSecondary,
                fontFeatures: kTabularNumbers,
              ),
            ),
          ],
        ),
      ),
      // 孩子挂在花园里的装饰：买到的要能看见（一件都没有时整块不渲染）
      if (decorItems.isNotEmpty) ...<Widget>[
        _gapMd,
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '花园里多了什么',
                style: TextStyle(
                  fontSize: AppFontSize.md,
                  fontWeight: FontWeight.w600,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  for (final GardenShopItem item in decorItems)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(_gardenIcon(item.icon), size: 18, color: palette.success),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          item.shortName,
                          style: TextStyle(fontSize: AppFontSize.sm, color: palette.text),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
      _gapMd,
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '今日小贴士',
              style: TextStyle(
                fontSize: AppFontSize.md,
                fontWeight: FontWeight.w600,
                color: palette.text,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  const TextSpan(text: '完成所有任务可以获得 '),
                  TextSpan(
                    text: '${GardenConfig.dailyTaskReward}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: palette.warning,
                      fontFeatures: kTabularNumbers,
                    ),
                  ),
                  const TextSpan(text: ' 阳光，坚持学习还能解锁更多勋章哦！'),
                ],
              ),
              style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary, height: 1.6),
            ),
          ],
        ),
      ),
    ]);
  }

  /// 带图标的小统计卡（Row 里用 Expanded 包一层）
  Widget _statTile({
    required String label,
    required String value,
    String? unit,
    required IconData icon,
    required Color color,
  }) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: AppSpacing.sm),
          StatBlock(label: label, value: value, unit: unit, color: color),
        ],
      ),
    );
  }

  // ---- 2. 今日任务（Web 版 TasksPage.tsx）----

  Widget _buildTasks(GardenState garden, AppPalette palette) {
    final int percent = _percent(garden);
    return _pageList(<Widget>[
      const SectionHeader(title: '今日任务'),
      Row(
        children: <Widget>[
          Expanded(
            child: _statTile(
              label: '今日完成',
              value: '${garden.completedCount}',
              unit: '个任务',
              icon: Icons.check_circle_outline,
              color: palette.success,
            ),
          ),
          _gapSm,
          Expanded(
            child: _statTile(
              label: '完成率',
              value: '$percent%',
              icon: Icons.trending_up_outlined,
              color: palette.primary,
            ),
          ),
          _gapSm,
          Expanded(
            child: _statTile(
              label: '连续学习',
              value: '${garden.streakDays}',
              unit: '天',
              icon: Icons.local_fire_department_outlined,
              color: palette.danger,
            ),
          ),
        ],
      ),
      _gapMd,
      for (final GardenTask task in garden.tasks)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _taskCard(task, palette),
        ),
    ]);
  }

  Widget _taskCard(GardenTask task, AppPalette palette) {
    final bool done = task.done;
    final Color accent = done ? palette.success : palette.primary;
    return AppCard(
      child: Row(
        children: <Widget>[
          _CheckButton(done: done, onTap: done ? null : () => _completeTask(task)),
          const SizedBox(width: AppSpacing.sm),
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(_gardenIcon(task.icon), size: 20, color: accent),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  task.name,
                  style: TextStyle(
                    fontSize: AppFontSize.md,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(
                  task.description,
                  style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: <Widget>[
                    Icon(Icons.schedule, size: 14, color: palette.textTertiary),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      '${task.duration} 分钟',
                      style: TextStyle(
                        fontSize: AppFontSize.xs,
                        color: palette.textTertiary,
                        fontFeatures: kTabularNumbers,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.wb_sunny_outlined,
                    size: 14,
                    color: done ? palette.textTertiary : palette.warning,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '+${task.reward}',
                    style: TextStyle(
                      fontSize: AppFontSize.md,
                      fontWeight: FontWeight.w700,
                      color: done ? palette.textTertiary : palette.warning,
                      fontFeatures: kTabularNumbers,
                    ),
                  ),
                ],
              ),
              Text(
                '阳光',
                style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- 3. 古诗背诵（Web 版 PoemPage.tsx）----

  Widget _buildPoems(GardenState garden, AppPalette palette) {
    final String today = todayKey();
    final List<String> doneToday =
        garden.poemDate == today ? garden.todayPoemIds : const <String>[];
    final int target = GardenConfig.badgeTargets['poet'] ?? 10;
    final int percent = target > 0 ? math.min(100, (garden.poemCount / target * 100).round()) : 0;
    final int remain = math.max(0, target - garden.poemCount);

    return _pageList(<Widget>[
      const SectionHeader(title: '古诗背诵'),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  const TextSpan(text: '累计背会 '),
                  TextSpan(
                    text: '${garden.poemCount}',
                    style: TextStyle(
                      fontSize: AppFontSize.md,
                      fontWeight: FontWeight.w700,
                      color: palette.primary,
                      fontFeatures: kTabularNumbers,
                    ),
                  ),
                  TextSpan(
                    text: remain > 0 ? ' 首，还差 $remain 首解锁「小诗人」' : ' 首，已经解锁「小诗人」啦',
                  ),
                ],
              ),
              style: TextStyle(fontSize: AppFontSize.sm, color: palette.text),
            ),
            const SizedBox(height: AppSpacing.sm),
            _ProgressBar(value: percent / 100, color: palette.primary, track: palette.surfaceSoft),
          ],
        ),
      ),
      _gapMd,
      for (final GardenPoem poem in GardenConfig.poems)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _poemCard(poem, doneToday.contains(poem.id), palette),
        ),
    ]);
  }

  Widget _poemCard(GardenPoem poem, bool done, AppPalette palette) {
    final bool expanded = _expandedPoems.contains(poem.id);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(_gardenIcon('book'), size: 18, color: palette.primary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  '《${poem.title}》',
                  style: TextStyle(
                    fontSize: AppFontSize.md,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
              ),
              Text(
                poem.author,
                style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // 默认收一行，点一下看全文（孩子一屏能扫过 12 首）
          GestureDetector(
            onTap: () => _togglePoem(poem.id),
            child: Text(
              poem.text,
              maxLines: expanded ? null : 1,
              overflow: expanded ? null : TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary, height: 1.6),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              TextButton(
                onPressed: () => _togglePoem(poem.id),
                style: TextButton.styleFrom(
                  foregroundColor: palette.primary,
                  textStyle: const TextStyle(fontSize: AppFontSize.xs),
                ),
                child: Text(expanded ? '收起' : '展开全文'),
              ),
              const Spacer(),
              if (done)
                _StatusChip(label: '今天已背会', color: palette.success)
              else
                FilledButton(
                  onPressed: () => _recite(poem),
                  style: FilledButton.styleFrom(minimumSize: _buttonSize),
                  child: Text('我背会了 +${poem.reward}'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- 4. 语文预习（Web 版 ChinesePage.tsx）----

  Widget _buildChinese(GardenState garden, AppPalette palette) {
    final String today = todayKey();
    final Map<String, int> steps =
        garden.chineseDate == today ? garden.chineseSteps : const <String, int>{};

    return _pageList(<Widget>[
      const SectionHeader(title: '语文预习', subtitle: '每打卡一次都记一次花园任务'),
      for (final GardenChinesePractice practice in GardenConfig.chinesePractices)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _practiceCard(practice, steps[practice.id] ?? 0, palette),
        ),
    ]);
  }

  Widget _practiceCard(GardenChinesePractice practice, int current, AppPalette palette) {
    final bool done = current >= practice.timesPerDay;
    final int percent = practice.timesPerDay > 0
        ? math.min(100, (current / practice.timesPerDay * 100).round())
        : 0;
    final Color accent = done ? palette.success : palette.primary;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(_gardenIcon('read'), size: 18, color: accent),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  practice.title,
                  style: TextStyle(
                    fontSize: AppFontSize.md,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
              ),
              if (done) Icon(Icons.check_circle, size: 20, color: palette.success),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            practice.desc,
            style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ProgressBar(value: percent / 100, color: accent, track: palette.surfaceSoft),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              Text(
                '已完成 $current/${practice.timesPerDay} 次',
                style: TextStyle(
                  fontSize: AppFontSize.xs,
                  color: palette.textTertiary,
                  fontFeatures: kTabularNumbers,
                ),
              ),
              const Spacer(),
              Text(
                '每次 +${practice.reward} 阳光',
                style: TextStyle(
                  fontSize: AppFontSize.xs,
                  color: palette.warning,
                  fontFeatures: kTabularNumbers,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: done ? null : () => _practice(practice, current),
              style: FilledButton.styleFrom(minimumSize: _buttonSize),
              child: Text(
                done
                    ? '今天已完成'
                    : '${practice.actionLabel} ($current/${practice.timesPerDay}) +${practice.reward}',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- 5. 阳光花园（Web 版 GardenPage.tsx）----

  Widget _buildGarden(GardenState garden, AppPalette palette) {
    final String today = todayKey();
    // 成长度与顶部「今日进度」同一个口径（都是 store 从 tasks 派生的任务完成数）
    final int growth = _percent(garden);
    // 「今天浇过水没有」只看浇水自己的记录：做完任务不该把浇水按钮顶掉
    final bool caredToday = garden.lastWaterDate == today;
    final int careTarget = GardenConfig.badgeTargets['plant_warrior'] ?? 7;
    final int carePercent =
        careTarget > 0 ? math.min(100, (garden.gardenCareDays / careTarget * 100).round()) : 0;

    return _pageList(<Widget>[
      const SectionHeader(title: '我的阳光花园'),
      AppCard(
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.warning.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Icon(Icons.wb_sunny_outlined, color: palette.warning),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '花园成长度',
                        style: TextStyle(
                          fontSize: AppFontSize.md,
                          fontWeight: FontWeight.w600,
                          color: palette.text,
                        ),
                      ),
                      Text(
                        '完成更多任务，让花园更茂盛！',
                        style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$growth%',
                  style: TextStyle(
                    fontSize: AppFontSize.lg,
                    fontWeight: FontWeight.w700,
                    color: palette.success,
                    fontFeatures: kTabularNumbers,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _ProgressBar(value: growth / 100, color: palette.success, track: palette.surfaceSoft),
          ],
        ),
      ),
      _gapMd,
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Icon(Icons.park_outlined, color: palette.primary),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '照顾花园 · 植物战士',
                        style: TextStyle(
                          fontSize: AppFontSize.md,
                          fontWeight: FontWeight.w600,
                          color: palette.text,
                        ),
                      ),
                      Text(
                        '${garden.gardenCareDays}/$careTarget 天',
                        style: TextStyle(
                          fontSize: AppFontSize.xs,
                          color: palette.textTertiary,
                          fontFeatures: kTabularNumbers,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _ProgressBar(value: carePercent / 100, color: palette.primary, track: palette.surfaceSoft),
            const SizedBox(height: AppSpacing.sm),
            Text(
              caredToday
                  ? '今天已经照顾过植物啦，明天记得再来～'
                  : '给植物浇浇水，坚持 $careTarget 天就能解锁「植物战士」勋章',
              style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: caredToday ? null : _care,
                style: FilledButton.styleFrom(minimumSize: _buttonSize),
                child: Text(caredToday ? '今天已照顾' : '浇浇水'),
              ),
            ),
          ],
        ),
      ),
      _gapMd,
      for (final _Plant plant in _plants)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _plantCard(plant, caredToday, palette),
        ),
    ]);
  }

  Widget _plantCard(_Plant plant, bool caredToday, AppPalette palette) {
    return AppCard(
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Icon(plant.icon, size: 22, color: palette.success),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  plant.name,
                  style: TextStyle(
                    fontSize: AppFontSize.md,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
                Text(
                  plant.desc,
                  style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          OutlinedButton(
            onPressed: caredToday ? null : _care,
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.primary,
              side: BorderSide(color: palette.border),
            ),
            child: Text(caredToday ? '今天已照顾' : '浇浇水'),
          ),
        ],
      ),
    );
  }

  // ---- 6. 阳光商城（Web 版 ShopPage.tsx）----

  Widget _buildShop(GardenState garden, AppPalette palette) {
    final GardenShopItem? avatarItem = _itemById(garden.equippedAvatar);
    final GardenShopItem? titleItem = _itemById(garden.equippedTitle);
    final List<GardenShopItem> decorItems = GardenConfig.shopItems
        .where((GardenShopItem item) =>
            item.category == GardenShopCategory.decor && garden.equippedDecor.contains(item.id))
        .toList();

    return _pageList(<Widget>[
      const SectionHeader(title: '阳光商城'),
      AppCard(
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.warning.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Icon(Icons.wb_sunny_outlined, color: palette.warning),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '我的阳光余额',
                style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
              ),
            ),
            Text(
              '${garden.balance}',
              style: TextStyle(
                fontSize: AppFontSize.xl,
                fontWeight: FontWeight.w700,
                color: palette.warning,
                fontFeatures: kTabularNumbers,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '阳光',
              style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
            ),
          ],
        ),
      ),
      _gapMd,
      // 现在戴着 / 挂着的：买过的东西一眼能看见，不再只有一句「已拥有」
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '现在戴着 / 挂着的',
              style: TextStyle(
                fontSize: AppFontSize.md,
                fontWeight: FontWeight.w600,
                color: palette.text,
              ),
            ),
            _wearingRow(
              '头像框',
              avatarItem?.shortName,
              avatarItem == null ? null : _gardenIcon(avatarItem.icon),
              '还没戴',
              palette,
            ),
            _wearingRow(
              '称号',
              titleItem?.shortName,
              titleItem == null ? null : _gardenIcon(titleItem.icon),
              '还没挂',
              palette,
            ),
            _wearingRow(
              '花园里',
              decorItems.isEmpty
                  ? null
                  : decorItems.map((GardenShopItem item) => item.shortName).join('、'),
              decorItems.isEmpty ? null : _gardenIcon(decorItems.first.icon),
              '还没有装饰',
              palette,
            ),
            const SizedBox(height: AppSpacing.sm),
            // store 的规则：装饰挂满 maxDecor 件后再挂新的，会挤掉最早那件（不报错），
            // 所以把规则写在孩子挑装饰的地方，别让旧的悄悄消失。
            Text(
              '装饰最多挂 ${GardenConfig.maxDecor} 件（已挂 '
              '${garden.equippedDecor.length}/${GardenConfig.maxDecor}），新挂上的会挤掉最早那件',
              style: TextStyle(
                fontSize: AppFontSize.xs,
                color: palette.textTertiary,
                fontFeatures: kTabularNumbers,
              ),
            ),
          ],
        ),
      ),
      _gapMd,
      for (final GardenShopCategory category in _categoryOrder) ...<Widget>[
        SectionHeader(
          title: category.label,
          subtitle: category == GardenShopCategory.decor
              ? '花园里最多挂 ${GardenConfig.maxDecor} 件'
              : null,
        ),
        for (final GardenShopItem item in GardenConfig.shopItems
            .where((GardenShopItem entry) => entry.category == category))
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _shopItemCard(garden, item, palette),
          ),
        _gapSm,
      ],
    ]);
  }

  Widget _wearingRow(
    String label,
    String? value,
    IconData? icon,
    String empty,
    AppPalette palette,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: AppSpacing.xl * 2,
            child: Text(
              label,
              style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: value == null
                ? Text(
                    empty,
                    style: TextStyle(fontSize: AppFontSize.sm, color: palette.textTertiary),
                  )
                : Row(
                    children: <Widget>[
                      if (icon != null) ...<Widget>[
                        Icon(icon, size: 16, color: palette.primary),
                        const SizedBox(width: AppSpacing.xs),
                      ],
                      Flexible(
                        child: Text(
                          value,
                          style: TextStyle(fontSize: AppFontSize.sm, color: palette.text),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _shopItemCard(GardenState garden, GardenShopItem item, AppPalette palette) {
    final bool owned = garden.ownedItems.contains(item.id);
    final bool affordable = garden.balance >= item.cost;
    final bool inUse = _isInUse(garden, item);
    final Color statusColor =
        inUse || owned ? palette.success : (affordable ? palette.primary : palette.textTertiary);
    final String statusText = inUse
        ? '正在用'
        : owned
            ? '已拥有'
            : affordable
                ? '可以兑换'
                : '阳光不够';

    return AppCard(
      highlight: inUse,
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(_gardenIcon(item.icon), size: 22, color: palette.primary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.name,
                  style: TextStyle(
                    fontSize: AppFontSize.md,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  item.desc,
                  style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.wb_sunny_outlined,
                          size: 14,
                          color: affordable ? palette.warning : palette.textTertiary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '${item.cost}',
                          style: TextStyle(
                            fontSize: AppFontSize.sm,
                            fontWeight: FontWeight.w700,
                            color: affordable ? palette.warning : palette.textTertiary,
                            fontFeatures: kTabularNumbers,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '阳光',
                          style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                        ),
                      ],
                    ),
                    _StatusChip(label: statusText, color: statusColor),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (owned)
            OutlinedButton(
              onPressed: () => _handleToggle(garden, item),
              style: OutlinedButton.styleFrom(
                foregroundColor: inUse ? palette.textSecondary : palette.primary,
                side: BorderSide(color: inUse ? palette.border : palette.primary),
              ),
              child: Text(inUse ? '取下' : _equipLabel(item.category)),
            )
          else
            FilledButton(
              onPressed: () => _handleExchange(garden, item),
              style: FilledButton.styleFrom(minimumSize: _buttonSize),
              child: const Text('兑换'),
            ),
        ],
      ),
    );
  }

  /// 「戴上 / 挂上」的文案：头像框与称号是戴，装饰是挂（都用孩子听得懂的话）
  String _equipLabel(GardenShopCategory category) =>
      category == GardenShopCategory.decor ? '挂上' : '戴上';

  /// 这件东西现在是不是正用着
  bool _isInUse(GardenState garden, GardenShopItem item) => switch (item.category) {
        GardenShopCategory.avatar => garden.equippedAvatar == item.id,
        GardenShopCategory.title => garden.equippedTitle == item.id,
        GardenShopCategory.decor => garden.equippedDecor.contains(item.id),
      };

  GardenShopItem? _itemById(String? id) {
    if (id == null) return null;
    for (final GardenShopItem item in GardenConfig.shopItems) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// 兑换。买之前先按显示余额拦一道（Web 版同口径：balance 含未同步增量），
  /// 再把 [ShopBuyResult] 的四种结果都回给孩子。
  void _handleExchange(GardenState garden, GardenShopItem item) {
    if (garden.balance < item.cost) {
      _toast('阳光不够啦，先去完成任务攒阳光吧！');
      return;
    }
    final ShopBuyResult result = garden.buyItem(item.id);
    final String message = switch (result) {
      ShopBuyResult.owned => '已经拥有「${item.shortName}」啦，不用重复兑换',
      ShopBuyResult.insufficient => '阳光不够啦，先去完成任务攒阳光吧！',
      ShopBuyResult.unknown => '没有找到这个物品，请刷新后再试',
      ShopBuyResult.ok => '兑换成功！「${item.shortName}」已拥有（-${item.cost} 阳光）',
    };
    _toast(
      message,
      success: result == ShopBuyResult.ok,
      error: result == ShopBuyResult.unknown,
    );
  }

  /// 「戴上 / 挂上」与「取下」共用一个按钮：正在用的再点一次就是取下来
  void _handleToggle(GardenState garden, GardenShopItem item) {
    if (_isInUse(garden, item)) {
      garden.unequipItem(item.id);
      _toast(
        item.category == GardenShopCategory.decor
            ? '「${item.shortName}」已经从花园里摘下来啦'
            : '「${item.shortName}」已经取下来啦',
      );
      return;
    }
    final EquipResult result = garden.equipItem(item.id);
    final String message = switch (result) {
      EquipResult.owned => '还没有这件东西，先去兑换吧',
      EquipResult.unknown => '没有找到这个物品，请刷新后再试',
      EquipResult.ok => item.category == GardenShopCategory.decor
          ? '「${item.shortName}」挂到花园里啦'
          : '「${item.shortName}」戴上啦',
    };
    _toast(
      message,
      success: result == EquipResult.ok,
      error: result == EquipResult.unknown,
    );
  }

  // ---- 7. 我的奖励（Web 版 RewardsPage.tsx）----

  Widget _buildRewards(GardenState garden, AppPalette palette) {
    final int earnedCount = garden.badges.where((Badge badge) => badge.earned).length;
    final int totalCount = garden.badges.length;
    final int percent = totalCount > 0 ? (earnedCount / totalCount * 100).round() : 0;

    return _pageList(<Widget>[
      AppCard(
        highlight: true,
        child: Row(
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.warning.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Icon(Icons.emoji_events_outlined, size: 24, color: palette.warning),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '花园小达人',
                    style: TextStyle(
                      fontSize: AppFontSize.md,
                      fontWeight: FontWeight.w700,
                      color: palette.text,
                    ),
                  ),
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        const TextSpan(text: '已获得 '),
                        TextSpan(
                          text: '$earnedCount',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: palette.warning,
                            fontFeatures: kTabularNumbers,
                          ),
                        ),
                        const TextSpan(text: ' 枚勋章'),
                      ],
                    ),
                    style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _ProgressBar(
                    value: percent / 100,
                    color: palette.primary,
                    track: palette.surfaceSoft,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        const TextSpan(text: '成就进度 '),
                        TextSpan(
                          text: '$percent%',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: palette.primary,
                            fontFeatures: kTabularNumbers,
                          ),
                        ),
                      ],
                    ),
                    style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      _gapMd,
      const SectionHeader(title: '我的勋章'),
      LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double cardWidth = (constraints.maxWidth - AppSpacing.sm) / 2;
          return Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              for (final Badge badge in garden.badges)
                SizedBox(width: cardWidth, child: _badgeCard(garden, badge, palette)),
            ],
          );
        },
      ),
    ]);
  }

  Widget _badgeCard(GardenState garden, Badge badge, AppPalette palette) {
    final int? target = GardenConfig.badgeTargets[badge.id];
    final int current = badge.id == 'poet' ? garden.poemCount : garden.gardenCareDays;
    final int progress = target != null && target > 0
        ? math.min(100, (current / target * 100).round())
        : 0;
    final Color accent = badge.earned ? palette.success : palette.textTertiary;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(_gardenIcon(badge.icon), size: 20, color: accent),
              ),
              const Spacer(),
              _StatusChip(
                label: badge.earned ? '已获得' : '未获得',
                color: badge.earned ? palette.success : palette.textTertiary,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            badge.name,
            style: TextStyle(
              fontSize: AppFontSize.md,
              fontWeight: FontWeight.w600,
              color: palette.text,
            ),
          ),
          Text(
            badge.description,
            style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
          ),
          // 「小诗人」「植物战士」是累计型：没解锁也让孩子看到还差多少
          if (target != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _ProgressBar(
              value: progress / 100,
              color: badge.earned ? palette.success : palette.primary,
              track: palette.surfaceSoft,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              badge.id == 'poet'
                  ? '背诵 $current/$target 首'
                  : '照顾花园 $current/$target 天',
              style: TextStyle(
                fontSize: AppFontSize.xs,
                color: badge.earned ? palette.success : palette.textTertiary,
                fontFeatures: kTabularNumbers,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---- 8. 学习记录（Web 版 RecordsPage.tsx）----

  Widget _buildRecords(GardenState garden, AppPalette palette) {
    final List<LedgerRecord> records = garden.cachedRecords;

    return _pageList(<Widget>[
      const SectionHeader(title: '学习记录'),
      // 今日完成是任务数口径：completedCount 由 store 从 tasks 派生，最多等于任务总数；
      // 「获得阳光」按今天实际入账求和（背诗、语文练习一天可能入账多次）
      AppCard(
        child: Row(
          children: <Widget>[
            Expanded(
              child: StatBlock(
                label: '今日完成',
                value: '${garden.completedCount}/${garden.tasks.length}',
                unit: '个任务',
                color: palette.primary,
                icon: Icons.check_circle_outline,
              ),
            ),
            Expanded(
              child: StatBlock(
                label: '获得阳光',
                value: '${_earnedToday(garden)}',
                unit: '阳光',
                color: palette.warning,
                icon: Icons.wb_sunny_outlined,
              ),
            ),
          ],
        ),
      ),
      _gapMd,
      const SectionHeader(title: '阳光流水', subtitle: '最近的花园流水（含待同步）'),
      if (records.isEmpty)
        const AppCard(
          child: EmptyView(message: '还没有学习记录', hint: '完成任务、背古诗、语文打卡都会记在这里'),
        )
      else
        AppCard(
          child: Column(
            children: <Widget>[
              for (int index = 0; index < records.length; index++) ...<Widget>[
                if (index > 0) Divider(height: AppSpacing.md, color: palette.border),
                _recordRow(records[index], palette),
              ],
            ],
          ),
        ),
    ]);
  }

  Widget _recordRow(LedgerRecord record, AppPalette palette) {
    final bool rejected = record.isRejected;
    final bool pending = record.isPending;
    final IconData icon = rejected
        ? Icons.cancel_outlined
        : pending
            ? Icons.schedule_outlined
            : Icons.check_circle_outline;
    final Color iconColor = rejected
        ? palette.danger
        : pending
            ? palette.warning
            : palette.success;
    final String? statusLabel = record.status?.label;
    final String timeText = _timeLabel(record.createdAt);

    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _recordTitle(record),
                style: TextStyle(
                  fontSize: AppFontSize.sm,
                  fontWeight: FontWeight.w600,
                  color: palette.text,
                ),
              ),
              Text(
                statusLabel == null ? timeText : '$timeText · $statusLabel',
                style: TextStyle(
                  fontSize: AppFontSize.xs,
                  color: palette.textTertiary,
                  fontFeatures: kTabularNumbers,
                ),
              ),
            ],
          ),
        ),
        Text(
          record.signedAmount,
          style: TextStyle(
            fontSize: AppFontSize.md,
            fontWeight: FontWeight.w700,
            color: record.amount >= 0 ? palette.success : palette.danger,
            fontFeatures: kTabularNumbers,
          ),
        ),
      ],
    );
  }
}

// ---- 复用的小组件 ----

/// 圆润进度条（value 传 0~1）
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value, required this.color, this.track});

  final double value;
  final Color color;
  final Color? track;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1).toDouble(),
        minHeight: AppSpacing.sm,
        color: color,
        backgroundColor: track ?? context.palette.surfaceSoft,
      ),
    );
  }
}

/// 横向菜单胶囊（选中态用 AppCard 的 highlight）
class _MenuChip extends StatelessWidget {
  const _MenuChip({required this.menu, required this.selected, required this.onTap});

  final GardenMenu menu;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return AppCard(
      onTap: onTap,
      highlight: selected,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      margin: const EdgeInsets.only(right: AppSpacing.sm),
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            _gardenIcon(menu.icon),
            size: 18,
            color: selected ? palette.primary : palette.textTertiary,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            menu.label,
            style: TextStyle(
              fontSize: AppFontSize.sm,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? palette.primary : palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 任务卡片左侧的大勾选圆钮（儿童向：40px 触控区）
class _CheckButton extends StatelessWidget {
  const _CheckButton({required this.done, this.onTap});

  final bool done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done ? palette.success : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: done ? palette.success : palette.border, width: 2),
          ),
          child: done ? Icon(Icons.check, size: 22, color: palette.surface) : null,
        ),
      ),
    );
  }
}

/// 状态小胶囊（正在用 / 已拥有 / 可以兑换 / 阳光不够 / 已获得…）
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: AppFontSize.xs, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
