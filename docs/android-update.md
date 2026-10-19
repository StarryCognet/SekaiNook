# 安卓自动更新（应用内下载 → 校验 → 调起系统安装器）

> 适用：`E:\Git\SekaiNook-App`（Flutter，安卓）。网页版不走这条路 —— 刷新页面就是最新版。
> 一句话：**发版 = 改版本号 → 跑 `tool\publish_apk.ps1`**；手机上打开 App 就会自己发现有新版，点一下装完。

---

## 1. 一页速查

| 想做什么 | 命令 / 位置 |
|---|---|
| 发一个新版本 | `.\tool\publish_apk.ps1 -Changelog "这次改了啥"` |
| 只传一个已经打好的包 | `.\tool\publish_apk.ps1 -SkipBuild -ApkPath D:\x\app-release.apk` |
| 顺带发通用包 | 加 `-Universal`（三种 ABI 都在里面，约 60MB；默认只装 arm64 那一份，约 22MB） |
| 看线上清单 | `Invoke-RestMethod https://pub.starrymiku.com/sekainook/latest.json` |
| 改清单地址 | `lib/config/app_constants.dart` 的 `appUpdateManifestUrl`（也可 `--dart-define=UPDATE_MANIFEST_URL=...`） |
| App 端逻辑 | `lib/state/update_state.dart`（状态机）、`lib/core/apk_installer*.dart`（下载/校验/安装）、`lib/ui/widgets/update_dialog.dart`（弹窗与设置里的两行） |
| 关掉自动检查 | App 内「设置 → 关于 → 自动检测更新」开关（本机记在 `sekainook_auto_check_update`，默认开） |
| 安卓原生侧 | `android/app/src/main/kotlin/com/sekainook/sekainook_app/MainActivity.kt` + `AndroidManifest.xml` 的 FileProvider |

清单地址：`https://pub.starrymiku.com/sekainook/latest.json`（R2 桶 `flclash-updates`，前缀 `sekainook/`）。

---

## 2. 用户侧是什么体验

1. **打开 App**：**每次都**静默看一眼清单。有新版本就弹「发现新版本 v1.32.0」，正文是这一版的完整更新日志（跟「设置 → 关于 → 版本日志」同一份数据，按版本号对齐；云端读不到时才退回清单里的单行说明），再加安装包大小。
2. **点「立即更新」**：下载 → 校验 sha256 → 自动调起系统安装界面。中途有进度条，返回键关不掉（怕留下半截文件）。
3. **第一次装**：安卓会拦一道「安装未知应用」。App 会把你送到系统设置页，允许之后**回来再点一次**即可 —— 包还在，不会重下 60MB。
4. **点「以后再说」**：记下这个版本，自动检查不再提它；想装随时去「设置 → 关于 → 检查更新」。
5. **手动检查**：点一次真发一次请求；没网会如实说「连不上更新服务器」，而不是骗你说「已是最新」。
6. **设置 → 关于 → 自动检测更新**：开关**默认开**。关掉之后启动不再自动查（手动检查照旧），弹窗也不会自己冒出来；重新打开开关会立刻查一次。
7. **网页版**：设置页不出现这两行，也不需要 —— 刷新即最新。

---

## 3. 一次性设置（已经做完了，这里只记着别丢东西）

| 东西 | 位置 | 说明 |
|---|---|---|
| 签名库 | `android/app/sekainook-release.jks` | **丢了就再也无法覆盖升级**（只能让全家卸载重装）。请另行备份 |
| 口令 | `android/app/key.properties` | 同上，一起备份；两文件都在 `.gitignore` 里 |
| 重新生成签名 | `tool/make_keystore.ps1` | 只在签名库真丢了时用；已存在就报错退出（防手滑覆盖）。注意：换了签名等于换了 App 身份，老用户必须卸载重装 |
| 签名配置 | `android/app/build.gradle.kts` | 有 `key.properties` 就用 release 签名，没有则退回 debug 签名（只够本机调试） |
| 安装权限 | `AndroidManifest.xml` | `REQUEST_INSTALL_PACKAGES` |
| 共享文件 | `AndroidManifest.xml` + `res/xml/file_paths.xml` | `FileProvider`（authority `${applicationId}.fileprovider`），放出来的是 `cache/updates/` 与 `files/updates/` |
| 云端 | R2 桶 `flclash-updates` + 自定义域 `pub.starrymiku.com` | 前缀 `sekainook/`；wrangler 已登录 |

> 手机上如果装的是**早先 debug 签名**的版本，必须**卸载重装一次**：签名不同，安卓不允许覆盖。

---

## 4. 发一版要动什么

1. **改版本号**：`pubspec.yaml` 的 `version: 1.31.0+2` → `1.32.0+3`。
   `+` 后面那个数就是安卓的 `versionCode`，**每次必须比上一版大**（App 就是拿它比大小的）。
2. **写这次改了啥**：
   * 更新弹窗里的那段话来自发布命令的 `-Changelog`（会写进 `latest.json`）。
   * App 内「设置 → 关于 → 版本日志」读的是网页仓库 D1 里的 `changelog` 表（`src/config/changelog.ts` → `/api/changelog`），跟版本号一起改比较省心；本机兜底文件 `lib/config/changelog.dart` 由网页仓库 `npm run changelog:fallback` 生成，别手改。
3. **发布**：
   ```powershell
   cd E:\Git\SekaiNook-App
   .\tool\publish_apk.ps1 -Changelog "修了花园浇水的一处错算"
   ```
   脚本会：构建 arm64 包 → **从 APK 里读 versionName/versionCode**（不是读 pubspec，见第 6 节）→ 算 sha256 → 传 APK → 传 `latest.json`。

   传完核对一下：
   ```powershell
   Invoke-RestMethod https://pub.starrymiku.com/sekainook/latest.json
   ```

