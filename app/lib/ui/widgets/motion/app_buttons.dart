import 'package:flutter/material.dart';

import 'elastic_press.dart';

/// 给任意可点组件套上 FlClash 的果冻手感：按住膨胀、能横向拽出去、松手弹回。
///
/// 用的是 [ElasticPress] 的**纯视觉模式** —— 它内部只有 [Listener]，
/// 不参与手势竞技场、不注册 tap，所以包在按钮/图标外面不会抢走点击。
/// 点击仍然由里面的组件自己处理。
class AppPressable extends StatelessWidget {
  const AppPressable({
    super.key,
    required this.child,
    this.enabled = true,
    this.haptic = true,
  });

  final Widget child;
  final bool enabled;
  final bool haptic;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return ElasticPress(haptic: haptic, child: child);
  }
}

/// [FilledButton] + 果冻。
///
/// 全站按钮统一走这几个包装，而不是各处手写 [ElasticPress]：
/// 参数名与 Material 版本一致，替换时只改类名。
class AppFilledButton extends StatelessWidget {
  const AppFilledButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
    this.autofocus = false,
    this.focusNode,
    this.statesController,
  })  : icon = null,
        label = null;

  const AppFilledButton.icon({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.style,
    this.autofocus = false,
    this.focusNode,
    this.statesController,
  }) : child = null;

  final VoidCallback? onPressed;
  final Widget? child;
  final ButtonStyle? style;
  final bool autofocus;
  final FocusNode? focusNode;
  final WidgetStatesController? statesController;
  final Widget? icon;
  final Widget? label;

  @override
  Widget build(BuildContext context) {
    final Widget button = icon != null && label != null
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: icon!,
            label: label!,
            style: style,
            autofocus: autofocus,
            focusNode: focusNode,
          )
        : FilledButton(
            onPressed: onPressed,
            style: style,
            autofocus: autofocus,
            focusNode: focusNode,
            child: child!,
          );
    return AppPressable(enabled: onPressed != null, child: button);
  }
}

/// [OutlinedButton] + 果冻。
class AppOutlinedButton extends StatelessWidget {
  const AppOutlinedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
    this.autofocus = false,
    this.focusNode,
  })  : icon = null,
        label = null;

  const AppOutlinedButton.icon({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.style,
    this.autofocus = false,
    this.focusNode,
  }) : child = null;

  final VoidCallback? onPressed;
  final Widget? child;
  final ButtonStyle? style;
  final bool autofocus;
  final FocusNode? focusNode;
  final Widget? icon;
  final Widget? label;

  @override
  Widget build(BuildContext context) {
    final Widget button = icon != null && label != null
        ? OutlinedButton.icon(
            onPressed: onPressed,
            icon: icon!,
            label: label!,
            style: style,
            autofocus: autofocus,
            focusNode: focusNode,
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: style,
            autofocus: autofocus,
            focusNode: focusNode,
            child: child!,
          );
    return AppPressable(enabled: onPressed != null, child: button);
  }
}

/// [TextButton] + 果冻。
class AppTextButton extends StatelessWidget {
  const AppTextButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
    this.autofocus = false,
    this.focusNode,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final ButtonStyle? style;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      enabled: onPressed != null,
      child: TextButton(
        onPressed: onPressed,
        style: style,
        autofocus: autofocus,
        focusNode: focusNode,
        child: child,
      ),
    );
  }
}

/// [IconButton] + 果冻（顶栏图标、返回箭头、列表行尾部动作）。
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.iconSize,
    this.color,
    this.tooltip,
    this.style,
    this.focusNode,
    this.isSelected,
    this.selectedIcon,
    this.constraints,
    this.padding,
    this.enableFeedback = true,
  });

  final VoidCallback? onPressed;
  final Widget icon;
  final double? iconSize;
  final Color? color;
  final String? tooltip;
  final ButtonStyle? style;
  final FocusNode? focusNode;
  final bool? isSelected;
  final Widget? selectedIcon;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? padding;
  final bool enableFeedback;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      enabled: onPressed != null,
      child: IconButton(
        onPressed: onPressed,
        icon: icon,
        iconSize: iconSize,
        color: color,
        tooltip: tooltip,
        style: style,
        focusNode: focusNode,
        isSelected: isSelected,
        selectedIcon: selectedIcon,
        constraints: constraints,
        padding: padding,
        enableFeedback: enableFeedback,
      ),
    );
  }
}
