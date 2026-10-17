# 动效工具包（页面作者契约）

> 目标：把 SekaiNook Flutter 版做成「动得像同一个东西」——
> 所有时长/曲线只从 `lib/theme/motion.dart` 取，页面里不要再散写
> `Duration(milliseconds: 300)` 或 `Curves.easeInOut`。
>
> 设计参考 FlClash（Material 3 + 弹簧 + 错峰进场），调研记录见
> `docs/design-ref-flclash.md`。

## 一、导入

```dart
import '../../theme/motion.dart';          // AppMotion 令牌（时长/曲线/弹簧）
import '../../widgets/motion_widgets.dart'; // 动效组件统一出口
```

（路径按所在目录调整；`lib/ui/pages/**` 下的页面用 `../../`。）

## 二、令牌 `AppMotion`

| 类别 | 名称 | 值 | 用在哪 |
| --- | --- | --- | --- |
| 时长 | `instant` | 90ms | 按压反馈、图标切换 |
| | `fast` | 160ms | 高亮、小展开、内容切换 |
| | `normal` | 240ms | **默认**：卡片入场、列表错峰 |
| | `slow` | 360ms | 页面转场、弹层 |
| | `slower` | 520ms | 数字滚动、主题切换 |
| | `celebrate` | 900ms | 对勾 + 光环 |
| | `skeleton` | 1600ms | 骨架屏呼吸周期 |
| 曲线 | `standard` | `Cubic(0.2,0,0,1)` | 绝大多数过渡 |
| | `decelerate` | `Cubic(0.05,0.7,0.1,1)` | 进场 |
| | `accelerate` | `Cubic(0.3,0,0.8,0.15)` | 退场 |
| | `emphasized` | `easeInOutCubicEmphasized` | 对称过渡 |
| | `overshoot` | `easeOutBack` | **只喂 scale/offset，绝不喂 Opacity** |
| 弹簧 | `spring` / `springSoft` / `springSnappy` | `SpringCurve` | 只喂 scale/offset（会越过 1） |
| 量 | `enterOffset` 14 / `pressScale` 0.97 / `staggerStep` 42ms / `staggerMax` 10 | | |
| 函数 | `AppMotion.stagger(index)` | 第 index 项的错峰延迟（超出 10 封顶） | |

## 三、组件

### 1. `EnterBox` —— 入场（淡入 + 位移，可选放大）

```dart
// 列表：按序号错峰
ListView.builder(itemCount: n, itemBuilder: (c, i) => EnterBox(index: i, child: _row(i)))

// 单块内容：显式延迟
EnterBox(delay: const Duration(milliseconds: 80), child: card)
```

参数：`index`（错峰序号）、`delay`（显式延迟，优先于 index）、`distance`（默认 14）、
`duration`（默认 `AppMotion.normal`）、`scaleFrom`（给了就从该比例放大到 1）、`axis`。

> 只给**首屏可见**的元素加错峰。`ListView.builder` 里滚到后面的项也会播一次进场，
> 这是期望行为（新内容淡入），但不要给上千行的大表每一行都加。

### 2. `PressInkWell` / `PressScale` —— 按压反馈

```dart
PressInkWell(onTap: _open, borderRadius: radius, child: content) // 水波纹 + 缩放（首选）
PressScale(onTap: _open, child: customThing)                      // 只要缩放
```

`PressInkWell` 用 `InkWell.onHighlightChanged` 拿按压态，**可以安全地和 onTap 一起用**；
`PressScale` 自带 `GestureDetector`，**不要**套在 `FilledButton` 之类的按钮外面（会抢走点击）。
`AppCard(onTap:)` 已经内置了这套反馈 + 描边高亮，不用再包一层。

### 3. `AnimatedCount` —— 数字滚动

```dart
AnimatedCount(value: family.balance, style: bigNumStyle)   // 从 0 滚到值，变化时脉冲
AnimatedCount(value: sun, style: s, from: previousSun, pulse: false)
```

大数字的 `style` 请带上 `fontFeatures: kTabularNumbers`（`theme/tokens.dart`），否则滚动时左右抖。

### 4. `AnimatedProgressBar` / `PulseDot`

