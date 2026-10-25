import 'dart:math' as math;

import 'package:sekainook_app/fl_ui/icons/app_glyphs.dart';
import 'package:sekainook_app/fl_ui/icons/glyph.dart';

/// SekaiNook 的图标入口。
///
/// 页面一律用 [GlyphIcon] + 这里的常量，不再直接用 Material `Icons.*`：
/// - 能复用 FlClash 自绘 Glyph 的，直接别名到 [AppGlyphs]；
/// - 业务专属图标（花/树/钱袋/奖杯…）用同一套 24×24 原语新绘，保持
///   `Glyph.strokeWidth = 1.8` 描边、`body / detail / line` 三层粗细，
///   与 FlClash 图标混排时不会一半填充一半线框。
abstract final class AppIcons {
  // ── 复用 FlClash 自绘图标 ────────────────────────────────────────────
  static const arrowBack = AppGlyphs.arrowBack;
  static const chevronBack = AppGlyphs.chevronBack;
  static const chevronForward = AppGlyphs.chevronForward;
  static const chevronDown = AppGlyphs.chevronDown;
  static const chevronUp = AppGlyphs.chevronUp;
  static const add = AppGlyphs.add;
  static const addCircle = AppGlyphs.addCircle;
  static const remove = AppGlyphs.remove;
  static const removeCircle = AppGlyphs.removeCircle;
  static const close = AppGlyphs.close;
  static const check = AppGlyphs.check;
  static const checkDouble = AppGlyphs.checkDouble;
  static const checkCircle = AppGlyphs.checkCircle;
  static const delete = AppGlyphs.delete;
  static const edit = AppGlyphs.edit;
  static const compose = AppGlyphs.compose;
  static const copy = AppGlyphs.copy;
  static const refresh = AppGlyphs.refresh;
  static const reset = AppGlyphs.reset;
  static const undo = AppGlyphs.undo;
  static const download = AppGlyphs.cloudDownload;
  static const upload = AppGlyphs.upload;
  static const sync = AppGlyphs.cloudSync;
  static const eye = AppGlyphs.eye;
  static const eyeOff = AppGlyphs.eyeOff;
  static const lock = AppGlyphs.lock;
  static const lockOpen = AppGlyphs.lockOpen;
  static const key = AppGlyphs.key;
  static const sliders = AppGlyphs.sliders;
  static const settings = AppGlyphs.settings;
  static const dashboard = AppGlyphs.dashboard;
  static const profiles = AppGlyphs.profiles;
  static const requests = AppGlyphs.requests;
  static const info = AppGlyphs.info;
  static const warning = AppGlyphs.warning;
  static const error = AppGlyphs.error;
  static const palette = AppGlyphs.palette;
  static const camera = AppGlyphs.camera;
  static const photos = AppGlyphs.photos;
  static const star = AppGlyphs.star;
  static const bolt = AppGlyphs.bolt;
  static const broom = AppGlyphs.broom;
  static const devices = AppGlyphs.devices;
  static const clock = AppGlyphs.requests;
  static const sun = AppGlyphs.sun;
  static const pureBlack = AppGlyphs.pureBlack;
  static const motion = AppGlyphs.motion;
  static const language = AppGlyphs.language;
  static const font = AppGlyphs.font;
  static const textSize = AppGlyphs.textSize;
  static const link = AppGlyphs.link;
  static const send = AppGlyphs.send;
  static const sort = AppGlyphs.sort;
  static const filter = AppGlyphs.filter;
  static const sparkle = AppGlyphs.sparkle;
  static const target = AppGlyphs.target;
  static const puzzle = AppGlyphs.puzzle;
  static const layers = AppGlyphs.layers;
  static const speed = AppGlyphs.speed;
  static const dataUsage = AppGlyphs.dataUsage;
  static const memory = AppGlyphs.memory;
  static const cpu = AppGlyphs.cpu;
  static const qrCode = AppGlyphs.qrCode;
  static const torch = AppGlyphs.torch;
  static const vpn = AppGlyphs.vpn;
  static const verified = AppGlyphs.verified;
  static const swap = AppGlyphs.swap;
  static const split = AppGlyphs.split;
  static const account = AppGlyphs.account;
  static const tools = AppGlyphs.tools;
  static const wrench = AppGlyphs.wrench;
  static const toggle = AppGlyphs.toggle;
  static const pin = AppGlyphs.pin;
  static const locate = AppGlyphs.locate;
  static const wifi = AppGlyphs.wifi;
  static const wifiOff = AppGlyphs.wifiOff;
  static const dns = AppGlyphs.dns;
  static const appsList = AppGlyphs.appsList;
  static const rules = AppGlyphs.rules;
  static const code = AppGlyphs.code;
  static const keyboard = AppGlyphs.keyboard;
  static const openExternal = AppGlyphs.openExternal;
  static const cloudDownload = AppGlyphs.cloudDownload;
  static const liquidGlass = AppGlyphs.liquidGlass;
  static const image = AppGlyphs.photos;

