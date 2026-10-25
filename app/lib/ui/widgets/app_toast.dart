import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sekainook_app/fl_ui/icons/icons.dart';
import 'package:sekainook_app/fl_ui/shape.dart';
import 'package:sekainook_app/fl_ui/surface.dart';
import 'package:sekainook_app/fl_ui/typography.dart';
import 'package:sekainook_app/theme/app_theme.dart';

/// 提示的语气：决定底色、图标和文字颜色。
enum AppToastTone { neutral, success, warning, error }

/// 全站轻提示 —— 顶部下滑的浮动卡片，替代 SnackBar 的默认外观。
///
/// 为什么在顶部：底部是胶囊导航的地盘，提示压上去既挡手又容易被误触；
/// 顶部从顶栏下方滑入，视觉上更接近「系统回执」，而且不会盖住导航。
///
/// 实现用 root Overlay 而不是 ScaffoldMessenger —— SnackBar 只能停底边，
/// 且会被页面 Scaffold 的 body 裁掉；Overlay 能保证它始终浮在所有页面之上。
///
/// ```dart
/// AppToast.show(context, '已保存');
/// AppToast.show(context, '提交失败，请重试', tone: AppToastTone.error);
/// AppToast.show(context, '已提交，等家长审批', actionLabel: '撤销', onAction: _undo);
/// ```
abstract final class AppToast {
  static OverlayEntry? _entry;

  /// 顶栏高度（AppTopBar innerHeight）+ 上下留白，见 [AppShellMetrics]。
  static const double _topGap = 8;
  static const double _sideMargin = 16;
  static const double _maxWidth = 520;

  static void show(
    BuildContext context,
    String text, {
    AppToastTone tone = AppToastTone.neutral,
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!context.mounted) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final scheme = Theme.of(context).colorScheme;
    final palette = context.palette;
    final card = SurfaceLevel.card.colorOf(scheme);
    final accent = switch (tone) {
      AppToastTone.neutral => null,
      AppToastTone.success => palette.success,
      AppToastTone.warning => palette.warning,
      AppToastTone.error => palette.danger,
    };
    final background = accent == null
        ? card
        : Color.alphaBlend(accent.withValues(alpha: 0.14), card);
    final foreground = accent ?? scheme.onSurface;
    final glyph = switch (tone) {
      AppToastTone.neutral => AppGlyphs.info,
      AppToastTone.success => AppGlyphs.checkCircle,
      AppToastTone.warning => AppGlyphs.warning,
      AppToastTone.error => AppGlyphs.error,
    };
    final hold = duration ?? Duration(seconds: tone == AppToastTone.warning ? 5 : 3);
    final top = MediaQuery.viewPaddingOf(context).top + 60 + _topGap;

    // 轻提示不排队：新的直接顶掉旧的，否则连点几下会攒一叠。
    final previous = _entry;
    if (previous != null) {
      _entry = null;
      previous.remove();
    }

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: top,
        left: _sideMargin,
        right: _sideMargin,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: SizedBox(
              width: double.infinity,
              child: _ToastCard(
                text: text,
                background: background,
                foreground: foreground,
                glyph: glyph,
                tone: tone,
                scheme: scheme,
                hold: hold,
                actionLabel: actionLabel,
                onAction: onAction,
                onDone: () {
                  if (identical(_entry, entry)) {
                    _entry = null;
                    entry.remove();
                  }
                },
              ),
            ),
          ),
        ),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({
    required this.text,
    required this.background,
    required this.foreground,
    required this.glyph,
    required this.tone,
    required this.scheme,
    required this.hold,
    required this.onDone,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final Color background;
  final Color foreground;
  final Glyph glyph;
  final AppToastTone tone;
  final ColorScheme scheme;
  final Duration hold;
  final VoidCallback onDone;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    reverseDuration: const Duration(milliseconds: 160),
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: const Cubic(0.2, 0, 0, 1),
    reverseCurve: Curves.easeIn,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -0.16),
    end: Offset.zero,
  ).animate(_curve);

  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _timer = Timer(widget.hold, _close);
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    await _controller.reverse();
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyle.subheadline.of(context).copyWith(
      color: widget.foreground,
      fontWeight: FontWeight.w500,
    );
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: _slide,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: widget.background,
            shape: AppShape.lg,
            shadows: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                GlyphIcon(widget.glyph, size: 18, color: widget.foreground),
                const SizedBox(width: 10),
                Expanded(child: Text(widget.text, style: style)),
                if (widget.actionLabel != null) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () {
                      _close();
                      widget.onAction?.call();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text(
                        widget.actionLabel!,
                        style: AppTextStyle.subheadline.of(context).copyWith(
                          color: widget.scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
