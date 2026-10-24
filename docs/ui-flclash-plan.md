# 把 SekaiNook 的 UI 换成 FlClash 那套：可行性与方案（2026-10-24）

> 结论先行：**「把 fl_ui 全部用上」不建议也做不到** —— 92 个文件里约一半是 FlClash 的**桌面端/展示站**专用件（多窗口、键盘焦点导航、窗口拖拽、演示画廊），SekaiNook 只有 Android + Web。
> **但「把页面范式整套换成 FlClash 的」完全可行**，而且你现在已经接了三分之一地基。下面给的是分三批的做法、估时和风险。

---

## 1. 现状：你已经用了 fl_ui 的哪一层

SekaiNook 对 fl_ui 的依赖很薄，外部只 import 了 11 个模块：

| 已用 | 在哪 |
|---|---|
| `navigation_dock.dart`（2049 行，整套壳里最核心的那个） | `ui/shell/main_shell.dart:219` 底部胶囊导航 |
| `view_scope.dart` / `measure.dart` / `liquid_glass.dart` | `app.dart:204-217` 三层作用域（玻璃**默认关**，`const bool glass = false`） |
| `icons/*`（贴纸风格图标） | 导航、顶栏、设置 |
| `dialog.dart` | 6 处弹窗 |
| `typography` / `surface` / `shape` / `card` / `loading` | 零散样式与结构 |

页面骨架则是**自研**的：原生 `Scaffold` + 自研 `AppTopBar`（481 行）+ `AppCard`（87 处使用）+ `state_views.dart`（Loading/Error/Empty 三态）。

也就是说：**底座（组件库、主题作用域、图标、导航）已经接好，页面层还是自己画的。**

## 2. fl_ui 里那些「没用上」的，哪些能用、哪些别碰

92 文件 / 29667 行，从 `main.dart` 不可达 39 个 / 9726 行。按能不能用到 SekaiNook 分三类：

### A. 值得接上（移动端 + Web 都成立，约 25 个）

| 组件 | 行数 | 换成它意味着什么 |
|---|---|---|
| `scaffold.dart` `CommonScaffold` | 1338 | **FlClash 的页面标准骨架**：滚动折叠 AppBar、搜索栏、body clearance、溢出菜单。替代现在的「原生 Scaffold + 自研 AppTopBar 浮层」 |
| `popup.dart` `CommonPopupRoute` | 2687 | 锚点弹层（点哪弹哪、带 morph 动画）。替代自研 toast/菜单/确认框 |
| `snap_sheet.dart` `SnapSheet` | 1447 | FlClash 的底部抽屉（弹簧、多档吸附）。替代 `showModalBottomSheet` 和现在的自定义面板 |
| `list.dart` `ListItem/ListHeader/ListFooter` | 601 | 标准行式列表（标题/副标题/尾部选项/点击区）。替代自研 `task_row` 与卡片里的散装 Row |
| `null_status.dart` `NullStatus(+Switcher)` | 753 | **四态自动切换**（loading / empty / noResults / content）+ 插画空态。直接替掉 `state_views.dart` 三件套 |
| `card.dart` `CommonCard / InfoHeader` | 271 | FlClash 的卡片范式 |
| `sheet.dart` / `sheet_header.dart` / `form_sheet.dart` / `side_sheet.dart` | ~900 | 面板与表单页（编辑提醒、加任务） |
| `search_field.dart` / `segmented_control.dart` | 180 | 搜索框 / 分段控制（家庭页分区切换） |
| `line_chart.dart` | 220 | 家庭页 14 天趋势图（现在是自绘） |
| `skeleton.dart` | 114 | 骨架屏（替代自研 SkeletonList） |
| `chip.dart` / `button.dart` / `input.dart` | ~700 | 统一的标签/按钮/输入 |
| `open_container.dart` / `sortable.dart` / `keyed_animated_list.dart` / `collapsible_section.dart` | ~1800 | 详情转场 / 拖拽排序 / 增删动画 / 折叠区 |
| `motion.dart` / `effect.dart` / `fade_box.dart` / `loading.dart` | ~500 | 动效与加载态 |

### B. 桌面端专用，**别用**（约 20 个，占不可达文件的一半）

- 多窗口/窗口管理：`navigator_resizable.dart`(523)、`sidebar.dart`(574)、`context_menu.dart`(215)、`table_layout.dart`(243)、`drag_back.dart`(262)、`navigator.dart`(213)
- 键盘焦点导航（桌面 Tab/方向键那套）：`focus.dart`、`focus_keyboard.dart`、`focus_arrow_keys.dart`、`focus_landing.dart`、`focus_moved_by_key.dart`、`keyboard.dart`、`keyboard_inset_hold.dart`、`caret_popup.dart`、`text_loupe.dart`、`pop_scope.dart`、`selection_mark.dart`
- 展示站/gallery 残留：`liquid_glass_capture.dart`(967)、`generated/models.freezed.dart`(887)

这些在手机上要么没有触发入口，要么会跟系统手势/输入法打架。

### C. 系统件，保留不动

