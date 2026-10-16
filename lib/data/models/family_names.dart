/// 家庭称呼里的两个人（对应 Web 版 `displayName(names, who)` 的 `who`）
enum FamilyWho { mom, kid }

/// 家庭称呼设置（对应 Web 版 `FamilyNames`）。
///
/// 逻辑：**昵称优先** —— 填了昵称就用昵称，没填昵称才用称呼，称呼也没填回退出厂默认。
class FamilyNames {
  const FamilyNames({
    this.momCall = defaultMomCall,
    this.momNickname = '',
    this.kidCall = defaultKidCall,
    this.kidNickname = '',
  });

  /// 出厂默认称呼
  static const String defaultMomCall = '妈妈';
  static const String defaultKidCall = '女儿';

  /// 称呼最多 12 个字
  static const int maxNameLength = 12;

  static const FamilyNames defaults = FamilyNames();

  final String momCall;
  final String momNickname;
  final String kidCall;
  final String kidNickname;

  /// 界面上该显示的名字
  String displayName(FamilyWho who) {
    if (who == FamilyWho.mom) {
      final nick = momNickname.trim();
      if (nick.isNotEmpty) return nick;
      final call = momCall.trim();
      return call.isNotEmpty ? call : defaultMomCall;
    }
    final nick = kidNickname.trim();
    if (nick.isNotEmpty) return nick;
    final call = kidCall.trim();
    return call.isNotEmpty ? call : defaultKidCall;
  }

  /// 妈妈的显示名
  String get momDisplay => displayName(FamilyWho.mom);

  /// 孩子的显示名
  String get kidDisplay => displayName(FamilyWho.kid);

  /// 校验称呼/昵称：超长返回中文提示，合法返回 null（对应 Web 版 `validateName`）
  static String? validateName(String value) =>
      value.trim().length > maxNameLength ? '最多 $maxNameLength 个字' : null;

  FamilyNames copyWith({
    String? momCall,
    String? momNickname,
    String? kidCall,
    String? kidNickname,
  }) =>
      FamilyNames(
        momCall: momCall ?? this.momCall,
        momNickname: momNickname ?? this.momNickname,
        kidCall: kidCall ?? this.kidCall,
        kidNickname: kidNickname ?? this.kidNickname,
      );

  factory FamilyNames.fromJson(Map<String, dynamic> json) => FamilyNames(
        momCall: (json['momCall'] as String?)?.trim().isNotEmpty == true
            ? json['momCall'] as String
            : defaultMomCall,
        momNickname: (json['momNickname'] as String?) ?? '',
        kidCall: (json['kidCall'] as String?)?.trim().isNotEmpty == true
            ? json['kidCall'] as String
            : defaultKidCall,
        kidNickname: (json['kidNickname'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'momCall': momCall,
        'momNickname': momNickname,
        'kidCall': kidCall,
        'kidNickname': kidNickname,
      };
}