  // ── 业务专属新绘（24×24 网格，内容区 3.5–20.5）────────────────────────

  /// 房子：首页/家庭。
  static const home = Glyph([
    GlyphPolyline([
      GlyphVertex(4, 11.2),
      GlyphVertex(12, 4, 1.6),
      GlyphVertex(20, 11.2, 1.6),
      GlyphVertex(20, 20.5, 2.2),
      GlyphVertex(4, 20.5, 2.2),
    ], closed: true),
    GlyphPolyline([
      GlyphVertex(9.8, 20.5),
      GlyphVertex(9.8, 15, 1),
      GlyphVertex(14.2, 15, 1),
      GlyphVertex(14.2, 20.5),
    ], role: GlyphRole.detail),
  ]);

  /// 铃铛：通知。
  static const bell = Glyph([
    GlyphPolyline([
      GlyphVertex(6.6, 16.6, 2.4),
      GlyphVertex(7.4, 14.4, 1),
      GlyphVertex(7.4, 11, 1.6),
      GlyphVertex(12, 5.2, 3),
      GlyphVertex(16.6, 11, 1.6),
      GlyphVertex(16.6, 14.4, 1),
      GlyphVertex(17.4, 16.6, 2.4),
      GlyphVertex(6.6, 16.6, 2.4),
    ]),
    GlyphPolyline([
      GlyphVertex(3.6, 16.6),
      GlyphVertex(20.4, 16.6),
    ], role: GlyphRole.detail),
    GlyphCircle(12, 19.4, 1.5, role: GlyphRole.detail, solid: true),
  ]);

  /// 月亮：夜间模式。
  static const moon = Glyph([
    GlyphPath(
      'M14.6 3.6 C9.6 4.6 5.2 8 5.2 12 C5.2 16.4 9.2 20.2 14.4 20.4 '
      'C10.4 17.2 9.8 6.6 14.6 3.6 Z',
    ),
  ]);

  /// 花：花园/种植。
  static const flower = Glyph([
    GlyphCircle(12, 7.6, 3.1),
    GlyphCircle(7.2, 11.8, 3.1),
    GlyphCircle(16.8, 11.8, 3.1),
    GlyphCircle(9.4, 16.6, 2.8),
    GlyphCircle(14.6, 16.6, 2.8),
    GlyphCircle(12, 12.2, 1.9, role: GlyphRole.detail, solid: true),
  ]);

  /// 树：户外/公园。
  static const tree = Glyph([
    GlyphPolyline([
      GlyphVertex(12, 3.6, 2),
      GlyphVertex(18.4, 12.4, 1.6),
      GlyphVertex(15.2, 12.4, 1),
      GlyphVertex(19.6, 18.6, 1.6),
      GlyphVertex(4.4, 18.6, 1.6),
      GlyphVertex(8.8, 12.4, 1),
      GlyphVertex(5.6, 12.4, 1.6),
      GlyphVertex(12, 3.6, 2),
    ]),
    GlyphPolyline([
      GlyphVertex(12, 18.6),
      GlyphVertex(12, 20.6),
    ], role: GlyphRole.detail),
  ]);

