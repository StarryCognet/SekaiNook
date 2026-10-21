// [gallery patch] 原文件 import 'dart:io' 并使用 Platform.isMacOS；
// web 平台无法编译 dart:io，展示站以 defaultTargetPlatform 等价替代（见文档「Web 适配」）。
import 'package:flutter/foundation.dart';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

SingleActivator controlSingleActivator(LogicalKeyboardKey trigger) {
  final control = defaultTargetPlatform == TargetPlatform.macOS ? false : true;
  return SingleActivator(trigger, control: control, meta: !control);
}
