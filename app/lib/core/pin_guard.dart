import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_constants.dart';

/// 家长口令的存储与试错节流（对应 Web 版 `src/store/useFamilyStore.ts` 的 PIN 部分）。
///
/// 存储格式与 Web 版**逐字节兼容**（同一个浏览器里 Flutter Web 版与 Web 版共用 localStorage）：
/// - 正常：`sha256:<hex>`，hex = SHA-256('sekainook-pin:' + 口令) 小写十六进制
/// - 兼容老数据：`plain:<明文>`（Web 版在非安全上下文下的降级写法）与**没有任何前缀**的裸明文
///
/// 与 Web 版的一处差异：Dart 的 crypto 任何环境都能算，不存在「非安全上下文」，
/// 所以写入一律走摘要，不再降级明文。但**读取**仍兼容明文格式。
class PinGuard {
  PinGuard(this._prefs);

  final SharedPreferences _prefs;

  /// 摘要的固定 salt 前缀，避免有人拿现成的 SHA-256 彩虹表直接反查 4 位数字口令
  static const String pinSalt = 'sekainook-pin:';

  /// 存储值前缀：一眼看清这一条是摘要还是降级明文（也用于容错解析）
  static const String hashPrefix = 'sha256:';
  static const String plainPrefix = 'plain:';

  /// 出厂家长口令（家长可在设置页修改）
  static const String defaultParentPin = '1234';

  /// 出厂口令的摘要常量（SHA-256(`sekainook-pin:1234`)）。
  /// 用来回答「现在用的还是不是出厂口令」—— 只看「存过没有」会把「改回 1234」误判成自定义口令。
  static const String defaultPinHash =
      'adb4335c1a09e3dda9a90ff1605cbcbdb75681d549eb2e832673d96c04e61cf5';

  /// 允许连续失败的次数，超过就锁定
  static const int maxFreeAttempts = 5;

  /// 锁定时长：第 5 次失败锁 60 秒，之后每多失败一次翻倍，上限 10 分钟
  static const Duration baseLock = Duration(seconds: 60);
  static const Duration maxLock = Duration(minutes: 10);

  /// 口令 → SHA-256 十六进制摘要（[pinSalt] 作为固定 salt 前缀）
  static String hashPin(String pin) =>
      sha256.convert(utf8.encode('$pinSalt$pin')).toString();

  /// 存的这条是不是「出厂口令」。
  /// - 什么都没存：是（校验时走出厂口令）
  /// - 存了摘要：比摘要常量（家长把口令改回 1234 也算没自定义）
  /// - 存了明文：直接比字面
  bool get isDefaultStoredPin {
    final stored = _readStoredPin();
    if (stored == null) return true;
    return stored.mode == _PinMode.hash
        ? stored.value == defaultPinHash
        : stored.value == defaultParentPin;
  }

  /// 是否用的是自己的家长口令（改回出厂口令 1234 也算没自定义）
  bool get hasCustomParentPin => !isDefaultStoredPin;

  /// 距离解锁还剩多少毫秒（0 = 未锁定）。纯同步读，供 UI 显示倒计时。
  Duration get lockRemaining {
    final raw = _prefs.get(AppConstants.keyPinLockUntil);
    final until = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
    if (until == null) return Duration.zero;
    final remain = until - DateTime.now().millisecondsSinceEpoch;
    return remain > 0 ? Duration(milliseconds: remain) : Duration.zero;
  }

  /// 还能试几次（锁定中为 0），供 UI 显示「还可以试 N 次」
  int get attemptsLeft {
    final left = maxFreeAttempts - _readFails();
    return left > 0 ? left : 0;
  }

  /// verify 是否正在跑（M-3）：快速连点会让多次 verify 读到同一份失败计数，
  /// 「读 → 加 1 → 写」被并发绕过，5 次锁定形同虚设。串行化即可。
  bool _verifying = false;

