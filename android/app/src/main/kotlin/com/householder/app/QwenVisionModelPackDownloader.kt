package com.householder.app

import android.content.Context
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean

/** Downloads the official Qwen3-VL 2B Q4_K_M language model and Q8_0 vision projector. */
class QwenVisionModelPackDownloader(context: Context) {
    companion object {
        const val MODEL_ID = "qwen3-vl-2b-instruct-q4_k_m"
        const val MODEL_DIRECTORY = "model-pack/$MODEL_ID"
        const val MODEL_FILE = "Qwen3VL-2B-Instruct-Q4_K_M.gguf"
        const val MMPROJ_FILE = "mmproj-Qwen3VL-2B-Instruct-Q8_0.gguf"

        // Immutable official Qwen repository revision containing both files.
        private const val REVISION = "d38d39f5972e27cd58023f9b1e9f994b0c85ca47"
        private const val BASE_URL =
            "https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct-GGUF/resolve/$REVISION"
        private const val MODEL_URL = "$BASE_URL/$MODEL_FILE?download=true"
        private const val MMPROJ_URL = "$BASE_URL/$MMPROJ_FILE?download=true"

        // SHA-256 values published by the official Hugging Face Xet pointers.
        private const val MODEL_SHA256 =
            "089d75c52f4b7ffc56ba998ffc50aae89fcafc755f9e7208aacca281dca6c2ae"
        private const val MMPROJ_SHA256 =
            "f9a68fabba69c3b81e153367b2c7521030b0fa8bb0de400c9599c8e6725f9c82"
        const val MMPROJ_BYTES = 445_053_056L
        // Exact size is verified by SHA-256; this conservative value is used only for storage planning/progress.
        const val MODEL_ESTIMATED_BYTES = 1_110_000_000L
        const val TOTAL_ESTIMATED_BYTES = MODEL_ESTIMATED_BYTES + MMPROJ_BYTES
        private const val REQUIRED_HEADROOM_BYTES = 512L * 1024L * 1024L
        private const val IO_BUFFER_BYTES = 1024 * 1024
    }

    private val appContext = context.applicationContext
    private val downloading = AtomicBoolean(false)
    @Volatile private var stage = "idle"
    @Volatile private var downloadedBytes = 0L
    @Volatile private var lastError: String? = null

    fun paths(): Pair<File, File> {
        val directory = File(appContext.filesDir, MODEL_DIRECTORY)
        return File(directory, MODEL_FILE) to File(directory, MMPROJ_FILE)
    }

    fun isInstalled(): Boolean {
        val (model, mmproj) = paths()
        return model.isFile && mmproj.isFile
    }

    fun status(): Map<String, Any?> {
        val (model, mmproj) = paths()
        return mapOf(
            "modelId" to MODEL_ID,
            "installed" to isInstalled(),
            "downloading" to downloading.get(),
            "stage" to stage,
            "downloadedBytes" to downloadedBytes,
            "totalEstimatedBytes" to TOTAL_ESTIMATED_BYTES,
            "modelPath" to model.absolutePath,
            "mmprojPath" to mmproj.absolutePath,
            "error" to lastError,
        )
    }

    /** Blocking; invoke on a background executor. */
    fun downloadAndInstall(): Map<String, Any?> {
        if (!downloading.compareAndSet(false, true)) {
            throw IllegalStateException("Qwen3-VL model download is already running")
        }
        val directory = File(appContext.filesDir, MODEL_DIRECTORY).apply { mkdirs() }
        val required = TOTAL_ESTIMATED_BYTES + REQUIRED_HEADROOM_BYTES
        if (directory.usableSpace < required) {
            downloading.set(false)
            throw IllegalStateException("Not enough free space for Qwen3-VL model pack")
        }

        val (modelTarget, mmprojTarget) = paths()
        val modelPart = File(directory, "$MODEL_FILE.part")
        val mmprojPart = File(directory, "$MMPROJ_FILE.part")
        try {
            lastError = null
            stage = "model"
            downloadAndVerify(MODEL_URL, modelPart, MODEL_SHA256, 0L)
            val modelBytes = modelPart.length()
            stage = "mmproj"
            downloadAndVerify(MMPROJ_URL, mmprojPart, MMPROJ_SHA256, modelBytes)
            if (mmprojPart.length() != MMPROJ_BYTES) {
                throw IllegalStateException("Vision projector size mismatch")
            }
            stage = "installing"
            replaceAtomically(modelPart, modelTarget)
            replaceAtomically(mmprojPart, mmprojTarget)
            downloadedBytes = modelTarget.length() + mmprojTarget.length()
            stage = "ready"
            return status()
        } catch (error: Throwable) {
            lastError = error.message ?: error.javaClass.simpleName
            stage = "failed"
            throw error
        } finally {
            downloading.set(false)
        }
    }

