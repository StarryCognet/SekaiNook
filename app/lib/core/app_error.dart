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
    return const AppErrorCard(message: '页面出了点问题，点「重新加载」试试');
  };
}

/// 出错兜底卡片。
///
/// 刻意只用最小依赖的组件（不依赖 MaterialApp / Theme）：出错时上层可能已经不完整，
/// 兜底组件自己再抛错就真的白屏了 —— 这也是 Web 版那份只用原生 DOM + 内联样式的原因。
/// 配色是「主题取不到时的兜底值」，与 Web 版 `var(--color-bg, #f5f6fa)` 同源，
/// 所以这里允许出现字面量颜色。
class AppErrorCard extends StatelessWidget {
  const AppErrorCard({super.key, required this.message, this.compact = false});

  final String message;

  /// true = 内容区二级兜底（不占满屏），false = 整页兜底
  final bool compact;

  static const Color _bg = Color(0xFFF5F6FA);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _text = Color(0xFF262626);
  static const Color _textSecondary = Color(0xFF595959);
  static const Color _textTertiary = Color(0xFF8C8C8C);
  static const Color _primary = Color(0xFF1677FF);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: compact ? null : _bg,
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
            color: _surface,
            shadows: const <BoxShadow>[
              BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 6)),
            ],
            shape: AppShape.all(AppRadius.lg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('🌱', style: TextStyle(fontSize: compact ? 32 : 40, height: 1)),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                '页面出了点问题',
                style: TextStyle(
                  fontSize: AppFontSize.lg,
                  color: _text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                compact
                    ? '这一块没加载出来，重新加载一下；也可以先切到别的页面继续用。'
                    : '刚才加载出错了，重新加载一下通常就好了。',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: AppFontSize.sm,
                  height: 1.6,
                  color: _textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: reloadApp,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: ShapeDecoration(
                      color: _primary,
                      shape: AppShape.all(AppRadius.sm),
                    ),
                    child: const Text(
                      '重新加载',
                      style: TextStyle(fontSize: 15, color: _surface),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: AppFontSize.xs,
                  height: 1.5,
                  color: _textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
