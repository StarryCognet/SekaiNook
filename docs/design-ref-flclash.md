# FlClash 视觉设计语言与动效实现参考

> 调研对象：[chen08209/FlClash](https://github.com/chen08209/FlClash)（Flutter 跨平台网络代理客户端，Material 3 Expressive 风格）
> 源码版本：`main` 分支，`pubspec.yaml version: 0.9.0+2026101401`，`sdk: '>=3.10.0 <4.0.0'`
> 取源方式：`codeload.github.com/chen08209/FlClash/tar.gz/refs/heads/main` 全量解压到本地工作副本后逐文件阅读
> 所有文件路径均相对仓库根目录，原始 Raw 地址形如 `https://raw.githubusercontent.com/chen08209/FlClash/main/<path>`

---

## 0. 一页速查

### 一句话结论

FlClash 的「高级感」**不是靠玻璃拟态或阴影堆出来的**，而是靠三件事：

1. **一套统一的圆角尺度**（`AppCorner` 6 档 + `ThemeData.withAppShapes` 一次性把 15 个组件的 shape 全部对齐，且用的是 M3 Expressive 的**超椭圆圆角** `RoundedSuperellipseBorder` 而不是普通 `RoundedRectangleBorder`）；
2. **一套统一的三级时长 + 弹簧曲线体系**（`100 / 200 / 300 ms` + `SpringCurve` + `Easing.emphasizedDecelerate`），所有动效都从这两个文件取参数；
3. **大量手写弹簧驱动的手势反馈**（按压是「膨胀」不是「缩小」，拖拽有橡皮筋和果冻形变），**零重型动画依赖**——只用官方 `animations` 包 + `dart:ui` + `flutter/physics`。

### 关键参数总表

| 类别 | 值 | 位置 |
|---|---|---|
| 圆角档位 | none 0 / xs 4 / sm 8 / md 16 / lg 20 / xl 24 / xxl 28 / full 1000 | `lib/common/shape.dart:6-26` |
| 卡片圆角 | 16 (`md`) | `shape.dart:252` |
| 对话框圆角 | 28 (`xxl`) | `shape.dart:254` |
| 底部弹层圆角 | 顶部 28，底部 0 | `shape.dart:255` |
| SnackBar 圆角 | 4 (`xs`) | `shape.dart:256` |
| Chip / Tooltip 圆角 | 8 / 4 | `shape.dart:258,260` |
| 按钮圆角 | `AppShape.full`（胶囊） | `shape.dart:296` |
| 输入框圆角 | 16 + 超椭圆 | `shape.dart:273` |
| 时长档 | 100 / 200 / 300 ms | `lib/common/constant.dart:102-104` |
| Tab 淡入淡出 | 220 ms / `Curves.easeInOut` | `lib/common/motion.dart:4-5` |
| 页面转场 | 450 ms / `easeInOutCubicEmphasized` | `lib/widgets/page_transition.dart:19,41` |
| SharedAxis 转场 | 官方默认 300 ms | `lib/common/navigator.dart:84` |
| 桌面 Route 转场 | 200 ms | `lib/common/navigator.dart:117-121` |
| 侧边栏展开 | 250 ms | `lib/widgets/sidebar.dart:20` |
| 侧边栏指示器 | 320 ms | `lib/widgets/sidebar.dart:21` |
| 列表增删 | 300 ms / in `easeOutCubic` out `easeInCubic` | `lib/widgets/keyed_animated_list.dart:5,61-68` |
| 按压提升弹簧 | 280 ms bounce 0.2 | `navigation_dock.dart:65-68` |
| 松手回弹弹簧 | 500 ms bounce 0.32 | `navigation_dock.dart:69-72` |
| 拖拽跟手弹簧 | 120 ms | `navigation_dock.dart:61-63` |
| 悬浮弹簧 | 260 ms bounce 0.18 | `navigation_dock.dart:73-76` |
| 文字缩放钳制 | 0.8 ~ 1.4 | `lib/manager/theme_manager.dart:47-59` |

---

## 1. 依赖清单（pubspec.yaml 中与 UI / 动效相关）

```yaml
dependencies:
  material_ui: ^1.5.0              # M3 Expressive 组件：RoundedSuperellipseBorder / Easing / DualTransitionBuilder / ButtonStyle 扩展
  material_new_shapes: ^1.0.0      # 新形状（超椭圆等）
  material_color_utilities: ^0.13.0 # Hct / harmonizeWith，配合 fromSeed 调色
  dynamic_color: ^2.1.0            # Android Monet 动态取色
  animations: ^3.0.0               # 官方动画包：SharedAxisPageTransitionsBuilder / FadeThroughTransition / PageTransitionSwitcher
  super_sliver_list: ^0.4.1        # 大列表高性能 sliver
  flutter_svg: ^2.3.0
  flutter_riverpod / riverpod: ^3.4.3
  # 其余非 UI：drift, dio, shared_preferences, intl, collection, crypto, yaml, freezed,
  #            file_picker, mobile_scanner, url_launcher, package_info_plus, device_info_plus,
  #            connectivity_plus, flutter_cache_manager, re_highlight, emoji_regex,
  #            uni_platform, archive, ffi, win32
```

**没有用**：`flutter_animate`、`shimmer`、`auto_animated`、`lottie`、`rive`、`getwidget`、`flutter_staggered_animations`。

👉 对 SekaiNook 的意义：FlClash 证明**只要 `animations: ^3.0.0` 一个包 + 手写 `AnimationController`/`SpringSimulation`，就能做出全套高级动效**。你现在连 `animations` 都没有，加它一个（纯官方、体积小）即可复刻本文绝大部分手法。

字体（`pubspec.yaml` 的 `fonts:` 段）**只声明了两个**，都不是界面正文字体：

```yaml
  fonts:
    - family: JetBrainsMono   # 仅用于代码/配置文本
      fonts: [assets/fonts/JetBrainsMono-Regular.ttf]
    - family: Twemoji         # emoji 彩色字形
      fonts: [assets/fonts/Twemoji.Mozilla.ttf]
```

正文**完全使用系统字体**，只在 `lib/common/font.dart` 做「汉字字形兜底」：

```dart
// lib/common/font.dart:67-78（节选）
String? appFontFamilyFallback({TargetPlatform? platform, List<Locale>? locales, String? fontFamily}) {
  final typography = Typography.material2021(platform: platform).black.bodyMedium!;
  // 以 bodyMedium 的 fontFamily / fontFamilyFallback 为基底，再拼上按 locale 选出的汉字字体族
}
```

`_HanFamilies` 按平台 × 4 种汉字变体（简体 / 繁体 / 日文 / 韩文）列出系统字体族（Windows: Microsoft YaHei UI / JhengHei UI / Yu Gothic UI / Malgun Gothic；macOS: PingFang SC/TC、Hiragino Sans、Apple SD Gothic Neo；Linux: Noto Sans CJK 系列），`_hanVariantOf(locales)` 用 `languageCode` + `scriptCode('Hant'/'Hans')` + `countryCode(TW/HK/MO)` 判繁简。注释里点明了这么做的原因：**系统兜底会按 UI locale 挑字形，英文界面下会把中文用户数据画成日文字形**。

> 🔧 对 SekaiNook：这条思路很值——不用引字体文件，只把「按 locale 拼 CJK 兜底族」这一段加上，就能解决中/英/日混排时的字形错乱。Android 上可以简化为给 `fontFamilyFallback` 追加 `['Noto Sans CJK SC', 'Noto Sans SC', 'sans-serif']`。

---

## 2. 整体设计语言

### 2.1 Material 3 + `ColorScheme.fromSeed`，不是自定义 ColorScheme

`lib/application.dart:205-220`：

```dart
MaterialApp(
  theme: ThemeData(
    useMaterial3: true,
    pageTransitionsTheme: _pageTransitionsTheme,
    actionIconTheme: _actionIconTheme,
    colorScheme: _getAppColorScheme(Brightness.light),
    fontFamily: themeProps.fontFamily,
    fontFamilyFallback: fontFamilyFallback,
  ).withAppShapes,
  darkTheme: /* 同上，Brightness.dark */,
  themeMode: themeProps.themeMode,
  scrollBehavior: const BaseScrollBehavior(),
  home: KeyboardInsetHold(child: HomePage()),
)
```

`useMaterial3: true`，配色**全部由 `ColorScheme.fromSeed` 生成**，没有任何硬编码的 `ColorScheme` 常量。`lib/providers/state/theme.dart:29-64`：

```dart
ColorScheme genColorScheme(Ref ref, Brightness brightness, {Color? color, bool ignoreConfig = false, bool pureBlack = false}) {
  // 种子色优先级：显式 color > themeSetting.primaryColor > dynamicColor.lightSeed/darkSeed > dynamicColor.accentColor
  return ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
    dynamicSchemeVariant: variant,
  ).toPureBlack(pureBlack);
}
```

三个要点值得抄：

1. **种子色有一条明确的优先级链**（显式传入 → 用户设置 → 系统 Monet → 系统强调色），任何一层缺失都能回落到下一层；
2. **动态取色是「种子」而不是「整套色板」**——`dynamic_color` 拿到的只是 accent color，仍然走 `fromSeed` 生成完整 M3 色板，所以用户自己换主色和跟随系统壁纸在代码路径上完全一致（`lib/bootstrap.dart:46-88` 的 `_initDynamicColor()` 只在 Android 上调 `DynamicColorPlugin.getAccentColor()`）；
3. **`ColorScheme` 有 LRU 缓存**：

```dart
// lib/providers/state/theme.dart:66-90 附近
const _maxCachedColorSchemes = 64;
// key = (seedColor, brightness, variant, pureBlack)
```

`ColorScheme.fromSeed` 是纯计算且不便宜，而 FlClash 的主题预览页要把几十个色块各生成一套深/浅色板，所以必须缓存。**这是个很实际的性能细节**——颜色选择器/主题预览类的 UI 一定要缓存，否则滑动时会掉帧。

另外有 `pureBlack` 开关（`ColorScheme.toPureBlack(bool)` 扩展）：深色模式下把 surface 系列压成纯黑，这是 OLED 屏的常见需求。

### 2.2 表面层级的分法：只按「角色」取色，不按「深浅」取色

FlClash 从不写 `Colors.grey[100]`，而是严格使用 M3 的角色 token，形成一套稳定约定：

| 用途 | 取的 token |
|---|---|
| 页面底色 | `surface` |
| 普通卡片 | `surfaceContainerLow` |
| 实心卡片（FilledButton 形态） | `surfaceContainerHigh` |
| 选中态卡片 | `secondaryContainer` |
| 卡片描边（静息） | `surfaceContainerHighest` |
| 卡片描边（hover/pressed） | `primary.opacity60` → `primary.opacity80`（选中时） |
| 侧边栏/底栏模糊色调 | `surfaceContainer` |
| 骨架屏占位 | `surfaceContainerHighest` |
| 错误态描边 | `error.opacity30 / 60 / 80` |

`lib/widgets/card.dart:131-198`（`CommonCard`）：

```dart
Color? _buildBackgroundColor(BuildContext context) {
  final colorScheme = context.colorScheme;
  if (type == CommonCardType.filled) {
    if (isSelected) return colorScheme.secondaryContainer.opacity80;
    return colorScheme.surfaceContainerHigh;
  }
  if (isSelected) return colorScheme.secondaryContainer;
  return colorScheme.surfaceContainerLow;
}

BorderSide _buildBorderSide(BuildContext context, Set<WidgetState> states) {
  final colorScheme = context.colorScheme;
  if (type == CommonCardType.filled) return BorderSide.none;
  final hoverColor = isSelected ? colorScheme.primary.opacity80 : colorScheme.primary.opacity60;
  if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused) || states.contains(WidgetState.pressed)) {
    return BorderSide(color: hoverColor);
  }
  return BorderSide(color: isSelected ? colorScheme.primary : colorScheme.surfaceContainerHighest);
}
```

**层级思路总结（可直接搬到任一套自研色板）：**
用「底色 → 容器色 → 容器高色 → 选中色」四级，而不是靠阴影区分。**选中态用 accent 容器色 + 1px accent 描边表达，而不是加阴影或加深底色。**

FlClash 还常在色板内做「压暗派生」，集中在 `lib/common/theme.dart:11-48`：

```dart
class CommonTheme {
  Color get darkenSecondaryContainer        => secondaryContainer.blendDarken(factor: 0.1);
  Color get darkenSecondaryContainerLighter => secondaryContainer.blendDarken(factor: 0.1).opacity60;
  Color get darken2SecondaryContainer       => secondaryContainer.blendDarken(factor: 0.2);
  Color get darken3PrimaryContainer         => primaryContainer.blendDarken(factor: 0.3);
}
// blendDarken 见 lib/common/color.dart：
//   Color.lerp(this, brightness == Brightness.dark ? Colors.white : Colors.black, factor)
```

注意 `blendDarken` 在暗色模式下是**向白色 lerp**（即提亮），配上一个带缓存的 `_colorMap`（`updateCacheValue`）——所以它并不真的「darken」，而是「向对比方向推」。**这正是 ThemeExtension 该干的事**，SekaiNook 的 `AppPalette` 可以直接照这个思路补 3~4 个派生色字段。

### 2.3 圆角尺度：单一来源 + 一次注满主题

`lib/common/shape.dart` 是**全项目圆角唯一来源**，其他任何文件都不写裸数字圆角。

```dart
// lib/common/shape.dart:6-26
class AppCorner {
  static const double none = 0;
  static const double xs   = 4;
  static const double sm   = 8;
  static const double md   = 16;
  static const double lg   = 20;
  static const double xl   = 24;
  static const double xxl  = 28;
  static const double full = 1000;

  /// 按容器最短边自适应降档：limit = shortestSide / 3，从 xxl 逐级下取
  static double fit(double shortestSide) { ... }
}
```

`AppShape` 把这些数值包成 `OutlinedBorder`，关键在于它用的是 **M3 Expressive 的超椭圆**（不是普通圆角矩形）：

```dart
// lib/common/shape.dart:66-107（节选）
class AppShape {
  static const OutlinedBorder md = RoundedSuperellipseBorder(borderRadius: AppRadius.md);
  static const OutlinedBorder xxl = RoundedSuperellipseBorder(borderRadius: AppRadius.xxl);
  static const OutlinedBorder circle = CircleBorder();
  static OutlinedBorder all(double r) => RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(r));
  static OutlinedBorder top(double r) => RoundedSuperellipseBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(r)));
  static const InputBorder input = AppInputBorder();
}
```

> 超椭圆（squircle）与普通圆角矩形的差别在**曲率连续**：普通圆角在直边与圆弧的接点有一阶不连续，视觉上会有个「硬拐点」；超椭圆是平滑过渡。这就是 FlClash 看起来比一般 Material 应用「贵」的一大原因。`material_ui` 包提供了 `RoundedSuperellipseBorder`；Flutter 3.32+ 在 `flutter/painting` 里也有实验性的 `RoundedSuperellipseBorder`，可以检查 SDK 版本后直接用、省掉依赖。

**然后是整份文档里最值得直接照抄的一段** —— `lib/common/shape.dart:250-304`，一个 `ThemeData` 扩展把圆角一次性铺满全主题：

```dart
extension AppShapeThemeExt on ThemeData {
  ThemeData get withAppShapes => copyWith(
    cardTheme: cardTheme.copyWith(shape: AppShape.md),                              // 16
    dialogTheme: dialogTheme.copyWith(shape: AppShape.xxl),                         // 28
    bottomSheetTheme: bottomSheetTheme.copyWith(
      shape: AppShape.top(AppCorner.xxl)),                                          // 顶部 28 / 底部 0
    snackBarTheme: snackBarTheme.copyWith(shape: AppShape.xs),                      // 4
    tooltipTheme: tooltipTheme.copyWith(
      decoration: ShapeDecoration(
        shape: AppShape.xs,
        color: switch (brightness) {
          Brightness.dark  => Colors.white.withAlpha(230),
          Brightness.light => Colors.grey[700]!.withAlpha(230),
        },
      ),
    ),
    chipTheme: chipTheme.copyWith(shape: AppShape.sm),                              // 8
    popupMenuTheme: popupMenuTheme.copyWith(shape: AppShape.md),                    // 16
    menuTheme: MenuThemeData(
      style: (menuTheme.style ?? const MenuStyle())
          .copyWith(shape: const WidgetStatePropertyAll(AppShape.md)),
    ),
    inputDecorationTheme: inputDecorationTheme.copyWith(border: AppShape.input),
    floatingActionButtonTheme: floatingActionButtonTheme.copyWith(shape: AppShape.md),
    navigationBarTheme: navigationBarTheme.copyWith(indicatorShape: AppShape.full),
    navigationRailTheme: navigationRailTheme.copyWith(indicatorShape: AppShape.full),
    progressIndicatorTheme: progressIndicatorTheme.copyWith(borderRadius: AppRadius.full),
    filledButtonTheme: filledButtonTheme.copyWith(style: /* merge _pillButton */),
    textButtonTheme: /* ... */,
    outlinedButtonTheme: /* ... */,
    elevatedButtonTheme: /* ... */,
    iconButtonTheme: /* ... */,
  );
}

const _pillButton = ButtonStyle(shape: WidgetStatePropertyAll(AppShape.full));
```

配套的自定义输入框边框（`AppInputBorder extends InputBorder`，`shape.dart:109-248`）值得一读：它内部也用 `RoundedSuperellipseBorder`，并用 `clipRect(..., clipOp: ClipOp.difference)` 在描边上「挖」出浮动 label 的缺口，缺口深度 `= max(topLeft.y, topRight.y) + borderSide.width`。

### 2.4 卡片/容器的视觉：无玻璃、无 elevation、只有 1px 描边

- **没有** `BackdropFilter` 玻璃拟态（唯一用到模糊的地方是 `imageFilter` 做「材质化」过渡，见 §3.5，以及可选的开窗模糊 `feature.sidebarBlur`）；
- **卡片一律 `elevation: 0`**（`card.dart:230,263`），层级全靠背景色 + 描边；
- 唯一的阴影是给**浮动底栏**的，且刻意做成 iOS 风格的「大而软」而不是 Material elevation（`navigation_dock.dart:170-185`）：

```dart
/// A soft, wide drop in the manner of iOS rather than a Material elevation.
List<BoxShadow> _dockShadows(ColorScheme colorScheme) {
  final strength = colorScheme.brightness == Brightness.dark ? 3.0 : 1.0;  // 暗色下阴影加 3 倍
  return [
    BoxShadow(color: colorScheme.shadow.withValues(alpha: 0.08 * strength), blurRadius: 24, offset: const Offset(0, 8)),
    BoxShadow(color: colorScheme.shadow.withValues(alpha: 0.04 * strength), blurRadius: 3,  offset: const Offset(0, 1)),
  ];
}
```

👉 两条可直接用的经验：**(a)** 暗色模式下阴影必须加重，否则完全看不见；**(b)** 用「24px 大模糊 + 8px 下移」的软投影代替 `elevation`，观感高级且不依赖 Material 的 elevation 计算。

- 分割线用 `outlineVariant`；选中态用 `AppShape.circle` 的 `Material(color: inversePrimary)` 打勾徽标（`card.dart:375-389`）。

### 2.5 字体与字号层级

- 无自定义显示字体（见 §1），字号层级**完全走 `Typography.material2021`**，业务代码通过 `context.sectionHeaderStyle` 这类语义化 getter 取值，不写裸 `fontSize`；
- 唯一的自定义排版常量在底栏：`_labelSize = 10`、`_minLabelSize = 9`、`_iconSize = 24`（`navigation_dock.dart:22-27`），并用 `TextPainter` + `MediaQuery.textScalerOf` 预先测量文字宽度来做自适应布局（`_measureLabel`，`navigation_dock.dart:187-201`）——**这是让自定义栏位在用户放大字号后依然不溢出的正确做法**；
- 全局字号缩放是**钳制**的（`lib/manager/theme_manager.dart:47-59`）：`max(min(用户设置或系统值, 1.4), 0.8)`。理由很实在：无障碍要求支持大字号，但超过 1.4 后大量横排布局必崩，所以给一个上限，同时用上面的 `TextPainter` 方案兜底。

---

## 3. 动效（重点）

### 3.1 基础：三级时长 + 无障碍总开关

`lib/common/constant.dart:102-104`：

```dart
const animateDuration = Duration(milliseconds: 100);  // 微反馈
const midDuration     = Duration(milliseconds: 200);  // 小范围状态切换
const commonDuration  = Duration(milliseconds: 300);  // 常规进场/切换
```

**所有**动画时长都经过一个 context 扩展，以便统一响应系统的「减弱动效」无障碍设置（`lib/common/context.dart:86-89`）：

```dart
bool get disableAnimations => MediaQuery.disableAnimationsOf(this);
Duration motionDuration(Duration duration) => disableAnimations ? Duration.zero : duration;
```

用法：`duration: context.motionDuration(commonDuration)`。同时所有自定义入场组件在 `build` 开头都有 `if (context.disableAnimations) return widget.child;`（`fade_box.dart:173-175,244-246`），`_EnterAnimation` mixin（`fade_box.dart:180-197`）则在 `didChangeDependencies` 里直接把 controller 拉到 `upperBound`。

> 🔧 这是**最容易被忽略但访谈里最容易被夸**的一点。SekaiNook 只需要加一个 `context.motionDuration()` 扩展 + 在每个自定义动画 build 开头短路，就同时拿到了无障碍合规和一个统一的「动效总开关」。

### 3.2 路由转场

两个层次：

**(a) 移动端 / 通用路由** — 直接用官方 `animations` 包的 SharedAxis（`lib/common/navigator.dart:84-87`）：

```dart
const commonSharedXPageTransitions = SharedAxisPageTransitionsBuilder(
  transitionType: SharedAxisTransitionType.horizontal,
  fillColor: Colors.transparent,   // 必须显式设透明：M3 默认会填 surface 色，导致新旧页叠加时底色跳动
);
```

挂载（`lib/application.dart:84-91`）：

```dart
const _pageTransitionsTheme = PageTransitionsTheme(builders: {
  TargetPlatform.android: commonSharedXPageTransitions,
  TargetPlatform.windows: commonSharedXPageTransitions,
  TargetPlatform.linux:  commonSharedXPageTransitions,
  TargetPlatform.macOS:  commonSharedXPageTransitions,
});
```

**注意 iOS 被刻意排除**，保留 Cupertino 原生手势返回。SharedAxis 官方默认时长 300 ms。

**(b) 桌面端自定义 Route** — `CommonDesktopRoute`（`lib/common/navigator.dart:92-122`），前/后向均 200 ms，且把「拖拽返回」和转场绑在一起：

```dart
@override
Duration get transitionDuration => const Duration(milliseconds: 200);
@override
Duration get reverseTransitionDuration => const Duration(milliseconds: 200);

@override
Widget buildTransitions(BuildContext context, Animation<double> animation,
    Animation<double> secondaryAnimation, Widget child) {
  return dragBackDetector(
    isDragBackActive ? dragBackSlide(context, animation, child)
                     : FadeTransition(opacity: animation, child: child),
  );
}
```

**(c) 手写的 Android 14 风格共享轴转场** — `SharedXPageTransition`（`lib/widgets/page_transition.dart`，303 行）是全项目最精致的一段转场，值得单独看：

```dart
// lib/widgets/page_transition.dart:19-65（节选）
static const duration = Duration(milliseconds: 450);

/// Android 14's page slide, as FadeForwardsPageTransitionsBuilder has it.
static const pageSlide = Offset(0.25, 0);          // 位移 = 页宽的 25%

static final _slideCurve = CurveTween(curve: Curves.easeInOutCubicEmphasized);
static const _fadeInCurve  = Interval(0.15, 0.55, curve: Curves.easeOutCubic);
static const _fadeOutCurve = Interval(0, 0.3);
static final _fadeIn  = CurveTween(curve: _fadeInCurve);
static final _fadeOut = Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: _fadeOutCurve));

// 两个页面的淡入淡出在 1/5 处交接，此时两页各三分之一不透明；
// 上层页只在自己那一侧显示，所以不会出现「双影」。
static const _handOver = 0.2;
```

配套的 `_HandOver` 曲线（`page_transition.dart:152-166`）就是实现「交接点」的小工具：

```dart
class _HandOver extends Curve {
  const _HandOver(this.curve, {required this.at, required this.leaving});
  final Curve curve; final double at; final bool leaving;
  @override
  double transformInternal(double t) {
    if (leaving) return t < at ? curve.transform(t) : 1;
    return t < at ? 0 : curve.transform(t);
  }
}
```

还有一个**性能层面的关键技巧**，代码注释写得很清楚（`page_transition.dart:4-6`）：

> Slides pages by `slide` while they fade. A page fades by laying `color` over it wherever only that color lies beneath, **since an opacity layer costs Impeller an offscreen pass of the page every frame**.

也就是说，它**不用 `Opacity`/`FadeTransition` 做页面淡出**，而是用 `_PageFade`（一个 `RenderProxyBox`）在页面上「刷一层背景色」来模拟淡出，避免每帧为整页开离屏层（`page_transition.dart:186-302`）：

```dart
@override
void paint(PaintingContext context, Offset offset) {
  final opacity = _opacity.value;
  if (child == null || opacity == 0) return;
  if (opacity == 1) { super.paint(context, offset); return; }
  if (_opaque) context.canvas.drawRect(offset & size, Paint()..color = _color);
  super.paint(context, offset);
  context.canvas.drawRect(offset & size,
      Paint()..color = _color.withValues(alpha: _color.a * (1 - opacity)));
}
```

👉 如果 SekaiNook 的 Web 端转场掉帧，这条是最直接的解药：**整页级淡出不要用 `FadeTransition`，改成在页面上画一层颜色**。（Flutter Web 用 CanvasKit 时同样有 offscreen 开销。）

### 3.3 导航：三种不同的选中指示器，全部手写

FlClash 里导航有四种形态（侧边栏 / 浮动底栏 / 普通底栏 / 导航轨道），指示器做法各不相同。

**(a) 侧边栏竖条指示器：会「拉伸」的指示器**（`lib/widgets/sidebar.dart:485-564`）——最值得抄的一段，因为它比「滑动一个固定尺寸的色块」高级得多：

```dart
const _indicatorWidth    = 3.0;
const _indicatorHeight   = 16.0;
const _expandDuration    = Duration(milliseconds: 250);
const _indicatorDuration = Duration(milliseconds: 320);

/// The indicator moves by stretching toward the new row before its trailing
/// edge catches up, rather than sliding at a fixed size.
class _SelectionIndicatorState extends State<_SelectionIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this, duration: _indicatorDuration, value: 1);
  late int _from = widget.index;

  @override
  void didUpdateWidget(covariant _SelectionIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _from = oldWidget.index;
      _controller.forward(from: 0);
    }
  }

  double _topOf(int index) =>
      index * widget.stride + (widget.stride - _indicatorHeight) / 2;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final from = _topOf(_from);
        final to   = _topOf(widget.index);
        // 前缘 60% 就走完（easeOutCubic），后缘从 35% 才开始追（easeInOutCubic）
        final lead  = Curves.easeOutCubic.transform(math.min(1, t / 0.6));
        final trail = Curves.easeInOutCubic.transform(math.max(0, (t - 0.35) / 0.65));
        final (top, bottom) = to >= from
            ? (lerpDouble(from, to, trail)!, lerpDouble(from, to, lead)!)
            : (lerpDouble(from, to, lead)!,  lerpDouble(from, to, trail)!);
        return PositionedDirectional(
          start: widget.start, top: top,
          width: _indicatorWidth,
          height: bottom - top + _indicatorHeight,   // 高度随时间先变长再变短
          child: child!,
        );
      },
      child: IgnorePointer(child: DecoratedBox(
        decoration: ShapeDecoration(color: widget.color, shape: AppShape.full))),
    );
  }
}
```

**原理**：把指示器当成一条线段，`top` 和 `bottom` 用**两条不同的缓动**分别插值。因为前缘追得快、后缘追得慢，线段会先被拉长、再收回——视觉上像「一根橡皮筋被甩过去」。

**(b) 浮动底栏的「镜头（lens）」**（`navigation_dock.dart:672-676` 的类注释）：

> A floating pill of destinations whose selection is a lens that springs between them, after iOS's tab bar. Pressing swells the bar as `ElasticPress` does and **lifts the lens under the finger; dragging slides the lens across the bar**, selecting where it is let go, and stretches the bar past either end.

相关常量（`navigation_dock.dart:30-38`）：`_lensGrowth = 14`、`_lensMagnify = 0.12`、`_hoverMagnet = 0.2`、`_hoverParallax = 0.5`、`_hoverAlpha = 0.08`、`_hoverSwell = 0.4`、`_jellySpeed = 8`、`_jellyStretch = 0.25`、`_overdrag = 0.35`、`_flingProjection = Duration(milliseconds: 100)`。

镜头本体只是一个**被弹簧驱动位置的胶囊**（`navigation_dock.dart:1100-1143`）：

```dart
class _Lens extends StatelessWidget {
  // ...
  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final rect = _lensRect(position: position, velocity: velocity,
                          extent: extent, height: height, lift: lift);
    return PositionedDirectional(
      start: rect.left, top: rect.top, width: rect.width, height: rect.height,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: Color.alphaBlend(
            colorScheme.onSecondaryContainer.withValues(alpha: 0.08 * lift.clamp(0.0, 1.0)),
            colorScheme.secondaryContainer,
          ),
          shape: AppShape.full,
        ),
      ),
    );
  }
}
```

注意 **`Color.alphaBlend` 做「按下加深」**：底是 `secondaryContainer`，上面叠 8% 的 `onSecondaryContainer`，并且用 `lift` 控制叠加强度——比切换两个颜色要连续、没有跳变。

浮起用的柔光/放大是另一个独立 sweep：`_LensTint`（`navigation_dock.dart:1297-1355`）与 `_HoverHighlight`（`navigation_dock.dart:1067-1098`，用 `onSurface.withValues(alpha: 0.08 * opacity)` 画一个 `AppShape.full` 的高亮）。

> 底栏几何常量（`navigation_dock.dart:14-28`）：`_barHeight = 62`、`_barPadding = 4`、`_edgeMargin = 21`、`_shadowRoom = 8`、`_fabGap = 8`、`_hitSlop = 8`、`_maxItemExtent = 72`、`_fullWidthCount = 5`、`_iconSize = 24`、`_trailingIconSize = 28`、`_labelGap = 2`、`_labelInset = 2`、`_labelSize = 10`、`_minLabelSize = 9`、`_pressGrowth = 1/8`、`_maxPressGrowth = 16`。

**(c) 普通底栏 / 轨道** —— 直接用主题里的 `indicatorShape: AppShape.full`（见 §2.3），即 M3 自带的胶囊指示器，不额外手写。

### 3.4 列表动效：按 key 做 diff 的增删动画 + 自动「滑动让位」

`lib/widgets/keyed_animated_list.dart`（402 行）是一个**不依赖 `AnimatedList`**、完全自建的列表动画组件。核心注释（`:10-12`）：

> A lazily built vertical list that diffs `items` by key: removed items collapse out, inserted items grow in, and items whose key survives slide from their previous slot to the new one.

```dart
const _defaultDuration = Duration(milliseconds: 300);
// Rows sized towards zero all fit the viewport, so each one is laid out.
const _maxAnimatedChanges = 50;   // 变更超过 50 条就放弃逐条动画，直接整体替换
```

```dart
// keyed_animated_list.dart:54-68
late final AnimationController _transition =
    AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((status) { if (status.isCompleted) setState(_settle); });
late final CurvedAnimation _entering = CurvedAnimation(parent: _transition, curve: Curves.easeOutCubic);
late final CurvedAnimation _leaving  = CurvedAnimation(
    parent: ReverseAnimation(_transition), curve: Curves.easeInCubic);
```

行本身的进出用 **`SizeTransition` + `FadeTransition`，且 `alignment: Alignment.topCenter`**（`:161-186`）：

```dart
Widget _buildRow(BuildContext context, int index) {
  final entry = _entries[index];
  Widget row = widget.itemBuilder(context, entry.item);
  if (separator != null && index < _entries.length - 1) {
    row = Column(mainAxisSize: MainAxisSize.min, children: [row, separator]);
  }
  final animation = switch (entry.phase) {
    _Phase.settled  => null,
    _Phase.entering => _entering,
    _Phase.leaving  => _leaving,
  };
  if (animation != null) {
    row = SizeTransition(sizeFactor: animation, alignment: Alignment.topCenter,
        child: FadeTransition(opacity: animation, child: row));
  }
  return _SlideOnMove(key: ValueKey(entry.key), generation: _generation,
      duration: widget.duration, child: row);
}
```

`_maxAnimatedChanges` 这个上限是**非常实用的一笔**：一次性刷新几百行时逐条动画反而是负优化，所以超过阈值直接 `_replaceItems`（`:102-108`）跳过动画。

`_SlideOnMove`（`:205-402`）解决的是「列表重排后，幸存的元素如何平滑滑到新位置」——这是一个用 `RenderProxyBox` 手写的实现，思路是**在 paint 阶段量出自己在滚动内容中的偏移，跨 generation 记下发前/发后差值，然后在 paint 时用 `pushTransform` 平移**，并且平移量按 `Curves.easeOutCubic` 衰减到 0：

```dart
double get _translation {
  if (_startPending) return _delta;
  if (!_controller.isAnimating) return 0;
  return _delta * (1 - Curves.easeOutCubic.transform(_controller.value));
}

@override
void paint(PaintingContext context, Offset offset) {
  final current = _contentOffset();
  _settlePendingMove(current);
  _lastOffset = current;
  final translation = _translation;
  if (translation.abs() < 0.5) { super.paint(context, offset); return; }
  context.pushTransform(needsCompositing, offset,
      Matrix4.translationValues(0, translation, 0), super.paint);
}
```

它还重写了 `applyPaintTransform` 和 `hitTestChildren`，保证点击位置随形变一起偏移——**这是「视觉动画」与「命中测试」保持一致的正确做法**，很多手写动画会漏掉导致点错。

> 🔧 对 SekaiNook：这套 `_SlideOnMove` 的完整实现较复杂（要处理 sliver 的 layoutOffset 生命周期）。**建议先用它的轻量版**：`AnimatedSize` + `AnimatedSwitcher`，或者给每行套 `FadeScaleEnterBox` 做进场即可；等列表确实需要「重排让位」时再移植 `_SlideOnMove`。

### 3.5 列表/卡片进场：三个现成包装组件

`lib/widgets/fade_box.dart`（326 行）是一整套「进场包装」工具箱，命名即用途：

| 组件 | 效果 | 实现要点 |
|---|---|---|
| `FadeBox` | 纯淡入淡出 | `AnimatedSwitcher`，in `easeOut` / out `easeIn`，300 ms |
| `FadeThroughBox` | 淡出穿透（旧先淡出，新再淡入） | 官方 `PageTransitionSwitcher` + `FadeThroughTransition` |
| `FadeScaleBox` | 淡入 + 缩放 | scale `0.4 → 1`，in `easeInBack` / out `easeOutBack` |
| `FadeRotationScaleBox` | 淡入 + 旋转 + 缩放 | turns `0.8 → 1.0`，opacity `0.6 → 1.0`，in `easeOutBack` |
| `FadeScaleEnterBox` | 单次进场 | 见下 |
| `FadeSlideEnterBox` | 单次进场 + 位移 + 可延时 | 见下（做 staggered 用这个） |

**（a）`FadeScaleEnterBox` / `FadeScaleEnterTransition`（`:140-178, 298-326`）**

```dart
class _FadeScaleEnterBoxState extends State<FadeScaleEnterBox>
    with SingleTickerProviderStateMixin, _EnterAnimation {
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: commonDuration); // 300ms
    _animation = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }
  @override
  Widget build(BuildContext context) {
    if (context.disableAnimations) return widget.child;
    return FadeScaleEnterTransition(animation: _animation, child: widget.child);
  }
}

class FadeScaleEnterTransition extends StatelessWidget {
  static final Animatable<double> _fadeInTransition =
      CurveTween(curve: const Interval(0.0, 0.3));
  static final Animatable<double> _scaleInTransition = Tween<double>(begin: 0.70, end: 1.00)
      .chain(CurveTween(curve: Easing.legacyDecelerate));

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fadeInTransition.animate(animation),
    child: ScaleTransition(scale: _scaleInTransition.animate(animation), child: child),
  );
}
```

**关键**：**透明度用 `Interval(0, 0.3)` 在前 30% 就走完，缩放用 `(0.70 → 1.00)` 且缓动为减速型**。这两个「非同步」是高级感的来源——同步的 fade+scale 看起来廉价，分离后才有「浮现」感。

**（b）`FadeSlideEnterBox` / `FadeSlideEnterTransition`（`:199-296`）——做 staggered 就靠它的 `delay`**

```dart
const _defaultSlideDistance = 24.0;

class _FadeSlideEnterBoxState extends State<FadeSlideEnterBox>
    with SingleTickerProviderStateMixin, _EnterAnimation {
  @override
  void initState() {
    super.initState();
    final total = commonDuration + widget.delay;                   // 延时被算进总时长
    _controller = AnimationController(vsync: this, duration: total);
    final start = widget.delay.inMicroseconds / total.inMicroseconds;
    _animation = start == 0 ? _controller.view
                            : _controller.drive(CurveTween(curve: Interval(start, 1)));
  }
  // build 里 return FadeSlideEnterTransition(animation: _animation, distance: widget.distance, axis: widget.axis, child: ...)
}

class FadeSlideEnterTransition extends StatelessWidget {
  static final Animatable<double> _fadeInTransition = CurveTween(curve: const Interval(0.0, 0.25));
  static final Animatable<double> _slideInCurve    = CurveTween(curve: Easing.emphasizedDecelerate);

  @override
  Widget build(BuildContext context) {
    final begin = axis == Axis.horizontal ? Offset(-distance, 0) : Offset(0, distance);
    final slide = Tween<Offset>(begin: begin, end: Offset.zero)
        .chain(_slideInCurve).animate(animation);
    return FadeTransition(
      opacity: _fadeInTransition.animate(animation),
      child: AnimatedBuilder(
        animation: slide,
        builder: (_, child) => Transform.translate(offset: slide.value, child: child),
        child: child,
      ),
    );
  }
}
```

**参数**：位移 24 px（水平默认从左侧 `-24` 滑入）、淡入只占前 25%、位移用 `Easing.emphasizedDecelerate`（M3 强调型减速曲线）。staggered 的用法就是给第 n 个元素 `delay: Duration(milliseconds: 40 * n)`——**不需要任何第三方 staggered 包**。

**（c）`_EnterAnimation` mixin（`:180-197`）—— 保证「只进场一次」且无障碍安全**

```dart
mixin _EnterAnimation<T extends StatefulWidget> on State<T> {
  AnimationController get _controller;
  bool _entered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entered) return;
    _entered = true;
    if (context.disableAnimations) {
      _controller.value = _controller.upperBound;   // 直接到终态，不播
    } else {
      _controller.forward();
    }
  }
}
```

用 `didChangeDependencies` 而不是 `initState` 是为了能读 `context`（`MediaQuery`）。**「只播一次」的 `_entered` 标志**也是必需的：否则任何 `MediaQuery` 变化（键盘弹出、旋转）都会重播动画。

**（d）进场动画在业务里的接法**（`lib/widgets/card.dart:337-341`）：

```dart
return switch (enterAnimated) {
  true  => FadeScaleEnterBox(child: card),
  false => card,
};
```

`CommonCard` 直接暴露 `enterAnimated` 布尔参数，页面里列表项一排 `CommonCard(enterAnimated: true, ...)` 即可，**调用方零动画代码**。

### 3.6 按压反馈：STS 手写弹簧体系（全篇最核心的一节）

FlClash 的按压反馈**不是 Material 的涟漪（ripple）**，而是「**按下时膨胀 + 跟手拉扯 + 松手回弹**」。而且**按下是变大（grow），不是变小**——这是 M3 Expressive 的核心主张，也是它和绝大多数 App 观感差异最大的一处。

**(a) 弹簧驱动器 `_Spring`（`navigation_dock.dart:112-168`）—— 25 行，可原样复用**

```dart
class _Spring extends ChangeNotifier implements ValueListenable<double> {
  _Spring(TickerProvider vsync, this._value) { _ticker = vsync.createTicker(_tick); }

  late final Ticker _ticker;
  double _value;
  double _target = 0;
  SpringSimulation? _simulation;
  double _now = 0;
  double _start = 0;

  double get value => _value;
  double get velocity => _simulation?.dx(_now - _start) ?? 0;

  void springTo(double target, SpringDescription spring) {
    // 用「当前值 + 当前速度」起新模拟，所以中途改目标不会打断手感
    _simulation = SpringSimulation(spring, _value, target, velocity);
    _target = target;
    if (_ticker.isActive) { _start = _now; return; }
    _now = _start = 0;
    _ticker.start();
  }

  void jumpTo(double value) {
    _simulation = null; _ticker.stop(); _value = value; notifyListeners();
  }

  void _tick(Duration elapsed) {
    _now = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final simulation = _simulation!;
    final time = _now - _start;
    if (simulation.isDone(time)) {
      _value = _target; _simulation = null; _ticker.stop();
    } else {
      _value = simulation.x(time);
    }
    notifyListeners();
  }
}
```

**为什么值得抄**：`AnimationController` + `CurvedAnimation` 表达不了「弹簧在被打断时保留速度」，而 `SpringSimulation` 可以。`springTo` 每次都拿 `velocity` 作为初速度，所以连续点击/拖拽不会出现「重新从 0 加速」的断裂感。

**(b) 弹簧参数（`navigation_dock.dart:61-79`）**

```dart
final _trackSpring  = SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 120));
final _liftSpring   = SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 280), bounce: 0.2);
final _settleSpring = SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 500), bounce: 0.32);
final _hoverSpring  = SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 260), bounce: 0.18);
final _fadeSpring   = SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 200));
```

| 用途 | 时长 | bounce |
|---|---|---|
| 拖拽跟手 | 120 ms | 0 |
| 按下提升 | 280 ms | 0.2 |
| 松手回弹 | 500 ms | 0.32 |
| hover | 260 ms | 0.18 |

**规律**：**跟手要快且无弹（120/0），按下要中速微弹（280/0.2），松手要慢且明显回弹（500/0.32）**。这三个数直接决定了「脆不脆」。bounce 0.32 已经相当弹了。

**(c) `ElasticPress`（`navigation_dock.dart:461-552`）**

```dart
/// Grows under a press and stretches after a dragging finger, springing back
/// on release, as the bar's lens does.
///
/// The press only paints: layout, hit testing, and anything anchored to the
/// child, such as a popup menu or a tooltip, see it at rest.
class ElasticPress extends StatefulWidget {
  const ElasticPress({super.key, this.enabled = true, required this.child});

  /// Leaves a press on the button inside to the swell alone.
  static const buttonStyle = ButtonStyle(
    splashFactory: NoSplash.splashFactory,                       // 关掉 ripple
    overlayColor: WidgetStateMapper<Color?>({WidgetState.pressed: Colors.transparent}),
  );
  // ...
}

class _ElasticPressState extends State<ElasticPress> with TickerProviderStateMixin {
  late final _Spring _lift  = _Spring(this, 0);
  late final _Spring _pullX = _Spring(this, 0);
  late final _Spring _pullY = _Spring(this, 0);
  late final Listenable _motion = Listenable.merge([_lift, _pullX, _pullY]);
  int? _pointer;
  Offset _origin = Offset.zero;

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.enabled || _pointer != null || event.buttons & kPrimaryButton == 0) return;
    _pointer = event.pointer;
    _origin = event.localPosition;
    _lift.springTo(1, _liftSpring);                              // 按下 → lift 0→1
  }

  // A pointer's events keep reaching the hit-test path recorded at its down,
  // so a press removed mid-gesture still hears its moves and release.
  void _handlePointerMove(PointerMoveEvent event) {
    if (!mounted || event.pointer != _pointer) return;
    final limit = context.size!.shortestSide * _pullLimit;        // limit = 最短边 × 7/32
    final pull = event.localPosition - _origin;
    _pullX.springTo(_rubberBand(pull.dx, limit), _trackSpring);   // 跟手 + 橡皮筋阻尼
    _pullY.springTo(_rubberBand(pull.dy, limit), _trackSpring);
  }

  void _handlePointerEnd(PointerEvent event) {
    if (!mounted || event.pointer != _pointer) return;
    _pointer = null;
    _lift.springTo(0, _settleSpring);
    _pullX.springTo(0, _settleSpring);
    _pullY.springTo(0, _settleSpring);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerEnd,
      onPointerCancel: _handlePointerEnd,
      child: AnimatedBuilder(
        animation: _motion,
        builder: (_, child) => _PressTransform(
          lift: _lift.value, pull: Offset(_pullX.value, _pullY.value), child: child),
        child: widget.child,
      ),
    );
  }
}
```

**(d) 橡皮筋函数（`navigation_dock.dart:98-101`）—— 4 行，通用**

```dart
double _rubberBand(double overshoot, double limit) {
  final pull = 1 - 1 / (overshoot.abs() * 0.55 / limit + 1);
  return limit * pull * overshoot.sign;
}
```

拉得越远，实际位移越接近但永远不超过 `limit`。**这个函数可以直接用来做「列表过度滚动」「下拉刷新」的阻尼**。

**(e) 形变渲染（`navigation_dock.dart:617-670`）—— 「膨胀 + 拉扯」的公式**

```dart
const double _pressGrowth    = 1 / 8;   // 0.125
const double _maxPressGrowth = 16;
const double _pullLimit      = 7 / 32;  // ≈ 0.219
const double _pullStretch    = 0.5;

Matrix4 get _transform {
  // 关键：按最长边归一化，保证小按钮和大按钮的膨胀幅度观感一致
  final swell = 1 + _lift * math.min(_pressGrowth * 2, _maxPressGrowth / size.longestSide);
  // 拉扯方向上的额外拉伸（X/Y 独立）
  final scaleX = swell * (1 + _pull.dx.abs() / size.width  * _pullStretch);
  final scaleY = swell * (1 + _pull.dy.abs() / size.height * _pullStretch);
  final center = size.center(Offset.zero);
  return Matrix4.diagonal3Values(scaleX, scaleY, 1)
    ..setTranslationRaw(
      center.dx * (1 - scaleX) + _pull.dx,     // 绕中心缩放 + 跟随手指位移
      center.dy * (1 - scaleY) + _pull.dy,
      0);
}

@override
void paint(PaintingContext context, Offset offset) {
  if (child == null || size.isEmpty || (_lift == 0 && _pull == .zero)) {
    layer = null; super.paint(context, offset); return;      // 静息态零开销
  }
  layer = context.pushTransform(needsCompositing, offset, _transform, super.paint,
      oldLayer: layer is TransformLayer ? layer as TransformLayer? : null);  // 复用 layer
}
```

**三个必须学的细节**：
1. `_maxPressGrowth / size.longestSide` —— 大元素膨胀幅度自动变小，保证**不同尺寸的按钮观感一致**；
2. `setTranslationRaw(center * (1 - scale))` —— 绕中心缩放（因为 `Matrix4.diagonal3Values` 默认绕原点）；
3. 用 `pushTransform` + `oldLayer` **只重绘、不触发布局**，且静息态直接短路（`_lift == 0 && _pull == zero`）——注释明确写了「The press only paints: layout, hit testing ... see it at rest」，所以弹窗/tooltip 的定位不会被形变带偏。

**(f) 简易版按压（`lib/widgets/effect.dart:18-66`）** —— 如果不想引弹簧，这是最小实现：

```dart
class EffectGestureDetector extends StatefulWidget { /* child, onLongPress, onTap, onSecondaryTap */ }

class _EffectGestureDetectorState extends State<EffectGestureDetector>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _scale,
      duration: kThemeAnimationDuration,   // 200ms
      curve: Curves.easeOut,
      child: GestureDetector(
        onLongPressStart: (_) => setState(() => _scale = 0.95),   // 缩小 5%
        onLongPressEnd:   (_) => setState(() => _scale = 1),
        child: widget.child,
      ),
    );
  }
}
```

**(g) `commonProxyDecorator`（`effect.dart:128-148`）—— 拖拽排序时被拖起元素的反馈**

```dart
Widget commonProxyDecorator(Widget child, int index, Animation<double> animation) {
  return AnimatedBuilder(
    animation: animation,
    builder: (_, Widget? child) {
      final double animValue = Curves.easeInOut.transform(animation.value);
      final double scale = lerpDouble(1, 1.02, animValue)!;    // 只放大 2%
      return ProxyDecoratorProvider(
        isProxyDecorator: true, lift: animValue,
        child: Transform.scale(scale: scale, child: child),
      );
    },
    child: child,
  );
}
```

**只放大 2%**——克制是高级感的来源。

### 3.7 主题切换：**没有**过渡动画，但有一个可抄的动画补丁

全仓库 grep `AnimatedTheme` / `ThemeData.lerp` / `themesDuration` —— **零命中**。也就是说 FlClash 的浅↔深切换是**瞬时**的（`MaterialApp` 的 `ThemeData` 直接换掉）。

但它提供了一个可复用的模式：**主题预览页里用 `Tween<ColorScheme>` 把色板变化做成动画**（`lib/views/theme_preview.dart:152-155, 257-276`）：

```dart
class _ColorSchemeTween extends Tween<ColorScheme> {
  _ColorSchemeTween({super.end});
  @override
  ColorScheme lerp(double t) => ColorScheme.lerp(begin!, end!, t);
}

// 使用：
TweenAnimationBuilder<ColorScheme>(
  tween: _ColorSchemeTween(end: colorScheme),
  duration: _duration,
  builder: (_, colorScheme, _) => AnimatedSwitcher(
    duration: _duration,
    child: AnimatedBuilder(
      key: ValueKey(floatingBar),
      animation: _slideCurve,
      builder: (_, _) => MiniScreen(colorScheme: colorScheme, /* ... */),
    ),
  ),
)
```

👉 **如果 SekaiNook 想在切换主题时做全局过渡**，正确做法是：
```dart
AnimatedTheme(data: myThemeData, duration: const Duration(milliseconds: 300), child: ...)
```
`AnimatedTheme` 内部就是用 `ThemeData.lerp`。但代价是**换主题时会整棵树重建并插值 300ms**，对 7 套色板的切换体验提升有限，而且 `fl_chart` 这类第三方图表未必跟着插值。FlClash 选择不做，是有道理的。**建议：换主题不做全局动画，只在「色板预览小图」上做**（照抄 `TweenAnimationBuilder<ColorScheme>` + `MiniScreenThumb`，`theme_preview.dart:110-155`）。

### 3.8 数字滚动：只用 `TweenAnimationBuilder`，不引包

仓库里数字动画**只有 6 处**，全部是 `TweenAnimationBuilder<double>`：

| 文件 | 用途 |
|---|---|
| `lib/views/dashboard/widgets/memory_info.dart:501` | 内存/流量进度条数字 |
| `lib/views/dashboard/widgets/outbound_mode.dart:107` | 流量速率 |
| `lib/views/dashboard/widgets/start_button.dart:172` | 启动按钮进度 |
| `lib/views/theme_preview.dart:257` | 色板插值（见上） |
| `lib/widgets/sidebar.dart:140` | 侧边栏宽度（`TweenAnimationBuilder<double>` + `_expandDuration` 250ms） |
| `lib/widgets/source_icon.dart:52` | 源图标 |

`lib/widgets/donut_chart.dart` 的环形图进度是驱动一个 `AnimationController`，并同样走 `context.motionDuration(widget.duration)`。

> 🔧 结论：**数字滚动不需要 `animated_number` / `odometer` 之类的包**，`TweenAnimationBuilder<double>` + 字符串格式化就够。注意用 `Intl` 保证滚动过程中数字宽度不抖（等宽数字 `FontFeature.tabularFigures`，FlClash 用 JetBrainsMono 承载这类数字）。

### 3.9 弹层（BottomSheet / SideSheet / Dialog）

`lib/widgets/sheet.dart` + `snap_sheet.dart`(1125 行) + `side_sheet.dart`(539) + `paged_sheet.dart`(513) 是一套自研弹层体系。要点：

- **跨断点自适应**：`context.isMobileView` 决定是底部弹层（移动）还是侧边弹层（桌面），并且**跨断点时自动以另一种形态重开、结果由关闭的那一侧 resolve**（`sheet.dart:110-202` 的 `showSnapSheet`，用 `Completer` 统一两种形态的返回值）。这是 FlClash 作为「跨平台同一套 UI」的关键设计。
- **多档停靠（detents）**：`const snapSheetDetents = [9 / 16, 0.9];`（`snap_sheet.dart:21`），从最短档打开，可拖到 90%。
- **弹簧与物理参数**（`snap_sheet.dart:23-42`）：

```dart
final _settleSpring = SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 450));
const _settleTolerance   = Tolerance(distance: 0.5, velocity: 10);
const _decelerationRate  = 0.998;      // 跟手抛掷衰减
const _bounceExtent      = 120.0;      // 越界最多拉出 120px
const _bounceResistance  = 6.0;
const _dismissVelocity   = 700.0;      // 下甩超过 700 px/s 就关闭
const _wheelTurnGap      = Duration(milliseconds: 500);
```

- **弹层自身转场时长**：`transitionDuration = 300ms`（正向）/ `reverseTransitionDuration = 200ms`（反向）——**关闭比打开快**，这是几乎所有成熟 App 的共识。
- **叠层弹层的「堆叠」效果**（`sheet.dart:39-42`）：

```dart
const stackedSheetPeek  = 14.0;
/// Flutter's Cupertino sheet measured this on iOS 18.
const stackedSheetScale = 1 - 0.0835;
```

即开启新弹层时，下层弹层**缩小到 91.65% 并露出 14px**——这个数值直接来自 iOS 18 的测量。
- **遮罩色**：统一用 `context.colorScheme.modalScrim`。
- **主题继承**：每次 push 都做 `capturedThemes: InheritedTheme.capture(from: context, to: navigator.context)`——**自研导航栈时这条极易漏，漏了会导致弹层里 `Theme.of` 拿不到外层主题**。

### 3.10 骨架屏：壁钟同步的「呼吸」，不是 shimmer 扫光

`lib/widgets/skeleton.dart`（96 行，全文可抄）——**没有用 shimmer 包，没有扫光渐变**，只是一个 1600ms 周期的正弦呼吸：

```dart
class _SkeletonTextState extends State<SkeletonText> with SingleTickerProviderStateMixin {
  static const _period = Duration(milliseconds: 1600);

  late final AnimationController _controller;
  late final Animation<double> _opacity = _controller.drive(const _Pulse());

  @override
  void initState() {
    super.initState();
    // Starting from the wall clock keeps bars that appear at different times
    // pulsing in step.
    _controller = AnimationController(
      vsync: this, duration: _period,
      value: DateTime.now().millisecondsSinceEpoch % _period.inMilliseconds / _period.inMilliseconds,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.disableAnimations) { _controller.stop(); }
    else if (!_controller.isAnimating) { _controller.repeat(); }
  }
  // build: DecoratedBox(shape: AppShape.full, color: surfaceContainerHighest) 外面套 FadeTransition
}

class _Pulse extends Animatable<double> {
  const _Pulse();
  @override
  double transform(double t) => 0.75 + 0.25 * math.cos(2 * math.pi * t);   // 0.5 ~ 1.0
}
```

**两个细节很值**：
1. **用壁钟初始化 controller 的相位**，让不同时刻出现的骨架条**相位对齐**，不会各闪各的；
2. 骨架条的形状是 `AppShape.full` 的胶囊，底色是 `surfaceContainerHighest`，并且**用真实文本 `Text(' ', style: style)` 占位来决定高度**（配合 `MediaQuery.textScalerOf` 缩放），所以骨架高度和真实文字高度永远一致。

### 3.11 其它值得一提的微交互

| 微交互 | 实现 | 位置 |
|---|---|---|
| **FAB 出现/消失** | `AnimatedScale(scale: loading ? 0 : 1)` + `AnimatedOpacity`，400ms `Curves.easeInOutBack` | `widgets/scaffold.dart:944-972` |
| **展开箭头** | 旋转 0 → 0.5 turns，200ms `Curves.fastOutSlowIn` | `widgets/effect.dart:68-124` |
| **工具栏按钮隐藏**（编辑/搜索态） | `AnimatedOpacity(duration: context.motionDuration(kThemeAnimationDuration))` + `IgnorePointer` + `ExcludeFocus` + `ExcludeSemantics` 四件套 | `widgets/scaffold.dart:376-390` |
| **「材质化」槽位进出**（底栏动态插入的项） | 500ms 进 / 220ms 退；scale `0.5→1` 且用 bounce 0.3 的 `SpringCurve`；退出 scale `0.7→1` 用 `easeOutCubic`；同时 **blur 6 → 0** | `navigation_dock.dart:424-459` |
| **列表项重排让位** | `_SlideOnMove`，`easeOutCubic` 衰减平移 | `keyed_animated_list.dart:205-402` |
| **拖拽排序抬起** | scale 1 → 1.02，`easeInOut` | `widgets/effect.dart:128-148` |
| **侧边栏展开** | `TweenAnimationBuilder<double>`，250ms | `widgets/sidebar.dart:20,140` |
| **长按缩小** | `AnimatedScale` 0.95，`kThemeAnimationDuration`(200ms)，`easeOut` | `widgets/effect.dart:46-52` |
| **禁用动效** | 全局 `context.motionDuration()` + 每个自定义动画 build 短路 | `common/context.dart:86-89` |

**「材质化」那一段单独贴出来**，因为它用 `ImageFilter.blur` 做进出，是「不需要玻璃拟态依赖也能做高级模糊」的范例（`navigation_dock.dart:424-459`）：

```dart
const _slotDuration      = Duration(milliseconds: 500);
const _slotExitDuration  = Duration(milliseconds: 220);
const double _slotEnterScale = 0.5;
const double _slotExitScale  = 0.7;
const double _slotBlur       = 6;
const _slotRevealCurve = Interval(0, 0.5, curve: Curves.easeOut);

final _slotPopCurve = SpringCurve(
  SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 400), bounce: 0.3),
  seconds: 0.5);

class _SlotMaterialize extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        final entering = animation.status != AnimationStatus.reverse;
        final scale = entering
            ? lerpDouble(_slotEnterScale, 1, _slotPopCurve.transform(t))!
            : lerpDouble(_slotExitScale, 1, Curves.easeOutCubic.transform(t))!;
        final reveal = entering ? _slotRevealCurve.transform(t) : Curves.easeOut.transform(t);
        final blur = _slotBlur * (1 - reveal);
        return Opacity(
          opacity: reveal,
          child: Transform.scale(
            scale: scale,
            child: ImageFiltered(
              enabled: blur > 0.05,
              imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}
```

**注意 `enabled: blur > 0.05`**：模糊为 0 时关掉 `ImageFiltered`，避免持续付出离屏渲染成本。

### 3.12 `SpringCurve`：把弹簧塞进只能吃 `Curve` 的地方

`lib/common/motion.dart:9-21` —— 这是全项目复用率最高的 12 行：

```dart
/// Plays [spring] over the first [seconds] of an animation, easing out the
/// remaining residual so the curve still ends exactly at 1.
class SpringCurve extends Curve {
  SpringCurve(SpringDescription spring, {required this.seconds})
    : _simulation = SpringSimulation(spring, 0, 1, 0);
  final double seconds;
  final SpringSimulation _simulation;
  late final double _residual = 1 - _simulation.x(seconds);
  @override
  double transformInternal(double t) =>
      _simulation.x(t * seconds) + _residual * t;
}
```

**原理**：弹簧模拟在 `seconds` 秒时通常还没收敛到 1，直接截断会有跳变。所以它算出残差 `_residual`，在剩余时间里**线性补齐**——既有弹簧手感，又能严格落在 1.0。这让弹簧可以用在任何接受 `Curve` 的 API 里（`CurvedAnimation`、`AnimatedContainer`、`Tween.chain`），**不需要改造成 `AnimationController` + `Simulation`**。

> 🔧 这一个类就解决了「想用弹簧但 API 只收 Curve」的全部场景。强烈建议第一个移植。

---

## 4. 最值得借鉴的 10 段代码（索引）

| # | 内容 | 文件:行 | 为什么值得抄 |
|---|---|---|---|
| 1 | `withAppShapes`：一次 `copyWith` 铺满 15 个组件的圆角 | `lib/common/shape.dart:250-304` | 消除圆角不一致，改动集中在一处 |
| 2 | `AppCorner` + `AppShape`（`RoundedSuperellipseBorder`） | `lib/common/shape.dart:6-107` | 超椭圆是「贵」的来源；`AppCorner.fit()` 自适应 |
| 3 | `SpringCurve` | `lib/common/motion.dart:9-21` | 12 行，让弹簧可用在任何吃 `Curve` 的地方 |
| 4 | `_Spring`（弹簧驱动器） | `lib/widgets/navigation_dock.dart:112-168` | 保速度的打断式弹簧，25 行 |
| 5 | `ElasticPress` + `_RenderPressTransform` + `_rubberBand` | `navigation_dock.dart:461-670, 98-101` | 「膨胀 + 拉扯 + 回弹」全套，按尺寸归一化 |
| 6 | `_SelectionIndicator`（会拉伸的侧边栏指示器） | `lib/widgets/sidebar.dart:485-564` | lead/trail 双缓动，比固定尺寸滑动高级得多 |
| 7 | `FadeSlideEnterBox` / `FadeScaleEnterTransition` | `lib/widgets/fade_box.dart:140-326` | staggered 进场零依赖方案（`delay` + 24px + Interval） |
| 8 | `SharedXPageTransition`（450ms Android 14 风格） | `lib/widgets/page_transition.dart:1-302` | 曲线配比 + 「画色块代替 Opacity」的 Impeller 优化 |
| 9 | `_SlotMaterialize`（scale + blur 进出场） | `lib/widgets/navigation_dock.dart:424-459` | 不用玻璃拟态依赖也有模糊质感 |
| 10 | `SkeletonText` / `_Pulse` | `lib/widgets/skeleton.dart:1-96` | 壁钟对齐相位的呼吸骨架屏 |

---

## 5. 给 SekaiNook 的落地建议（Android + Flutter Web）

前提约束：已有 7 套自研色板（`lib/theme/app_theme.dart`，`ThemeData` + `ThemeExtension<AppPalette>`），**不改配色值**；不引重型依赖；目标是 Android 手机 + Web。

### 5.1 必须做的（收益最大、成本最低）

1. **加一个 `lib/common/motion.dart`**，内容 = FlClash 的 `SpringCurve` + 三级时长常量（100/200/300）+ `motionDuration` context 扩展。**这一步就解锁了后面所有动效，且零新依赖。**
2. **加一个 `lib/theme/app_shape.dart`**，照抄 `AppCorner` 六档 + `extension on ThemeData { get withAppShapes }`，把 card / dialog / bottomSheet / chip / popupMenu / all buttons / FAB 的 shape 一次性对齐。**SekaiNook 已有 7 套主题，正好用这个扩展统一收口**——每套主题都 `.withAppShapes` 一次即可，不碰任何颜色。
3. **加 `animations: ^3.0.0`（官方包，唯一新增依赖）**，然后 `PageTransitionsTheme` 里挂 `SharedAxisPageTransitionsBuilder(transitionType: horizontal, fillColor: Colors.transparent)`。**注意 `fillColor: Colors.transparent` 必须显式写**，否则 Web/Android 上换页会有底色闪。
4. **列表进场统一用 `FadeSlideEnterBox`**（24px + `Interval(0,0.25)` 淡入 + `Easing.emphasizedDecelerate`）。`Easing` 来自 `material_ui` 包——如果不想加这个依赖，用 `Curves.easeOutCubicEmphasized`（Flutter 内置 `Curves` 里就有）等价替代。
5. **关掉按钮 ripple 风险提示**：FlClash 关掉了 `splashFactory`（`ElasticPress.buttonStyle`）。SekaiNook 的 S3 风格产品（积分/家庭管理）是否关 ripple 是审美选择；如果保留 Material ripple，也要保证 `overlayColor` 的 pressed 值不冲突。

### 5.2 建议做的（提升「高级感」，中等成本）

6. **侧边栏/底部导航指示器**：Web 端如果是左侧导航，直接移植 `_SelectionIndicator` 的 lead/trail 双缓动（320ms，lead `easeOutCubic` 在 60% 处完成、trail `easeInOutCubic` 从 35% 开始）。手机端如果用 `NavigationBar`，只需设 `indicatorShape: AppShape.full` 即可，M3 自带指示器动画。
7. **卡片按压缩放**：`AnimatedScale` 0.95 / 200ms / `easeOut`（`EffectGestureDetector` 版本），或升级成 `ElasticPress` 的膨胀版。**注意 FlClash 是「放大」而不是「缩小」**——如果 SekaiNook 想更接近 Material 习惯，用缩小；想更「贵」，用放大。
8. **骨架屏**照抄 `SkeletonText`：`surfaceContainerHighest` 胶囊条 + 1600ms 呼吸 + **壁钟相位对齐**。Web 上尤其重要，因为 Web 首屏加载慢，骨架屏是必经之路。
9. **弹层**：`showModalBottomSheet` 时长正向 300ms / 反向 200ms（`reverseTransitionDuration`），并给 `bottomSheetTheme.shape = AppShape.top(28)`。叠层弹层可以加 `1 - 0.0835` 缩放 + 14px 露边。

### 5.3 谨慎做的 / 不建议做

10. **不建议移植**：`navigation_dock.dart`（1581 行浮动底栏 + lens + jelly + hover magnet + 拖拽选择）——它重度依赖指针 hover 与拖拽，**在 Android 触屏上没有 hover，Web 上又和鼠标习惯冲突**，投入产出比低。同理 `commonProxyDecorator` 的 hover 逻辑。
11. **不建议移植**：`_SlideOnMove`（列表重排让位）。它是 FlClash 为 `super_sliver_list` 定制的手写 RenderObject，**依赖 sliver 的 layoutOffset 生命周期**，移植成本高、易出诡异 bug。SekaiNook 若需重排动画，优先考虑 `AnimatedList` + key。
12. **不建议做**：主题切换全局过渡（`AnimatedTheme`）。FlClash 刻意不做，理由见 §3.7。7 套色板切换 + 图表库混合时，整树插值收益低、风险高。
13. **`RoundedSuperellipseBorder` 的依赖问题**：它来自 `material_ui`（FlClash 的依赖）。Flutter 3.32+ 的 `flutter/painting.dart` 已有实验性 `RoundedSuperellipseBorder`，**先在 SekaiNook 的 SDK 版本上 `grep RoundedSuperellipseBorder $(flutter --version 对应的 sdk 路径)/packages/flutter/lib/src/painting/borders.dart` 确认**；有就直接用（零依赖），没有就退回 `RoundedRectangleBorder`——**代价只是圆角接点略硬，其它动效方案完全不受影响**。

### 5.4 Web 平台特别注意

- §3.6 的 `ElasticPress` 用 `Listener` + `PointerDownEvent.localPosition` 实现跟手拉扯，**在 Flutter Web 上完全可用**（Pointer 事件是平台无关的），不需要任何 `dart:html` 分支。
- §3.2 的 `_PageFade`（画色块代替 Opacity）**在 CanvasKit 渲染下同样有收益**，因为 offscreen 开销来自 Impeller/Skia 层而非平台。
- `ImageFilter.blur`（§3.11 的 `_SlotMaterialize`）在 Web 上开销明显高于移动端，**务必保留 `enabled: blur > 0.05` 的短路**，并避免在大面积元素上持续模糊。

---

## 附：文件清单与 Raw 地址模板

```
https://raw.githubusercontent.com/chen08209/FlClash/main/lib/common/motion.dart
https://raw.githubusercontent.com/chen08209/FlClash/main/lib/common/shape.dart
https://raw.githubusercontent.com/chen08209/FlClash/main/lib/common/theme.dart
https://raw.githubusercontent.com/chen08209/FlClash/main/lib/common/constant.dart
https://raw.githubusercontent.com/chen08209/FlClash/main/lib/common/font.dart
https://raw.githubusercontent.com/chen08209/FlClash/main/lib/common/navigator.dart
https://raw.githubusercontent.com/chen08209/FlClash/main/lib/common/context.dart
https://raw.githubusercontent.com/chen08209/FlClash/main/lib/application.dart
https://raw.githubusercontent.com/chen08209/FlClash/main/lib/providers/state/theme.dart
https://raw.githubusercontent.com/chen08209/FlClash/main/lib/manager/theme_manager.dart
https://raw.githubusercontent.com/chen08209/FlClash/main/lib/widgets/page_transition.dart
https://raw.githubusercontent.com/chen08209/FlClash/main/lib/widgets/fade_box.dart
https://raw.githubusercontent.com/chen08209/FlClash/main/lib/widgets/sidebar.dart
https://raw.githubusercontent.com/chen08209/FlClash/main/lib/widgets/navigation_dock.dart
https://raw.githubusercontent.com/chen08209/FlClash/main/lib/widgets/keyed_animated_list.dart
https://raw.githubusercontent.com/chen08209/FlClash/main/lib/widgets/skeleton.dart
https://raw.githubusercontent.com/chen08209/FlClash/main/lib/widgets/effect.dart
https://raw.githubusercontent.com/chen08209/FlClash/main/lib/widgets/card.dart
https://raw.githubusercontent.com/chen08209/FlClash/main/lib/widgets/sheet.dart
https://raw.githubusercontent.com/chen08209/FlClash/main/lib/widgets/snap_sheet.dart
https://raw.githubusercontent.com/chen08209/FlClash/main/lib/widgets/scaffold.dart
https://raw.githubusercontent.com/chen08209/FlClash/main/lib/views/theme.dart
https://raw.githubusercontent.com/chen08209/FlClash/main/lib/views/theme_preview.dart
https://raw.githubusercontent.com/chen08209/FlClash/main/pubspec.yaml
```
