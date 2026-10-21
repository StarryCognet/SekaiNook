import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/changelog.dart';
import '../../data/models/app_update.dart';
import '../../state/update_state.dart';
import '../../theme/app_shape.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import './motion/app_buttons.dart';

/// 应用内更新的两个弹层 + 设置页那一行「检查更新」。
///
/// 只有安卓会真的走到（[UpdateState.supported] 在网页版为 false），
/// 但文件里没有 `dart:io`，Web 构建照样过。

/// 有新版本 → 问一句 → 下载安装。
///
/// [allowSkip] 为 true 时（启动后的自动检查），点「以后再说」会把版本号记进本机，
/// 自动检查不再弹它；手动检查来的不记，用户想装随时还能点。
Future<void> promptUpdate(
  BuildContext context, {
  required UpdateState update,
  required AppUpdateInfo info,
  bool allowSkip = true,
}) async {
  final bool go = await _confirmUpdate(
    context,
    info: info,
    log: update.pendingLog,
    allowSkip: allowSkip,
  );
  if (!context.mounted) return;
  if (!go) {
    if (allowSkip) await update.skipPending();
    return;
  }
  await downloadAndInstall(context, update: update);
}

/// 下载 + 拉起系统安装器，全程一个进度弹窗。
Future<void> downloadAndInstall(BuildContext context, {required UpdateState update}) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final UpdateInstallResult? result = await showDialog<UpdateInstallResult>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => _DownloadProgressDialog(update: update),
  );
  if (result == null || result == UpdateInstallResult.launched) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        result == UpdateInstallResult.needPermission
            ? '系统会问你要「安装未知应用」的权限，允许之后回来再点一次就行'
            : update.lastError ?? '更新失败，稍后再试',
      ),
    ),
  );
}

Future<bool> _confirmUpdate(
  BuildContext context, {
  required AppUpdateInfo info,
  required ChangelogEntry? log,
  required bool allowSkip,
}) async {
  final AppPalette palette = context.palette;
  final bool? go = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text('发现新版本 v${info.versionName}'),
      content: ConstrainedBox(
        // 日志长了就在这块里往下滑（限半屏高），别把下面的按钮挤出屏幕。
        // 约束必须套在滚动视图**外面**，套在里面等于把内容截断、滑不动。
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '安装包 ${info.sizeText}，装好之后聊天记录、积分、照片都在。',
                style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              _UpdateLogBlock(info: info, log: log),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        AppTextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(allowSkip ? '以后再说' : '取消'),
        ),
        AppFilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('立即更新'),
        ),
      ],
    ),
  );
  return go ?? false;
}

/// 弹窗里的「这一版改了什么」。
///
/// 首选云端日志里跟这个版本对上的那条（标题 + 改动列表，跟设置页「版本日志」
/// 是同一份数据）；拿不到就退回清单里那行说明，再没有就整块不出现。
class _UpdateLogBlock extends StatelessWidget {
  const _UpdateLogBlock({required this.info, required this.log});

  final AppUpdateInfo info;
  final ChangelogEntry? log;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final String title = log?.title.trim() ?? '';
    final List<String> changes = log?.changes ?? const <String>[];
    final String fallback = info.changelog?.trim() ?? '';
    if (title.isEmpty && changes.isEmpty && fallback.isEmpty) {
      return const SizedBox.shrink();
    }

    // 只管把标题和改动列表排出来，能不能滑由外面的弹窗决定。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (title.isNotEmpty) ...<Widget>[
          Text(
            title,
            style: TextStyle(
              fontSize: AppFontSize.sm,
              fontWeight: FontWeight.w600,
              height: 1.5,
              color: palette.text,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        for (final String change in changes)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '· $change',
              style: TextStyle(
                fontSize: AppFontSize.xs,
                height: 1.6,
                color: palette.textTertiary,
              ),
            ),
          ),
        if (title.isEmpty && changes.isEmpty)
          Text(
            fallback,
            style: TextStyle(
              fontSize: AppFontSize.xs,
              height: 1.6,
              color: palette.textTertiary,
            ),
          ),
      ],
    );
  }
}

