# 悬浮弹簧底栏（FlClash 风格）· 复制即用

把底部 Tab 栏做成**浮起来的圆角胶囊**：按下透镜弹、拖动跟手、松手过冲回弹，每换一格震一下。
交互与参数取自 [FlClash](https://github.com/chen08209/FlClash) 的 `lib/widgets/navigation_dock.dart`（MIT），
这里是零项目依赖的精简可复用版 —— 不依赖任何主题包、状态管理、路由库。

```
floating-dock/
├── floating_dock.dart       ← 组件本体（FloatingDock / DockDestination / DockStyle / DockMotion / readableOn）
├── spring_utils.dart        ← 两个弹簧工具（SpringDriver 保留速度的驱动器 / SpringCurve 弹簧曲线）
├── floating_dock_test.dart  ← 8 条行为回归测试（放进项目 test/ 就能跑）
└── README.md                ← 本文档
```

## 1. 三十秒接入

1. 把 `floating_dock.dart`、`spring_utils.dart` 复制到项目里（例如 `lib/ui/floating_dock/`）；
2. `Scaffold` 的 `bottomNavigationBar` 槽位放它：

```dart
Scaffold(
  extendBody: true,                       // 可选：让内容穿到 dock 下面
  bottomNavigationBar: FloatingDock(
    destinations: const <DockDestination>[
      DockDestination(icon: Icons.home_outlined, selectedIcon: Icons.home, label: '首页', badge: 3),
      DockDestination(icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long, label: '账本'),
      DockDestination(icon: Icons.local_florist_outlined, selectedIcon: Icons.local_florist, label: '花园'),
      DockDestination(icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: '设置'),
    ],
    selectedIndex: _index,
    onSelected: (int i) => setState(() => _index = i),
  ),
  body: pageFor(_index),
)
```

3. 颜色默认全从 `Theme.of(context).colorScheme` 取（`surfaceContainer` / `secondaryContainer` /
   `onSecondaryContainer` / `onSurfaceVariant` / `error`），**所以什么都不用配就已经是 Material 3 的样子**。
   要换皮肤就传 `DockStyle(...)`，别去改组件内部。

> 用了 `extendBody: true`（或自己在 `Stack` 里叠）时，列表底部留白要加
> `FloatingDock.reservedHeight(context)`，否则最后一条会被 dock 压住。

## 2. 它为什么「Q 弹」——三条主线 + 四个公式

**交互主线**（少一条都不对味）：

| 阶段 | 发生什么 |
| --- | --- |
| 按下 | 透镜（选中高亮）**立刻**跳到手指所在格并放大；整条 dock 轻微膨胀；松手前不改 `selectedIndex` |
| 拖动 | 过 `kTouchSlop` 才算拖；透镜用「跟手弹簧」追手指；拖出条外整条被橡皮筋拽动；每跨一格 `HapticFeedback.selectionClick()` |
| 松手 | 透镜落到最近格（过冲回弹）；轻震；**只有真的换了格**才回调 `onSelected` |

**四个公式**（都在这两个文件里，改数值前先看后果）：

| 机制 | 公式 / 取值 | 作用 |
| --- | --- | --- |
| 果冻拉伸 | `stretch = (velocity.abs()/8).clamp(0,1) * 0.25`，宽度 `×(1+stretch)`、高度 `×(1-stretch/2)` | 甩得越快透镜拉得越长、压得越扁 —— 「果冻感」的来源 |
| 橡皮筋 | `limit × (1 − 1/(\|overshoot\|×0.55/limit + 1)) × sign` | 拖到条外越拖越沉，永远拉不出无限量（可用于下拉刷新） |
| 按下膨胀 | `swell = lift × min(16/条宽, 1/8)` | 按**条宽**归一化，大小屏、几格都观感一致 |
| 透镜几何 | `left = (position+0.5)×extent − width/2`，`top = (height−lensHeight)/2` | 透镜是独立一层，不是给格子换背景色，所以能跨格滑动、能拉伸 |

**弹簧四档**（`DockMotion`，值 = FlClash 原值）：

| 名称 | 参数 | 用在哪 |
| --- | --- | --- |
| `track` | 120ms / bounce 0 | 跟手（要快、不过冲） |
| `press` | 280ms / bounce 0.2 | 按下 |
| `settle` | 500ms / bounce 0.32 | 松手落位（回弹主角） |
| `hover` | 260ms / bounce 0.18 | 桌面 hover（本实现没接，留着备用） |

> `SpringDriver` 的关键在「**保留速度**」：重定向只把时间基准挪到当前时刻，
> `SpringSimulation(spring, 当前值, 目标值, 当前速度)` 重建。所以连点、反向拖都不会被
> 「重启」钉住。`AnimationController.animateWith` 做不到这一点 —— 它每次重定向重启
> ticker，而 ticker 第一帧读不到已流逝时间，手指每帧都在动时值会卡住不动。

## 3. 坑（照抄就能躲过）

1. **格子本身不要再挂 `GestureDetector` / `InkWell` / `onTap`。** 整条 dock 只有一个
   `Listener`，松手时统一提交一次。格子再挂一份 → 一次点击回调两次、还会把透镜起手拖慢。
   读屏用户的激活路径用 `Semantics(onTap:)`（组件里已经写好）。
2. **不要在 `initState` 里读 `MediaQuery`**（`maybeDisableAnimationsOf` 会触发
   `dependOnInheritedWidgetOfExactType` 断言）→ 放 `didChangeDependencies`，用 `bool` 守卫只跑一次。
3. **无障碍「减少动态效果」必须直接落位**（`SpringDriver.jumpTo`），别让动画绊住人。
   本组件读 `MediaQuery.maybeDisableAnimationsOf(context)`，震动也会一起停。
4. **颜色要成对**：彩色底就用成对的 `onXxx`（默认已经这么做）。中性灰字压在彩色底上
   就是「字和底色撞在一起看不清」的经典病灶。角标这种底色是运行时给的，用 `readableOn(bg)`。
5. **`Scaffold` 不会给 `bottomNavigationBar` 留底部安全区**（它把这个槽位贴在屏幕最底，
   `scaffold.dart` 的 `_ScaffoldLayout.performLayout` 里只有 FAB/SnackBar 吃 `minViewPadding`），
   所以本组件自己加 `MediaQuery.paddingOf(context).bottom`。**如果你在外面已经套了 `SafeArea`，
   就把 `DockStyle(handleSystemInset: false)` 传上，免得留两遍白。**
6. **`Scaffold` 的 `body` 默认已经被扣掉底栏高度**；想让内容从 dock 下面穿过去（更「悬浮」）
   用 `extendBody: true`，并把 `FloatingDock.reservedHeight(context)` 加进列表留白。
7. **别在 `build` 里 new 弹簧驱动器 / 建 `Ticker`**：`SpringDriver` 必须在 `initState` 建、`dispose` 里销毁。
8. **圆角与颜色从主题来**：`BorderRadius.circular(999)` 就是胶囊；不要为了「圆一点」写死像素。
9. Web 上少用 `ImageFilter.blur`（本组件刻意没做 FlClash 的透镜着色层，一半原因就是它）。

## 4. 参数速查

`DockStyle`（全都有默认值，只传要改的）：

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `background` | `colorScheme.surfaceContainer` | 条底色；页面有背景图时传 `surface.withValues(alpha: 0.82)` 让照片透出来 |
| `indicatorColor` | `secondaryContainer` | 透镜底色 |
| `selectedForeground` | `onSecondaryContainer` | 选中格图标/文字色（与上面成对） |
| `idleForeground` | `onSurfaceVariant` | 未选中格颜色 |
| `badgeColor` / `badgeTextColor` | `error` / `readableOn(error)` | 角标 |
| `height` / `barPadding` | `58` / `4` | 条内高度与内边距 |
| `edgeMargin` / `bottomMargin` | `16` / `8` | 两侧与底部留白（浮起来的关键） |
| `iconSize` / `labelSize` | `24` / `12` | 图标与文字 |
| `showLabels` | `true` | 只留图标（辅助 `Tooltip` 时） |
| `showShadow` | `true` | 柔和投影（亮/暗主题自动调透明度） |
| `haptics` | `true` | 换格/落位震动（桌面与 Web 上是空操作） |
| `handleSystemInset` | `true` | 见坑 5 |

`DockMotion`（静态常量，想改手感就改这里，别散落到各处）：见第 2 节的弹簧表，
另有 `jellySpeed 8`、`jellyStretch 0.25`、`lensGrowth 14`、`pressGrowth 1/8`、
`maxPressGrowth 16`、`pullLimit 7/32`。

## 5. 与 FlClash 原版的差异（有意省略）

- **不做鼠标 hover 磁吸与透镜放大镜着色层**：Android 没有 hover，Web 上 `ImageFilter.blur` 太贵；
  指针交互只保留「按下 → 跟手 → 落位」这条主线（桌面项目要补 hover，可参考
  `_hoverMagnet` / `_HoverHighlight`）。
- **不做透镜内文字的放大/着色渲染层**（FlClash 用自定义 `RenderObject` 做 `_LensTint`）；
  这里透镜就是一层纯色胶囊，性能与可维护性优先。
- 依赖超椭圆圆角（`material_ui` 的 `RoundedSuperellipseBorder`）在多数项目里不必要，这里用普通圆角。

## 6. 自测

```bash
# 复制进项目后（测试文件放 test/ 下，import 路径改成包内路径）
flutter test test/floating_dock_test.dart
```

8 条断言守的是**行为**：每格都在 / 角标数字 / 点击只回调一次 / 拖动松手落位 / 拖动中途不提交 /
减少动态效果仍能选中 / 选中态语义标记 / 自定义样式不崩 + `readableOn` 明暗方向。
（透镜的视觉效果测不了，靠截图或真机看。）

## 7. 想移植到别的技术栈？

同一套公式可以直接搬：透镜位置 = 一个弹簧驱动的标量（0 = 第一格中心），
宽度/高度按速度拉伸，整条用另一个弹簧做位移与缩放，松手时按「最近格」取整。
要点只有四条：**保留速度的弹簧**、`kTouchSlop` 门槛、**橡皮筋阻尼**、
**只在松手时提交选中**。Web 上可用 `framer-motion` 的 `spring`（它同样保留速度），
但 `stiffness/damping` 的数值需要按各自的单位换算，别直接照抄毫秒数。

---

参考实现：本项目 `lib/ui/shell/app_nav_bar.dart`（同逻辑，颜色接到项目自己的
`AppPalette`，安全区交给外层 `SafeArea`）。两份代码是同一套交互，改一处记得对齐另一处。
