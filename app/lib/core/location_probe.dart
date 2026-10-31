import 'package:geolocator/geolocator.dart';

/// 打卡照片上要写的位置文字，如 `N39.91500° E116.40400°`。
///
/// **这一层绝不抛异常、也绝不拖住打卡**：定位只是锦上添花，
/// 关掉定位开关 / 拒绝授权 / 室内搜不到星 / 网页跑在 HTTP 下
/// （浏览器只在安全上下文里给 `navigator.geolocation`）都会走到
/// 「返回 null → 水印写『位置未获取』」这条路上。
///
/// 为什么用经纬度而不是「XX 市 XX 区 XX 路」：逆地理编码要接地图厂商的
/// Web 服务（带 key、带配额、还要把 key 塞进客户端），为了三个字的地址
/// 不值得。经纬度本身就是可核查的位置信息，真要看地址拿坐标一搜就到。
Future<String?> captureLocationText({
  Duration timeout = const Duration(seconds: 6),
}) async {
  try {
    // 系统定位总开关关着时直接放弃：这一步比 requestPermission 快得多，
    // 否则用户会先看到授权弹窗、再被系统告知「定位已关闭」。
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    // 先拿一次「上次已知位置」：通常几毫秒就回来，室内/刚打开 App 时
    // 这些够用；拿不到再走真正的一次定位（可能等好几秒）。
    final Position? lastKnown = await Geolocator.getLastKnownPosition();
    if (lastKnown != null) {
      return formatLatLng(lastKnown.latitude, lastKnown.longitude);
    }

    final Position position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: timeout,
      ),
    );
    return formatLatLng(position.latitude, position.longitude);
  } catch (_) {
    // TimeoutException / PermissionDeniedException / PlatformException 全吞掉：
    // 拿不到位置就该继续打卡，不该让用户卡在这一步
    return null;
  }
}

/// 把经纬度写成照片水印上用的短字符串（5 位小数 ≈ 1 米精度）。
String formatLatLng(double latitude, double longitude) {
  final String lat = latitude.abs().toStringAsFixed(5);
  final String lng = longitude.abs().toStringAsFixed(5);
  final String latHemisphere = latitude >= 0 ? 'N' : 'S';
  final String lngHemisphere = longitude >= 0 ? 'E' : 'W';
  return '$latHemisphere$lat° $lngHemisphere$lng°';
}
