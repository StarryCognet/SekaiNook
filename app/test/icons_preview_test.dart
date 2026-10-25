import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sekainook_app/fl_ui/icons/glyph.dart';
import 'package:sekainook_app/fl_ui/icons/glyph_icon.dart';
import 'package:sekainook_app/theme/app_theme.dart';
import 'package:sekainook_app/ui/icons/app_icons.dart';

/// 图标总览（golden 快照）：`flutter test --update-goldens test/icons_preview_test.dart`
/// 产出的 PNG 放在 `test/goldens/icons_preview.png`，用来肉眼核对新绘图标。
///
/// 只在 Windows 跑：参考图是在 Windows 上生成的，Linux/CI 的字体与抗锯齿
/// 渲染有约 0.4% 的像素差（golden 天生不跨平台），会被误判成回归。
void main() {
  testWidgets('icons preview sheet', (tester) async {
    tester.view.physicalSize = const Size(1240, 1020);
    tester.view.devicePixelRatio = 1;

    final preview = <String, Glyph>{
      'home': AppIcons.home,
      'bell': AppIcons.bell,
      'moon': AppIcons.moon,
      'flower': AppIcons.flower,
      'tree': AppIcons.tree,
      'leaf': AppIcons.leaf,
      'meal': AppIcons.meal,
      'laundry': AppIcons.laundry,
      'store': AppIcons.store,
      'gift': AppIcons.gift,
      'savings': AppIcons.savings,
      'wallet': AppIcons.wallet,
      'family': AppIcons.family,
      'checklist': AppIcons.checklist,
      'assignment': AppIcons.assignment,
      'trophy': AppIcons.trophy,
      'fire': AppIcons.fire,
      'calculate': AppIcons.calculate,
      'receipt': AppIcons.receipt,
      'calendar': AppIcons.calendar,
      'file': AppIcons.file,
      'trendUp': AppIcons.trendUp,
      'trendDown': AppIcons.trendDown,
      'radioOn': AppIcons.radioOn,
      'radioOff': AppIcons.radioOff,
      'imageBroken': AppIcons.imageBroken,
      'inbox': AppIcons.inbox,
      'alarmOff': AppIcons.alarmOff,
      'cloudOff': AppIcons.cloudOff,
      'logout': AppIcons.logout,
      'play': AppIcons.play,
      'history': AppIcons.history,
      // 以下为复用 FlClash 的，做混排对照
      'check': AppIcons.check,
      'checkCircle': AppIcons.checkCircle,
      'chevronForward': AppIcons.chevronForward,
      'settings': AppIcons.settings,
      'dashboard': AppIcons.dashboard,
      'star': AppIcons.star,
      'bolt': AppIcons.bolt,
      'clock': AppIcons.clock,
      'sun': AppIcons.sun,
      'photos': AppIcons.photos,
      'palette': AppIcons.palette,
      'eye': AppIcons.eye,
      'lock': AppIcons.lock,
      'broom': AppIcons.broom,
      'sparkle': AppIcons.sparkle,
      'devices': AppIcons.devices,
    };

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(ThemeId.rose, dark: false),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in preview.entries)
                  SizedBox(
                    width: 96,
                    height: 88,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GlyphIcon(entry.value, size: 40),
                        const SizedBox(height: 8),
                        Text(entry.key, style: const TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/icons_preview.png'),
    );
  }, skip: !Platform.isWindows);
}
