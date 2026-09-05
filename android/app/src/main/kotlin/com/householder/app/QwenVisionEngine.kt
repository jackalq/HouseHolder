package com.householder.app

import android.content.Context
import java.io.File

/**
 * Android boundary for the Qwen3-VL multimodal runtime.
 *
 * Model-pack lifecycle is usable before native mtmd is linked. Image inference
 * deliberately fails closed until the JNI bridge reports itself available;
 * Flutter can then fall back to the existing ML Kit timetable OCR path.
 */
class QwenVisionEngine(context: Context) {
    private val downloader = QwenVisionModelPackDownloader(context)

    fun status(): Map<String, Any?> {
        val base = downloader.status().toMutableMap()
        base["runtime"] = "llama.cpp/mtmd"
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
        if (!downloader.isInstalled()) {
            throw IllegalStateException("Qwen3-VL model pack is not installed")
        }
        if (!QwenVisionNative.isAvailable()) {
            throw UnsupportedOperationException("llama.cpp libmtmd native runtime is not linked yet")
        }
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
            "runtime" to "llama.cpp/mtmd",
        )
    }
}

/** JNI contract. Native loading is optional so existing APKs remain bootable. */
private object QwenVisionNative {
    private val loaded: Boolean = try {
        System.loadLibrary("householder_qwen_vl")
        true
    } catch (_: UnsatisfiedLinkError) {
        false
    }

    fun isAvailable(): Boolean = loaded

    external fun analyzeImage(
        modelPath: String,
        mmprojPath: String,
        imagePath: String,
        prompt: String,
        maxTokens: Int,
        temperature: Float,
    ): String
}
