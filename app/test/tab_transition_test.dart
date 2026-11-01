import 'package:flutter_test/flutter_test.dart';
import 'package:sekainook_app/theme/tab_transition.dart';

/// 换页转场这个枚举会被两处读：设置页列出来选、MainShell 拿去分派。
/// 它坏掉的方式很小儿科但很烦 —— 存进去的 id 读不出来、或者两个候选撞了 id，
/// 于是用户挑了半天发现重启后回到默认。这里把这几条钉死。
void main() {
  test('id 唯一（重复了就会有一个候选永远选不中）', () {
    final ids = TabTransition.values.map((item) => item.id).toSet();
    expect(ids.length, TabTransition.values.length);
  });

  test('每个候选都有能显示出来的名字和说明', () {
    for (final item in TabTransition.values) {
      expect(item.label.trim(), isNotEmpty);
      expect(item.hint.trim(), isNotEmpty);
      expect(item.group.trim(), isNotEmpty);
    }
  });

  test('时长都是正数，且不超过 1 秒（转场再长就该关掉了）', () {
    for (final item in TabTransition.values) {
      expect(item.duration.inMilliseconds, greaterThan(0));
      expect(item.reverseDuration.inMilliseconds, greaterThan(0));
      expect(item.duration.inMilliseconds, lessThanOrEqualTo(1000));
    }
  });

  test('fromId 认得出存过的值', () {
    for (final item in TabTransition.values) {
      expect(TabTransition.fromId(item.id), item);
    }
  });

  test('fromId 遇到脏值一律回默认，不让设置问题拦住启动', () {
    expect(TabTransition.fromId(null), TabTransition.defaultTransition);
    expect(TabTransition.fromId(''), TabTransition.defaultTransition);
    expect(TabTransition.fromId('不存在的东西'), TabTransition.defaultTransition);
    // 枚举 name（'slideFade'）不是合法 id（id 是 'slide-fade'）——
    // 要是哪天有人拿 name 写盘，这里会红
    expect(
      TabTransition.fromId(TabTransition.slideFade.name),
      TabTransition.defaultTransition,
    );
  });

  test('出厂默认是「逐层揭开」，老用户没选过也走它', () {
    expect(TabTransition.defaultTransition, TabTransition.stagger);
    expect(TabTransition.defaultTransition.id, 'stagger');
    expect(TabTransition.defaultTransition.label, '逐层揭开');
  });
}