    private fun downloadAndVerify(url: String, temporary: File, sha256: String, baseBytes: Long) {
        var existing = if (temporary.isFile) temporary.length() else 0L
        downloadedBytes = baseBytes + existing
        var connection = openFollowingRedirects(url, existing)
        var response = connection.responseCode
        if (existing > 0 && response == HttpURLConnection.HTTP_OK) {
            connection.disconnect()
            temporary.delete()
            existing = 0L
            connection = openFollowingRedirects(url, 0L)
            response = connection.responseCode
        }
        if (response != HttpURLConnection.HTTP_OK && response != HttpURLConnection.HTTP_PARTIAL) {
            connection.disconnect()
            throw IllegalStateException("Download failed with HTTP $response")
        }
        val append = existing > 0 && response == HttpURLConnection.HTTP_PARTIAL
        connection.inputStream.buffered(IO_BUFFER_BYTES).use { input ->
            FileOutputStream(temporary, append).buffered(IO_BUFFER_BYTES).use { output ->
                val buffer = ByteArray(IO_BUFFER_BYTES)
                var total = if (append) existing else 0L
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    output.write(buffer, 0, count)
                    total += count
                    downloadedBytes = baseBytes + total
                }
            }
        }
        connection.disconnect()
        stage = "verifying"
        if (!fileSha256(temporary).equals(sha256, ignoreCase = true)) {
            temporary.delete()
            throw IllegalStateException("SHA-256 verification failed for ${temporary.name}")
        }
    }

    private fun openFollowingRedirects(source: String, rangeStart: Long): HttpURLConnection {
        var current = URL(source)
        repeat(10) {
            val connection = (current.openConnection() as HttpURLConnection).apply {
                instanceFollowRedirects = false
                connectTimeout = 30_000
                readTimeout = 60_000
                requestMethod = "GET"
                setRequestProperty("User-Agent", "HouseHolder-Android/0.1")
                setRequestProperty("Accept-Encoding", "identity")
                if (rangeStart > 0) setRequestProperty("Range", "bytes=$rangeStart-")
            }
            if (connection.responseCode !in setOf(301, 302, 303, 307, 308)) return connection
            val location = connection.getHeaderField("Location")
                ?: throw IllegalStateException("Redirect did not contain Location")
            current = URL(current, location)
            connection.disconnect()
        }
        throw IllegalStateException("Too many redirects while downloading Qwen3-VL")
    }

    private fun fileSha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).buffered(IO_BUFFER_BYTES).use { input ->
            val buffer = ByteArray(IO_BUFFER_BYTES)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun replaceAtomically(source: File, target: File) {
        if (!source.isFile) throw IllegalStateException("Verified source missing: ${source.name}")
        val expectedBytes = source.length()
        if (target.exists() && !target.delete()) throw IllegalStateException("Unable to replace ${target.name}")
        if (source.renameTo(target)) return
        if (!source.exists() && target.isFile && target.length() == expectedBytes) return
        FileInputStream(source).use { input ->
            FileOutputStream(target, false).use { output ->
                input.copyTo(output, IO_BUFFER_BYTES)
                output.fd.sync()
            }
        }
        if (target.length() != expectedBytes) throw IllegalStateException("Installed file size mismatch")
        source.delete()
    }
}
