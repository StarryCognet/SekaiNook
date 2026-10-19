/// 花园数据模型（对应 Web 版 `src/types/garden.ts`）。
library;

/// 花园今日任务（对应 `GardenTask`）
class GardenTask {
  const GardenTask({
    required this.id,
    required this.name,
    required this.duration,
    required this.description,
    required this.reward,
    required this.icon,
    this.done = false,
    this.completedAt,
  });

  final String id;
  final String name;

  /// 建议时长（分钟）
  final int duration;
  final String description;

  /// 完成可得阳光
  final int reward;

  /// 图标 key（对应 Web 版 components/garden/GardenIcon 的键）
  final String icon;

  /// 今天是否已完成（由账本记录派生，不是服务端字段）
  final bool done;
  final DateTime? completedAt;

  GardenTask copyWith({bool? done, DateTime? completedAt}) => GardenTask(
        id: id,
        name: name,
        duration: duration,
        description: description,
        reward: reward,
        icon: icon,
        done: done ?? this.done,
        completedAt: completedAt ?? this.completedAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'duration': duration,
        'description': description,
        'reward': reward,
        'icon': icon,
        'done': done,
        if (completedAt != null) 'completedAt': completedAt!.toUtc().toIso8601String(),
      };

  static GardenTask fromJson(Map<String, dynamic> json) => GardenTask(
        id: (json['id'] ?? '') as String,
        name: (json['name'] ?? '') as String,
        duration: (json['duration'] as num?)?.toInt() ?? 0,
        description: (json['description'] ?? '') as String,
        reward: (json['reward'] as num?)?.toInt() ?? 0,
        icon: (json['icon'] ?? '') as String,
        done: json['done'] == true,
        completedAt: json['completedAt'] is String
            ? DateTime.tryParse(json['completedAt'] as String)?.toLocal()
            : null,
      );
}

/// 勋章（对应 `Badge`）
class Badge {
  const Badge({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    this.earned = false,
  });

  final String id;
  final String name;
  final String description;
  final String icon;
  final bool earned;

  Badge copyWith({bool? earned}) => Badge(
        id: id,
        name: name,
        description: description,
        icon: icon,
        earned: earned ?? this.earned,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'description': description,
        'icon': icon,
        'earned': earned,
      };

  static Badge fromJson(Map<String, dynamic> json) => Badge(
        id: (json['id'] ?? '') as String,
        name: (json['name'] ?? '') as String,
        description: (json['description'] ?? '') as String,
        icon: (json['icon'] ?? '') as String,
        earned: json['earned'] == true,
      );
}

/// 古诗（对应 `GardenPoem`）
class GardenPoem {
  const GardenPoem({
    required this.id,
    required this.title,
    required this.author,
    required this.text,
    required this.reward,
  });

  final String id;
  final String title;
  final String author;

  /// 全文（含标点）
  final String text;

  /// 背会后获得的阳光
  final int reward;
}

/// 语文练习项（对应 `GardenChinesePractice`）
class GardenChinesePractice {
  const GardenChinesePractice({
    required this.id,
    required this.title,
    required this.desc,
    required this.actionLabel,
    required this.reward,
    required this.timesPerDay,
  });

  final String id;
  final String title;
  final String desc;

  /// 打卡按钮文案（如「我写完了」）
  final String actionLabel;

  /// 每次打卡获得的阳光
  final int reward;

  /// 每天可打卡次数（按自然日重置）
  final int timesPerDay;
}

/// 商城物品分类（对应 `GardenShopCategory`）
enum GardenShopCategory { avatar, title, decor }

extension GardenShopCategoryX on GardenShopCategory {
  /// 分类中文名
  String get label => switch (this) {
        GardenShopCategory.avatar => '头像框',
        GardenShopCategory.title => '称号',
        GardenShopCategory.decor => '花园装饰',
      };
}

/// 商城物品（对应 `GardenShopItem`）
class GardenShopItem {
  const GardenShopItem({
    required this.id,
    required this.name,
    required this.cost,
    required this.icon,
    required this.desc,
    required this.category,
  });

  final String id;
  final String name;

  /// 兑换所需阳光
  final int cost;
  final String icon;
  final String desc;
  final GardenShopCategory category;

  /// 去掉商品名里的分类前缀：孩子看到的只是「小诗人」「彩虹花架」。
  /// 对应 Web 版 `toShopItemShortName`（分隔符是 U+30FB 片假名中点）。
  String get shortName {
    final index = name.indexOf(shopItemNameSeparator);
    return index >= 0 ? name.substring(index + 1) : name;
  }
}

/// 商品名里的分类前缀分隔符（「称号・小诗人」中间那个点）
const String shopItemNameSeparator = '\u30FB';

/// 儿童工作台的一个菜单（对应 `GARDEN_MENUS` 的条目）
class GardenMenu {
  const GardenMenu({required this.key, required this.label, required this.icon});

  final String key;
  final String label;
  final String icon;
}