  /// 叶子：环保/成长。
  static const leaf = Glyph([
    GlyphPath(
      'M4.4 19.8 C4.4 10.6 11 4.2 20 4.2 C20 13.4 13.4 19.8 4.4 19.8 Z',
    ),
    GlyphPolyline([
      GlyphVertex(7, 17.2),
      GlyphVertex(16.6, 7.6),
    ], role: GlyphRole.detail),
  ]);

  /// 餐具：吃饭类任务。
  static const meal = Glyph([
    GlyphPath(
      'M3.8 11.8 C3.8 16.6 7.4 20.2 12 20.2 C16.6 20.2 20.2 16.6 20.2 11.8 Z',
    ),
    GlyphPolyline([
      GlyphVertex(8.6, 8.6),
      GlyphVertex(8.6, 5.2),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(12, 7.8),
      GlyphVertex(12, 4.2),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(15.4, 8.6),
      GlyphVertex(15.4, 5.2),
    ], role: GlyphRole.detail),
  ]);

  /// 洗衣机：洗衣类任务。
  static const laundry = Glyph([
    GlyphBox(4, 3.6, 20, 20.4, 2.6),
    GlyphCircle(12, 13.4, 4.6, role: GlyphRole.detail),
    GlyphCircle(7.6, 7.2, 0.9, role: GlyphRole.detail, solid: true),
  ]);

  /// 商店：兑换/奖励。
  static const store = Glyph([
    GlyphBox(4.2, 10, 19.8, 20.4, 2),
    GlyphPolyline([
      GlyphVertex(3.8, 10, 1),
      GlyphVertex(5.4, 6, 1.6),
      GlyphVertex(18.6, 6, 1.6),
      GlyphVertex(20.2, 10, 1),
    ]),
    GlyphPolyline([
      GlyphVertex(10.2, 20.4),
      GlyphVertex(10.2, 14.6),
      GlyphVertex(13.8, 14.6),
      GlyphVertex(13.8, 20.4),
    ], role: GlyphRole.detail),
  ]);

  /// 礼卡：奖励/礼物。
  static const gift = Glyph([
    GlyphBox(4.2, 10, 19.8, 20.4, 2),
    GlyphBox(3.6, 6.6, 20.4, 10, 1.4),
    GlyphPolyline([
      GlyphVertex(10.8, 6.6),
      GlyphVertex(10.8, 20.4),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(13.2, 6.6),
      GlyphVertex(13.2, 20.4),
    ], role: GlyphRole.detail),
    GlyphCircle(8.8, 4.4, 2, role: GlyphRole.detail),
    GlyphCircle(15.2, 4.4, 2, role: GlyphRole.detail),
  ]);

  /// 硬币堆：储蓄。
  static const savings = Glyph([
    GlyphOval(4.6, 5.8, 19.4, 11.4),
    GlyphOval(4.6, 10.2, 19.4, 15.8),
    GlyphOval(4.6, 14.6, 19.4, 20.2),
  ]);

  /// 钱包：积分余额。
  static const wallet = Glyph([
    GlyphBox(3.6, 6, 20.4, 18.4, 3),
    GlyphPolyline([
      GlyphVertex(3.6, 10.4),
      GlyphVertex(20.4, 10.4),
    ], role: GlyphRole.detail),
    GlyphCircle(16.4, 14.4, 1.5, role: GlyphRole.detail, solid: true),
  ]);

  /// 家庭：家长/孩子。
  static const family = Glyph([
    GlyphCircle(8.4, 8, 2.8),
    GlyphArc(8.4, 17.4, 5.2, math.pi, math.pi),
    GlyphCircle(16.6, 10.6, 2.1, role: GlyphRole.detail),
    GlyphArc(16.6, 18.2, 3.9, math.pi, math.pi, role: GlyphRole.detail),
  ]);

  /// 清单核对：任务/检查表。
  static const checklist = Glyph([
    GlyphBox(3.6, 3.6, 20.4, 20.4, 3),
    GlyphPolyline([
      GlyphVertex(7.4, 12),
      GlyphVertex(10, 14.8, 0.4),
      GlyphVertex(15.4, 8.6),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(15.4, 15),
      GlyphVertex(16.8, 15),
    ], role: GlyphRole.detail),
  ]);

