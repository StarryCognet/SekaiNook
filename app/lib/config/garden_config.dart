import '../data/models/garden.dart';

/// 花园配置（对应 Web 版 `src/config/garden.ts`，逐条照抄）。
///
/// 这些都是**纯本地常量**：花园任务、勋章、古诗、语文练习、商城商品
/// 都不存在后端表里，兑换/完成状态是从账本流水派生出来的。
abstract final class GardenConfig {
  /// 今日任务列表（8 条）
  static const List<GardenTask> tasks = <GardenTask>[
    GardenTask(id: 'poem', name: '背一首古诗', duration: 10, description: '背诵并理解一首古诗', reward: 10, icon: 'book'),
    GardenTask(id: 'chinese', name: '语文预习 15 分钟', duration: 15, description: '预习明天要学的课文', reward: 15, icon: 'read'),
    GardenTask(id: 'math', name: '数学预习 15 分钟', duration: 15, description: '预习数学新章节', reward: 15, icon: 'calc'),
    GardenTask(id: 'reading', name: '课外阅读 20 分钟', duration: 20, description: '阅读课外书籍', reward: 20, icon: 'book-open'),
    GardenTask(id: 'writing', name: '练字 10 分钟', duration: 10, description: '认真练习书写', reward: 10, icon: 'pen'),
    GardenTask(id: 'eyes', name: '休息眼睛 5 分钟', duration: 5, description: '远眺放松眼睛', reward: 5, icon: 'eye'),
    GardenTask(id: 'sport', name: '运动 20 分钟', duration: 20, description: '户外活动或锻炼', reward: 20, icon: 'sport'),
    GardenTask(id: 'chore', name: '做一件家务', duration: 15, description: '帮助家人做家务', reward: 15, icon: 'home'),
  ];

  /// 勋章列表（7 枚，初始均未获得）
  static const List<Badge> badges = <Badge>[
    Badge(id: 'sunrise', name: '第一缕阳光', description: '完成第一个任务', icon: 'sun'),
    Badge(id: 'gardener', name: '小园丁', description: '累计完成 10 个任务', icon: 'flower'),
    Badge(id: 'streak3', name: '坚持 3 天', description: '连续学习 3 天', icon: 'calendar'),
    Badge(id: 'week_champ', name: '一周冠军', description: '连续学习 7 天', icon: 'trophy'),
    Badge(id: 'poet', name: '小诗人', description: '背诵 10 首古诗', icon: 'feather'),
    Badge(id: 'plant_warrior', name: '植物战士', description: '照顾花园植物 7 天', icon: 'leaf'),
    Badge(id: 'sun_rich', name: '阳光富翁', description: '累计获得 500 阳光', icon: 'coin'),
  ];

  /// 古诗（12 首，累计背会 10 首解锁「小诗人」）
  static const List<GardenPoem> poems = <GardenPoem>[
    GardenPoem(id: 'jingyesi', title: '静夜思', author: '李白', text: '床前明月光，疑是地上霜。举头望明月，低头思故乡。', reward: 10),
    GardenPoem(id: 'chunxiao', title: '春晓', author: '孟浩然', text: '春眠不觉晓，处处闻啼鸟。夜来风雨声，花落知多少。', reward: 10),
    GardenPoem(id: 'chizhou', title: '池上', author: '白居易', text: '小娃撑小艇，偷采白莲回。不解藏踪迹，浮萍一道开。', reward: 10),
    GardenPoem(id: 'xiaochi', title: '小池', author: '杨万里', text: '泉眼无声惜细流，树阴照水爱晴柔。小荷才露尖尖角，早有蜻蜓立上头。', reward: 10),
    GardenPoem(id: 'yonge', title: '咏鹅', author: '骆宾王', text: '鹅，鹅，鹅，曲项向天歌。白毛浮绿水，红掌拨清波。', reward: 10),
    GardenPoem(id: 'minnong', title: '悯农', author: '李绅', text: '锄禾日当午，汗滴禾下土。谁知盘中餐，粒粒皆辛苦。', reward: 10),
    GardenPoem(id: 'dengguanquelou', title: '登鹳雀楼', author: '王之涣', text: '白日依山尽，黄河入海流。欲穷千里目，更上一层楼。', reward: 10),
    GardenPoem(id: 'wanglushanpubu', title: '望庐山瀑布', author: '李白', text: '日照香炉生紫烟，遥看瀑布挂前川。飞流直下三千尺，疑是银河落九天。', reward: 10),
    GardenPoem(id: 'jiangxue', title: '江雪', author: '柳宗元', text: '千山鸟飞绝，万径人踪灭。孤舟蓑笠翁，独钓寒江雪。', reward: 10),
    GardenPoem(id: 'zengwanglun', title: '赠汪伦', author: '李白', text: '李白乘舟将欲行，忽闻岸上踏歌声。桃花潭水深千尺，不及汪伦送我情。', reward: 10),
    GardenPoem(id: 'xunyinzhe', title: '寻隐者不遇', author: '贾岛', text: '松下问童子，言师采药去。只在此山中，云深不知处。', reward: 10),
    GardenPoem(id: 'huichong', title: '惠崇春江晚景', author: '苏轼', text: '竹外桃花三两枝，春江水暖鸭先知。蒌蒿满地芦芽短，正是河豚欲上时。', reward: 10),
  ];

