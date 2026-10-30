import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../fl_ui/dialog.dart';
import '../../state/family_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'app_toast.dart';

/// 家长敏感操作（审批 / 驳回 / 删除 / 撤销调整 / 推送测试）的统一口令入口。
///
/// 为什么不在客户端单独打接口验证口令：服务端每个写接口都会自己校验
/// （`gateAdminPassword`），客户端再验一次等于多一个可试错的入口、多一次往返。
/// 这里只负责「拿到口令」，对错交给被调用的那个写接口。
///
/// 口令输入成功后缓存在 [FamilyState]（内存，不落盘），本会话内后续操作不再弹框；
/// 服务端回 401 说明缓存失效，调用方清缓存后下次会重新弹。

/// 弹框要一次家长口令。返回 null = 用户取消。
Future<String?> promptAdminPassword(
  BuildContext context, {
  String title = '家长验证',
  String description = '这一步会改动账本，需要输入家长口令',
}) {
  return showFloatingDialog<String>(
    context: context,
    dismissible: false,
    child: _AdminPasswordPromptDialog(title: title, description: description),
  );
}

/// 先拿到口令（缓存优先，没有就弹框），再执行 [action]。
///
/// 返回 false = 用户取消或口令被服务端拒绝（已清缓存并提示），调用方直接 return；
/// 其它异常原样抛给调用方，由各页面自己的错误提示处理。
Future<bool> runWithAdminPassword(
  BuildContext context, {
  required Future<void> Function(String password) action,
  String title = '家长验证',
  String description = '这一步会改动账本，需要输入家长口令',
}) async {
  final family = context.read<FamilyState>();
  final password = family.adminPassword ??
      await promptAdminPassword(
        context,
        title: title,
        description: description,
      );
  if (password == null || password.isEmpty) return false;
  try {
    await action(password);
    family.cacheAdminPassword(password);
    return true;
  } on ApiException catch (error) {
    if (error.status == 401) {
      // 缓存的口令过期 / 被家长在设置里改掉了：忘掉它，下次重新弹框
      family.clearAdminPassword();
      if (context.mounted) {
        AppToast.show(context, '口令不对，请重新输入', tone: AppToastTone.error);
      }
      return false;
    }
    if (error.status == 503) {
      // 「口令还没配置」这类服务端状态：原文就是给家长看的，别吞
      if (context.mounted) {
        AppToast.show(context, error.message, tone: AppToastTone.error);
      }
      return false;
    }
    rethrow;
  }
}

class _AdminPasswordPromptDialog extends StatefulWidget {
  const _AdminPasswordPromptDialog({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  State<_AdminPasswordPromptDialog> createState() =>
      _AdminPasswordPromptDialogState();
}

class _AdminPasswordPromptDialogState
    extends State<_AdminPasswordPromptDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = '请输入家长口令');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return CommonDialog(
      title: widget.title,
      hasFields: true,
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('确定'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            widget.description,
            style: TextStyle(
              fontSize: AppFontSize.xs,
              color: palette.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            style: TextStyle(fontSize: AppFontSize.sm, color: palette.text),
            decoration: InputDecoration(
              hintText: '家长口令',
              isDense: true,
              hintStyle: TextStyle(
                fontSize: AppFontSize.sm,
                color: palette.textTertiary,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: palette.primary),
              ),
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _error!,
              style: TextStyle(fontSize: AppFontSize.xs, color: palette.danger),
            ),
          ],
        ],
      ),
    );
  }
}
