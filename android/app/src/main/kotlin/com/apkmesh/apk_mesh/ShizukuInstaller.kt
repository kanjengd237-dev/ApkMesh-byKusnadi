package com.apkmesh.apk_mesh

import android.content.ComponentName
import android.content.Context
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelFileDescriptor
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import rikka.shizuku.Shizuku

class ShizukuInstaller(context: Context) {
    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val lock = Any()
    private val userServiceArgs = Shizuku.UserServiceArgs(
        ComponentName(
            appContext.packageName,
            ShizukuInstallerService::class.java.name,
        ),
    ).daemon(false)
        .processNameSuffix("apkmesh_installer")
        .tag("apkmesh-shizuku-installer")
        .version(1)

    private var activeRequest: InstallRequest? = null
    private var disposed = false

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

        request.connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName, service: IBinder) {
                if (request.completed.get()) {
                    unbind(request)
                    return
                }
                val installer = IShizukuInstaller.Stub.asInterface(service)
                try {
                    executor.execute { runInstall(request, installer) }
                } catch (error: Exception) {
                    fail(
                        request,
                        "SHIZUKU_INSTALL_UNAVAILABLE",
                        error.message ?: "无法执行 Shizuku 安装",
                    )
                }
            }

            override fun onServiceDisconnected(name: ComponentName) {
                fail(
                    request,
                    "SHIZUKU_SERVICE_DISCONNECTED",
                    "Shizuku 安装服务已断开",
                )
            }
        }
        try {
            Shizuku.bindUserService(userServiceArgs, request.connection!!)
        } catch (error: RuntimeException) {
            fail(
                request,
                "SHIZUKU_SERVICE_UNAVAILABLE",
                error.message ?: "无法连接 Shizuku 安装服务",
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

    private fun runInstall(request: InstallRequest, installer: IShizukuInstaller) {
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

        val outcome = try {
            ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use {
                installer.install(it, size)
            }
        } catch (error: Exception) {
            fail(
                request,
                "SHIZUKU_INSTALL_FAILED",
                error.message ?: "Shizuku 安装调用失败",
            )
            return
        }
        if (outcome == success) {
            succeed(request)
            return
        }
        val message = outcome
            .removePrefix(failurePrefix)
            .trim()
            .ifBlank { "Package Manager 未返回成功结果" }
        fail(request, "SHIZUKU_INSTALL_FAILED", message)
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
        synchronized(lock) {
            if (activeRequest === request) activeRequest = null
        }
        unbind(request)
        return true
    }

    private fun unbind(request: InstallRequest) {
        val connection = request.connection ?: return
        runCatching {
            if (Shizuku.pingBinder()) {
                Shizuku.unbindUserService(userServiceArgs, connection, true)
            }
        }
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
        var connection: ServiceConnection? = null
    }

    private companion object {
        const val success = "success"
        const val failurePrefix = "failure:"
    }
}
