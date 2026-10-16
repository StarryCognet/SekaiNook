import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../config/family_rules.dart';
import '../../state/family_state.dart';
import '../../state/settings_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// 身份选择门（对应 Web 版 `src/components/RoleGate.tsx`）。
///
/// 只有真正选过身份才放行 —— **绝不能缺省为家长**，
/// 否则妹妹手机第一次打开就是家长模式，能自己审批自己的打卡。
class RoleGatePage extends StatelessWidget {
  const RoleGatePage({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final settings = context.watch<SettingsState>();

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'SekaiNook',
                  style: TextStyle(
                    fontSize: AppFontSize.xl,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '先选一下你是谁',
                  style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xl),
                _RoleCard(
                  emoji: '🌸',
                  title: settings.kidName,
                  subtitle: '打卡赚积分、看花园、背古诗',
                  color: palette.primary,
                  onTap: () => _chooseKid(context),
                ),
                const SizedBox(height: AppSpacing.md),
                _RoleCard(
                  emoji: '👩',
                  title: settings.momName,
                  subtitle: '审批打卡、看账本、管设置',
                  color: palette.success,
                  onTap: () => _chooseParent(context),
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

  Future<void> _chooseKid(BuildContext context) async {
    await context.read<FamilyState>().setRole(FamilyRole.child);
    if (context.mounted) context.go('/home');
  }

  Future<void> _chooseParent(BuildContext context) async {
    final family = context.read<FamilyState>();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ChangeNotifierProvider<FamilyState>.value(
        value: family,
        child: const _ParentPinDialog(),
      ),
    );
    if (ok == true && context.mounted) context.go('/home');
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: 320,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
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
                          color: palette.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: palette.textTertiary),
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
      content: Column(
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
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
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
