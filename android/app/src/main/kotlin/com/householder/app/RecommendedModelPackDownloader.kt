package com.householder.app

import android.content.Context
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Downloads the HouseHolder recommended local model pack directly into
 * app-private storage. URLs are pinned to a known Hugging Face revision and
 * every file is verified with SHA-256 before it replaces the active model.
 *
 * The selected pack is MediaTek Research's ExecuTorch export of Meta Llama
 * 3.2 3B Instruct SpinQuant INT4/EO8, 2048-token context.
 */
class RecommendedModelPackDownloader(context: Context) {
    companion object {
        const val MODEL_DIRECTORY = "model-pack"
        const val MODEL_FILE = "llama3_2-2048-spin.pte"
        const val TOKENIZER_FILE = "tokenizer.model"

        private const val MODEL_NAME = "Llama 3.2 3B Instruct SpinQuant INT4/EO8"
        private const val MODEL_SOURCE = "MediaTek Research / Hugging Face"
        private const val MODEL_SOURCE_URL =
            "https://huggingface.co/MediaTek-Research/Llama-3.2-3B-Instruct-SpinQuant_INT4_EO8-executorch"
        private const val LICENSE_URL =
            "https://www.llama.com/llama3_2/license/"
        private const val REVISION = "6fbc4a4f3b9005d860c9f91f449ad84ab8ce6f58"
        private const val BASE_URL =
            "https://huggingface.co/MediaTek-Research/Llama-3.2-3B-Instruct-SpinQuant_INT4_EO8-executorch/resolve/$REVISION"
        private const val MODEL_URL = "$BASE_URL/$MODEL_FILE?download=true"
        private const val TOKENIZER_URL = "$BASE_URL/$TOKENIZER_FILE?download=true"

        const val MODEL_BYTES = 2_553_367_552L
        const val TOKENIZER_BYTES = 2_183_982L
        const val TOTAL_BYTES = MODEL_BYTES + TOKENIZER_BYTES
        private const val MODEL_SHA256 =
            "55d7f829f13063331c3d421816128553b545847628e1f0c71f44a78cb9229271"
        private const val TOKENIZER_SHA256 =
            "82e9d31979e92ab929cd544440f129d9ecd797b69e327f80f17e1c50d5551b55"
        private const val REQUIRED_HEADROOM_BYTES = 512L * 1024L * 1024L
    }

    private val appContext = context.applicationContext
    private val downloading = AtomicBoolean(false)

    @Volatile private var stage: String = "idle"
    @Volatile private var downloadedBytes: Long = 0L
    @Volatile private var lastError: String? = null

    fun info(): Map<String, Any?> = mapOf(
        "name" to MODEL_NAME,
        "source" to MODEL_SOURCE,
        "sourceUrl" to MODEL_SOURCE_URL,
        "licenseUrl" to LICENSE_URL,
        "modelBytes" to MODEL_BYTES,
        "tokenizerBytes" to TOKENIZER_BYTES,
        "totalBytes" to TOTAL_BYTES,
        "recommendedRamBytes" to 6L * 1024L * 1024L * 1024L,
    )

    fun status(): Map<String, Any?> = mapOf(
        "downloading" to downloading.get(),
        "stage" to stage,
        "downloadedBytes" to downloadedBytes,
        "totalBytes" to TOTAL_BYTES,
        "error" to lastError,
    )

