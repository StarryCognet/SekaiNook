import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:sekainook_app/theme/app_theme.dart';

/// 对比度回归：七套主题里「字压在有色的底上」的每一组都必须看得清。
///
/// 这是用户反馈「字色和底色撞在一起看不清」的自动化防线 ——
/// 主题色板一改，这里就会红。
///
/// 阈值按 WCAG：正文 4.5、大字/次要文字 3.5。
double _contrast(Color foreground, Color background) {
  final double fg = _luminance(_composite(foreground, background));
  final double bg = _luminance(background);
  final double hi = math.max(fg, bg);
  final double lo = math.min(fg, bg);
  return (hi + 0.05) / (lo + 0.05);
}

/// 半透明前景压到底色上的实际观感色。
Color _composite(Color foreground, Color background) {
  final double a = foreground.a;
  if (a >= 1) return foreground;
  return Color.from(
    alpha: 1,
    red: foreground.r * a + background.r * (1 - a),
    green: foreground.g * a + background.g * (1 - a),
    blue: foreground.b * a + background.b * (1 - a),
  );
}

double _luminance(Color c) =>
    c.computeLuminance();

void main() {
  for (final AppThemePreset preset in AppTheme.all) {
    final AppPalette p = preset.palette;
    final String where = '主题 ${preset.id.name}（${preset.name}）';

    group(where, () {
      void expectVisible(String what, Color fg, Color bg, {double min = 4.5}) {
        final double ratio = _contrast(fg, bg);
        expect(
          ratio,
          greaterThanOrEqualTo(min),
          reason: '$where 的 $what 对比度只有 ${ratio.toStringAsFixed(2)}:1（要求 ≥ $min）',
        );
      }

      test('正文压在普通底上', () {
        expectVisible('text / surface', p.text, p.surface);
        expectVisible('text / bg', p.text, p.bg);
        expectVisible('textSecondary / surface', p.textSecondary, p.surface, min: 3.5);
        expectVisible('textSecondary / bg', p.textSecondary, p.bg, min: 3.5);
      });

      // 这一组是「用户说看不清」的头号来源：出厂主题的 textTertiary 原本只有
      // 2.4~2.6:1（浅色主题），StatBlock 的 label/unit、空态提示、时间戳全在用它。
      // 卡片底（surface）上按正文标准要求 4.5；页面底（bg）比卡片略深或略浅，
      // 同一档字色在其上必然略低，所以只要求 4.0。
      test('三级文字（标签/提示/时间戳）也读得清', () {
        expectVisible('textTertiary / surface', p.textTertiary, p.surface);
        expectVisible('textTertiary / bg', p.textTertiary, p.bg, min: 4.0);
      });

      test('字压在主色（含 primarySoft 选中底）上', () {
        expectVisible('onPrimary / primary', p.onPrimary, p.primary);
        expectVisible('onSoft / primarySoft', p.onSoft, p.primarySoft, min: 4.5);
      });

      test('语义色块上的字', () {
        expectVisible('onColor / success', p.onColor(p.success), p.success);
        expectVisible('onColor / danger', p.onColor(p.danger), p.danger);
        expectVisible('onColor / warning', p.onColor(p.warning), p.warning, min: 3.5);
      });

      test('语义色当字色落在中性底上（ink 家族）', () {
        expectVisible('primaryInk / surface', p.primaryInk, p.surface);
        expectVisible('successInk / surface', p.successInk, p.surface);
        expectVisible('dangerInk / surface', p.dangerInk, p.surface);
        expectVisible('warningInk / surface', p.warningInk, p.surface);
        expectVisible('ink(warning, bg) / bg', p.ink(p.warning, p.bg), p.bg);
        expectVisible('ink(danger, bg) / bg', p.ink(p.danger, p.bg), p.bg);
      });

      test('导航与分段控件的选中底', () {
        expectVisible('onColor / sider', p.onColor(p.sider), p.sider);
        expectVisible('onColor / siderSelected', p.onColor(p.siderSelected), p.siderSelected);
        expectVisible(
          'onColor / segmentedSelected',
          p.onColor(p.segmentedSelected),
          p.segmentedSelected,
        );
      });
    });
  }
}
