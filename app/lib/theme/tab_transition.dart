import 'motion.dart';

/// 换 Tab 时内容页怎么切过来。
///
/// 为什么单独一个枚举：设置页要把它们列出来让人挑、转场实现要按它分派、
/// 而它本身只是「名字 + 文案 + 时长档」，不依赖任何 widget 树 —— 放 theme 层，
/// 和 [AppMotion] 一样属于「动效的语言」，谁都能读，没人会去改它的实现细节。
///
/// 时长原则同 motion.dart：**只从 [AppMotion] 取**，不要在这里写裸毫秒数，
/// 否则调一档时长要满仓库找。
enum TabTransition {
  // ---- 基准：现在线上跑的那一个 ----

  slideFade(
    id: 'slide-fade',
    group: '基准',
    label: '滑入淡出',
    hint: '现在的默认：旧页往回走 16px 淡出，新页跟着方向滑进来',
    duration: AppMotion.fast,
    reverseDuration: AppMotion.instant,
  ),

  // ---- 方向感：位移大，越翻越像翻页 ----

  paging(
    id: 'paging',
    group: '方向感',
    label: '整屏滑动',
    hint: '新旧两页整屏并排平移，像 iOS 分页 —— 最贵也最直观',
    duration: AppMotion.slow,
    reverseDuration: AppMotion.slow,
  ),
  parallax(
    id: 'parallax',
    group: '方向感',
    label: '视差滑入',
    hint: '旧页只退 34% 并缩到 0.965，新页全速盖上来',
    duration: AppMotion.slow,
    reverseDuration: AppMotion.slow,
  ),

  // ---- 景深：缩放代替位移，适合「同一件事的不同层」 ----

  scaleFade(
    id: 'scale-fade',
    group: '景深',
    label: '缩放淡入',
    hint: '新页从 0.92 放大到位，旧页放大到 1.05 淡出',
    duration: AppMotion.normal,
    reverseDuration: AppMotion.normal,
  ),
  zoomThrough(
    id: 'zoom-through',
    group: '景深',
    label: '穿越推近',
    hint: '新页从 1.08 压进来，旧页缩到 0.9 退走 —— 比缩放更「冲」',
    duration: AppMotion.normal,
    reverseDuration: AppMotion.normal,
  ),

  // ---- 质感：靠模糊 / 擦除做「材质感」，不靠位移 ----

  blurSlide(
    id: 'blur-slide',
    group: '质感',
    label: '模糊滑入',
    hint: '带 8px 模糊滑进，落定时收干 —— 老机型可能掉帧',
    duration: AppMotion.slow,
    reverseDuration: AppMotion.slow,
  ),
  wipe(
    id: 'wipe',
    group: '质感',
    label: '方向擦除',
    hint: '没有位移，从翻页来的一侧把新页擦出来',
    duration: AppMotion.slow,
    reverseDuration: AppMotion.slow,
  ),

  // ---- 物理：弹簧曲线，落点会冲过头 ----

  springSlide(
    id: 'spring-slide',
    group: '物理',
    label: '弹簧过冲',
    hint: '56px 位移带弹簧回弹，落点会轻轻冲过头再回来',
    // 弹簧要留出回弹的时间，240 太短会「跳」到终点，取 slower 档
    duration: AppMotion.slower,
    reverseDuration: AppMotion.fast,
  ),
  popScale(
    id: 'pop-scale',
    group: '物理',
    label: '弹性缩放',
    hint: '从 0.86 弹到 1，回弹最明显 —— 连续点会有跟手感',
    duration: AppMotion.slower,
    reverseDuration: AppMotion.fast,
  ),

  // ---- 编排：让「新内容」不是整体一起到，而是有先后 ----

  stagger(
    id: 'stagger',
    group: '编排',
    label: '逐层揭开',
    hint: '新页从上往下揭开并轻轻上移，比整体淡入更有层次',
    duration: AppMotion.normal,
    reverseDuration: AppMotion.instant,
  ),
  dockFirst(
    id: 'dock-first',
    group: '编排',
    label: '底栏先行',
    hint: '底栏先响应，内容晚 70ms 再淡进来 —— 点击反馈更快',
    duration: AppMotion.normal,
    reverseDuration: AppMotion.fast,
  ),
  flip3d(
    id: 'flip-3d',
    group: '编排',
    label: '3D 翻转',
    hint: '沿竖轴转 18° 进来，翻转方向跟着翻页方向',
    duration: AppMotion.slow,
    reverseDuration: AppMotion.slow,
  ),
  sharedAxisY(
    id: 'shared-axis-y',
    group: '编排',
    label: '纵向推进',
    hint: 'SharedAxis 的竖直版：新页从下方 30% 推进来',
    duration: AppMotion.slow,
    reverseDuration: AppMotion.slow,
  );

  const TabTransition({
    required this.id,
    required this.group,
    required this.label,
    required this.hint,
    required this.duration,
    required this.reverseDuration,
  });

  /// 落盘用的稳定标识 —— **不要用枚举的 name**，以后重命名枚举不该让用户的选择失效。
  final String id;

  /// 设置页的分组标题（按手感分，不是按实现分）
  final String group;

  /// 设置页显示的名字
  final String label;

  /// 设置页一句话说明「动起来是什么感觉」
  final String hint;

  /// 进场时长
  final Duration duration;

  /// 退场时长（新页进来时旧页走多久）
  final Duration reverseDuration;

  /// 出厂默认 = 逐层揭开：新页从上往下揭开并轻轻上移，比整体淡入更有层次。
  /// 没在设置里选过的人都走这一套；选过的人照旧读自己存的那一个。
  static const TabTransition defaultTransition = TabTransition.stagger;

  /// 从存储里读到的字符串还原（脏值/老值一律回默认，不让设置问题拦住启动）。
  static TabTransition fromId(String? raw) {
    for (final TabTransition item in values) {
      if (item.id == raw) return item;
    }
    return defaultTransition;
  }
}
