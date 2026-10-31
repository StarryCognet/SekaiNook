import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
// 只取 DateFormat：intl 还导出一个自己的 `TextDirection`（LTR/RTL 枚举），
// 整包导入会把 dart:ui 的 `TextDirection.ltr` 遮住，TextPainter 那边直接编译不过。
import 'package:intl/intl.dart' show DateFormat;

/// 打卡照片的水印内容：任务名 + 拍摄时刻 + 位置。
///
/// 水印是**打卡可信度的一部分**：照片必须证明「什么时候、在哪儿、做的是哪件事」。
/// 所以三项缺一不可 —— 位置拿不到时也要写明「位置未获取」，
/// 而不是留白让人以为水印没压上去。
class WatermarkInfo {
  const WatermarkInfo({
    required this.title,
    required this.time,
    this.location,
  });

  /// 任务名（如「整理房间」）
  final String title;

  /// 拍摄时刻（设备本地时间，不是上传时刻 —— 用户可能拍完过一会儿才提交）
  final DateTime time;

  /// 「N39.91500° E116.40400°」这类文字；拿不到定位时传 null
  final String? location;

  /// 第二行：2026年10月31日 22:37:18
  String get timeText => DateFormat('yyyy年M月d日 HH:mm:ss').format(time);

  /// 第三行：位置（拿不到就明说，不留空）
  String get locationText =>
      (location == null || location!.isEmpty) ? '位置未获取' : location!;
}

/// 底部遮罩：从全透明渐变到接近纯黑，保证白字在任何照片上都读得清。
const Color _scrimFrom = Color(0x00000000);
const Color _scrimTo = Color(0xD9000000);
const Color _titleColor = Color(0xFFFFFFFF);
const Color _bodyColor = Color(0xFFEDEDED);

/// 把水印压到照片底部，返回新的 JPEG 字节；解不出图片时返回 `null`。
///
/// 为什么用 Flutter 的 Canvas 而不是 `package:image` 的 `drawString`：
/// image 包自带的是 5×7 点阵字体、**只认 ASCII**，而任务名与位置都是中文。
/// 走 [TextPainter] 直接用系统字体渲染，Android 与 Web 表现一致。
///
/// 调用方（拍照后的处理流程）拿到的源图已经压过一轮（长边 1600），
/// 这里的解码 + 重编码在主线程上是百毫秒级，不需要再开 isolate
/// （何况 `dart:ui` 的绘制本来就只能在主 isolate 做）。
Future<Uint8List?> applyPhotoWatermark(
  Uint8List bytes,
  WatermarkInfo info,
) async {
  final ui.Image source;
  try {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    source = frame.image;
  } catch (_) {
    // 不是图片 / 文件损坏：交给调用方退回原图，别把打卡堵死
    return null;
  }

  final int width = source.width;
  final int height = source.height;
  final double w = width.toDouble();
  final double h = height.toDouble();

  // 字号跟着图片宽度走：1600px 宽的照片上标题约 88px，缩略图里也认得出。
  final double titleSize = (w * 0.055).clamp(20.0, 120.0);
  final double bodySize = titleSize * 0.60;
  final double padding = titleSize * 0.75;
  final double lineGap = titleSize * 0.24;
  final double maxTextWidth = w - padding * 2;

  final TextPainter title = _painter(
    info.title,
    fontSize: titleSize,
    weight: FontWeight.w700,
    color: _titleColor,
    maxWidth: maxTextWidth,
  );
  final TextPainter timeLine = _painter(
    info.timeText,
    fontSize: bodySize,
    weight: FontWeight.w500,
    color: _bodyColor,
    maxWidth: maxTextWidth,
  );
  final TextPainter place = _painter(
    info.locationText,
    fontSize: bodySize,
    weight: FontWeight.w400,
    color: _bodyColor,
    maxWidth: maxTextWidth,
  );

  final double contentHeight =
      title.height + lineGap + timeLine.height + lineGap + place.height;
  final double barHeight = contentHeight + padding * 2;

  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);

  canvas.drawImage(source, Offset.zero, Paint());

  // 只压住底部一条，照片本身尽量少挡
  final Rect bar = Rect.fromLTWH(0, h - barHeight, w, barHeight);
  canvas.drawRect(
    bar,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, h - barHeight),
        Offset(0, h),
        const <Color>[_scrimFrom, _scrimTo],
      ),
  );

  double y = h - barHeight + padding;
  title.paint(canvas, Offset(padding, y));
  y += title.height + lineGap;
  timeLine.paint(canvas, Offset(padding, y));
  y += timeLine.height + lineGap;
  place.paint(canvas, Offset(padding, y));

  final ui.Picture picture = recorder.endRecording();
  final Uint8List? png;
  try {
    final ui.Image rendered = await picture.toImage(width, height);
    final ByteData? data =
        await rendered.toByteData(format: ui.ImageByteFormat.png);
    rendered.dispose();
    png = data?.buffer.asUint8List();
  } finally {
    picture.dispose();
    source.dispose();
    title.dispose();
    timeLine.dispose();
    place.dispose();
  }

  if (png == null) return null;
  // 统一回 JPEG（与 image_compress.dart 的产出同格式、同质量档），
  // 上传链路和 R2 里的历史照片保持一致，体积也比 PNG 小一个量级。
  final img.Image? decoded = img.decodePng(png);
  if (decoded == null) return null;
  return Uint8List.fromList(img.encodeJpg(decoded, quality: 85));
}

TextPainter _painter(
  String text, {
  required double fontSize,
  required FontWeight weight,
  required Color color,
  required double maxWidth,
}) {
  final TextPainter painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: weight,
        color: color,
        height: 1.2,
        // 照片上没有主题色可用：字色是固定的白/浅灰，不能跟着 App 主题走
        fontFamilyFallback: const <String>['Noto Sans CJK SC', 'sans-serif'],
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  );
  painter.layout(maxWidth: maxWidth);
  return painter;
}
