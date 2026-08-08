package com.apkmesh.apk_mesh

import android.annotation.SuppressLint
import android.content.Context
import android.content.IIntentReceiver
import android.content.IIntentSender
import android.content.Intent
import android.content.IntentSender
import android.content.pm.IPackageInstaller
import android.content.pm.IPackageInstallerSession
import android.content.pm.IPackageManager
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.IInterface
import android.os.Looper
import android.os.Process
import android.util.Log
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import org.lsposed.hiddenapibypass.HiddenApiBypass
import rikka.shizuku.Shizuku
import rikka.shizuku.ShizukuBinderWrapper
import rikka.shizuku.SystemServiceHelper

class ShizukuInstaller(context: Context) {
    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val lock = Any()

    private var activeRequest: InstallRequest? = null
    private var disposed = false

    init {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            runCatching { HiddenApiBypass.addHiddenApiExemptions("") }
                .onFailure { Log.e(tag, "Unable to enable hidden PackageInstaller APIs", it) }
        }
    }

    fun install(
        filePath: String,
        onSuccess: () -> Unit,
        onError: (String, String) -> Unit,
    ) {
        val request = InstallRequest(filePath, onSuccess, onError)
        val rejected = synchronized(lock) {
            when {
                disposed -> true
                activeRequest != null -> true
                else -> {
                    activeRequest = request
                    false
                }
            }
        }
        if (rejected) {
            val message = if (disposed) {
                "安装服务已关闭"
            } else {
                "已有 Shizuku 安装任务正在进行"
            }
            dispatch { onError("SHIZUKU_INSTALL_BUSY", message) }
            return
        }
        if (!isAuthorized()) {
            fail(
                request,
                "SHIZUKU_PERMISSION_DENIED",
                "Shizuku 未运行或未授予 APK Mesh 权限",
            )
            return
        }

        Log.d(tag, "Starting Shizuku Binder installation")
        scheduleTimeout(
            request,
            installTimeoutMillis,
            "SHIZUKU_INSTALL_TIMEOUT",
            "Shizuku 安装超时",
        )
        try {
            executor.execute { runInstall(request) }
        } catch (error: Exception) {
            fail(
                request,
                "SHIZUKU_INSTALL_UNAVAILABLE",
                error.message ?: "无法执行 Shizuku 安装",
            )
        }
    }

    fun dispose() {
        val request = synchronized(lock) {
            disposed = true
            activeRequest
        }
        if (request != null) {
            fail(request, "SHIZUKU_INSTALL_CANCELLED", "安装服务已关闭")
        }
        executor.shutdownNow()
    }

    private fun runInstall(request: InstallRequest) {
        val file = File(request.filePath)
        if (!file.isFile) {
            fail(request, "APK_FILE_NOT_FOUND", "找不到要安装的 APK 文件")
            return
        }
        val size = file.length()
        if (size <= 0) {
            fail(request, "APK_FILE_INVALID", "APK 文件为空")
            return
        }
        val packageName = appContext.packageManager
            .getPackageArchiveInfo(file.path, 0)
            ?.packageName
        if (packageName.isNullOrBlank()) {
            fail(request, "APK_FILE_INVALID", "无法读取 APK 包名")
            return
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
                setAppPackageName(packageName)
                setSize(size)
            }
            addInstallFlag(params, installReplaceExisting)

            sessionId = packageInstaller.createSession(params)
            abandonSession = true
            session = packageInstaller.openSession(sessionId)
            wrapSessionBinder(session)
            Log.d(tag, "Created wrapped PackageInstaller session $sessionId for $packageName")

            file.inputStream().use { input ->
                session.openWrite(baseApkName, 0, size).use { output ->
                    input.copyTo(output)
                    session.fsync(output)
                }
            }
            Log.d(tag, "APK stream written to wrapped session $sessionId")

            val receiver = LocalIntentReceiver()
            session.commit(receiver.intentSender)
            val result = receiver.awaitResult(resultTimeoutMillis)
                ?: throw IllegalStateException("等待 PackageInstaller 结果超时")
            val status = result.getIntExtra(
                PackageInstaller.EXTRA_STATUS,
                PackageInstaller.STATUS_FAILURE,
            )
            val message = result.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
            if (status != PackageInstaller.STATUS_PENDING_USER_ACTION) {
                abandonSession = false
            }
            Log.d(tag, "Wrapped PackageInstaller session $sessionId returned $status: $message")
            when (status) {
                PackageInstaller.STATUS_SUCCESS -> succeed(request)
                PackageInstaller.STATUS_PENDING_USER_ACTION -> fail(
                    request,
                    "SHIZUKU_USER_ACTION_REQUIRED",
                    "系统仍要求用户确认安装，当前设备不允许 Shizuku 静默安装",
                )
                else -> fail(
                    request,
                    "SHIZUKU_INSTALL_FAILED",
                    message ?: "PackageInstaller 安装失败，状态码：$status",
                )
            }
        } catch (error: Throwable) {
            Log.e(tag, "Shizuku Binder installation failed", error)
            fail(
                request,
                "SHIZUKU_INSTALL_FAILED",
                error.message ?: "Shizuku PackageInstaller 安装失败",
            )
        } finally {
            runCatching { session?.close() }
            if (abandonSession && sessionId != invalidSessionId) {
                runCatching { packageInstaller?.abandonSession(sessionId) }
            }
        }
    }

    private fun createPackageInstaller(): PackageInstaller {
        val packageManagerBinder = SystemServiceHelper.getSystemService("package")
            ?: throw IllegalStateException("无法连接系统 Package Manager")
        val packageManager = IPackageManager.Stub.asInterface(
            ShizukuBinderWrapper(packageManagerBinder),
        )
        val installer = IPackageInstaller.Stub.asInterface(
            ShizukuBinderWrapper(packageManager.packageInstaller.asBinder()),
        )
        val userId = Process.myUid() / userIdRange
        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
                PackageInstaller::class.java.getDeclaredConstructor(
                    IPackageInstaller::class.java,
                    String::class.java,
                    String::class.java,
                    Int::class.javaPrimitiveType,
                ).apply { isAccessible = true }
                    .newInstance(installer, shellPackageName, null, userId)
            }
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O -> {
                PackageInstaller::class.java.getDeclaredConstructor(
                    IPackageInstaller::class.java,
                    String::class.java,
                    Int::class.javaPrimitiveType,
                ).apply { isAccessible = true }
                    .newInstance(installer, shellPackageName, userId)
            }
            else -> {
                PackageInstaller::class.java.getDeclaredConstructor(
                    Context::class.java,
                    PackageManager::class.java,
                    IPackageInstaller::class.java,
                    String::class.java,
                    Int::class.javaPrimitiveType,
                ).apply { isAccessible = true }
                    .newInstance(
                        appContext,
                        appContext.packageManager,
                        installer,
                        shellPackageName,
                        userId,
                    )
            }
        }
    }

    @SuppressLint("DiscouragedPrivateApi", "SoonBlockedPrivateApi")
    private fun wrapSessionBinder(session: PackageInstaller.Session) {
        val field = PackageInstaller.Session::class.java
            .getDeclaredField("mSession")
            .apply { isAccessible = true }
        val original = field.get(session) as IInterface
        val wrapped = IPackageInstallerSession.Stub.asInterface(
            ShizukuBinderWrapper(original.asBinder()),
        )
        field.set(session, wrapped)
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

    private fun isAuthorized(): Boolean = try {
        Shizuku.pingBinder() &&
            !Shizuku.isPreV11() &&
            Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
    } catch (_: RuntimeException) {
        false
    }

    private fun succeed(request: InstallRequest) {
        if (!complete(request)) return
        dispatch(request.onSuccess)
    }

    private fun fail(request: InstallRequest, code: String, message: String) {
        if (!complete(request)) return
        dispatch { request.onError(code, message) }
    }

    private fun complete(request: InstallRequest): Boolean {
        if (!request.completed.compareAndSet(false, true)) return false
        cancelTimeout(request)
        synchronized(lock) {
            if (activeRequest === request) activeRequest = null
        }
        return true
    }

    private fun scheduleTimeout(
        request: InstallRequest,
        delayMillis: Long,
        code: String,
        message: String,
    ) {
        cancelTimeout(request)
        val action = Runnable {
            Log.w(tag, "$message after ${delayMillis}ms")
            fail(request, code, message)
        }
        request.timeoutAction = action
        mainHandler.postDelayed(action, delayMillis)
    }

    private fun cancelTimeout(request: InstallRequest) {
        val action = request.timeoutAction ?: return
        request.timeoutAction = null
        mainHandler.removeCallbacks(action)
    }

    private fun dispatch(action: () -> Unit) {
        mainHandler.post(action)
    }

    private class InstallRequest(
        val filePath: String,
        val onSuccess: () -> Unit,
        val onError: (String, String) -> Unit,
    ) {
        val completed = AtomicBoolean(false)
        @Volatile
        var timeoutAction: Runnable? = null
    }

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
            .getDeclaredConstructor(IIntentSender::class.java)
            .apply { isAccessible = true }
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
        const val tag = "ShizukuInstaller"
        const val shellPackageName = "com.android.shell"
        const val baseApkName = "base.apk"
        const val invalidSessionId = -1
        const val userIdRange = 100_000
        const val installReplaceExisting = 0x00000002
        const val resultTimeoutMillis = 4 * 60_000L
        const val installTimeoutMillis = 5 * 60_000L
    }
}