```dart
AnimatedProgressBar(value: done / total, color: palette.primary, height: 10)
const PulseDot(color: c) // 未读、22 点提醒、「注意我」
```

### 5. 骨架屏 `SkeletonBox` / `SkeletonLine` / `SkeletonCard` / `SkeletonList`

```dart
SkeletonList(count: 3)                       // 首屏列表加载
const SkeletonBox(width: 120, height: 14)
const SkeletonBox.circle(size: 40)
SkeletonLine(widthFactor: 0.6)
```

首屏加载**优先骨架屏**，不要整页转圈（`LoadingView` 留给局部/按钮旁）。

### 6. `SlideFadeSwitcher` —— 内容切换（Tab / 菜单 / 筛选）

```dart
SlideFadeSwitcher(
  childKey: ValueKey<String>(_tab),
  offset: 12,
  axis: Axis.horizontal,      // 左右 Tab 用 horizontal，上下菜单用 vertical
  child: _buildTab(_tab),
)
```

只有 `childKey` 变化时才播动画；`MediaQuery.disableAnimations` 时自动退化为直切。

`SlidingHighlight(index:, count:, height:)`：等宽选项之间的滑块（分段控件）。

### 7. `SuccessBurst` / `showBurst` —— 成功那一下

```dart
showBurst(context);                       // 盖在整页上，不挡点击，播完自动消失
SuccessBurst(color: palette.success)      // 或自己放进对话框/卡片里
```

用在：打卡成功、审批通过、兑换到账、领取奖励。

### 8. 出错 / 空态

`ErrorView` / `EmptyView` / `LoadingView` 已内置入场动画与圆形软底图标，直接调用即可。

### 9. `AppCard` / `StatBlock`

```dart
AppCard(onTap: ..., onLongPress: ..., highlight: true, child: ...)  // 按压有缩放+描边高亮
StatBlock(label: '余额', number: family.balance, formatter: (v) => v.toStringAsFixed(2), unit: '积分')
```

`StatBlock` 传 `number` 会滚动；传 `value`（String）则原样显示。

### 10. 文字对比度铁律：`palette.onColor` / `onColorSoft`

**只要文字或图标落在一层「有色底」上，字色就不许直接取 `text` / `textSecondary` /
`textTertiary`。** 有色底指：`primary`、`primarySoft`、`sider`、`siderSelected`、
`success`、`danger`、`warning`、`colorScheme.*Container`，以及任何 `LinearGradient`
或 `Color.alphaBlend` 的结果。

```dart
final bg = palette.primary; // 或 primarySoft / sider / success / danger / 渐变插值结果
Text('标题', style: TextStyle(color: palette.onColor(bg)));      // 同色系近黑 / 近白
Text('说明', style: TextStyle(color: palette.onColorSoft(bg)));  // 弱一档，仍有对比度
```

两个常用捷径：`palette.onPrimary`（主色块上的字）、`palette.onSoft`（`primarySoft`
选中底上的字）。反过来说，**普通卡片底（`surface` / `softColor(...)`）上照旧用
`text` / `textSecondary` / `textTertiary`**，不要一律改成 `onColor`。

为什么必须有这条：`original` 主题的主色 `#1A1A2E` 和正文色 `text` 是同一个值，
`midnight` 的亮蓝主色同理 —— 深底上放深字会直接糊掉；而 `ColorScheme.fromSeed`
只会按种子色自己推一套容器色，与 palette 的「哪个字配哪个底」无关（Chip /
SegmentedButton / NavigationBar / FilledButton 这些已在 `AppTheme.build` 里显式
收口，页面里剩下的必须自己用 `onColor`）。

`onColor` 保证 **≥ 4.5:1**、`onColorSoft` 保证 **≥ 3.5:1**（WCAG 正文/次要文字），
七套主题逐组由 `test/palette_contrast_test.dart` 自动守着（42 条），
改色板跑一下就知道有没有踩线。