  /// 校验家长口令：异步比对 + 失败锁定。
  ///
  /// - 锁定期内直接 false（不校验、不计失败，也不透露任何关于正确口令的信息）
  /// - 成功清零失败计数
  /// - 失败累计到阈值就锁定，锁定时长逐次翻倍
  Future<bool> verify(String pin) async {
    // 锁定期内连正确口令也返回 false —— 这是「锁」的意义所在
    if (lockRemaining > Duration.zero) return false;
    if (_verifying) return false;
    _verifying = true;
    try {
      await migrateLegacyPin();
      final stored = _readStoredPin();

      // 还没设过口令：出厂口令生效（这条路径本地不存任何东西）
      if (stored == null) {
        if (pin != defaultParentPin) {
          _registerFailure();
          return false;
        }
        clearGuards();
        return true;
      }

      if (stored.mode == _PinMode.hash) {
        if (hashPin(pin) == stored.value) {
          clearGuards();
          return true;
        }
        _registerFailure();
        return false;
      }

      if (pin == stored.value) {
        clearGuards();
        return true;
      }
      _registerFailure();
      return false;
    } finally {
      _verifying = false;
    }
  }

  /// 写入新口令（一律存 `sha256:<hex>`，localStorage 里再也看不到明文）
  Future<void> writePin(String pin) async {
    await _prefs.setString(AppConstants.keyParentPinHash, '$hashPrefix${hashPin(pin)}');
  }

  /// 更新家长口令，并顺手解锁（家长已经站在家长模式里了，没必要再等倒计时）
  Future<void> setParentPin(String pin) async {
    await writePin(pin);
    clearGuards();
  }

  /// 校验成功 / 改口令成功时清零失败计数与锁定
  void clearGuards() {
    _prefs.remove(AppConstants.keyPinFails);
    _prefs.remove(AppConstants.keyPinLockUntil);
  }

  /// 首次读取时顺手迁移老键：明文 → 新键。迁移幂等；写入失败时不删老键，
  /// 绝不会因此把人锁在门外。
  Future<void> migrateLegacyPin() async {
    final legacy = _prefs.getString(AppConstants.keyParentPinLegacy);
    if (legacy == null) return;
    try {
      await writePin(legacy);
      await _prefs.remove(AppConstants.keyParentPinLegacy);
    } catch (_) {
      // 写不进去就留着老键，下次再说
    }
  }

  int _readFails() {
    final raw = _prefs.get(AppConstants.keyPinFails);
    final value = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
    if (value == null || value <= 0) return 0;
    return value;
  }

  Future<void> _writeFails(int fails) async {
    if (fails > 0) {
      await _prefs.setInt(AppConstants.keyPinFails, fails);
    } else {
      await _prefs.remove(AppConstants.keyPinFails);
    }
  }

  /// 记一次失败：从第 [maxFreeAttempts] 次起锁定，往后每多失败一次时长翻倍（上限 10 分钟）
  void _registerFailure() {
    final fails = _readFails() + 1;
    // 不 await：调用方要的是「立刻锁定」的同步效果，写盘慢一点不影响判断
    unawaited(_writeFails(fails));
    if (fails < maxFreeAttempts) return;
    final factor = 1 << (fails - maxFreeAttempts);
    final lockMs = baseLock.inMilliseconds * factor;
    final capped = lockMs > maxLock.inMilliseconds ? maxLock.inMilliseconds : lockMs;
    unawaited(_prefs.setInt(
      AppConstants.keyPinLockUntil,
      DateTime.now().millisecondsSinceEpoch + capped,
    ));
  }

  /// 同步读当前口令记录
  _StoredPin? _readStoredPin() {
    final raw = _prefs.getString(AppConstants.keyParentPinHash);
    if (raw != null && raw.isNotEmpty) {
      if (raw.startsWith(hashPrefix)) {
        return _StoredPin(_PinMode.hash, raw.substring(hashPrefix.length));
      }
      if (raw.startsWith(plainPrefix)) {
        return _StoredPin(_PinMode.plain, raw.substring(plainPrefix.length));
      }
      return _StoredPin(_PinMode.plain, raw); // 容错：没有前缀的旧格式，按明文比
    }
    final legacy = _prefs.getString(AppConstants.keyParentPinLegacy);
    return legacy != null ? _StoredPin(_PinMode.plain, legacy) : null;
  }
}

enum _PinMode { hash, plain }

class _StoredPin {
  const _StoredPin(this.mode, this.value);

  final _PinMode mode;
  final String value;
}
