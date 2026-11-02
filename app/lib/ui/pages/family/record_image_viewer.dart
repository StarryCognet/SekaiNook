import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/app_constants.dart';
import '../../../data/models/ledger_record.dart';
import '../../../theme/app_shape.dart';
import '../../../theme/tokens.dart';
import '../../icons/icons.dart';
import '../../widgets/format.dart';
import '../../widgets/motion/press_scale.dart';

/// 打开历史记录的「沉浸式全屏」图片查看器（选型里的 B1）。
///
/// 与原来的居中浮层相比：
/// - 纯黑底 + 全屏，图片按原始比例 contain，双击/捏合可放大到 4 倍；
/// - 顶部一行「关闭 + 日期」，底部是这条流水本身的信息（任务名 / 时间 / 备注 /
///   金额 / 状态），家长还能直接从这里删掉这条记录；
/// - 同一天有图的流水会一起进来看，左右箭头（或左右滑动）切换 —— 于是「看照片」
///   变成一连串翻过去，而不是看一张关掉再点下一张。
///
/// [records] 传当前列表里的全部记录，这里自己挑出有图的；[initialIndex] 是
/// 传进来的那条记录**在 records 里**的下标（不是在有图列表里的下标）。
Future<void> showRecordImageViewer({
  required BuildContext context,
  required List<LedgerRecord> records,
  required int initialIndex,
  required bool isParent,
  Future<void> Function(LedgerRecord record)? onDelete,
}) {
  final List<LedgerRecord> photos = <LedgerRecord>[
    for (final LedgerRecord record in records)
      if (record.imageUrl != null && record.imageUrl!.isNotEmpty) record,
  ];
  if (photos.isEmpty) return Future<void>.value();

  final LedgerRecord? target =
      (initialIndex >= 0 && initialIndex < records.length) ? records[initialIndex] : null;
  int page = 0;
  if (target != null) {
    final int at = photos.indexWhere((LedgerRecord r) => r.id == target.id);
    page = at < 0 ? 0 : at;
  }

  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => _RecordImageViewer(
        records: photos,
        initialIndex: page,
        isParent: isParent,
        onDelete: onDelete,
      ),
      transitionsBuilder: (_, Animation<double> animation, _, Widget child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _RecordImageViewer extends StatefulWidget {
  const _RecordImageViewer({
    required this.records,
    required this.initialIndex,
    required this.isParent,
    this.onDelete,
  });

  final List<LedgerRecord> records;
  final int initialIndex;
  final bool isParent;
  final Future<void> Function(LedgerRecord record)? onDelete;

  @override
  State<_RecordImageViewer> createState() => _RecordImageViewerState();
}

class _RecordImageViewerState extends State<_RecordImageViewer> {
  late final PageController _page = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  final TransformationController _zoom = TransformationController();

  @override
  void dispose() {
    _page.dispose();
    _zoom.dispose();
    super.dispose();
  }

  LedgerRecord get _record => widget.records[_index];

  void _go(int delta) {
    final int next = _index + delta;
    if (next < 0 || next >= widget.records.length) return;
    _zoom.value = Matrix4.identity();
    unawaited(
      _page.animateToPage(
        next,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  /// 双击在「原大」与「2.2 倍」之间切换（跟系统相册的习惯一致）
  void _toggleZoom() {
    _zoom.value = _zoom.value.isIdentity()
        ? (Matrix4.identity()..scaleByDouble(2.2, 2.2, 2.2, 1))
        : Matrix4.identity();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bool multiple = widget.records.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                onDoubleTap: _toggleZoom,
                child: PageView.builder(
                  controller: _page,
                  itemCount: widget.records.length,
                  onPageChanged: (int index) {
                    setState(() {
                      _index = index;
                      _zoom.value = Matrix4.identity();
                    });
                  },
                  itemBuilder: (BuildContext context, int index) {
                    final LedgerRecord record = widget.records[index];
                    return InteractiveViewer(
                      // 只有当前这一页接缩放：否则相邻页的矩阵会互相带偏
                      transformationController: index == _index ? _zoom : null,
                      minScale: 1,
                      maxScale: 4,
                      child: Center(
                        child: Image.network(
                          record.imageUrl!,
                          headers: AppConstants.imageHeaders,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const GlyphIcon(
                                  AppIcons.imageBroken,
                                  size: 32,
                                  color: Colors.white54,
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  '图片加载失败',
                                  style: TextStyle(
                                    fontSize: AppFontSize.sm,
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            _buildTopBar(),
            if (multiple) ..._buildArrows(),
            _buildInfoPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, AppSpacing.md, 28),
          decoration: BoxDecoration(
            // 不用 BackdropFilter（项目禁毛玻璃，1.31.6 踩过），渐变足够压住亮图
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.black.withValues(alpha: 0.72),
                Colors.black.withValues(alpha: 0),
              ],
            ),
          ),
          child: Row(
            children: <Widget>[
              _glassCircle(
                onTap: () => Navigator.of(context).maybePop(),
                child: const GlyphIcon(AppIcons.close, size: 18, color: Colors.white),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  formatDateTime(_record.createdAt),
                  style: TextStyle(
                    fontSize: AppFontSize.sm,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ),
              if (widget.records.length > 1)
                Text(
                  '${_index + 1}/${widget.records.length}',
                  style: TextStyle(
                    fontSize: AppFontSize.xs,
                    fontFeatures: kTabularNumbers,
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildArrows() {
    return <Widget>[
      Positioned(
        left: AppSpacing.sm,
        top: 0,
        bottom: 0,
        child: Center(
          child: _index == 0
              ? const SizedBox(width: 36, height: 36)
              : _glassCircle(
                  onTap: () => _go(-1),
                  size: 36,
                  child: const GlyphIcon(AppIcons.chevronBack, size: 18, color: Colors.white),
                ),
        ),
      ),
      Positioned(
        right: AppSpacing.sm,
        top: 0,
        bottom: 0,
        child: Center(
          child: _index >= widget.records.length - 1
              ? const SizedBox(width: 36, height: 36)
              : _glassCircle(
                  onTap: () => _go(1),
                  size: 36,
                  child: Transform.flip(
                    flipX: true,
                    child: const GlyphIcon(
                      AppIcons.chevronBack,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
        ),
      ),
    ];
  }

  Widget _glassCircle({
    required VoidCallback onTap,
    required Widget child,
    double size = 40,
  }) {
    return PressInkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          shape: AppShape.all(AppRadius.full),
        ),
        child: child,
      ),
    );
  }

  Widget _buildInfoPanel() {
    final LedgerRecord record = _record;
    final bool positive = record.amount >= 0;
    final bool rejected = record.status == LedgerStatus.rejected;
    final Color amountColor = rejected
        ? Colors.white.withValues(alpha: 0.5)
        : (positive ? const Color(0xFFB7E24A) : const Color(0xFFFF8B7A));
    final String statusLabel = switch (record.status) {
      LedgerStatus.pending => '待审批',
      LedgerStatus.rejected => '已驳回',
      _ => '已入账',
    };
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 36, AppSpacing.lg, AppSpacing.md),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: <Color>[
              Colors.black.withValues(alpha: 0.9),
              Colors.black.withValues(alpha: 0),
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      record.taskName,
                      style: const TextStyle(
                        fontSize: AppFontSize.md,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: AppFontSize.xs,
                      color: Colors.white.withValues(alpha: 0.62),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${positive ? '+' : ''}${record.amount}',
                    style: TextStyle(
                      fontSize: AppFontSize.md,
                      fontWeight: FontWeight.w700,
                      fontFeatures: kTabularNumbers,
                      color: amountColor,
                      decoration: rejected ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                record.note != null && record.note!.isNotEmpty
                    ? '${formatDateTime(record.createdAt)} · ${record.note!}'
                    : formatDateTime(record.createdAt),
                style: TextStyle(
                  fontSize: AppFontSize.xs,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              if (widget.isParent && widget.onDelete != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 36,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await widget.onDelete!(record);
                      if (mounted) Navigator.of(context).maybePop();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white.withValues(alpha: 0.86),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
                    ),
                    icon: const GlyphIcon(AppIcons.delete, size: 15),
                    label: const Text('删除这条记录'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