另外：**`textTertiary` 是校准过的**（标签、单位、时间戳、空态提示都用它）。出厂值
`#9CA3AF` 在白卡上只有 2.54:1，是「字和底撞一起看不清」的头号来源；现在七套主题
都压在卡片底 ≥ 4.5:1、页面底 ≥ 4.0:1（浅色主题的 `textTertiary` 因此明显变深，
这是有意的）。加新主题时别凭手感挑一个浅灰 —— 直接跑那个测试。

### 11. `SpringDriver` —— 保留速度的弹簧（进阶）

`AppMotion.springTrack` / `springPress` / `springSettle` / `springHover` 是
`SpringDescription`（不是 `Curve`），喂给 `SpringDriver`：

```dart
final driver = SpringDriver(this /* TickerProvider */, 0); // 记得 dispose
driver.springTo(1, AppMotion.springSettle);                 // 连点/拖动不打断手感
driver.jumpTo(0);                                           // 减少动态效果时直接落位
```

与 `AnimationController.animateWith` 的区别：后者的 ticker 每次重定向都要重启，
首帧读不到已流逝时间，手指每帧都在动时值会被钉住不动。底部导航
（`lib/ui/shell/app_nav_bar.dart`）的「透镜跟手 + 果冻拉伸 + 松手落位」就是靠它。

### 12. 悬浮底栏 `AppNavBar`（Shell 独占，页面不用碰）

底部 Tab 栏是 FlClash 那套悬浮 dock：`lib/ui/shell/app_nav_bar.dart`，只在
`main_shell.dart` 里挂一次，**页面不要自己再加底栏**。

```dart
AppNavBar(
  selectedIndex: index,
  hasBackground: hasBackground,          // 有背景图时走玻璃底
  onSelected: (i) => context.go(_locations[i]),
  destinations: [AppNavDestination(icon: ..., selectedIcon: ..., label: '首页', badge: 3)],
)
```

行为（与 FlClash `navigation_dock.dart` 对齐，参数同名同值）：
- **按下**：透镜（lens）移到按下的格子并放大（`springPress` 280ms bounce 0.2），整条 dock 轻微「膨胀」（`_pressGrowth = 1/8`，上限 16px）。
- **拖动**：过 `kTouchSlop` 才进入拖拽；透镜跟手（`springTrack` 120ms bounce 0，**保留速度**，不被打断）；越过两端时果冻阻尼 `_rubberBand(overshoot, limit) = limit × (1 − 1/(|o|×0.55/limit + 1))`，横向拉伸上限 `_pullLimit = 7/32` 屏宽；**每换一格 `HapticFeedback.selectionClick()`**。
- **松手**：透镜落到最近格子（`springSettle` 500ms bounce 0.32）、拉伸归零、`HapticFeedback.lightImpact()`、`onSelected(index)`（与当前页相同时不回调）。
- **减少动态效果**（`MediaQuery.disableAnimations`）时全部 `jumpTo`，不做位移。

刻意没抄的：hover 磁吸与透镜放大镜着色（Android 没有 hover，Web 上 blur 着色开销高）。
格子本身**不挂 `GestureDetector`** —— 整条 dock 只有一个 `Listener` 提交选中，
避免「格子 tap + dock drag」双份提交；无障碍语义靠每个格子的 `Semantics(button/selected/label)`。

回归：`test/app_nav_bar_test.dart`（5 条：角标、点击、拖动、减少动态效果、选中语义）。

## 四、页面改造清单（每页都该有的东西）

1. **首屏内容错峰进场**：主要卡片 / 列表项包 `EnterBox(index:)`。
2. **Tab / 菜单 / 筛选切换**用 `SlideFadeSwitcher`，不要硬切。
3. **数字**（余额、积分、连续天数、统计）换成 `AnimatedCount` / `StatBlock(number:)`。
4. **进度**（今日任务进度、目标完成度、勋章进度）换成 `AnimatedProgressBar`。
5. **首屏加载**换 `SkeletonList`。
6. **成功瞬间**调 `showBurst(context)`。
7. **弹窗 / 底部弹层**：进场用 `AppMotion.slow`、出场 `AppMotion.fast`
   （`showModalBottomSheet` 自带；自定义路由在 `pageTransitionsTheme` 里已统一）。
   路由级转场全平台统一为官方 `animations` 包的 **shared axis（水平）** ——
   见 `AppMotion.pageTransitionsTheme` 与 `SharedAxisPageTransitionsBuilder`
   （`fillColor: Colors.transparent` 必须显式给，否则过渡期新页会铺一层不透明底
   把旧页整个盖住，看起来像闪一下底色）。