  /// 语文/汉字练习（3 项）
  static const List<GardenChinesePractice> chinesePractices = <GardenChinesePractice>[
    GardenChinesePractice(id: 'read_aloud', title: '课文朗读', desc: '朗读今天学的课文，读给家人听', actionLabel: '我读完了', reward: 5, timesPerDay: 3),
    GardenChinesePractice(id: 'new_words', title: '生字认读', desc: '认读本课生字，每个字读两遍并组词', actionLabel: '我认读完了', reward: 5, timesPerDay: 2),
    GardenChinesePractice(id: 'write_words', title: '生字书写', desc: '在田字格里认真书写本课生字', actionLabel: '我写完了', reward: 10, timesPerDay: 1),
  ];

  /// 阳光商城商品（6 件，一次性拥有，不可重复兑换）
  static const List<GardenShopItem> shopItems = <GardenShopItem>[
    GardenShopItem(id: 'avatar_sun', name: '阳光头像框', cost: 60, icon: 'sun', desc: '把头像装进金色阳光里', category: GardenShopCategory.avatar),
    GardenShopItem(id: 'avatar_star', name: '星星头像框', cost: 80, icon: 'star', desc: '闪闪发光的星星围着你的头像', category: GardenShopCategory.avatar),
    GardenShopItem(id: 'title_poet', name: '称号・小诗人', cost: 100, icon: 'feather', desc: '名字旁边挂上「小诗人」', category: GardenShopCategory.title),
    GardenShopItem(id: 'title_gardener', name: '称号・小园丁', cost: 120, icon: 'flower', desc: '名字旁边挂上「小园丁」', category: GardenShopCategory.title),
    GardenShopItem(id: 'decor_rainbow', name: '装饰・彩虹花架', cost: 150, icon: 'flower', desc: '花园里多一架七色花', category: GardenShopCategory.decor),
    GardenShopItem(id: 'decor_lantern', name: '装饰・星星灯串', cost: 200, icon: 'star', desc: '夜里给花园挂上小灯', category: GardenShopCategory.decor),
  ];

  /// 今日任务全做完能拿到的阳光总数（由 tasks 求和算出，现在 = 110）。
  /// 页面与文案里不要再写死这个数字。
  static int get dailyTaskReward =>
      tasks.fold<int>(0, (sum, task) => sum + task.reward);

  /// 花园里同时挂着的装饰上限：挂满后再挂新的，替换掉最早挂上的那件
  static const int maxDecor = 3;

  /// 累计型勋章的进度目标（id -> 目标值）
  static const Map<String, int> badgeTargets = <String, int>{
    'poet': 10,
    'plant_warrior': 7,
  };

  /// 儿童工作台 8 个菜单
  static const List<GardenMenu> menus = <GardenMenu>[
    GardenMenu(key: 'overview', label: '学习总览', icon: 'dashboard'),
    GardenMenu(key: 'tasks', label: '今日任务', icon: 'check'),
    GardenMenu(key: 'poem', label: '古诗背诵', icon: 'book'),
    GardenMenu(key: 'chinese', label: '语文预习', icon: 'read'),
    GardenMenu(key: 'garden', label: '阳光花园', icon: 'flower'),
    GardenMenu(key: 'shop', label: '阳光商城', icon: 'shop'),
    GardenMenu(key: 'rewards', label: '我的奖励', icon: 'trophy'),
    GardenMenu(key: 'records', label: '学习记录', icon: 'history'),
  ];

  /// 花园菜单在路由里的查询参数名（对应 Web 版 `/garden?tab=poem` 的 `tab`）。
  /// 用 URL 承载菜单是为了让系统返回键沿菜单回退，而不是直接退出花园。
  static const String menuParam = 'tab';

  /// 进花园没带参数（或参数不认识）时落的那个菜单
  static const String defaultMenu = 'tasks';

  /// 校验菜单 key 是否合法（未知 / 空值一律回退默认菜单，不渲染空白）
  static bool isMenuKey(String? value) =>
      value != null && menus.any((menu) => menu.key == value);
}
