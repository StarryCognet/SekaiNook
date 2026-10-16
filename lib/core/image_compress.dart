import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 图片压缩（对应 Web 版 `src/utils/image.ts`）。
///
/// 规则：长边超过 1600px 才缩放，统一输出 JPEG 质量 80。
/// 为什么要压：打卡照片直传 R2，原图动辄 5MB，上传接口上限就是 5MB。
/// 纯 Dart 实现（不依赖原生插件），所以 Flutter Web 与 Android 行为一致。
const int maxImageSide = 1600;
const int jpegQuality = 80;

/// 缩放并重新编码为 JPEG。解码失败返回 null（调用方提示用户换一张）。
Uint8List? compressImage(List<int> bytes) {
  final decoded = img.decodeImage(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
  if (decoded == null) return null;

  var output = decoded;
  if (decoded.width > maxImageSide || decoded.height > maxImageSide) {
    output = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: maxImageSide)
        : img.copyResize(decoded, height: maxImageSide);
  }

  return Uint8List.fromList(img.encodeJpg(output, quality: jpegQuality));
}
