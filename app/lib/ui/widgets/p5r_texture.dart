import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// P5R 主题的底纹：网点纸。
///
/// 只在 [ThemeId.p5r] 下出现（其它主题拿不到 [P5rSkin]，直接返回空）。
/// 玩家记忆里的 P5R 界面是「黑底 / 白纸底 + 一层印刷网点」——不是干净渐变。
/// 这一层铺在背景图之上、所有页面之下，且不接收点击。
///
/// 为什么用 CustomPainter 画而不是贴图：网点尺寸要跟屏幕逻辑像素对齐，
/// 贴图在 2x/3x 屏上会糊成一片灰；画出来是清晰的圆点，且零素材体积。
class P5rTexture extends StatelessWidget {
  const P5rTexture({super.key});

  @override
  Widget build(BuildContext context) {
    final P5rSkin? skin = Theme.of(context).extension<P5rSkin>();
    if (skin == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        painter: _P5rTexturePainter(dark: skin.dark),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _P5rTexturePainter extends CustomPainter {
  const _P5rTexturePainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    // 深色：白点压在黑底上（像印刷网点）；浅色：黑点压在纸白上（像旧报纸）。
    final Paint dot = Paint()
      ..color = dark ? const Color(0x0DFFFFFF) : const Color(0x14000000)
      ..isAntiAlias = true;

    const double step = 16;
    const double radius = 1.2;
    int row = 0;
    for (double y = 0; y < size.height + step; y += step, row++) {
      // 隔行错开半格，避免排成规整的棋盘
      final double shift = row.isEven ? 0 : step / 2;
      for (double x = -step + shift; x < size.width + step; x += step) {
        canvas.drawCircle(Offset(x, y), radius, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_P5rTexturePainter oldDelegate) => oldDelegate.dark != dark;
}
