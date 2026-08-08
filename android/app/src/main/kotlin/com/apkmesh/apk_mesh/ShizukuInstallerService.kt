package com.apkmesh.apk_mesh

import android.annotation.SuppressLint
import android.content.Context
import android.content.IIntentReceiver
import android.content.IIntentSender
import android.content.Intent
import android.content.IntentSender
import android.content.pm.IPackageInstaller
import android.content.pm.IPackageManager
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.os.Process
import android.os.ServiceManager
import android.util.Log
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

class ShizukuInstallerService : IShizukuInstaller.Stub {
    private val packageContext: Context?

    constructor() : super() {
        packageContext = null
    }

    constructor(context: Context) : super() {
        packageContext = context
    }

    override fun install(apk: ParcelFileDescriptor, size: Long): String {
        if (size <= 0) {
            apk.close()
            return failure("APK 文件为空")
        }

        var packageInstaller: PackageInstaller? = null
        var session: PackageInstaller.Session? = null
        var sessionId = invalidSessionId
        var abandonSession = false
        try {
            packageInstaller = createPackageInstaller()
            val params = PackageInstaller.SessionParams(
                PackageInstaller.SessionParams.MODE_FULL_INSTALL,
            ).apply {
                setSize(size)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    setInstallReason(PackageManager.INSTALL_REASON_USER)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    setRequireUserAction(
                        PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED,
                    )
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    setPackageSource(PackageInstaller.PACKAGE_SOURCE_DOWNLOADED_FILE)
                }
            }
            addInstallFlag(params, installReplaceExisting)

            sessionId = packageInstaller.createSession(params)
            abandonSession = true
            session = packageInstaller.openSession(sessionId)
            Log.d(tag, "Created PackageInstaller session $sessionId for $size bytes")

            ParcelFileDescriptor.AutoCloseInputStream(apk).use { input ->
                session.openWrite(baseApkName, 0, size).use { output ->
                    input.copyTo(output)
                    session.fsync(output)
                }
            }
            Log.d(tag, "APK stream written to session $sessionId")

            val receiver = LocalIntentReceiver()
            session.commit(receiver.intentSender)
            val result = receiver.awaitResult(resultTimeoutMillis)
                ?: return failure("等待 PackageInstaller 结果超时")
            val status = result.getIntExtra(
                PackageInstaller.EXTRA_STATUS,
                PackageInstaller.STATUS_FAILURE,
            )
            val message = result.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
            if (status != PackageInstaller.STATUS_PENDING_USER_ACTION) {
                abandonSession = false
            }
            Log.d(tag, "PackageInstaller session $sessionId returned $status: $message")
            return when (status) {
                PackageInstaller.STATUS_SUCCESS -> success
                PackageInstaller.STATUS_PENDING_USER_ACTION -> failure(
                    "系统仍要求用户确认安装，当前设备不允许 Shizuku 静默安装",
                )
                else -> failure(message ?: "PackageInstaller 安装失败，状态码：$status")
            }
        } catch (error: Throwable) {
            Log.e(tag, "PackageInstaller session failed", error)
            return failure(error.message ?: "PackageInstaller 安装失败")
        } finally {
            runCatching { session?.close() }
            if (abandonSession && sessionId != invalidSessionId) {
                runCatching { packageInstaller?.abandonSession(sessionId) }
            }
            runCatching { apk.close() }
        }
    }

    override fun destroy() {
        System.exit(0)
    }

    private fun createPackageInstaller(): PackageInstaller {
        val packageManagerBinder = ServiceManager.getService("package")
            ?: throw IllegalStateException("无法连接系统 Package Manager")
        val packageManager = IPackageManager.Stub.asInterface(packageManagerBinder)
        val installer = packageManager.packageInstaller
        val installerPackageName = if (Process.myUid() == 0) {
            packageContext?.packageName ?: shellPackageName
        } else {
            shellPackageName
        }
        val userId = Process.myUid() / userIdRange
        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
                PackageInstaller::class.java.getConstructor(
                    IPackageInstaller::class.java,
                    String::class.java,
                    String::class.java,
                    Int::class.javaPrimitiveType,
                ).newInstance(installer, installerPackageName, null, userId)
            }
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O -> {
                PackageInstaller::class.java.getConstructor(
                    IPackageInstaller::class.java,
                    String::class.java,
                    Int::class.javaPrimitiveType,
                ).newInstance(installer, installerPackageName, userId)
            }
            else -> {
                val context = packageContext
                    ?: throw UnsupportedOperationException(
                        "当前 Shizuku 版本无法在此 Android 版本创建安装会话",
                    )
                PackageInstaller::class.java.getConstructor(
                    Context::class.java,
                    PackageManager::class.java,
                    IPackageInstaller::class.java,
                    String::class.java,
                    Int::class.javaPrimitiveType,
                ).newInstance(
                    context,
                    context.packageManager,
                    installer,
                    installerPackageName,
                    userId,
                )
            }
        }
    }

    @SuppressLint("DiscouragedPrivateApi")
    private fun addInstallFlag(
        params: PackageInstaller.SessionParams,
        flag: Int,
    ) {
        val field = PackageInstaller.SessionParams::class.java
            .getDeclaredField("installFlags")
            .apply { isAccessible = true }
        field.setInt(params, field.getInt(params) or flag)
    }

    private fun failure(message: String): String = "failure:${message.take(maxOutputBytes)}"

    private class LocalIntentReceiver {
        private val result = AtomicReference<Intent?>()
        private val latch = CountDownLatch(1)
        private val localSender = object : IIntentSender.Stub() {
            override fun send(
                code: Int,
                intent: Intent?,
                resolvedType: String?,
                finishedReceiver: IIntentReceiver?,
                requiredPermission: String?,
                options: Bundle?,
            ): Int {
                accept(intent)
                return 0
            }

            override fun send(
                code: Int,
                intent: Intent?,
                resolvedType: String?,
                whitelistToken: IBinder?,
                finishedReceiver: IIntentReceiver?,
                requiredPermission: String?,
                options: Bundle?,
            ) {
                accept(intent)
            }
        }

        val intentSender: IntentSender = IntentSender::class.java
            .getConstructor(IIntentSender::class.java)
            .newInstance(localSender)

        fun awaitResult(timeoutMillis: Long): Intent? {
            if (!latch.await(timeoutMillis, TimeUnit.MILLISECONDS)) return null
            return result.get()
        }

        private fun accept(intent: Intent?) {
            if (intent == null || !result.compareAndSet(null, intent)) return
            latch.countDown()
        }
    }

    private companion object {
        const val tag = "ShizukuInstallerService"
        const val success = "success"
        const val shellPackageName = "com.android.shell"
        const val baseApkName = "base.apk"
        const val invalidSessionId = -1
        const val userIdRange = 100_000
        const val installReplaceExisting = 0x00000002
        const val maxOutputBytes = 16 * 1024
        const val resultTimeoutMillis = 4 * 60_000L
    }
}
