package com.apkmesh.apk_mesh

import android.os.ParcelFileDescriptor
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.util.concurrent.atomic.AtomicReference

class ShizukuInstallerService : IShizukuInstaller.Stub() {
    override fun install(apk: ParcelFileDescriptor, size: Long): String {
        if (size <= 0) {
            apk.close()
            return failure("APK 文件为空")
        }

        val process = try {
            ProcessBuilder(
                "/system/bin/pm",
                "install",
                "-r",
                "-S",
                size.toString(),
            ).redirectErrorStream(true).start()
        } catch (error: Exception) {
            apk.close()
            return failure(error.message ?: "无法启动 Package Manager")
        }
        val output = AtomicReference("")
        val outputThread = Thread {
            output.set(
                runCatching { readOutput(process.inputStream) }
                    .getOrElse { it.message ?: "无法读取 Package Manager 输出" },
            )
        }.apply { start() }

        var writeError: Exception? = null
        try {
            ParcelFileDescriptor.AutoCloseInputStream(apk).use { input ->
                process.outputStream.use { outputStream ->
                    input.copyTo(outputStream)
                }
            }
        } catch (error: Exception) {
            writeError = error
        }

        val exitCode = try {
            process.waitFor()
        } catch (error: InterruptedException) {
            process.destroy()
            Thread.currentThread().interrupt()
            return failure("安装被中断")
        }
        try {
            outputThread.join()
        } catch (error: InterruptedException) {
            Thread.currentThread().interrupt()
            return failure("安装被中断")
        }

        val message = output.get().trim()
        if (writeError != null) {
            return failure(message.ifBlank { writeError.message ?: "无法传输 APK 文件" })
        }
        return if (exitCode == 0 && message.contains("Success", ignoreCase = true)) {
            success
        } else {
            failure(message.ifBlank { "Package Manager 退出码：$exitCode" })
        }
    }

    override fun destroy() {
        System.exit(0)
    }

    private fun readOutput(input: InputStream): String {
        val output = ByteArrayOutputStream()
        input.use { stream ->
            val buffer = ByteArray(1024)
            while (true) {
                val read = stream.read(buffer)
                if (read < 0) break
                val remaining = maxOutputBytes - output.size()
                if (remaining > 0) {
                    output.write(buffer, 0, minOf(read, remaining))
                }
            }
        }
        return output.toString(Charsets.UTF_8.name())
    }

    private fun failure(message: String): String = "failure:${message.take(maxOutputBytes)}"

    private companion object {
        const val success = "success"
        const val maxOutputBytes = 16 * 1024
    }
}