`measure.dart`、`context.dart`、`inherited.dart`、`keep_scope.dart`、`deferred_push.dart`、`metrics.dart`、`l10n.dart`、`theme.dart`、`text_style.dart`、`common/*` —— 是 A 类组件的地基，已经在跑。

### D. 液态玻璃：**保持关闭**

`app.dart:195` 的 `const bool glass = false` 是踩过坑的选择（1.31.6 真机卡爆已回滚，AGENTS.md 有记录）。`liquid_glass.dart`(1505) 与 `liquid_glass_capture.dart`(967) 只在需要玻璃的局部（比如顶栏/胶囊导航的窄条）用**轻量层**，全屏玻璃不要再开。

## 3. 目标形态（换成 FlClash 后，页面长什么样）

| 现在 | 换成 |
|---|---|
| 原生 Scaffold + 自绘 AppTopBar 浮层 + 页面各自算 `contentInset` | `CommonScaffold`：顶栏随滚动折叠、搜索/菜单自动收纳，页面不用再手算状态栏与胶囊让位 |
| `AppCard` 大卡片堆叠（首页/家庭/花园/设置共 87 处） | `CommonCard` + `ListItem` 的组合：**信息密度更高、行式为主、卡片只用于成组模块** |
| `showDialog` + 自绘 bottom sheet | `CommonPopupRoute`（锚点弹层）+ `SnapSheet`（底部抽屉） |
| `state_views.dart` 三态 | `NullStatus`：四态 + 插画，一行切换 |
| 家庭页自绘趋势图 | `LineChart` |
| 自定义 tab/chip/按钮 | `SegmentedControl` / `Chip` / fl_ui Button |
| 各页自己写「加载中/出错/空」 | `NullStatusSwitcher` 统一 |

## 4. 分三批做（估时按一个人算）

### 批 1：把「交互件」换成 fl_ui（低风险，2-3 天）

范围：
- `state_views.dart` → `NullStatus`（所有页面的加载/错误/空态）
- 6 处 `showDialog` → `CommonPopupRoute` 或保留（确认框可留）
- 所有底部面板 → `SnapSheet`（提醒编辑、任务编辑、打卡弹窗）
- 家庭页分区 tab → `SegmentedControl`
- 加任务/编辑提醒表单 → `form_sheet`
- 骨架屏 → `skeleton.dart`

验收：现有 201 条测试全绿；真机点一遍四个页面的弹窗与空态；Web 构建通过。

风险：低。这些是「替换一个 widget」，不动布局树。

### 批 2：页面骨架换成 `CommonScaffold`（中风险，5-8 天）

范围：5 个主页面逐个改（家长首页 / 孩子首页 / 家庭页 / 花园页 / 设置页）。

要处理的耦合（这是真正的工作量）：
1. **顶栏**：`AppTopBarHost` 浮层机制要退役，页面改用 `CommonScaffold` 的 appBar 插槽；
2. **返回键**：现在的 `BackIntentDispatcher` + `_backStack`（`main_shell.dart:41-47`）与 `CommonScaffold` 的滚动折叠/搜索退出要接上，不能两套返回逻辑打架；
3. **底部胶囊**：`NavigationDock` 与 `CommonScaffold` 的 body 让位要重新对齐（现在靠 `extendBody` + 手工抹 `MediaQuery.padding`，见 `main_shell.dart:180-200` 那段长注释）；
4. **动画**：`SlideFadeSwitcher` 换页动画与 `page_transition.dart` 二选一。

建议**先改一个页面做试点**（家长首页或设置页），真机看观感与滚动性能，再决定其余四个。

### 批 3：卡片与列表体系全量替换（高风险，5-7 天）

范围：`AppCard` 87 处 → `CommonCard` / `ListItem`；家庭页趋势图 → `LineChart`；统一按钮/输入/chip。

风险最高，因为会动到**所有页面的视觉基线**：
- `AppCard` 与 `AppTheme` 的 `AppPalette`（实现了 lerp 的主题色板）深度绑定，`CommonCard` 用的是 FlClash 的色彩假设，可能出现「卡片突然不跟随主题」；
- 87 处替换意味着**几乎每个页面的截图都会变**，回归验证成本高；
- 必须逐页真机对比，不能只看 analyze 通过。

### 可选：批 0（半天）——先做一次「可行性试样」

不改业务页，只在设置页里加一个 `/ui-preview` 路由，把 `CommonScaffold + ListItem + SnapSheet + NullStatus` 拼一个静态样板页，装到手机上滑一遍。
**这半天能回答「FlClash 这套在 SekaiNook 的视觉与性能上到底合不合适」，比直接进批 3 划算得多。**

## 5. 总计与建议

| 批次 | 估时 | 风险 | 收益 |
|---|---|---|---|
| 批 0 试样 | 0.5 天 | 极低 | 提前排除方向性错误 |
| 批 1 交互件 | 2-3 天 | 低 | 空态/弹窗/面板统一，用户立刻能感知 |
| 批 2 页面骨架 | 5-8 天 | 中 | 「像 FlClash」的主要观感来源 |
| 批 3 卡片列表 | 5-7 天 | 高 | 信息密度与一致性，但回归成本最高 |

