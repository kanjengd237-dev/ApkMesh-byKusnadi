package com.apkmesh.apk_mesh

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import java.util.Locale
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val progressChannelId = "apkmesh_download_progress"
    private val eventChannelId = "apkmesh_download_events"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannels()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.apkmesh/install")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstallPackages" -> {
                        val allowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            packageManager.canRequestPackageInstalls()
                        result.success(allowed)
                    }
                    "requestInstallPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName"),
                                ),
                            )
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.apkmesh/download_notifications",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> result.success(requestNotificationPermission())
                "showProgress" -> {
                    showDownloadProgress(call)
                    result.success(null)
                }
                "showCompleted" -> {
                    showDownloadCompleted(call)
                    result.success(null)
                }
                "showFailed" -> {
                    showDownloadFailed(call)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                progressChannelId,
                "下载进度",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "APK 文件下载进度" },
        )
        manager.createNotificationChannel(
            NotificationChannel(
                eventChannelId,
                "下载结果",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply { description = "APK 文件下载完成或失败" },
        )
    }

    private fun requestNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            return true
        }
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7301)
        return false
    }

    private fun canPostNotifications(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private fun showDownloadProgress(call: MethodCall) {
        if (!canPostNotifications()) return
        val id = call.argument<String>("id") ?: return
        val title = call.argument<String>("title") ?: "APK 下载"
        val received = call.argument<Number>("received")?.toLong() ?: 0L
        val total = call.argument<Number>("total")?.toLong()
        val text = if (total != null && total > 0) {
            "${formatBytes(received)} / ${formatBytes(total)}"
        } else {
            "已下载 ${formatBytes(received)}"
        }
        val builder = notificationBuilder(progressChannelId)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(text)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
        if (total != null && total > 0) {
            val percent = ((received.toDouble() / total.toDouble()) * 100)
                .toInt()
                .coerceIn(0, 100)
            builder.setProgress(100, percent, false)
        } else {
            builder.setProgress(0, 0, true)
        }
        launchPendingIntent()?.let(builder::setContentIntent)
        notificationManager().notify(notificationId(id), builder.build())
    }

    private fun showDownloadCompleted(call: MethodCall) {
        if (!canPostNotifications()) return
        val id = call.argument<String>("id") ?: return
        val title = call.argument<String>("title") ?: "APK 下载"
        val path = call.argument<String>("path") ?: ""
        val builder = notificationBuilder(eventChannelId)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("下载完成：$title")
            .setContentText("点击返回 APK Mesh 查看")
            .setStyle(Notification.BigTextStyle().bigText("文件已保存到：$path"))
            .setAutoCancel(true)
        launchPendingIntent()?.let(builder::setContentIntent)
        notificationManager().notify(notificationId(id), builder.build())
    }

    private fun showDownloadFailed(call: MethodCall) {
        if (!canPostNotifications()) return
        val id = call.argument<String>("id") ?: return
        val title = call.argument<String>("title") ?: "APK 下载"
        val error = call.argument<String>("error") ?: "未知错误"
        val builder = notificationBuilder(eventChannelId)
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setContentTitle("下载失败：$title")
            .setContentText(error)
            .setStyle(Notification.BigTextStyle().bigText(error))
            .setAutoCancel(true)
        launchPendingIntent()?.let(builder::setContentIntent)
        notificationManager().notify(notificationId(id), builder.build())
    }

    private fun notificationBuilder(channelId: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            Notification.Builder(this)
        }

    private fun launchPendingIntent(): PendingIntent? {
        val intent = packageManager.getLaunchIntentForPackage(packageName) ?: return null
        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun notificationManager(): NotificationManager =
        getSystemService(NotificationManager::class.java)

    private fun notificationId(id: String): Int = id.hashCode() and Int.MAX_VALUE

    private fun formatBytes(bytes: Long): String {
        if (bytes < 1024) return "$bytes B"
        val units = arrayOf("KB", "MB", "GB", "TB")
        var value = bytes.toDouble()
        var unit = -1
        while (value >= 1024 && unit < units.lastIndex) {
            value /= 1024
            unit += 1
        }
        return String.format(Locale.US, "%.1f %s", value, units[unit])
    }
}
