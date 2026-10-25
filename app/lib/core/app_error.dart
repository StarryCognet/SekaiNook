import 'package:flutter/material.dart';

import '../theme/app_shape.dart';
import '../theme/tokens.dart';

/// 出错兜底卡片上「重新加载」按钮的钩子。
///
/// Web 版这里调 `window.location.reload()`；Flutter 侧等价做法是重建整棵 widget
/// 树（[SekaiNookApp] 启动时注册这个钩子），这样 Android / Web 一套代码。
VoidCallback? _reloadHandler;

void setReloadHandler(VoidCallback handler) => _reloadHandler = handler;

void reloadApp() {
  final handler = _reloadHandler;
  if (handler == null) {
    debugPrint('[SekaiNook] 应用尚未注册重新加载钩子，忽略这次点击');
    return;
  }
  handler();
}

/// 装一个中文兜底卡片：渲染期异常不再白屏（对应 Web 版 `components/ErrorBoundary.tsx`）。
void installErrorWidget() {
  ErrorWidget.builder = (FlutterErrorDetails details) {
    // 不把原始异常文本显示给用户（L-10）：里面有内部路径、类名、甚至参数值，
    // 截图外传不合适。日志留在 debug 通道，页面只给一句通用话。
    debugPrint('[SekaiNook] 渲染异常：${details.exceptionAsString()}');
    // 注意不能写 `const`：卡片现在按当前主题取色（深色下才不闪白）。
    return const AppErrorCard();
  };
}

/// 出错兜底卡片。
///
/// 刻意只用最小依赖的组件（不依赖具体页面 / Provider）：出错时上层可能已经不完整，
/// 兜底组件自己再抛错就真的白屏了。但**颜色跟当前主题走** —— 旧实现写死浅色，
/// 深色/纯黑主题下一出错就闪一整屏白卡片；取不到主题时退回下面这组兜底色
/// （与 Web 版 `var(--color-bg, #f5f6fa)` 同源），所以字面量颜色依然保留。
class AppErrorCard extends StatelessWidget {
  const AppErrorCard({
    super.key,
    this.message = '刚才加载出错了，点「重新加载」会回到首页重新开始',
    this.compact = false,
  });

  final String message;

  /// true = 内容区二级兜底（不占满屏），false = 整页兜底
  final bool compact;

  static const Color _lightBg = Color(0xFFF5F6FA);
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightText = Color(0xFF262626);
  static const Color _lightTextSecondary = Color(0xFF595959);
  static const Color _lightTextTertiary = Color(0xFF8C8C8C);
  static const Color _lightPrimary = Color(0xFF1677FF);
  static const Color _darkBg = Color(0xFF0E0E10);
  static const Color _darkSurface = Color(0xFF1A1A1E);

  @override
  Widget build(BuildContext context) {
    // Theme.of 在上层没有 Theme 时会回退到 ThemeData.fallback（浅色），不会抛错；
    // 正常运行时则能拿到深色/纯黑主题，兜底卡片和页面是同一套配色。
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color bg = dark ? _darkBg : _lightBg;
    final Color surface = dark ? _darkSurface : _lightSurface;
    final Color text = dark ? const Color(0xFFEDEDED) : _lightText;
    final Color textSecondary = dark ? const Color(0xFFB0B0B0) : _lightTextSecondary;
    final Color textTertiary = dark ? const Color(0xFF8A8A8A) : _lightTextTertiary;
    final Color primary = dark ? theme.colorScheme.primary : _lightPrimary;
    final Color onPrimary = dark ? theme.colorScheme.onPrimary : surface;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: compact ? null : bg,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 360),
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: compact ? AppSpacing.lg : AppSpacing.xl,
          ),
          decoration: ShapeDecoration(
            color: surface,
            shadows: <BoxShadow>[
              BoxShadow(
                color: dark ? const Color(0x66000000) : const Color(0x14000000),
                blurRadius: 24,
                offset: const Offset(0, 6),
              ),
            ],
            shape: AppShape.all(AppRadius.lg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('🌱', style: TextStyle(fontSize: compact ? 32 : 40, height: 1)),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '页面出了点问题',
                style: TextStyle(
                  fontSize: AppFontSize.lg,
                  color: text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                compact
                    ? '这一块没加载出来，重新加载一下；也可以先切到别的页面继续用。'
                    : '刚才加载出错了，重新加载一下通常就好了（会回到首页）。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppFontSize.sm,
                  height: 1.6,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              // 触控区补到 48dp：旧实现只有 10+10 的内边距（≈41dp），
              // 而且是个裸 GestureDetector，没有 button 语义（读屏念不到）。
              Semantics(
                container: true,
                button: true,
                label: '重新加载',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: reloadApp,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: 48,
                    width: double.infinity,
                    alignment: Alignment.center,
                    decoration: ShapeDecoration(
                      color: primary,
                      shape: AppShape.all(AppRadius.sm),
                    ),
                    child: Text(
                      '重新加载',
                      style: TextStyle(
                        fontSize: AppFontSize.md,
                        fontWeight: FontWeight.w600,
                        color: onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppFontSize.xs,
                  height: 1.5,
                  color: textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
