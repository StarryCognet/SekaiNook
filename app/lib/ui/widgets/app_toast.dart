import 'package:flutter/material.dart';
import 'package:sekainook_app/fl_ui/icons/icons.dart';
import 'package:sekainook_app/fl_ui/shape.dart';
import 'package:sekainook_app/fl_ui/surface.dart';
import 'package:sekainook_app/fl_ui/typography.dart';
import 'package:sekainook_app/theme/app_theme.dart';

/// 提示的语气：决定底色、图标和文字颜色。
enum AppToastTone { neutral, success, warning, error }

/// 全站轻提示 —— FlClash 风格的浮动卡片，替代 SnackBar 的默认外观。
///
/// 页面里的 `_toast()` helper 应该收敛到这一个入口，而不是各自拼 SnackBar：
/// 底色走四层表面色，圆角走超椭圆，语义色只做淡底 + 同色字，不整块涂满。
///
/// ```dart
/// AppToast.show(context, '已保存');
/// AppToast.show(context, '提交失败，请重试', tone: AppToastTone.error);
/// AppToast.show(context, '已提交，等家长审批', actionLabel: '撤销', onAction: _undo);
/// ```
abstract final class AppToast {
  static void show(
    BuildContext context,
    String text, {
    AppToastTone tone = AppToastTone.neutral,
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

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
    final style = AppTextStyle.subheadline.of(context).copyWith(
      color: foreground,
      fontWeight: FontWeight.w500,
    );

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        padding: EdgeInsets.zero,
        elevation: 0,
        backgroundColor: Colors.transparent,
        duration: duration ?? Duration(seconds: tone == AppToastTone.warning ? 5 : 3),
        content: DecoratedBox(
          decoration: ShapeDecoration(
            color: background,
            shape: AppShape.lg,
            shadows: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                GlyphIcon(glyph, size: 18, color: foreground),
                const SizedBox(width: 10),
                Expanded(child: Text(text, style: style)),
                if (actionLabel != null) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      messenger.hideCurrentSnackBar();
                      onAction?.call();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text(
                        actionLabel,
                        style: AppTextStyle.subheadline
                            .of(context)
                            .copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
