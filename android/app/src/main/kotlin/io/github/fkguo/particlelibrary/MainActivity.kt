package io.github.fkguo.particlelibrary

import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

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

  private fun validateApk(file: File): String? {
    val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      PackageManager.GET_SIGNING_CERTIFICATES
    } else {
      @Suppress("DEPRECATION")
      PackageManager.GET_SIGNATURES
    }
    val archive = packageManager.getPackageArchiveInfo(file.path, flags)
      ?: return "The downloaded file is not a valid APK."
    if (archive.packageName != packageName) {
      return "The downloaded APK belongs to another app."
    }
    val installed = try {
      packageManager.getPackageInfo(packageName, flags)
    } catch (_: Exception) {
      return "Could not read the installed app's signature."
    }
    val archiveVersion = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      archive.longVersionCode
    } else {
      @Suppress("DEPRECATION")
      archive.versionCode.toLong()
    }
    val installedVersion = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      installed.longVersionCode
    } else {
      @Suppress("DEPRECATION")
      installed.versionCode.toLong()
    }
    if (archiveVersion < installedVersion) {
      return "The downloaded APK is older than the installed version."
    }
    val archiveSigner = firstSigner(archive)
      ?: return "The downloaded APK has no signing certificate."
    val installedSigner = firstSigner(installed)
      ?: return "The installed app has no signing certificate."
    if (!MessageDigest.isEqual(archiveSigner, installedSigner)) {
      return "The downloaded APK is not signed by this app's release key."
    }
    return null
  }

  private fun firstSigner(info: PackageInfo): ByteArray? {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      return info.signingInfo?.apkContentsSigners?.firstOrNull()?.toByteArray()
    }
    @Suppress("DEPRECATION")
    return info.signatures?.firstOrNull()?.toByteArray()
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
    validateApk(file)?.let { reason ->
      result.error("invalid_apk", reason, null)
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