/// 进度弹窗：自己发起下载，完事带着结果关掉。
///
/// 下载放在弹窗里而不是外面，是为了不让「进度弹窗还没推上去就先 pop 了」这种
/// 抢路由的写法出现在调用点。
class _DownloadProgressDialog extends StatefulWidget {
  const _DownloadProgressDialog({required this.update});

  final UpdateState update;

  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  @override
  void initState() {
    super.initState();
    // 第一帧之后再动手：downloadAndInstall 会 notifyListeners，
    // 在 build 里发通知会撞上「build 期间标记重建」
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  Future<void> _run() async {
    final UpdateInstallResult result = await widget.update.downloadAndInstall();
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final UpdateState update = widget.update;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('正在下载更新'),
        content: AnimatedBuilder(
          animation: update,
          builder: (BuildContext context, Widget? child) {
            final double progress = update.progress.clamp(0, 1);
            final bool known = update.downloading && progress > 0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ClipPath(
                  clipper: ShapeBorderClipper(shape: AppShape.all(AppRadius.sm)),
                  child: LinearProgressIndicator(
                    value: known ? progress : null,
                    minHeight: 6,
                    backgroundColor: palette.surfaceSoft,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  known
                      ? '${(progress * 100).toStringAsFixed(0)}%　下载完会自动调起安装'
                      : '正在连接下载…',
                  style: TextStyle(
                    fontSize: AppFontSize.xs,
                    color: palette.textSecondary,
                    fontFeatures: kTabularNumbers,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 设置页「关于」里的那一行：一句状态 + 一个「检查更新」。
class UpdateCheckTile extends StatelessWidget {
  const UpdateCheckTile({super.key});

  @override
  Widget build(BuildContext context) {
    final UpdateState update = context.watch<UpdateState>();
    // 网页版刷新就是最新版，不摆这个入口
    if (!update.supported) return const SizedBox.shrink();

    final AppUpdateInfo? pending = update.pending;
    final AppPalette palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              pending != null
                  ? '新版本 v${pending.versionName} 可以装了'
                  : (update.autoCheckEnabled ? '有新版本会在这里提醒' : '自动检测已关，想查就点右边'),
              style: TextStyle(
                fontSize: AppFontSize.xs,
                color: pending == null ? palette.textSecondary : palette.primary,
              ),
            ),
          ),
          AppTextButton(
            onPressed: update.checking ? null : () => _check(context, update),
            child: Text(update.checking ? '检查中…' : '检查更新'),
          ),
        ],
      ),
    );
  }

  Future<void> _check(BuildContext context, UpdateState update) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final UpdateCheckResult result = await update.checkNow();
    if (!context.mounted) return;
    if (!result.reachable) {
      messenger.showSnackBar(const SnackBar(content: Text('连不上更新服务器，过会儿再试')));
      return;
    }
    final AppUpdateInfo? info = result.update;
    if (info == null) {
      messenger.showSnackBar(const SnackBar(content: Text('已经是最新版本')));
      return;
    }
    await promptUpdate(context, update: update, info: info, allowSkip: false);
  }
}

/// 设置页「关于」里的开关：每次打开 App 要不要自动查一次新版本。
///
/// 默认开。关掉之后只剩右边那行「检查更新」是手动的，弹窗也不再自己冒出来。
class UpdateAutoCheckTile extends StatelessWidget {
  const UpdateAutoCheckTile({super.key});

  @override
  Widget build(BuildContext context) {
    final UpdateState update = context.watch<UpdateState>();
    if (!update.supported) return const SizedBox.shrink();

    final AppPalette palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '自动检测更新',
                  style: TextStyle(fontSize: AppFontSize.sm, color: palette.text),
                ),
                const SizedBox(height: 2),
                Text(
                  '每次打开 App 都看一眼有没有新版本',
                  style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: update.autoCheckEnabled,
            onChanged: (bool value) => unawaited(update.setAutoCheckEnabled(value)),
          ),
        ],
      ),
    );
  }
}
