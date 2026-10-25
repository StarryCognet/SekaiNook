import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// 图片压缩（对应 Web 版 `src/utils/image.ts`）。
///
/// 规则：长边超过 1600px 才缩放，统一输出 JPEG 质量 80。
/// 为什么要压：打卡照片直传 R2，原图动辄 5MB，上传接口上限就是 5MB。
/// 纯 Dart 实现（不依赖原生插件），所以 Flutter Web 与 Android 行为一致。
const int maxImageSide = 1600;
const int jpegQuality = 80;

/// 选图时让平台先把长边缩到 1600。
///
/// 这是整条图片链路里最值钱的一步：手机原图动辄 4000×3000，把整张图解码进
/// Dart 堆再缩放是主线程上最大的一笔开销。`image_picker` 的 maxWidth/maxHeight
/// 在 Android/iOS 走原生缩放、Web 走 canvas，比在 Dart 里解原图快一个数量级。
const int pickMaxSide = maxImageSide;
const int pickQuality = 85;

/// 选中的文件解不出图片（不是图片 / 文件损坏）。
class ImageUnreadableException implements Exception {
  const ImageUnreadableException();
}

/// 选一张图并压成 JPEG（长边 ≤ 1600）。取消选择返回 `null`。
///
/// picker 层已经缩过一次，这里再走一遍 [compressImage] 是为了统一成 JPEG 80；
/// 第二次编码的对象是 1600px 的小图，代价可忽略（双重编码肉眼看不出）。
/// 解不出图片时抛 [ImageUnreadableException]，调用方提示用户换一张。
Future<Uint8List?> pickCompressedImage(
  ImagePicker picker, {
  required ImageSource source,
}) async {
  final XFile? picked = await picker.pickImage(
    source: source,
    maxWidth: pickMaxSide.toDouble(),
    maxHeight: pickMaxSide.toDouble(),
    imageQuality: pickQuality,
  );
  if (picked == null) return null;
  final Uint8List raw = await picked.readAsBytes();
  final Uint8List? compressed = await compressImageAsync(raw);
  if (compressed == null) throw const ImageUnreadableException();
  return compressed;
}

/// 在后台 isolate 压缩（Android / iOS）。
///
/// Web 端 `compute` 会退化成同步执行（dart2js 没有 isolate），但这时 picker 的
/// canvas 预缩放已经把最贵的「解 12MP 原图」省掉了，剩下 1600px 小图的编码
/// 在主线程上也只是百毫秒级。
Future<Uint8List?> compressImageAsync(Uint8List bytes) =>
    compute<Uint8List, Uint8List?>(_compressTopLevel, bytes);

Uint8List? _compressTopLevel(Uint8List bytes) => compressImage(bytes);

/// 缩放并重新编码为 JPEG。解码失败返回 null（调用方提示用户换一张）。
Uint8List? compressImage(List<int> bytes) {
  final decoded = img.decodeImage(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
  if (decoded == null) return null;

  // 按 EXIF 方向摆正（L-2）：竖拍照片的 EXIF 里只写「转 90°」，
  // 不 bake 的话压缩后方向被压平，家人看到的照片是躺倒的。
  var output = img.bakeOrientation(decoded);
  if (output.width > maxImageSide || output.height > maxImageSide) {
    output = output.width >= output.height
        ? img.copyResize(output, width: maxImageSide)
        : img.copyResize(output, height: maxImageSide);
  }

  return Uint8List.fromList(img.encodeJpg(output, quality: jpegQuality));
}
