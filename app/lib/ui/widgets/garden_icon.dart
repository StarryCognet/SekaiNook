import 'package:sekainook_app/ui/icons/icons.dart';
import 'package:flutter/widgets.dart';

/// 花园图标 key → 仓库自己的 [Glyph]（对应 Web 版 `src/components/garden/GardenIcon.tsx`
/// 的 `ICON_MAP`，逐条照抄）。
///
/// 以前这份 switch 在花园页与孩子首页**各写一遍**（20 个 case 完全重复），
/// 两边一改就漂移；现在只有这一处，页面只管调用。
///
/// 取值说明：`flower` / `leaf` 在 Material 里没有同名图标，取语义最近的
/// 花 / 叶；未知 key 回退星形（与 Web 版一致，不抛错 —— 图标是装饰，
/// 不该因为一个坏 key 让整页红屏）。
Glyph gardenGlyph(String key) => switch (key) {
      'book' => AppIcons.book,
      'read' => AppIcons.book,
      'book-open' => AppIcons.book,
      'calc' => AppIcons.calculate,
      'pen' => AppIcons.edit,
      'feather' => AppIcons.edit,
      'eye' => AppIcons.eye,
      'sport' => AppIcons.bolt,
      'home' => AppIcons.home,
      'sun' => AppIcons.sun,
      'flower' => AppIcons.flower,
      'leaf' => AppIcons.leaf,
      'calendar' => AppIcons.calendar,
      'trophy' => AppIcons.trophy,
      'coin' => AppIcons.savings,
      'dashboard' => AppIcons.dashboard,
      'check' => AppIcons.checkCircle,
      'shop' => AppIcons.store,
      'history' => AppIcons.history,
      'star' => AppIcons.star,
      _ => AppIcons.star,
    };

/// 直接画一颗花园图标（尺寸 / 颜色可选）。
///
/// 只是 [gardenGlyph] + [GlyphIcon] 的糖，省得每个调用点写两遍 key 与 size。
Widget gardenIcon(String key, {double size = 18, Color? color}) =>
    GlyphIcon(gardenGlyph(key), size: size, color: color);
