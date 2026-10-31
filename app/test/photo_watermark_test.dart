import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sekainook_app/core/photo_watermark.dart';

/// 水印是打卡照片的可信度凭据（任务 + 时刻 + 位置），压不上去等于白拍。
/// 这里只验三件在 CI 里能验的事：不崩、尺寸不变、底部遮罩真的压暗了。
///
/// 文字本身渲染成什么样（字体、断行）只能真机看 —— 但「遮罩没画上」
/// 这类回归（比如 gradient 的 colors 传错、bar 高度算成负数）这里能拦住。
void main() {
  testWidgets('水印压到照片底部且不改尺寸', (WidgetTester tester) async {
    final img.Image canvas = img.Image(width: 400, height: 300);
    img.fill(canvas, color: img.ColorRgb8(200, 120, 60));
    final Uint8List source = Uint8List.fromList(img.encodePng(canvas));

    final Uint8List? stamped = await applyPhotoWatermark(
      source,
      WatermarkInfo(
        title: '整理房间',
        time: DateTime(2026, 10, 31, 22, 37, 18),
        location: 'N39.91500° E116.40400°',
      ),
    );

    expect(stamped, isNotNull, reason: '合法 PNG 应该能压上水印');
    final img.Image? decoded = img.decodeJpg(stamped!);
    expect(decoded, isNotNull, reason: '产出的应该是可解码的 JPEG');
    expect(decoded!.width, 400);
    expect(decoded.height, 300);

    // 左上角是原色，左下角被底部渐变遮罩压暗 —— 差得越明显说明遮罩越到位
    final double topLuma = _luma(decoded, 4, 4);
    final double bottomLuma = _luma(decoded, 4, decoded.height - 4);
    expect(bottomLuma, lessThan(topLuma * 0.6));
  });

  testWidgets('解不出图片时返回 null 而不是抛异常', (WidgetTester tester) async {
    final Uint8List garbage = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8]);
    final Uint8List? stamped = await applyPhotoWatermark(
      garbage,
      WatermarkInfo(title: '整理房间', time: DateTime(2026, 10, 31)),
    );
    // 调用方（打卡弹窗）靠这个 null 退回原图，绝不能把异常抛到 UI 上
    expect(stamped, isNull);
  });

  test('位置缺失时水印文案写「位置未获取」而不是留空', () {
    final WatermarkInfo info = WatermarkInfo(
      title: '洗碗',
      time: DateTime(2026, 10, 31, 22, 37, 18),
    );
    expect(info.locationText, '位置未获取');
  });
}

double _luma(img.Image image, int x, int y) {
  final img.Pixel pixel = image.getPixel(x, y);
  return 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
}