    /** Blocking; call from a background executor. */
    fun downloadAndInstall(): Map<String, Any?> {
        if (!downloading.compareAndSet(false, true)) {
            throw IllegalStateException("Recommended model download is already running")
        }

        val directory = File(appContext.filesDir, MODEL_DIRECTORY).apply { mkdirs() }
        val required = TOTAL_BYTES + REQUIRED_HEADROOM_BYTES
        if (directory.usableSpace < required) {
            downloading.set(false)
            throw IllegalStateException(
                "Not enough free space. At least ${required / (1024 * 1024)} MB is required."
            )
        }

        val modelTarget = File(directory, MODEL_FILE)
        val tokenizerTarget = File(directory, TOKENIZER_FILE)
        val modelPart = File(directory, "$MODEL_FILE.part")
        val tokenizerPart = File(directory, "$TOKENIZER_FILE.part")

        try {
            lastError = null
            stage = "model"
            downloadVerified(
                MODEL_URL,
                modelPart,
                MODEL_BYTES,
                MODEL_SHA256,
                baseBytes = 0L,
            )

            stage = "tokenizer"
            downloadVerified(
                TOKENIZER_URL,
                tokenizerPart,
                TOKENIZER_BYTES,
                TOKENIZER_SHA256,
                baseBytes = MODEL_BYTES,
            )

            stage = "installing"
            replaceAtomically(modelPart, modelTarget)
            replaceAtomically(tokenizerPart, tokenizerTarget)

            downloadedBytes = TOTAL_BYTES
            stage = "ready"
            return mapOf(
                "installed" to true,
                "modelPath" to modelTarget.absolutePath,
                "tokenizerPath" to tokenizerTarget.absolutePath,
                "modelBytes" to modelTarget.length(),
            )
        } catch (error: Throwable) {
            lastError = error.message ?: error.javaClass.simpleName
            stage = "failed"
            throw error
        } finally {
            downloading.set(false)
        }
    }

    private fun downloadVerified(
        url: String,
        temporary: File,
        expectedBytes: Long,
        expectedSha256: String,
        baseBytes: Long,
    ) {
        if (temporary.exists() && temporary.length() > expectedBytes) temporary.delete()
        var existingBytes = if (temporary.exists()) temporary.length() else 0L
        downloadedBytes = baseBytes + existingBytes

        if (existingBytes < expectedBytes) {
            var connection = openFollowingRedirects(url, existingBytes)
            var response = connection.responseCode

            if (existingBytes > 0L && response == HttpURLConnection.HTTP_OK) {
                connection.disconnect()
                temporary.delete()
                existingBytes = 0L
                downloadedBytes = baseBytes
                connection = openFollowingRedirects(url, 0L)
                response = connection.responseCode
            }

            if (response != HttpURLConnection.HTTP_OK && response != HttpURLConnection.HTTP_PARTIAL) {
                connection.disconnect()
                throw IllegalStateException("Download failed with HTTP $response")
            }

            val append = existingBytes > 0L && response == HttpURLConnection.HTTP_PARTIAL
            connection.inputStream.buffered(1024 * 1024).use { input ->
                FileOutputStream(temporary, append).buffered(1024 * 1024).use { output ->
                    val buffer = ByteArray(1024 * 1024)
                    var totalForFile = if (append) existingBytes else 0L
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        totalForFile += count
                        downloadedBytes = baseBytes + totalForFile
                    }
                }
            }
            connection.disconnect()
        }

        if (temporary.length() != expectedBytes) {
            throw IllegalStateException(
                "Downloaded file size mismatch: ${temporary.length()} != $expectedBytes"
            )
        }

        stage = if (baseBytes == 0L) "verifying_model" else "verifying_tokenizer"
        val actualSha256 = sha256(temporary)
        if (!actualSha256.equals(expectedSha256, ignoreCase = true)) {
            temporary.delete()
            throw IllegalStateException("SHA-256 verification failed")
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
                if (rangeStart > 0L) setRequestProperty("Range", "bytes=$rangeStart-")
            }
            val code = connection.responseCode
            if (code !in setOf(301, 302, 303, 307, 308)) return connection
            val location = connection.getHeaderField("Location")
                ?: throw IllegalStateException("Redirect did not contain Location")
            current = URL(current, location)
            connection.disconnect()
        }
        throw IllegalStateException("Too many redirects while downloading model")
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).buffered(1024 * 1024).use { input ->
            val buffer = ByteArray(1024 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { byte -> "%02x".format(byte) }
    }

    private fun replaceAtomically(source: File, target: File) {
        if (target.exists() && !target.delete()) {
            throw IllegalStateException("Unable to replace ${target.name}")
        }
        if (!source.renameTo(target)) {
            source.copyTo(target, overwrite = true)
            if (!source.delete()) throw IllegalStateException("Unable to finalize ${target.name}")
        }
    }
}
