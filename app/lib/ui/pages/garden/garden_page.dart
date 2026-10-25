import 'dart:async';
import 'dart:math' as math;

import 'package:sekainook_app/fl_ui/dialog.dart';
import 'package:sekainook_app/ui/icons/icons.dart';
// Material 也有一个 Badge（小红点角标），花园的勋章模型重名，藏掉 Material 那个
import 'package:flutter/material.dart' hide Badge;
import 'package:sekainook_app/ui/widgets/app_toast.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../config/garden_config.dart';
import '../../../data/models/garden.dart';
import '../../../data/models/ledger_record.dart';
import '../../../state/garden_state.dart';
import '../../../state/theme_state.dart';
import '../../../theme/app_shape.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/motion.dart';
import '../../../theme/tokens.dart';
import '../../shell/app_nav_bar.dart';
import '../../shell/app_top_bar.dart';
import '../../widgets/app_card.dart';
import '../../widgets/format.dart';
import '../../widgets/garden_icon.dart';
import '../../widgets/motion_widgets.dart';
import '../../widgets/state_views.dart';
import '../../widgets/motion/app_buttons.dart';

/// 花园里养着的植物（照抄 Web 版 `src/views/garden/GardenPage.tsx` 的 `PLANTS`）
class _Plant {
  const _Plant({required this.name, required this.desc, required this.icon});

  final String name;
  final String desc;
  final Glyph icon;
}

const List<_Plant> _plants = <_Plant>[
  _Plant(name: '向日葵', desc: '阳光越足，长得越高', icon: AppIcons.sun),
  _Plant(name: '小玫瑰', desc: '需要细心照顾', icon: AppIcons.flower),
  _Plant(name: '仙人掌', desc: '坚强的小植物', icon: AppIcons.leaf),
];

/// 阳光花园儿童工作台（对应 Web 版 `src/views/garden/` 下的 8 个页面）。
///
/// 8 个菜单：学习总览 / 今日任务 / 古诗背诵 / 语文预习 / 阳光花园 / 阳光商城 /
/// 我的奖励 / 学习记录。菜单和 Web 版一样挂在 URL 上（`/garden?tab=poem`，
/// 参数名取 `GardenConfig.menuParam`），本页**不再自己存菜单 state**：
/// 地址栏是菜单的唯一真相，于是能深链、刷新 / 从后台回来不丢当前菜单。
///
/// 取舍（与 Web 版不同，是三个端共用的统一契约定的）：切换菜单用
/// `context.go('/garden?tab=<key>')`，replace 语义、不往返回栈堆历史，所以
/// 系统返回键从花园**直接退回上一层**，不沿点过的菜单逐个回退。选它的理由：
/// 菜单切换是同一页内的视图切换，不是新页面；若沿菜单堆历史，孩子在花园里
/// 点 5 个菜单就要按 5 次返回才出得去，等于给他造了个走不出去的迷宫。
/// 代价（没有菜单级历史）换来的是「离开花园永远一步」＋ 与底部导航切 tab
/// （同样是 `context.go`）一致的语义。
///
/// 数据只来自 [GardenState]：阳光余额 = 显示余额（权威值 + 未同步增量），
/// 今日进度 / 完成率都由 `tasks` 与 `completedCount` 同口径派生。
class GardenPage extends StatefulWidget {
  const GardenPage({super.key});

  @override
  State<GardenPage> createState() => _GardenPageState();
}

class _GardenPageState extends State<GardenPage> {
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

  /// 菜单胶囊的横向滚动控制器：8 个菜单在 375dp 下放不下，选中项得能被滚进视野。
  final ScrollController _menuScroll = ScrollController();

  /// 每个菜单胶囊一个 key —— 深链进来（`?tab=records`）时要 ensureVisible 到它，
  /// 否则选中项落在屏幕外，孩子看到的是「一排没选中任何东西的胶囊」。
  final Map<String, GlobalKey> _menuKeys = <String, GlobalKey>{};

  /// 上一帧的菜单 key：只在菜单变化（或首帧）时滚一次，不每帧都滚。
  String? _lastMenu;

  /// 流水列表是否已展开成「全部」（默认只渲前 [_recordPreview] 条）。
  bool _showAllRecords = false;

  /// 首屏只渲多少条流水，剩下的点「查看全部记录」（U-04：记录只增不减）
  static const int _recordPreview = 20;

  GlobalKey _menuKey(String key) => _menuKeys.putIfAbsent(key, () => GlobalKey());

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

  @override
  void dispose() {
    _menuScroll.dispose();
    super.dispose();
  }