**几分钟内生效**：清单只缓存 60 秒，APK 缓存一年（immutable）。装旧版的手机会在下一次打开（或点「检查更新」）时看到。

---

## 5. 清单长什么样

`https://pub.starrymiku.com/sekainook/latest.json`：

```json
{
  "versionName": "1.32.0",
  "versionCode": 3,
  "url": "https://pub.starrymiku.com/sekainook/SekaiNook-1.32.0-android-arm64-v8a.apk",
  "sha256": "…64 位小写十六进制…",
  "size": 23245348,
  "changelog": "修了花园浇水的一处错算"
}
```

App 侧的规矩（`lib/data/models/app_update.dart`）：字段缺一个、`url` 不是 https、`sha256` 不是 64 位、`versionCode`/`size` 不为正 —— 一律**当没读到**，宁可不更新也不装一个来路不明的包。

---

## 6. 版本号的两个坑（踩过，记下来）

* **别用 `--split-per-abi`**。Flutter 在「按 ABI 拆分」的构建里会给每个包加上 `1000 × ABI 序号`（arm64 就是 `+2000`），于是 pubspec 写 `+3`、APK 里是 `2003`。`publish_apk.ps1` 用 `aapt2 dump badging` 读 APK 的真实版本号，所以清单不会错；但**打包方式一旦换来换去，版本号就不再单调递增**，会出现「发了新版手机不提示」。脚本固定 `--target-platform android-arm64`（单包、无 ABI 过滤、没有偏移）。
* **`versionName` 与 `versionCode` 是一对**：App 比的是 `versionCode`（`PackageInfo.buildNumber`），`versionName` 只用来显示。只改名字不改数字，没人会收到更新。
* **默认那个包实际只有 arm64 的原生库**：`--target-platform android-arm64` 只让 Flutter 的 `libflutter.so`/`libapp.so` 进 arm64 目录，但 APK 里仍会残留 `armeabi-v7a`/`x86_64` 两个目录（各约 90KB，插件自带的 `libdartjni.so`）——于是老 32 位手机能装上却起不来。家里的手机都是 arm64，所以按 arm64 发；真要照顾 32 位机，用 `-Universal` 打通用包（约 60MB，`lib/` 下三个 ABI 齐全）。

---

## 7. 为什么不选别的路

| 方案 | 为什么不用 |
|---|---|
| Google Play 内购式更新 | 家里人用的 App，不打算上架、也不想走审核 |
| GitHub Releases + 系统浏览器 | 得跳到浏览器、要重新登录、装完还得自己找回来 |
| 自建服务器做更新接口 | 又一台机器要维护、要证书、要备份；静态文件放 R2 已经够了 |
| 增量更新（bsdiff 之类） | 60MB 的包在家里 Wi-Fi 下差别不大，算法和 patch 管理都是额外风险 |
| Flutter 热更新（第三方） | 改的是 Dart 代码，安卓侧合规与稳定性都不划算；真改了原生/插件还得走发版 |

选这条路的理由：**一份静态清单 + 一个静态 APK**，没有服务端代码，R2 免费额度足够；客户端只依赖 `dio` / `crypto` / `path_provider` / `package_info_plus`，全是官方生态里最稳的几个。

---

## 8. 排错

| 现象 | 原因 / 处理 |
|---|---|
| 点了「检查更新」说连不上 | 先 `Invoke-RestMethod https://pub.starrymiku.com/sekainook/latest.json`。404 = 还没发过第一版；域名不通 = R2 的自定义域没生效 |
| 传上去了，公网还是旧的 | wrangler 4 的 `r2 object put` **默认写本地模拟存储**，必须带 `--remote`（脚本已带） |
| 发了新版，手机不提示 | 多半是 `versionCode` 没变大（见第 6 节）；或这个版本点过「以后再说」（去设置页手动检查）；或清单缓存还没过 60 秒 |
| 下载完弹「安装包校验没通过」 | 上传中途断了 / 文件被换过。App 会删掉文件，重新点一次下载 |
| 弹了系统安装器但装不上 | 签名不一致（装过 debug 版或别人的包）→ 卸载重装一次；或存储空间不足 |
| 提示「安装未知应用」 | 正常流程：去系统设置里允许 SekaiNook，回来再点一次「立即更新」 |
| 想临时指到别的清单 | `flutter run --dart-define=UPDATE_MANIFEST_URL=https://.../latest.json` |

---

## 9. 相关文件

| 文件 | 作用 |
|---|---|
| `tool/publish_apk.ps1` | 构建 → 读 APK 版本号 → 传 APK + latest.json |
| `tool/make_keystore.ps1` | 生成正式签名（一次性；签名库丢失时才用） |
| `lib/state/update_state.dart` | 自动/手动检查、跳过某版本、下载安装状态机 |
| `lib/data/api/app_update_api.dart` | 拉清单（独立 Dio，失败一律返回 null） |
| `lib/data/models/app_update.dart` | 清单模型 + 严格校验 |
| `lib/core/apk_installer.dart` / `_io.dart` / `_stub.dart` | 条件导入：下载、sha256 校验、调起安装器；Web 用桩 |
| `lib/ui/widgets/update_dialog.dart` | 新版本弹窗、下载进度弹窗、设置页那一行 |
| `lib/ui/shell/main_shell.dart` | 启动后拿到新版本时弹一次（一次会话只问一次） |
| `android/app/src/main/kotlin/.../MainActivity.kt` | MethodChannel `installApk` / `canInstall` + FileProvider |
| `android/app/src/main/res/xml/file_paths.xml` | 放行 `updates/` 目录给安装器读 |
| `test/app_update_test.dart` | 清单解析、节流、跳过版本、手动检查的单元测试 |
