package io.github.fkguo.particlelibrary

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pdg.update")
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "canInstallPackages" -> result.success(canInstallPackages())
          "installApk" -> installApk(call.argument<String>("path"), result)
          else -> result.notImplemented()
        }
      }
  }

  private fun canInstallPackages(): Boolean =
    Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
      packageManager.canRequestPackageInstalls()

  private fun installApk(path: String?, result: MethodChannel.Result) {
    if (path.isNullOrBlank()) {
      result.error("bad_apk_path", "No APK path was supplied.", null)
      return
    }
    val file = File(path)
    if (!file.isFile) {
      result.error("missing_apk", "The downloaded APK does not exist.", null)
      return
    }
    if (!canInstallPackages()) {
      try {
        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
          .setData(Uri.parse("package:$packageName"))
        startActivity(intent)
      } catch (_: Exception) {
        // The caller shows the same permission guidance either way.
      }
      result.error(
        "install_permission",
        "Allow installation from this source, then choose Update again.",
        null,
      )
      return
    }
    try {
      val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
      val intent = Intent(Intent.ACTION_VIEW).apply {
        setDataAndType(uri, "application/vnd.android.package-archive")
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
      }
      startActivity(intent)
      result.success(true)
    } catch (error: Exception) {
      result.error("install_failed", error.message ?: "Could not open installer.", null)
    }
  }
}