  /// 逾期作业：纸 + 感叹号。
  static const assignment = Glyph([
    GlyphBox(4.6, 3.6, 19.4, 20.4, 2.4),
    GlyphPolyline([
      GlyphVertex(9.4, 3.6),
      GlyphVertex(9.4, 2.4, 0.8),
      GlyphVertex(14.6, 2.4, 0.8),
      GlyphVertex(14.6, 3.6),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(12, 8),
      GlyphVertex(12, 14),
    ], role: GlyphRole.detail),
    GlyphCircle(12, 17, 1.1, role: GlyphRole.detail, solid: true),
  ]);

  /// 奖杯：成就/连续打卡。
  static const trophy = Glyph([
    GlyphPolyline([
      GlyphVertex(6.8, 4.4, 1.6),
      GlyphVertex(17.2, 4.4, 1.6),
      GlyphVertex(16.2, 11, 1.6),
      GlyphVertex(12, 13.6, 2),
      GlyphVertex(7.8, 11, 1.6),
      GlyphVertex(6.8, 4.4, 1.6),
    ], closed: true),
    GlyphArc(5.6, 7.4, 2.6, -math.pi * 0.42, math.pi * 1.1, role: GlyphRole.line),
    GlyphArc(18.4, 7.4, 2.6, math.pi * 0.32, math.pi * 1.1, role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(12, 13.6),
      GlyphVertex(12, 17.4),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(8.6, 20.4),
      GlyphVertex(15.4, 20.4),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(9.8, 17.4),
      GlyphVertex(14.2, 17.4),
    ], role: GlyphRole.detail),
  ]);

  /// 火焰：连续坚持。
  static const fire = Glyph([
    GlyphPath(
      'M12 3.4 C15.6 7.6 18.6 10.4 18.6 14.2 C18.6 18 15.6 20.6 12 20.6 '
      'C8.4 20.6 5.4 18 5.4 14.2 C5.4 10.4 8.4 7.6 12 3.4 Z',
    ),
    GlyphPath(
      'M12 11.2 C13.4 13 14.6 14.2 14.6 15.8 C14.6 17.6 13.4 18.7 12 18.7 '
      'C10.6 18.7 9.4 17.6 9.4 15.8 C9.4 14.2 10.6 13 12 11.2 Z',
      role: GlyphRole.detail,
    ),
  ]);

  /// 计算器：统计/算术。
  static const calculate = Glyph([
    GlyphBox(5, 3.6, 19, 20.4, 2.4),
    GlyphBox(7.4, 6.2, 16.6, 10, 1.2, role: GlyphRole.detail),
    GlyphCircle(8.8, 13.2, 1, role: GlyphRole.detail, solid: true),
    GlyphCircle(12.6, 13.2, 1, role: GlyphRole.detail, solid: true),
    GlyphCircle(16.4, 13.2, 1, role: GlyphRole.detail, solid: true),
    GlyphCircle(8.8, 17, 1, role: GlyphRole.detail, solid: true),
    GlyphCircle(12.6, 17, 1, role: GlyphRole.detail, solid: true),
    GlyphCircle(16.4, 17, 1, role: GlyphRole.detail, solid: true),
  ]);

  /// 收据：账单/记录。
  static const receipt = Glyph([
    GlyphPolyline([
      GlyphVertex(5.6, 3.6, 1.4),
      GlyphVertex(18.4, 3.6, 1.4),
      GlyphVertex(18.4, 20.4, 1.4),
      GlyphVertex(15.9, 18.6, 0.6),
      GlyphVertex(13.5, 20.4, 0.6),
      GlyphVertex(11.1, 18.6, 0.6),
      GlyphVertex(8.7, 20.4, 0.6),
      GlyphVertex(5.6, 18.2, 1.4),
    ], closed: true),
    GlyphPolyline([
      GlyphVertex(8.4, 8),
      GlyphVertex(15.6, 8),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(8.4, 11.6),
      GlyphVertex(15.6, 11.6),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(8.4, 15.2),
      GlyphVertex(12.6, 15.2),
    ], role: GlyphRole.detail),
  ]);

  /// 日历：计划/日期。
  static const calendar = Glyph([
    GlyphBox(3.6, 5, 20.4, 20.4, 3),
    GlyphPolyline([
      GlyphVertex(3.6, 9.8),
      GlyphVertex(20.4, 9.8),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(7.6, 3),
      GlyphVertex(7.6, 7),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(16.4, 3),
      GlyphVertex(16.4, 7),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(8, 13.6),
      GlyphVertex(10.4, 13.6),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(13.6, 13.6),
      GlyphVertex(16, 13.6),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(8, 17.2),
      GlyphVertex(10.4, 17.2),
    ], role: GlyphRole.detail),
  ]);

  /// 文件：说明/文档。
  static const file = Glyph([
    GlyphPolyline([
      GlyphVertex(6, 3.6, 1.6),
      GlyphVertex(14, 3.6, 0.6),
      GlyphVertex(18, 7.6, 1.6),
      GlyphVertex(18, 20.4, 1.6),
      GlyphVertex(6, 20.4, 1.6),
      GlyphVertex(6, 3.6, 1.6),
    ], closed: true),
    GlyphPolyline([
      GlyphVertex(14, 3.6),
      GlyphVertex(14, 7.6, 0.6),
      GlyphVertex(18, 7.6),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(9, 12),
      GlyphVertex(15, 12),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(9, 15.6),
      GlyphVertex(13, 15.6),
    ], role: GlyphRole.detail),
  ]);

  /// 上升趋势。
  static const trendUp = Glyph([
    GlyphPolyline([
      GlyphVertex(4, 17, 0.6),
      GlyphVertex(9.2, 11.2, 0.6),
      GlyphVertex(13.2, 14.4, 0.6),
      GlyphVertex(20, 6.4, 0.6),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(15.6, 6.4),
      GlyphVertex(20, 6.4, 0.4),
      GlyphVertex(20, 10.8),
    ], role: GlyphRole.line),
  ]);

  /// 下降趋势。
  static const trendDown = Glyph([
    GlyphPolyline([
      GlyphVertex(4, 7, 0.6),
      GlyphVertex(9.2, 12.8, 0.6),
      GlyphVertex(13.2, 9.6, 0.6),
      GlyphVertex(20, 17.6, 0.6),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(15.6, 17.6),
      GlyphVertex(20, 17.6, 0.4),
      GlyphVertex(20, 13.2),
    ], role: GlyphRole.line),
  ]);

  /// 单选框（选中）。
  static const radioOn = Glyph([
    GlyphCircle(12, 12, 8.2),
    GlyphCircle(12, 12, 4.2, role: GlyphRole.detail, solid: true),
  ]);

  /// 单选框（未选中）。
  static const radioOff = Glyph([
    GlyphCircle(12, 12, 8.2),
  ]);

  /// 图片损坏：加载失败。
  static const imageBroken = Glyph([
    GlyphBox(3.6, 4.6, 20.4, 19.4, 2.4),
    GlyphPolyline([
      GlyphVertex(4.6, 16.4, 0.6),
      GlyphVertex(9, 11.4, 1),
      GlyphVertex(12.2, 14.6, 0.6),
      GlyphVertex(15, 11.4, 1),
      GlyphVertex(19.4, 15.6, 0.6),
    ], role: GlyphRole.detail),
    GlyphCircle(8, 8, 1.4, role: GlyphRole.detail, solid: true),
    GlyphPolyline([
      GlyphVertex(4, 20),
      GlyphVertex(20, 4),
    ], role: GlyphRole.line),
  ]);

  /// 收件箱：待处理。
  static const inbox = Glyph([
    GlyphBox(3.8, 12.6, 20.2, 20.2, 2),
    GlyphPolyline([
      GlyphVertex(3.8, 12.6, 1.2),
      GlyphVertex(7.2, 6.4, 1.4),
      GlyphVertex(16.8, 6.4, 1.4),
      GlyphVertex(20.2, 12.6, 1.2),
    ]),
    GlyphPolyline([
      GlyphVertex(3.8, 12.6),
      GlyphVertex(9.2, 12.6, 0.8),
      GlyphVertex(10.6, 15.2, 0.6),
      GlyphVertex(13.4, 15.2, 0.6),
      GlyphVertex(14.8, 12.6, 0.8),
      GlyphVertex(20.2, 12.6),
    ], role: GlyphRole.detail),
  ]);

  /// 闹钟关闭：提醒未开。
  static const alarmOff = Glyph([
    GlyphCircle(12, 13, 7.4),
    GlyphPolyline([
      GlyphVertex(12, 9.4),
      GlyphVertex(12, 13, 0.4),
      GlyphVertex(14.6, 14.8),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(4.6, 5.4),
      GlyphVertex(7.6, 3.4),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(19.4, 5.4),
      GlyphVertex(16.4, 3.4),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(3.6, 20.4),
      GlyphVertex(20.4, 3.6),
    ], role: GlyphRole.line),
  ]);

  /// 云断开：离线。
  static const cloudOff = Glyph([
    GlyphPath(
      'M7.2 18.2 C5 18.2 3.4 16.6 3.4 14.4 C3.4 12.4 4.8 11 6.6 10.6 '
      'C6.8 7.4 9.6 4.8 12.8 4.8 C15.8 4.8 18.2 7 18.6 9.6 '
      'C20.2 10.2 21 11.6 21 13 C21 15.2 19.2 18.2 16.8 18.2 Z',
    ),
    GlyphPolyline([
      GlyphVertex(4.2, 19.6),
      GlyphVertex(19.8, 4.2),
    ], role: GlyphRole.line),
  ]);

  /// 退出登录。
  static const logout = Glyph([
    GlyphPolyline([
      GlyphVertex(13, 3.6, 1.6),
      GlyphVertex(5.6, 3.6, 1.6),
      GlyphVertex(5.6, 20.4, 1.6),
      GlyphVertex(13, 20.4, 1.6),
    ]),
    GlyphPolyline([
      GlyphVertex(10.6, 12),
      GlyphVertex(20.2, 12, 0.4),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(16.4, 8.2),
      GlyphVertex(20.2, 12, 0.5),
      GlyphVertex(16.4, 15.8),
    ], role: GlyphRole.line),
  ]);

  /// 播放。
  static const play = Glyph([
    GlyphPolyline([
      GlyphVertex(8.4, 4.8, 1.6),
      GlyphVertex(19, 12, 1.6),
      GlyphVertex(8.4, 19.2, 1.6),
    ], closed: true),
  ]);

  /// 历史：最近记录。
  static const history = Glyph([
    GlyphArc(12, 12, 8.2, math.pi * 0.62, math.pi * 1.72),
    GlyphPolyline([
      GlyphVertex(12, 12),
      GlyphVertex(12, 7.4),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(12, 12),
      GlyphVertex(15.4, 14.4),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(3.8, 12.2),
      GlyphVertex(3.8, 8.6),
      GlyphVertex(7.2, 8.6),
    ], role: GlyphRole.line),
  ]);

  /// 书：阅读/日志。
  static const book = Glyph([
    GlyphPath(
      'M4.2 6.2 C4.2 6.2 7.2 5.2 12 7.4 C16.8 5.2 19.8 6.2 19.8 6.2 '
      'L19.8 18 C19.8 18 16.8 17.2 12 19.2 C7.2 17.2 4.2 18 4.2 18 Z',
    ),
    GlyphPolyline([
      GlyphVertex(12, 7.4),
      GlyphVertex(12, 19.2),
    ], role: GlyphRole.detail),
  ]);

  /// 图表：统计趋势。
  static const chart = Glyph([
    GlyphPolyline([
      GlyphVertex(4, 16.6, 0.6),
      GlyphVertex(8.8, 10.6, 0.6),
      GlyphVertex(13.2, 13.8, 0.6),
      GlyphVertex(20, 5.8, 0.6),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(4, 20.6),
      GlyphVertex(20, 20.6),
    ], role: GlyphRole.detail),
  ]);
}
