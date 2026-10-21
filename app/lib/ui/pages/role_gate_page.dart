import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../config/family_rules.dart';
import '../../state/family_state.dart';
import '../../state/settings_state.dart';
import '../../theme/app_shape.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import '../../theme/tokens.dart';
import '../widgets/motion_widgets.dart';
import '../widgets/motion/app_buttons.dart';

/// 身份选择门（对应 Web 版 `src/components/RoleGate.tsx`）。
///
/// 只有真正选过身份才放行 —— **绝不能缺省为家长**，
/// 否则妹妹手机第一次打开就是家长模式，能自己审批自己的打卡。
class RoleGatePage extends StatefulWidget {
  const RoleGatePage({super.key});

  @override
  State<RoleGatePage> createState() => _RoleGatePageState();
}

class _RoleGatePageState extends State<RoleGatePage> {
  /// 刚点下去的那张卡：只驱动选中态的弹簧与描边，不参与任何身份判断
  FamilyRole? _picked;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final settings = context.watch<SettingsState>();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                EnterBox(
                  index: 0,
                  scaleFrom: 0.96,
                  child: Text(
                    'SekaiNook',
                    style: TextStyle(
                      fontSize: AppFontSize.xl,
                      fontWeight: FontWeight.w700,
                      color: palette.text,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '先选一下你是谁',
                  style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xl),
                EnterBox(
                  index: 1,
                  scaleFrom: 0.94,
                  child: _RoleCard(
                    emoji: '🌸',
                    title: settings.kidName,
                    subtitle: '打卡赚积分、看花园、背古诗',
                    color: palette.primary,
                    selected: _picked == FamilyRole.child,
                    onTap: _chooseKid,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                EnterBox(
                  index: 2,
                  scaleFrom: 0.94,
                  child: _RoleCard(
                    emoji: '👩',
                    title: settings.momName,
                    subtitle: '审批打卡、看账本、管设置',
                    color: palette.success,
                    selected: _picked == FamilyRole.parent,
                    onTap: _chooseParent,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  '开户礼金 +${FamilyRules.welcomeBonus} 分 · ${FamilyRules.exchangeRateText}',
                  style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 选中态先弹一下（弹簧），再走原来的切身份 + 跳转 —— 顺序不变，只是中间多一拍反馈。
  Future<void> _chooseKid() async {
    if (_picked != null) return;
    setState(() => _picked = FamilyRole.child);
    await Future<void>.delayed(AppMotion.fast);
    if (!mounted) return;
    showBurst(context);
    await context.read<FamilyState>().setRole(FamilyRole.child);
    if (mounted) context.go('/home');
  }

  Future<void> _chooseParent() async {
    if (_picked != null) return;
    setState(() => _picked = FamilyRole.parent);
    await Future<void>.delayed(AppMotion.fast);
    if (!mounted) return;
    final family = context.read<FamilyState>();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ChangeNotifierProvider<FamilyState>.value(
        value: family,
        child: const _ParentPinDialog(),
      ),
    );
    if (ok != true || !mounted) {
      // 口令没对上（或者点了取消）：选中态弹回去，还能再点一次
      if (mounted) setState(() => _picked = null);
      return;
    }
    showBurst(context);
    context.go('/home');
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.selected = false,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  /// 选中的那张卡会弹出去一点、描边转成自己的强调色
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // 选中时底色是「强调色 12% 合到卡片底上」：里面的字/图标一律按这层底取色，
    // 不能再指望 palette.text（强调色淡底上压深字在部分主题里会糊）
    final Color selectedBase =
        Color.alphaBlend(color.withValues(alpha: 0.12), palette.surface);
    return SizedBox(
      width: 320,
      child: AnimatedScale(
        scale: selected ? 1.04 : 1,
        duration: AppMotion.fast,
        curve: AppMotion.spring,
        child: PressInkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.standard,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: ShapeDecoration(
              // 选中底用「算好的实色」而不是半透明色：设了背景图时半透明会透出照片，
              // 卡片和上面的字都跟着糊；这层实色 = 12% 强调色合到 surface 上，观感一致、对比度可算
              color: selected ? selectedBase : palette.surface,
              shape: AppShape.all(AppRadius.lg, side: BorderSide(color: selected ? color : palette.border, width: selected ? 2 : 1)),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: AppShape.all(AppRadius.md),
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 24)),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: AppFontSize.md,
                          fontWeight: FontWeight.w600,
                          color: selected ? palette.onColor(selectedBase) : palette.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: AppFontSize.xs,
                          color: selected
                              ? palette.onColorSoft(selectedBase)
                              : palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: selected ? palette.onColorSoft(selectedBase) : palette.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 家长口令输入框。返回 true = 验证通过。
class _ParentPinDialog extends StatefulWidget {
  const _ParentPinDialog();

  @override
  State<_ParentPinDialog> createState() => _ParentPinDialogState();
}

class _ParentPinDialogState extends State<_ParentPinDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  bool _busy = false;
  Timer? _lockTimer;

  /// 抖动计数：每失败一次 +1，驱动**一次**横向抖动（不是循环动画）
  int _shakeTick = 0;

  @override
  void initState() {
    super.initState();
    // 锁定期内每秒刷一次倒计时文案
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && context.read<FamilyState>().pinLockRemaining > Duration.zero) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final family = context.read<FamilyState>();
    if (family.pinLockRemaining > Duration.zero) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await family.verifyParentPin(_controller.text);
    if (!mounted) return;
    if (ok) {
      await family.setRole(FamilyRole.parent);
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _shakeTick++;
      final remaining = family.pinLockRemaining;
      if (remaining > Duration.zero) {
        _error = '试错太多次，请等 ${remaining.inSeconds} 秒后再试';
      } else {
        _error = '口令不对，还可以试 ${family.pinAttemptsLeft} 次';
      }
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final family = context.watch<FamilyState>();
    final locked = family.pinLockRemaining > Duration.zero;

    return AlertDialog(
      backgroundColor: palette.surface,
      title: const Text('家长口令'),
      content: TweenAnimationBuilder<Offset>(
        // 把「第几次抖动」编进 tween 的终点：每失败一次终点 +1，
        // 组件不重建（输入框不丢焦点），进度落在小数部分里做一次衰减横摆。
        tween: Tween<Offset>(begin: Offset.zero, end: Offset(_shakeTick.toDouble(), 0)),
        duration: AppMotion.slow,
        curve: AppMotion.linear,
        builder: (BuildContext context, Offset value, Widget? child) {
          final double phase = value.dx - value.dx.floorToDouble();
          final double dx = math.sin(phase * math.pi * 3) * (1 - phase) * 8;
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: true,
              enabled: !locked && !_busy,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(hintText: '输入口令'),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(fontSize: AppFontSize.xs, color: palette.danger)),
            ],
            if (family.hasCustomParentPin)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  '已修改过口令',
                  style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        AppTextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        AppFilledButton(
          onPressed: locked || _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('进入'),
        ),
      ],
    );
  }
}