  /// 把选中菜单滚进视野（居中；首帧与深链进入都要走这一下）。
  void _revealMenu(String menu) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final BuildContext? chip = _menuKeys[menu]?.currentContext;
      if (chip == null) return;
      Scrollable.ensureVisible(
        chip,
        alignment: 0.5,
        duration: AppMotion.fast,
        curve: AppMotion.standard,
      );
    });
  }

  /// 卡在骨架屏时的出路：重读存档 + 重拉一次流水（以前这里没有任何按钮可点）。
  void _retryLoad() {
    final GardenState garden = context.read<GardenState>();
    garden.init();
    unawaited(garden.flushPending());
    unawaited(garden.refreshLedger());
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

  /// 时刻文案统一走 `format.dart` 的 `formatDateTime`（「今天 / 昨天 / MM-dd HH:mm」），
  /// 不再在本页自己拼一套：以前这里读 `DateTime.now()`，跨零点不会翻成「昨天」、
  /// 也没法注入 now；而同一页的「今日已完成」又用了另一种格式。
  /// 调用点自己把 `now` 传下去（一次 build 只取一次 now，整屏口径一致）。

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
    // 兜底也要是人话：宁可给一句「花园记录」，也不把 `garden:xxx` 这种内部 id
    // 摆到孩子面前（审计 §4）。
    return '花园记录';
  }

  // ---- 轻提示与动作 ----

  /// 统一的轻提示（对应 Web 版的 antd `message`）
  void _toast(String message, {bool success = false, bool error = false}) {
    AppToast.show(
      context,
      message,
      tone: error
          ? AppToastTone.error
          : success
              ? AppToastTone.success
              : AppToastTone.neutral,
      duration: const Duration(seconds: 2),
    );
  }

  /// 切菜单 = 改地址栏（`/garden?tab=<key>`），不碰本地 state —— 菜单的唯一真相是 URL。
  ///
  /// `go` 是 replace 语义：不往返回栈堆菜单历史，所以系统返回键直接退出花园、
  /// 不沿菜单回退（原因与代价见类注释）。[current] = 此刻地址栏上的菜单。
  void _switchMenu(String key, String current) {
    if (!GardenConfig.isMenuKey(key)) return;
    if (key == current) return;
    context.go('/garden?tab=$key');
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
    // 走到这里才是真打卡成功（上面两条重复打卡分支都提前 return 了）
    showBurst(context);
  }

  void _recite(GardenPoem poem) {
    final GardenState garden = context.read<GardenState>();
    if (!garden.recitePoem(poem.id)) {
      _toast('《${poem.title}》今天已经背过啦，明天再来复习吧');
      return;
    }
    _toast('《${poem.title}》背诵成功！+${poem.reward} 阳光', success: true);
    showBurst(context);
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
    // completeChineseStep 返回 true 才算打卡成功（false 的分支上面已经 return）
    showBurst(context);
  }

  void _care() {
    final GardenState garden = context.read<GardenState>();
    if (garden.careForGarden()) {
      _toast('照顾成功！植物们精神多啦', success: true);
      // 浇水的「长大」：整页一下 + 植物卡片自己的收放（见 _GrowPulse）
      showBurst(context);
      return;
    }
    _toast('今天的花园已经照顾过啦，明天再来吧');
  }

  // ---- 页面骨架 ----

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final GardenState garden = context.watch<GardenState>();

    // 菜单的唯一真相在地址栏：`/garden?tab=<menuKey>`（参数名取 GardenConfig.menuParam，
    // 不写死 'tab'）。缺省或非法值回退 GardenConfig.defaultMenu，不渲染空白。
    final String raw = GoRouterState.of(context).uri.queryParameters[GardenConfig.menuParam] ?? '';
    final String menu = GardenConfig.isMenuKey(raw) ? raw : GardenConfig.defaultMenu;
    // 菜单变了（含首帧 / 深链进入）就把选中胶囊滚进视野；放在 build 里是因为
    // 菜单本身由地址栏派生，没有「菜单 setter」可以挂。
    if (menu != _lastMenu) {
      _lastMenu = menu;
      _revealMenu(menu);
    }

    return Scaffold(
      body: SafeArea(
        child: garden.tasks.isEmpty
            ? _GardenLoading(onRetry: _retryLoad)
            : Column(
                children: <Widget>[
                  if (garden.pending.isNotEmpty) _buildPendingBanner(garden, palette),
                  _buildHeader(garden, palette),
                  _buildMenuBar(menu),
                  Expanded(
                    // 菜单内容切换的转场：菜单 key 一换就上下滑入淡出（只换视觉，
                    // 菜单仍由地址栏派生、_switchMenu 走 context.go 不变）
                    child: SlideFadeSwitcher(
                      childKey: ValueKey<String>(menu),
                      axis: Axis.vertical,
                      child: _buildMenuContent(garden, palette, menu),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// 离线队列提示：还没同步的打卡 / 兑换，点一下立刻重试。
  /// 文案说人话（「还没传到云端」），不说「未同步 / 重试」这类工程词。
  Widget _buildPendingBanner(GardenState garden, AppPalette palette) {
    final int delta = garden.pendingDelta;
    final String deltaText = delta == 0 ? '' : '（还没传到云端 ${delta > 0 ? '+' : ''}$delta）';
    return EnterBox(
      index: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
        child: AppCard(
          highlight: true,
          onTap: () => garden.flushPending(),
          child: Row(
            children: <Widget>[
              GlyphIcon(AppIcons.upload, color: palette.onSoft),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        // 还有东西躺在离线队列里：让这颗小点自己「呼吸」提醒
                        // （小点也压在这张强调卡的淡主色底上，颜色要跟着底走）
                        PulseDot(
                          color: _tintForeground(palette, palette.warning, base: palette.primarySoft),
                          size: 6,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            '还有 ${garden.pending.length} 条没传上去',
                            style: TextStyle(
                              fontSize: AppFontSize.sm,
                              fontWeight: FontWeight.w600,
                              color: palette.onSoft,
                              fontFeatures: kTabularNumbers,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '再点一下试试$deltaText',
                      style: TextStyle(
                        fontSize: AppFontSize.xs,
                        color: palette.onColorSoft(palette.primarySoft),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '再试一次',
                style: TextStyle(
                  fontSize: AppFontSize.sm,
                  fontWeight: FontWeight.w700,
                  color: palette.onSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部常驻三件套：阳光余额 / 连续天数 / 今日进度（孩子第一眼要看到的）
  Widget _buildHeader(GardenState garden, AppPalette palette) {
    final int percent = _percent(garden);
    // 小字说明里的数字：字号颜色与原来一致，只是等宽（滚动时不左右抖）
    final TextStyle noteStyle = TextStyle(
      fontSize: AppFontSize.xs,
      color: palette.textSecondary,
      fontFeatures: kTabularNumbers,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _statRow(<Widget>[
              StatBlock(
                label: '阳光余额',
                number: garden.balance,
                // 四位数以上加千分位（1095 → 1,095），不然一串数字孩子要数零
                formatter: (num value) => formatCount(value),
                unit: '阳光',
                color: _readableAccent(palette, palette.warning),
                icon: AppIcons.sun,
              ),
              StatBlock(
                label: '连续学习',
                number: garden.streakDays,
                unit: '天',
                color: _readableAccent(palette, palette.danger),
                icon: AppIcons.fire,
              ),
              StatBlock(
                label: '今日任务',
                number: garden.completedCount,
                // 分母不参与滚动，只让分子滚（文案与原来一字不差）
                formatter: (num value) => '${value.round()}/${garden.tasks.length}',
                unit: '个',
                color: _readableAccent(palette, palette.primary),
                icon: AppIcons.checkCircle,
              ),
            ]),
            const SizedBox(height: AppSpacing.md),
            AnimatedProgressBar(
              value: percent / 100,
              color: palette.primary,
              trackColor: palette.surfaceSoft,
              height: AppSpacing.sm,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  const TextSpan(text: '今天已经赚到 '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: AnimatedCount(
                      value: _earnedToday(garden),
                      style: noteStyle,
                      pulse: false,
                    ),
                  ),
                  const TextSpan(text: ' 阳光，任务完成 '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: AnimatedCount(
                      value: percent,
                      formatter: (num value) => '${value.round()}%',
                      style: noteStyle,
                      pulse: false,
                    ),
                  ),
                ],
              ),
              style: noteStyle,
            ),
          ],
        ),
      ),
    );
  }

  /// 横排统计卡：宽屏一行 [tiles.length] 列，窄屏 / 无障碍大字号下退成两列 Wrap。
  ///
  /// 320dp + 大字号时三列每列只剩 ≈74dp，24px 的数字会被 `AppCard` 的
  /// `Clip.antiAlias` 直接切掉（审计 §3.4 实拍）；两列放得下，也不必把字号缩糊。
  /// 注意别改成 `FittedBox` 包 StatBlock：Row 里的 StatBlock 是 `mainAxisSize.max`，
  /// 在 FittedBox 的无界宽度下会拿到 ∞ 约束。
  Widget _statRow(List<Widget> tiles) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double scaled = MediaQuery.textScalerOf(context).scale(AppFontSize.xl);
        final bool narrow = constraints.maxWidth < 320 || scaled > AppFontSize.xl * 1.2;
        if (!narrow) {
          return Row(
            children: <Widget>[
              for (int index = 0; index < tiles.length; index++) ...<Widget>[
                if (index > 0) _gapSm,
                Expanded(child: tiles[index]),
              ],
            ],
          );
        }
        final double width = (constraints.maxWidth - AppSpacing.sm) / 2;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            for (final Widget tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }

  /// 横向 Tab 条：8 个菜单（375px 下横向滚动，不做换行挤压）。
  /// [current] 是地址栏上的当前菜单，点谁就把地址栏改成谁。
  Widget _buildMenuBar(String current) {
    return SingleChildScrollView(
      // 控制器 + 每个胶囊一个 key：深链（?tab=records）进来时把选中项滚进视野，
      // 否则选中态落在屏幕外，孩子只看到一排「谁都没选中」的胶囊。
      controller: _menuScroll,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: <Widget>[
          // 菜单胶囊按序号错峰滑入（像一排选项依次铺开）
          for (final (int index, GardenMenu menu) in GardenConfig.menus.indexed)
            EnterBox(
              index: index,
              axis: Axis.horizontal,
              child: _MenuChip(
                key: _menuKey(menu.key),
                menu: menu,
                selected: menu.key == current,
                onTap: () => _switchMenu(menu.key, current),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMenuContent(GardenState garden, AppPalette palette, String menu) {
    switch (menu) {
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

  /// 菜单内容的统一列表壳：每个子项按序号错峰进场（首屏元素依次浮现），
  /// 列表本身仍是普通 ListView，滚动行为不变。
  Widget _pageList(List<Widget> children) => Builder(
        // 借一层 Builder 拿 context：这层壳在多个子页复用，底部要让出悬浮底栏
        builder: (BuildContext context) => ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm + AppTopBar.contentInset(context),
            AppSpacing.md,
            AppSpacing.xl + AppNavBar.contentInset(context),
          ),
          children: <Widget>[
            for (int index = 0; index < children.length; index++)
              EnterBox(index: index, child: children[index]),
          ],
        ),
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
      // 这一排只放**顶部三件套没有**的数字：余额 / 连续天数 / 今日进度已经常驻
      // 在顶上（不随菜单滚走），这里再摆一遍只是把孩子往下推（审计 §3.4）。
      _statRow(<Widget>[
        _statTile(
          label: '已获勋章',
          number: earnedBadges,
          unit: '枚',
          icon: AppIcons.trophy,
          color: palette.success,
        ),
        _statTile(
          label: '累计完成',
          number: garden.totalCompleted,
          formatter: (num value) => formatCount(value),
          unit: '次',
          icon: AppIcons.checkCircle,
          color: palette.primary,
        ),
        _statTile(
          label: '背会古诗',
          number: garden.poemCount,
          unit: '首',
          icon: AppIcons.book,
          color: palette.warning,
        ),
      ]),
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
            AnimatedProgressBar(
              value: percent / 100,
              color: palette.primary,
              trackColor: palette.surfaceSoft,
              height: AppSpacing.sm,
            ),
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
                        GlyphIcon(
                          gardenGlyph(item.icon),
                          size: 18,
                          color: _readableAccent(palette, palette.success),
                        ),
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
                      color: _readableAccent(palette, palette.warning),
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

  /// 带图标的小统计卡（Row 里用 Expanded 包一层）；数字会滚动
  Widget _statTile({
    required String label,
    required num number,
    String? unit,
    String Function(num value)? formatter,
    required Glyph icon,
    required Color color,
  }) {
    final AppPalette palette = context.palette;
    // 强调色当数字色用：衬不住卡片底就沿色相压一档（金色 → 深金）
    final Color accent = _readableAccent(palette, color);
    // 图标坐在自己的 14% 淡色块上：按「块合到底色」的真实对比度选前景色
    final Color iconColor = _tintForeground(palette, accent);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: AppSize.iconTile,
            height: AppSize.iconTile,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: color.withValues(alpha: 0.14),
              shape: AppShape.all(AppRadius.md),
            ),
            child: GlyphIcon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(height: AppSpacing.sm),
          StatBlock(label: label, number: number, formatter: formatter, unit: unit, color: accent),
        ],
      ),
    );
  }

  // ---- 2. 今日任务（Web 版 TasksPage.tsx）----

  Widget _buildTasks(GardenState garden, AppPalette palette) {
    // 原来这里有一排「今日完成 / 完成率 / 连续学习」的统计卡，跟顶部常驻三件套
    // 完全重复（同屏出现两遍同样的数字），还把任务列表推到第二屏。删掉后
    // 孩子点进「今日任务」第一眼就是今天要做什么（审计 §3.4）。
    return _pageList(<Widget>[
      const SectionHeader(title: '今日任务', subtitle: '点左边的圆圈就能打勾'),
      for (final GardenTask task in garden.tasks)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _taskCard(task, palette),
        ),
    ]);
  }

  Widget _taskCard(GardenTask task, AppPalette palette) {
    final bool done = task.done;
    final Color accent = _readableAccent(palette, done ? palette.success : palette.primary);
    // 奖励标签（+10 阳光）也落在这张卡的白底上：金色同样要压到看得清
    final Color rewardColor = _readableAccent(palette, palette.warning);
    return AppCard(
      child: Row(
        children: <Widget>[
          _CheckButton(done: done, onTap: done ? null : () => _completeTask(task)),
          const SizedBox(width: AppSpacing.sm),
          Container(
            width: AppSize.iconBadge,
            height: AppSize.iconBadge,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: AppShape.all(AppRadius.md),
            ),
            child: GlyphIcon(
              gardenGlyph(task.icon),
              size: 20,
              color: _tintForeground(palette, accent, alpha: 0.12),
            ),
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
                    GlyphIcon(AppIcons.clock, size: 14, color: palette.textTertiary),
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
                  GlyphIcon(
                    AppIcons.sun,
                    size: 14,
                    color: done ? palette.textTertiary : rewardColor,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '+${task.reward}',
                    style: TextStyle(
                      fontSize: AppFontSize.md,
                      fontWeight: FontWeight.w700,
                      color: done ? palette.textTertiary : rewardColor,
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
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: AnimatedCount(
                      value: garden.poemCount,
                      style: TextStyle(
                        fontSize: AppFontSize.md,
                        fontWeight: FontWeight.w700,
                        color: _readableAccent(palette, palette.primary),
                        fontFeatures: kTabularNumbers,
                      ),
                      pulse: false,
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
            AnimatedProgressBar(
              value: percent / 100,
              color: palette.primary,
              trackColor: palette.surfaceSoft,
              height: AppSpacing.sm,
            ),
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
              GlyphIcon(gardenGlyph('book'), size: 18, color: palette.primary),
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
          PressInkWell(
            onTap: () => _togglePoem(poem.id),
            borderRadius: BorderRadius.circular(AppRadius.sm),
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
              AppTextButton(
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
                AppFilledButton(
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
    final Color accent = _readableAccent(palette, done ? palette.success : palette.primary);
    final Color rewardColor = _readableAccent(palette, palette.warning);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              GlyphIcon(gardenGlyph('read'), size: 18, color: accent),
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
              if (done) GlyphIcon(AppIcons.checkCircle, size: 20, color: accent),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            practice.desc,
            style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          AnimatedProgressBar(
            value: percent / 100,
            color: accent,
            trackColor: palette.surfaceSoft,
            height: AppSpacing.sm,
          ),
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
                  color: rewardColor,
                  fontFeatures: kTabularNumbers,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: AppFilledButton(
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
                  width: AppSize.iconCircle,
                  height: AppSize.iconCircle,
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: palette.warning.withValues(alpha: 0.14),
                    shape: AppShape.all(AppRadius.full),
                  ),
                  child: GlyphIcon(
                    AppIcons.sun,
                    color: _tintForeground(palette, palette.warning),
                  ),
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
                AnimatedCount(
                  value: growth,
                  formatter: (num value) => '${value.round()}%',
                  style: TextStyle(
                    fontSize: AppFontSize.lg,
                    fontWeight: FontWeight.w700,
                    color: _readableAccent(palette, palette.success),
                    fontFeatures: kTabularNumbers,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            AnimatedProgressBar(
              value: growth / 100,
              color: palette.success,
              trackColor: palette.surfaceSoft,
              height: AppSpacing.sm,
            ),
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
                  width: AppSize.iconCircle,
                  height: AppSize.iconCircle,
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: palette.primary.withValues(alpha: 0.12),
                    shape: AppShape.all(AppRadius.full),
                  ),
                  child: GlyphIcon(
                    AppIcons.tree,
                    color: _tintForeground(palette, palette.primary, alpha: 0.12),
                  ),
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
            AnimatedProgressBar(
              value: carePercent / 100,
              color: palette.primary,
              trackColor: palette.surfaceSoft,
              height: AppSpacing.sm,
            ),
            const SizedBox(height: AppSpacing.sm),
            // 文案如实说明机制：这一栏的「X/7 天」是**花园活跃天数**，浇水和完成
            // 任务都算（以前只说「浇浇水」，但做任务也会把它 +1，孩子算不明白）。
            Text(
              caredToday
                  ? '今天已经照顾过植物啦，明天记得再来～'
                  : '浇浇水，或者完成一个任务，今天就算照顾过花园；'
                      '坚持 $careTarget 天解锁「植物战士」勋章',
              style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: AppFilledButton(
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
          // 浇过水的那一下，植物轻轻「长大」再收回（见 _GrowPulse）
          _GrowPulse(
            cared: caredToday,
            child: Container(
              width: AppSize.iconCircle,
              height: AppSize.iconCircle,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: palette.success.withValues(alpha: 0.12),
                shape: AppShape.all(AppRadius.full),
              ),
              child: GlyphIcon(
                plant.icon,
                size: 22,
                color: _tintForeground(palette, palette.success, alpha: 0.12),
              ),
            ),
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
          // 植物卡只是「状态」：四张卡原来各带一个「浇浇水」按钮（描边样式，
          // 与上面照顾卡的主按钮两套样式），同一个动作出现 5 次。浇水的唯一
          // 入口留上面那颗主按钮，这里只说今天浇过没有。
          _StatusChip(
            label: caredToday ? '今天浇过水' : '今天还没浇',
            color: caredToday ? palette.success : palette.textTertiary,
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
      const SectionHeader(title: '阳光商城', subtitle: '阳光余额在最上面，随时能看见'),
      // 原来这里还有一张「我的阳光余额」大卡：同屏第二次出现同一个数字
      // （顶部三件套常驻、不随菜单滚走），删掉后商品列表直接上首屏。
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
              avatarItem == null ? null : gardenGlyph(avatarItem.icon),
              '还没戴',
              palette,
            ),
            _wearingRow(
              '称号',
              titleItem?.shortName,
              titleItem == null ? null : gardenGlyph(titleItem.icon),
              '还没挂',
              palette,
            ),
            _wearingRow(
              '花园里',
              decorItems.isEmpty
                  ? null
                  : decorItems.map((GardenShopItem item) => item.shortName).join('、'),
              decorItems.isEmpty ? null : gardenGlyph(decorItems.first.icon),
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
    Glyph? icon,
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
                        GlyphIcon(icon, size: 16, color: palette.primary),
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
    // inUse 的这一张是 highlight 卡（淡主色底）：卡里的字与图标得按这层底重算，
    // 否则深色主题里深色文字压在深色主色底上（1.2:1）直接看不见
    final Color cardBase = inUse ? palette.primarySoft : palette.surface;
    final Color titleColor = inUse ? palette.onSoft : palette.text;
    final Color descColor =
        inUse ? palette.onColorSoft(palette.primarySoft) : palette.textTertiary;
    // 价格：只有 inUse 那张落在有色底上才按底色重算；普通卡上仍是原来的金色
    final Color priceColor = !affordable
        ? descColor
        : inUse
            ? _tintForeground(palette, palette.warning, base: cardBase, minRatio: 4.5)
            : _readableAccent(palette, palette.warning);
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
            width: AppSize.iconCircle,
            height: AppSize.iconCircle,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: palette.primary.withValues(alpha: 0.12),
              shape: AppShape.all(AppRadius.md),
            ),
            child: GlyphIcon(
              gardenGlyph(item.icon),
              size: 22,
              color: _tintForeground(palette, palette.primary, alpha: 0.12, base: cardBase),
            ),
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
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  item.desc,
                  style: TextStyle(fontSize: AppFontSize.xs, color: descColor),
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
                        GlyphIcon(AppIcons.sun, size: AppSize.glyphXs, color: priceColor),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          formatCount(item.cost),
                          style: TextStyle(
                            fontSize: AppFontSize.sm,
                            fontWeight: FontWeight.w700,
                            color: priceColor,
                            fontFeatures: kTabularNumbers,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '阳光',
                          style: TextStyle(fontSize: AppFontSize.xs, color: descColor),
                        ),
                      ],
                    ),
                    _StatusChip(label: statusText, color: statusColor, background: cardBase),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (owned)
            AppOutlinedButton(
              onPressed: () => _handleToggle(garden, item),
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    inUse ? palette.onColorSoft(palette.primarySoft) : palette.primary,
                side: BorderSide(color: inUse ? palette.border : palette.primary),
              ),
              child: Text(inUse ? '取下' : _equipLabel(item.category)),
            )
          else
            AppFilledButton(
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
  /// 再让孩子**确认一次**（一次兑换 60–200 阳光，差不多是两天的任务量，
  /// 以前点一下就扣、没有撤销，审计 §3.4），最后把 [ShopBuyResult] 的四种
  /// 结果都回给孩子。
  Future<void> _handleExchange(GardenState garden, GardenShopItem item) async {
    if (garden.balance < item.cost) {
      _toast('阳光不够啦，先去完成任务攒阳光吧！');
      return;
    }
    final int after = garden.balance - item.cost;
    final bool? ok = await showFloatingDialog<bool>(
      context: context,
      child: AlertDialog(
        title: Text('兑换「${item.shortName}」？'),
        content: Text(
          '要花掉 ${formatCount(item.cost)} 阳光，兑换后还剩 ${formatCount(after)} 阳光。\n'
          '换到手就退不回来啦，想好了再点「兑换」。',
        ),
        actions: <Widget>[
          AppTextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('再想想'),
          ),
          AppFilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('兑换'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final ShopBuyResult result = garden.buyItem(item.id);
    final String message = switch (result) {
      ShopBuyResult.owned => '已经拥有「${item.shortName}」啦，不用重复兑换',
      ShopBuyResult.insufficient => '阳光不够啦，先去完成任务攒阳光吧！',
      ShopBuyResult.unknown => '没有找到这个物品，再试一次吧',
      ShopBuyResult.ok =>
        '兑换成功！「${item.shortName}」已拥有（-${formatCount(item.cost)} 阳光）',
    };
    _toast(
      message,
      success: result == ShopBuyResult.ok,
      error: result == ShopBuyResult.unknown,
    );
    if (result == ShopBuyResult.ok) {
      showBurst(context);
    }
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
    // 花园最多挂 GardenConfig.maxDecor 件装饰：挂满时 [GardenState.equipItem] 会把
    // 最早挂的那件挤掉（顺序是「先挂的在前」）。以前挤掉得静悄悄，孩子会发现
    // 昨天挂的东西不见了 —— 这里把被挤掉的那件说清楚（审计 §3.4）。
    String? displaced;
    if (item.category == GardenShopCategory.decor &&
        garden.equippedDecor.length >= GardenConfig.maxDecor &&
        garden.equippedDecor.isNotEmpty) {
      displaced = _itemById(garden.equippedDecor.first)?.shortName;
    }
    final EquipResult result = garden.equipItem(item.id);
    final String message = switch (result) {
      EquipResult.owned => '还没有这件东西，先去兑换吧',
      EquipResult.unknown => '没有找到这个物品，再试一次吧',
      EquipResult.ok => item.category == GardenShopCategory.decor
          ? displaced == null
              ? '「${item.shortName}」挂到花园里啦'
              : '「${item.shortName}」挂到花园里啦，位置不够，「$displaced」被摘下来了'
          : '「${item.shortName}」戴上啦',
    };
    _toast(
      message,
      success: result == EquipResult.ok,
      error: result == EquipResult.unknown,
    );
    if (result == EquipResult.ok) {
      showBurst(context);
    }
  }

  // ---- 7. 我的奖励（Web 版 RewardsPage.tsx）----

  Widget _buildRewards(GardenState garden, AppPalette palette) {
    final int earnedCount = garden.badges.where((Badge badge) => badge.earned).length;
    final int totalCount = garden.badges.length;
    final int percent = totalCount > 0 ? (earnedCount / totalCount * 100).round() : 0;

    // 顶上那张是 highlight 卡（淡主色底）：卡里的字与数字都得按这层底重算前景色，
    // 否则深色主色底 + 深色文字 = 一片糊
    final Color badgeNumColor = _tintForeground(
      palette,
      palette.warning,
      base: palette.primarySoft,
      minRatio: 4.5,
    );
    final Color progressNumColor = _tintForeground(
      palette,
      palette.primary,
      base: palette.primarySoft,
      minRatio: 4.5,
    );

    return _pageList(<Widget>[
      AppCard(
        highlight: true,
        child: Row(
          children: <Widget>[
            Container(
              width: AppSize.iconCircleLg,
              height: AppSize.iconCircleLg,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: palette.warning.withValues(alpha: 0.16),
                shape: AppShape.all(AppRadius.full),
              ),
              child: GlyphIcon(AppIcons.trophy, size: 24, color: palette.warning),
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
                      color: palette.onSoft,
                    ),
                  ),
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        const TextSpan(text: '已获得 '),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: AnimatedCount(
                            value: earnedCount,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: badgeNumColor,
                              fontFeatures: kTabularNumbers,
                            ),
                            pulse: false,
                          ),
                        ),
                        const TextSpan(text: ' 枚勋章'),
                      ],
                    ),
                    style: TextStyle(
                      fontSize: AppFontSize.xs,
                      color: palette.onColorSoft(palette.primarySoft),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AnimatedProgressBar(
                    value: percent / 100,
                    color: palette.primary,
                    trackColor: palette.surfaceSoft,
                    height: AppSpacing.sm,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        const TextSpan(text: '成就进度 '),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: AnimatedCount(
                            value: percent,
                            formatter: (num value) => '${value.round()}%',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: progressNumColor,
                              fontFeatures: kTabularNumbers,
                            ),
                            pulse: false,
                          ),
                        ),
                      ],
                    ),
                    style: TextStyle(
                      fontSize: AppFontSize.xs,
                      color: palette.onColorSoft(palette.primarySoft),
                    ),
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
              // 勋章格子按序号错峰进场（Wrap 里的项不在 _pageList 的列表上）
              for (final (int index, Badge badge) in garden.badges.indexed)
                EnterBox(
                  index: index,
                  child: SizedBox(width: cardWidth, child: _badgeCard(garden, badge, palette)),
                ),
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
    // 进度文字压在卡片底上：绿/金同样按底色压一档，别糊在底上
    final Color progressTextColor =
        badge.earned ? _readableAccent(palette, palette.success) : palette.textTertiary;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: AppSize.iconBadge,
                height: AppSize.iconBadge,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: accent.withValues(alpha: 0.14),
                  shape: AppShape.all(AppRadius.md),
                ),
                child: GlyphIcon(
                  gardenGlyph(badge.icon),
                  size: 20,
                  color: _tintForeground(palette, accent),
                ),
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
            AnimatedProgressBar(
              value: progress / 100,
              color: badge.earned ? palette.success : palette.primary,
              trackColor: palette.surfaceSoft,
              height: AppSpacing.sm,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  // 「照顾花园」这个措辞和实际机制对不上：做任务也会 +1 天（见
                  // GardenState.careForGarden 的注释）。改成「花园活跃」如实说。
                  TextSpan(text: badge.id == 'poet' ? '背诵 ' : '花园活跃 '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: AnimatedCount(
                      value: current,
                      formatter: (num value) => '${value.round()}/$target',
                      style: TextStyle(
                        fontSize: AppFontSize.xs,
                        color: progressTextColor,
                        fontFeatures: kTabularNumbers,
                      ),
                      pulse: false,
                    ),
                  ),
                  TextSpan(text: badge.id == 'poet' ? ' 首' : ' 天'),
                ],
              ),
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
    final List<GardenTask> doneTasks =
        garden.tasks.where((GardenTask task) => task.done).toList();
    // 一次 build 只取一次 now：整屏时间口径一致，跨零点不会半屏「今天」半屏「昨天」。
    final DateTime now = DateTime.now();
    // U-04：记录只增不减，store 已截到 gardenRecordLimit 条，但一次把几十行全建出来
    // 还是白花 —— 默认只渲最近 [_recordPreview] 条，剩下点「查看全部记录」。
    final int shown = _showAllRecords
        ? records.length
        : math.min(records.length, _recordPreview);
    final bool hasMore = records.length > shown;
    final bool hasBackground =
        context.select<ThemeState, bool>((ThemeState state) => state.background.isNotEmpty);
    // 流水整段画在一张卡上（和 AppCard 同一套底色 / 描边），但行交给
    // SliverList 虚拟化 —— 不能再用「AppCard 里套 Column 全量 for」。
    final ShapeBorder rowsShape = AppShape.card(palette.border);

    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm + AppTopBar.contentInset(context),
            AppSpacing.md,
            AppSpacing.sm,
          ),
          sliver: SliverList.list(
            children: <Widget>[
              const SectionHeader(title: '学习记录'),
              // 今日完成是任务数口径：completedCount 由 store 从 tasks 派生，最多等于任务总数；
              // 「获得阳光」按今天实际入账求和（背诗、语文练习一天可能入账多次）
              AppCard(
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: StatBlock(
                        label: '今日完成',
                        number: garden.completedCount,
                        formatter: (num value) => '${value.round()}/${garden.tasks.length}',
                        unit: '个任务',
                        color: palette.primary,
                        icon: AppIcons.checkCircle,
                      ),
                    ),
                    Expanded(
                      child: StatBlock(
                        label: '获得阳光',
                        number: _earnedToday(garden),
                        formatter: (num value) => formatCount(value),
                        unit: '阳光',
                        color: palette.warning,
                        icon: AppIcons.sun,
                      ),
                    ),
                  ],
                ),
              ),
              _gapMd,
              // 「今日已完成」（Web 版 RecordsPage 的那张列表卡）：任务名 + 完成时刻 + 奖励标签
              const SectionHeader(title: '今日已完成'),
              if (doneTasks.isEmpty)
                const AppCard(
                  // 换成自适应空态：原来 SizedBox(height: 240) + NullStatus 会把
                  // 引导文案裁在卡底下面，卡里还套了一层可滚动容器抢手势（审计 §3.4）
                  child: EmptyView(
                    message: '今天还没有完成任务',
                    hint: '去「今日任务」挑一个开始吧',
                    icon: AppIcons.checkCircle,
                  ),
                )
              else
                AppCard(
                  child: Column(
                    children: <Widget>[
                      for (int index = 0; index < doneTasks.length; index++) ...<Widget>[
                        if (index > 0) Divider(height: AppSpacing.md, color: palette.border),
                        _doneTaskRow(doneTasks[index], palette, now: now),
                      ],
                    ],
                  ),
                ),
              _gapMd,
              SectionHeader(
                title: '阳光记录',
                subtitle: hasMore
                    ? '先看最近 $shown 条，更早的可以展开'
                    : '最近的花园记录（还没传上去的也在里面）',
              ),
            ],
          ),
        ),
        if (records.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            sliver: SliverToBoxAdapter(
              child: const AppCard(
                child: EmptyView(
                  message: '还没有学习记录',
                  hint: '完成任务、背古诗、语文打卡都会记在这里',
                  icon: AppIcons.history,
                ),
              ),
            ),
          )
        else ...<Widget>[
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            sliver: DecoratedSliver(
              decoration: ShapeDecoration(
                color: palette.cardColor(hasBackground: hasBackground),
                shape: rowsShape,
              ),
              sliver: SliverPadding(
                padding: const EdgeInsets.all(AppSpacing.md),
                sliver: SliverList.separated(
                  itemCount: shown,
                  itemBuilder: (BuildContext context, int index) =>
                      _recordRow(records[index], palette, now: now),
                  separatorBuilder: (BuildContext context, int index) =>
                      Divider(height: AppSpacing.md, color: palette.border),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: hasMore
                    ? AppTextButton(
                        onPressed: () => setState(() => _showAllRecords = true),
                        child: Text('查看全部记录（共 ${formatCount(records.length)} 条）'),
                      )
                    : _showAllRecords && records.length > _recordPreview
                        ? AppTextButton(
                            onPressed: () => setState(() => _showAllRecords = false),
                            child: const Text('只看最近 20 条'),
                          )
                        : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: SizedBox(height: AppSpacing.xl + AppNavBar.contentInset(context)),
        ),
      ],
    );
  }

  /// 「今日已完成」的一行：任务名 + 完成时刻 + 奖励标签
  /// （对应 Web 版 RecordsPage 的 `List.Item`）
  Widget _doneTaskRow(GardenTask task, AppPalette palette, {required DateTime now}) {
    final DateTime? at = task.completedAt;
    final Color rewardColor = _readableAccent(palette, palette.warning);
    // 时间与流水行同一套格式（以前这里是裸 HH:mm，跟下面的「今天 HH:mm」两套）
    final String timeText = at == null ? '' : formatDateTime(at, now: now);

    return Row(
      children: <Widget>[
        GlyphIcon(AppIcons.checkCircle, size: 20, color: palette.success),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                task.name,
                style: TextStyle(
                  fontSize: AppFontSize.sm,
                  fontWeight: FontWeight.w600,
                  color: palette.text,
                ),
              ),
              if (timeText.isNotEmpty)
                Text(
                  timeText,
                  style: TextStyle(
                    fontSize: AppFontSize.xs,
                    color: palette.textTertiary,
                    fontFeatures: kTabularNumbers,
                  ),
                ),
            ],
          ),
        ),
        GlyphIcon(AppIcons.sun, size: AppSize.glyphXs, color: rewardColor),
        const SizedBox(width: AppSpacing.xs),
        AnimatedCount(
          value: task.reward,
          formatter: (num value) => '+${formatCount(value.round())}',
          style: TextStyle(
            fontSize: AppFontSize.sm,
            fontWeight: FontWeight.w700,
            color: rewardColor,
            fontFeatures: kTabularNumbers,
          ),
        ),
      ],
    );
  }

  Widget _recordRow(LedgerRecord record, AppPalette palette, {required DateTime now}) {
    final bool rejected = record.isRejected;
    final bool pending = record.isPending;
    final Glyph icon = rejected
        ? AppIcons.close
        : pending
            ? AppIcons.clock
            : AppIcons.checkCircle;
    final Color iconColor = rejected
        ? palette.danger
        : pending
            ? palette.warning
            : palette.success;
    final String? statusLabel = record.status?.label;
    // now 由调用方注入（一次 build 只取一次）：跨零点「今天」才会跟着翻成「昨天」
    final String timeText = formatDateTime(record.createdAt, now: now);
    // 金额也是卡片底上的强调色：正绿 / 负红都按底色压一档
    final Color amountColor = _readableAccent(
      palette,
      record.amount >= 0 ? palette.success : palette.danger,
    );

    return Row(
      children: <Widget>[
        GlyphIcon(icon, size: 20, color: iconColor),
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
        AnimatedCount(
          value: record.amount,
          // 符号跟最终值走（滚动中途不会出现「+0」这种别扭的中间态）
          formatter: (num value) =>
              record.amount >= 0 ? '+${formatCount(value.round())}' : formatCount(value.round()),
          style: TextStyle(
            fontSize: AppFontSize.md,
            fontWeight: FontWeight.w700,
            color: amountColor,
            fontFeatures: kTabularNumbers,
          ),
        ),
      ],
    );
  }
}

// ---- 对比度小工具 ----

/// [fg] 压在 [bg] 上的对比度（WCAG 口径，1~21）
double _contrastRatio(Color fg, Color bg) {
  final double a = fg.computeLuminance();
  final double b = bg.computeLuminance();
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

/// 强调色铺在自己的半透明色块上时（块里的图标、胶囊里的字），该用的前景色。
///
/// 浅色主题里「金色 icon 坐在淡金色块上」这类同色系撞色只有 ~1.8:1，整块糊成一片；
/// 这里按「色块合到底色之后」的真实颜色算对比度：衬不住就换 [AppPalette.onColor]
/// （同色系近黑 / 近白），衬得住就原样保留强调色 —— 不动原有的视觉语言。
Color _tintForeground(
  AppPalette palette,
  Color accent, {
  double alpha = 0.14,
  Color? base,
  double minRatio = 3,
}) {
  final Color blended = Color.alphaBlend(accent.withValues(alpha: alpha), base ?? palette.surface);
  return _contrastRatio(accent, blended) >= minRatio ? accent : palette.onColor(blended);
}

/// 强调色当正文 / 图标色用时的前景色（数字、奖励标签、勋章进度这类）。
///
/// 金色数字压在卡片白底上只有 ~2:1，跟底色糊在一起；衬不住就朝「底色的对色」
/// 方向压一档，压到够 [minRatio] 为止 —— 色相留着（金 → 深金），只动字色。
Color _readableAccent(
  AppPalette palette,
  Color accent, {
  Color? base,
  double minRatio = 4.5,
}) {
  final Color surface = base ?? palette.surface;
  if (_contrastRatio(accent, surface) >= minRatio) return accent;
  final Color target = palette.onColor(surface);
  for (double t = 0.1; t <= 1.0001; t += 0.1) {
    final Color mixed = Color.lerp(accent, target, t) ?? target;
    if (_contrastRatio(mixed, surface) >= minRatio) return mixed;
  }
  return target;
}

// ---- 复用的小组件 ----

/// 首屏加载中的花园：骨架屏；超过 [_stuckAfter] 还没出来就换成「重试」空态。
///
/// 「什么时候算加载中」的判定仍在 [GardenPage] 的 build 里（`tasks.isEmpty`）——
/// 这个判定本身是有问题的（请求失败后 tasks 也一直是空的），但页面拿不到
/// 「失败」信号，所以在这一层兜底：等太久就当作失败，给一个能点的出路。
class _GardenLoading extends StatefulWidget {
  const _GardenLoading({required this.onRetry});

  final VoidCallback onRetry;

  @override
  State<_GardenLoading> createState() => _GardenLoadingState();
}

class _GardenLoadingState extends State<_GardenLoading> {
  /// 骨架屏最多显示多久就改给「重试」按钮
  static const Duration _stuckAfter = Duration(seconds: 8);

  Timer? _timer;
  bool _stuck = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_stuckAfter, () {
      if (!mounted) return;
      setState(() => _stuck = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    if (_stuck) {
      return ErrorView(
        message: '花园打不开，可能是网络不太好',
        onRetry: () {
          // 点了重试就回到骨架屏，别停在错误页等下一次 build
          setState(() => _stuck = false);
          _timer?.cancel();
          _timer = Timer(_stuckAfter, () {
            if (!mounted) return;
            setState(() => _stuck = true);
          });
          widget.onRetry();
        },
      );
    }
    return Column(
      children: <Widget>[
        // 文案与原来一字不差，只是从「转圈」挪到骨架屏上方（Column 默认居中）
        Text(
          '正在打开花园…',
          style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        // 铺 4 张带左侧圆钮的卡片，形状跟真实的「今日任务」卡一致（loading 一结束
        // 就是同一排卡片，不会先看见一种形状再跳成另一种）
        const Expanded(child: SkeletonList(count: 4, lines: 2, showLeading: true)),
      ],
    );
  }
}

/// 浇水成功那一下：让植物轻轻「长大」再收回（一次收放，不循环）。
///
/// [cared] 从「今天还没浇」翻到「今天浇过了」时播一次；进页面时本来就已经浇过
/// 水不会重播 —— 所以不用在页面里额外存触发标记。
class _GrowPulse extends StatefulWidget {
  const _GrowPulse({required this.cared, required this.child});

  final bool cared;
  final Widget child;

  @override
  State<_GrowPulse> createState() => _GrowPulseState();
}

class _GrowPulseState extends State<_GrowPulse> with SingleTickerProviderStateMixin {
  /// 放大到的比例（比按压反馈明显一档，肉眼看得出「长大了」）
  static const double _grow = 1.12;

  late final AnimationController _controller =
      AnimationController(vsync: this, duration: AppMotion.slower, value: 1);

  bool _disableAnimations = false;

  /// 1 → [_grow] → 1（回落带一点过冲，像「弹回来」）
  late final Animation<double> _scale = TweenSequence<double>(<TweenSequenceItem<double>>[
    TweenSequenceItem<double>(
      tween: Tween<double>(begin: 1, end: _grow).chain(CurveTween(curve: AppMotion.decelerate)),
      weight: 45,
    ),
    TweenSequenceItem<double>(
      tween: Tween<double>(begin: _grow, end: 1).chain(CurveTween(curve: AppMotion.overshoot)),
      weight: 55,
    ),
  ]).animate(_controller);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 无障碍里的「减少动态效果」：直接停在终态，不播
    _disableAnimations = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  @override
  void didUpdateWidget(_GrowPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.cared && widget.cared) {
      if (_disableAnimations) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _scale,
        builder: (BuildContext context, Widget? child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: widget.child,
      );
}

/// 横向菜单胶囊（选中态用 AppCard 的 highlight）
class _MenuChip extends StatelessWidget {
  const _MenuChip({
    super.key,
    required this.menu,
    required this.selected,
    required this.onTap,
  });

  final GardenMenu menu;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    // 读屏：把「哪个菜单是当前页」念出来（以前选中态只体现在颜色上，看不见屏幕
    // 的人无从得知；语义对齐 fl_ui/navigation_dock.dart 的写法）
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: menu.label,
      excludeSemantics: true,
      onTap: onTap,
      child: AppCard(
        onTap: onTap,
        highlight: selected,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        margin: const EdgeInsets.only(right: AppSpacing.sm),
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            GlyphIcon(
              gardenGlyph(menu.icon),
              size: 18,
              // 选中态整颗胶囊是 highlight（淡主色底），字与图标都跟着这层底走
              color: selected ? palette.onSoft : palette.textTertiary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              menu.label,
              style: TextStyle(
                fontSize: AppFontSize.sm,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? palette.onSoft : palette.textSecondary,
              ),
            ),
          ],
        ),
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
    // 读屏：这个圆钮没有文字，只说「按钮」等于什么都没说 —— 补 label 与状态。
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: done ? '已完成' : '点击标记完成',
      child: PressInkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Container(
          width: AppSize.touchTarget,
          height: AppSize.touchTarget,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: done ? palette.success : Colors.transparent,
            shape: AppShape.all(AppRadius.full, side: BorderSide(color: done ? palette.success : palette.border, width: 2)),
          ),
          // 勾压在实心 success 底上：字色跟底色算，别拿卡片底色（surface）当字色
          child: done ? GlyphIcon(AppIcons.check, size: 22, color: palette.onColor(palette.success)) : null,
        ),
      ),
    );
  }
}

/// 状态小胶囊（正在用 / 已拥有 / 可以兑换 / 阳光不够 / 已获得…）
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color, this.background});

  final String label;
  final Color color;

  /// 胶囊实际压在哪层底上：卡片默认 [AppPalette.surface]，highlight 卡要显式传淡主色底
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.14),
        shape: AppShape.all(AppRadius.full),
      ),
      child: Text(
        label,
        // 小字压在自己的淡色块上：按「块合到底色」的真实对比度挑字色（浅色主题里
        // 金色小字坐在淡金块上只有 ~1.8:1，整块糊成一片）
        style: TextStyle(
          fontSize: AppFontSize.xs,
          fontWeight: FontWeight.w600,
          color: _tintForeground(
            palette,
            color,
            alpha: 0.14,
            base: background ?? palette.surface,
            minRatio: 4.5,
          ),
        ),
      ),
    );
  }
}
