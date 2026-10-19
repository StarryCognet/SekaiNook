package com.sekainook.sekainook_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// 应用内更新用到的两个原生动作：查「能不能装」和把下载好的 APK 交给系统安装器。
/// Dart 侧入口见 lib/core/apk_installer.dart。
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "com.sekainook.sekainook_app/install"
        const val APK_MIME = "application/vnd.android.package-archive"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstall" -> result.success(canInstallPackages())
                "installApk" -> installApk(call.argument<String>("path"), result)
                else -> result.notImplemented()
            }
        }
    }

    /// 安卓 8.0（API 26）起装 APK 要有「安装未知应用」授权，8.0 以下不用问。
    private fun canInstallPackages(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()

    /// 返回 true = 安装器已拉起；false = 没授权，已经跳到系统授权页，用户回来后要再点一次。
    private fun installApk(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrEmpty()) {
            result.error("BAD_ARGS", "installApk 缺少 path", null)
            return
        }
        if (!canInstallPackages()) {
            startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
            )
            result.success(false)
            return
        }
        val file = File(path)
        if (!file.exists()) {
            result.error("NOT_FOUND", "安装包不存在：$path", null)
            return
        }
        // 私有目录里的文件直接给 file:// 会被 FileUriExposedException 拦下，必须走 FileProvider
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        startActivity(
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, APK_MIME)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        )
        result.success(true)
    }
}
