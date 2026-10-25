import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/motion.dart';

/// 全局背景图层（对应 Web 版 `--app-bg-image` + 固定不动的 `background-attachment: fixed`）。
///
/// 用户设了自定义背景图时，照片铺满整屏并盖一层薄纱（[veil]），
/// 所有页面浮在它上面（各页面 Scaffold 的背景色在设了背景图时是透明的）。
///
/// 图片是一次性加载的：换背景图时 [AnimatedSwitcher] 交叉淡入，
/// 加载中的淡入交给 [Image.frameBuilder]，不会有半张图的闪烁。
class AppBackgroundLayer extends StatelessWidget {
  const AppBackgroundLayer({super.key, required this.url, required this.veil});

  final String url;

  /// 薄纱颜色，取 `palette.bgVeil`
  final Color veil;

  @override
  Widget build(BuildContext context) {
    final bool disableAnimations = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    // 背景图铺满整屏，但**按屏幕逻辑尺寸 × DPR 解码**就够：原图常见 3000px 宽，
    // 按原尺寸解码在低端安卓上要多花几十 MB 内存、首帧也慢（审查 U 项）。
    // 上限压到 2048，4K 原图也不会把内存撑爆。
    final Size screen = MediaQuery.sizeOf(context);
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final int decodeWidth = math.max(1, math.min(2048, (screen.width * dpr).round()));
    final int decodeHeight = math.max(1, math.min(4096, (screen.height * dpr).round()));

    final Widget layer = url.isEmpty
        ? const SizedBox.expand(key: ValueKey<String>('app-bg-none'))
        : Stack(
            key: ValueKey<String>(url),
            fit: StackFit.expand,
            children: <Widget>[
              Image.network(
                url,
                fit: BoxFit.cover,
                cacheWidth: decodeWidth,
                cacheHeight: decodeHeight,
                filterQuality: FilterQuality.medium,
                // 官方推荐的淡入写法：解码完成前透明，完成后淡入
                frameBuilder:
                    (
                      BuildContext context,
                      Widget child,
                      int? frame,
                      bool wasSynchronouslyLoaded,
                    ) {
                      if (wasSynchronouslyLoaded || disableAnimations) return child;
                      return AnimatedOpacity(
                        opacity: frame == null ? 0 : 1,
                        duration: AppMotion.slow,
                        curve: AppMotion.standard,
                        child: child,
                      );
                    },
                errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                    const SizedBox.expand(),
              ),
              ColoredBox(color: veil),
            ],
          );

    if (disableAnimations) return layer;

    return AnimatedSwitcher(
      duration: AppMotion.slow,
      switchInCurve: AppMotion.decelerate,
      switchOutCurve: AppMotion.standard,
      child: layer,
    );
  }
}
