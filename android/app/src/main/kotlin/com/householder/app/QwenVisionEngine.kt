package com.householder.app

import android.content.Context
import java.io.File

/** Android boundary for the Qwen3-VL multimodal runtime. */
class QwenVisionEngine(context: Context) {
    private val downloader = QwenVisionModelPackDownloader(context)

    fun status(): Map<String, Any?> {
        val base = downloader.status().toMutableMap()
        base["runtime"] = QwenVisionNative.runtimeVersionOrNull() ?: "llama.cpp/mtmd"
        base["nativeReady"] = QwenVisionNative.isAvailable()
        base["ready"] = downloader.isInstalled() && QwenVisionNative.isAvailable()
        return base
    }

    fun downloadAndInstall(): Map<String, Any?> = downloader.downloadAndInstall()

    fun analyzeImage(
        imagePath: String,
        prompt: String,
        maxTokens: Int,
        temperature: Float,
    ): Map<String, Any?> {
        val image = File(imagePath)
        require(image.isFile) { "Image does not exist: $imagePath" }
        require(prompt.isNotBlank()) { "prompt is required" }
        if (!downloader.isInstalled()) throw IllegalStateException("Qwen3-VL model pack is not installed")
        if (!QwenVisionNative.isAvailable()) throw UnsupportedOperationException("llama.cpp libmtmd native runtime is not linked")
        val (model, mmproj) = downloader.paths()
        val text = QwenVisionNative.analyzeImage(
            model.absolutePath,
            mmproj.absolutePath,
            image.absolutePath,
            prompt,
            maxTokens.coerceIn(1, 2048),
            temperature.coerceIn(0f, 2f),
        )
        return mapOf(
            "text" to text,
            "modelId" to QwenVisionModelPackDownloader.MODEL_ID,
            "runtime" to (QwenVisionNative.runtimeVersionOrNull() ?: "llama.cpp/mtmd"),
        )
    }
}

/**
 * Stable JNI contract. RegisterNatives is used by C++ so Kotlin/JVM symbol name
 * mangling cannot silently break the bridge.
 */
object QwenVisionNative {
    private val loaded: Boolean = try {
        System.loadLibrary("householder_qwen_vl")
        true
    } catch (_: UnsatisfiedLinkError) {
        false
    }

    fun isAvailable(): Boolean = loaded && runtimeVersionOrNull() != null

    fun runtimeVersionOrNull(): String? = if (!loaded) null else try {
        runtimeVersion()
    } catch (_: UnsatisfiedLinkError) {
        null
    }

    @JvmStatic external fun runtimeVersion(): String

    @JvmStatic external fun analyzeImage(
        modelPath: String,
        mmprojPath: String,
        imagePath: String,
        prompt: String,
        maxTokens: Int,
        temperature: Float,
    ): String
}