8. **图表**（fl_chart 1.2.0）：`duration: AppMotion.slower, curve: AppMotion.emphasized`。
   ⚠️ 这两个旋钮挂在 **`BarChart` widget** 上，不在 `BarChartData` 里；旧名
   `swapAnimationDuration` / `swapAnimationCurve` 在 1.2.0 已标 `@Deprecated`，
   写了会新增 `deprecated_member_use` info（源码就是
   `super(duration: swapAnimationDuration ?? duration, ...)`，同一组旋钮）。

## 五、硬约束

- **不改功能**：文案、导航路径、query 参数、状态逻辑、接口调用一律不动，只动表现层。
- **不改共享文件**：`lib/theme/**`、`lib/ui/widgets/**`、`lib/ui/shell/**`、`lib/core/**`、
  `lib/state/**`、`lib/data/**` 都不许改。需要新的共享组件就先找 Lead。
- **不加依赖**（`animations` 已在，够用）。
- **不跑 `dart format`**：仓库不是 tall-style 格式化的，一跑就是几千行 diff。
- **不要硬编码颜色 / 间距 / 圆角**：从 `context.palette` 与
  `theme/tokens.dart`（`AppSpacing` / `AppRadius` / `AppFontSize`）取。
- **无障碍**：不要自己写 `MediaQuery.disableAnimations` 判断——上面的组件都内置了；
  自己写 `AnimationController` 时要照做（`disableAnimations` 时直接 `value = 1`）。
- 验收：`flutter analyze --no-pub <自己改的文件>` **0 error**（info 保持不新增）。

## 六、怎么验收「动效真的在动」

静态截图证明不了动画，**必须抓到中间态**。两条路，都已经跑通。

### 1. 自动回归：`test/motion_widgets_test.dart`

```bash
flutter test --no-pub test/motion_widgets_test.dart   # 12 个用例
```

覆盖：`EnterBox` 起止透明度/位移（含 `delay` 段与 `disableAnimations` 短路）、
`AnimatedCount` 从旧值滚到新值、`PressScale` 按下-松手回到 1.0、
`AnimatedProgressBar` 的 widthFactor、骨架呼吸、`SlideFadeSwitcher` 切换时
「新旧内容同时在场」、`showBurst` 盖一层再收掉、`AppCard` 的 `onTap`
不被按压动画抢走。

### 2. 肉眼抓中间态：`--dart-define=SLOW_MO=N`

`lib/main.dart` 里有一个 inert 的验收开关：

```bash
flutter build web --release --no-pub --dart-define=SLOW_MO=60
```

它只做一件事：`timeDilation = N`（把全局动画放慢 N 倍，默认 1 倍不生效）。
慢放之后转场窗口从 300ms 拉到十几秒，CDP 截图这种「百毫秒级往返」的工具才抓得住。

```bash
flutter run -d chrome --dart-define=SLOW_MO=20     # 本地也可以直接这么看
```

⚠️ 慢放只影响时间轴，不影响布局；验收完记得 **不带 `SLOW_MO` 重新构建**，
否则产物跑起来所有动画都会慢得离谱。

### 3. 已留证的中间态截图（`docs/shots/`）

`21-page-transition-b.png` 是 `#/settings → #/family` 的转场中间态，一帧里同时能看到四件事：

- **路由 shared axis 转场**：新页（账本）正在滑入、旧页（设置）已淡出，底部导航停在「设置」；
- **错峰进场**：账本只有第一张卡（当前总积分）已显影，其余卡片还没轮到；
- **数字滚动**：大数字停在 `5`（`AnimatedCount` 正从 0 滚向 105）；
- **导航指示器滑动**：高亮胶囊卡在「家庭」和「设置」之间，两边的圆角都还在。

`docs/shots/10–14-*-mobile.png` 是 390×844 手机视口下 5 个主页面稳定态的实拍。
