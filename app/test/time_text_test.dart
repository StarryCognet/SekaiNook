import 'package:flutter_test/flutter_test.dart';
import 'package:sekainook_app/core/time_text.dart';

/// 「今天 14:32 / 昨天 09:05 / 9月20日 21:10」这套口径原来在三个页面里各写了一份，
/// 收敛到 `core/time_text.dart` 之后至少要有自己的看门测试。
void main() {
  group('clockText', () {
    test('两位补零', () {
      expect(clockText(DateTime(2026, 10, 19, 9, 5)), '09:05');
      expect(clockText(DateTime(2026, 10, 19, 23, 59)), '23:59');
      expect(clockText(DateTime(2026, 10, 19)), '00:00');
    });
  });

  group('relativeDayTime', () {
    test('同一天读「今天」', () {
      expect(
        relativeDayTime(DateTime(2026, 10, 19, 8, 4), now: DateTime(2026, 10, 19, 21, 10)),
        '今天 08:04',
      );
    });

    test('前一天读「昨天」', () {
      expect(
        relativeDayTime(DateTime(2026, 10, 18, 23, 59), now: DateTime(2026, 10, 19, 21, 10)),
        '昨天 23:59',
      );
    });

    test('更早写月日（不补零，与 Web 版一致）', () {
      expect(
        relativeDayTime(DateTime(2026, 10, 17, 7, 0), now: DateTime(2026, 10, 19, 21, 10)),
        '10月17日 07:00',
      );
      expect(
        relativeDayTime(DateTime(2026, 9, 30, 20, 0), now: DateTime(2026, 10, 19, 21, 10)),
        '9月30日 20:00',
      );
    });

    test('判的是本地日历天，不是 24 小时内的差', () {
      // 只差一小时，但跨了午夜 —— 昨天
      expect(
        relativeDayTime(DateTime(2026, 10, 18, 23, 30), now: DateTime(2026, 10, 19, 0, 30)),
        '昨天 23:30',
      );
      // 差了近一天，但同一天 —— 还是今天
      expect(
        relativeDayTime(DateTime(2026, 10, 19, 0, 30), now: DateTime(2026, 10, 19, 23, 0)),
        '今天 00:30',
      );
    });

    test('「昨天」跨月跨年时正确进位', () {
      expect(
        relativeDayTime(DateTime(2026, 12, 31, 22, 30), now: DateTime(2027, 1, 1, 10, 0)),
        '昨天 22:30',
      );
      expect(
        relativeDayTime(DateTime(2026, 3, 1, 9, 0), now: DateTime(2026, 3, 1, 9, 1)),
        '今天 09:00',
      );
    });

    test('不传 now 就按当下算（刚生成的时刻必然落在今天）', () {
      final DateTime moment = DateTime.now();
      expect(relativeDayTime(moment), '今天 ${clockText(moment)}');
    });
  });
}