建议顺序：**批 0 → 批 1 → 批 2（先一页试点）→ 视情况决定批 3**。
如果只想到「看起来是 FlClash 那套」，批 2 结束就够；批 3 是「彻底统一」，可以放两个版本做。

## 6. 明确不建议做的

- **不要为了「全部用上」而去接 B 类桌面件** —— 它们没有移动端入口，接了只会增加编译与维护负担。
- **不要开全屏液态玻璃** —— AGENTS.md 的 1.31.6 教训（真机卡爆已回滚）。
- **不要动 `MainShell` 的轮询/通知/更新逻辑** —— 上一轮刚做完请求合并，UI 重构不要顺手带进状态层。
- **不要一次性全量替换** —— 这批改动没有 CI 兜底（见优化审查 §6），一锅端出问题很难定位。

## 7. 需要你决定的三个点

1. **视觉方向**：要「FlClash 那种紧凑行式 + 锚点弹层」的观感，还是只想要「组件统一、观感不变」？前者要做批 2+3，后者批 1 就够。
2. **主题**：保留现在的 7 套色板 + 动态取色（`AppTheme`），还是换成 FlClash 的 Material 3 默认 scheme？前者安全，后者才「像」。
3. **节奏**：一个版本内做完（2-3 周），还是分两个版本（批 1 先发，批 2 下一版）？分两版对家里人更友好。

---

## 8. 实施记录（2026-10-24，首轮已落盘）

用户拍板「能做的全做了，毫无意义的不能用的就不用管了」，所以本轮直接接上了「低风险、看得见、不动状态层」的那部分。

### 8.1 已接

| 件 | 落点 | 效果 |
|---|---|---|
| `showAppSheet`（`SnapSheetRoute`） | 孩子打卡 `kid_home_page.dart`、家庭页代记账 `family_dashboard_page.dart`、家庭页驳回理由、提醒编辑 `reminder_editor_sheet.dart` | 弹窗从屏幕正中改成**底部升起的面板**，跟手拖拽、下拉关闭；挂在 root Navigator 上，比悬浮胶囊高一层，按钮不会再被挡 |
| `SegmentedControl` | 家庭页三个分区（任务区 / 待审批 / 历史记录） | 胶囊滑块替代 TabBar，高亮仍由 URL 派生 |
| `NullStatus` | 家庭页「暂无待审批」「暂无流水」、花园页「今日已完成」「阳光流水」 | 空态换成带插画 + 入场动画的 FlClash 空状态 |
| 试样间 `/ui-preview` | 新页面 `app/lib/ui/pages/ui_preview_page.dart`，设置 → 关于 → 「FlClash 试样间」进入 | 一页看全 `CommonScaffold` / `CommonCard` / `ListItem` / `SearchField` / `SkeletonPill` / `NullStatus` / `SnapSheet`，不挂主壳，用来判断「要不要真的把页面骨架全换」 |

新增文件：`app/lib/ui/widgets/app_sheet.dart`（`showAppSheet` 统一入口）、`app/lib/ui/pages/ui_preview_page.dart`。

### 8.2 本轮明确跳过（及理由）

- **`CommonScaffold` 换页面骨架（批 2）**：它会自带顶栏/搜索/溢出菜单，和现有 `MainShell` 的浮层顶栏 `AppTopBarHost` + 悬浮 `NavigationDock` 冲突。真要换得把 shell 一起重构，不是「接组件」而是「换壳」，回归风险最高 —— 先看试样间观感再定。
- **`AppCard` → `CommonCard`（批 3，87 处）**：`CommonCard` 是 `FilledButton` 语义，**没有 `onLongPress`**，而账本卡的长按菜单是现有交互；换掉会丢语义，收益只是圆角/按压手感。
- **`LineChart`**：它是「滑动窗口 + 高斯平滑的实时曲线」（`capacity`/`revision`），不是「14 天每日次数」的趋势图，语义不匹配。
- **`ListItem` 替换通知/流水卡**：这些行带未读高亮、正文配色、状态标签等业务语义，行式列表会丢信息。
- **确认框（兑换/删任务/撤回/删除记录）改底部面板**：确认框要的是「快」，居中反而更好；只把**表单类**（打卡、驳回理由、提醒编辑）改成了面板。
- **`state_views` 全局换 `NullStatus`**：`NullStatus` 自带滚动容器，在无固定高度的 `AppCard` 里会布局报错，所以只逐处替换（外面套固定高度）。

### 8.3 验证

- `flutter analyze --no-pub`：101 issues，与基线一致（全是既有 info/warning），**无 error**。
- `flutter test --no-pub`：201 条全过。首轮跑时 `garden_flow_test.dart` 有一例失败（打生产后端的已知偶发），单跑通过。
- **尚未发版**：视觉变化主观，建议先在试样间/真机看一眼，确认方向后再走 2.7.0 发版（网页版 + APK 一起）。

