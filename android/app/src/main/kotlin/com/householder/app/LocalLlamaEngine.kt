package com.householder.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.pytorch.executorch.extension.llm.LlmCallback
import org.pytorch.executorch.extension.llm.LlmGenerationConfig
import org.pytorch.executorch.extension.llm.LlmModule
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Android-only ExecuTorch adapter for the first HouseHolder MVP.
 *
 * Model files are intentionally installed outside the APK under app-private
 * storage so a multi-GB model pack can be downloaded, replaced and verified
 * independently from application releases.
 */
class LocalLlamaEngine(context: Context) {
    companion object {
        private const val MODEL_DIRECTORY = "model-pack"
        private const val MODEL_FILE = "llama32-3b-instruct.pte"
        private val TOKENIZER_FILES = listOf("tokenizer.bin", "tokenizer.model")
    }

    private val appContext = context.applicationContext
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var module: LlmModule? = null

    @Volatile
    private var generating = false

    data class ModelStatus(
        val ready: Boolean,
        val modelPath: String,
        val tokenizerPath: String?,
        val modelBytes: Long,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "ready" to ready,
            "modelPath" to modelPath,
            "tokenizerPath" to tokenizerPath,
            "modelBytes" to modelBytes,
        )
    }

    fun status(): ModelStatus {
        val model = modelFile()
        val tokenizer = tokenizerFileOrNull()
        return ModelStatus(
            ready = model.isFile && model.length() > 0L && tokenizer?.isFile == true,
            modelPath = model.absolutePath,
            tokenizerPath = tokenizer?.absolutePath,
            modelBytes = if (model.isFile) model.length() else 0L,
        )
    }

    fun generate(
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        onSuccess: (String) -> Unit,
        onError: (String, String) -> Unit,
    ) {
        if (prompt.isBlank()) {
            onError("EMPTY_PROMPT", "Prompt must not be empty")
            return
        }
        if (generating) {
            onError("LLM_BUSY", "Local Llama generation is already running")
            return
        }

        val currentStatus = status()
        if (!currentStatus.ready || currentStatus.tokenizerPath == null) {
            onError(
                "MODEL_NOT_INSTALLED",
                "Install $MODEL_FILE and a tokenizer file under ${modelDirectory().absolutePath}",
            )
            return
        }

        generating = true
        executor.execute {
            try {
                val llm = ensureLoaded(
                    currentStatus.modelPath,
                    currentStatus.tokenizerPath,
                    temperature,
                )
                val output = StringBuilder()
                val finished = AtomicBoolean(false)

                val config = LlmGenerationConfig.create()
                    .maxNewTokens(maxTokens.coerceIn(1, 1024))
                    .temperature(temperature.coerceIn(0.0f, 2.0f))
                    .echo(false)
                    .build()

                llm.generate(prompt, config, object : LlmCallback {
                    override fun onResult(token: String) {
                        output.append(token)
                    }

                    override fun onStats(statsJson: String) {
                        if (finished.compareAndSet(false, true)) {
                            generating = false
                            mainHandler.post { onSuccess(output.toString()) }
                        }
                    }

                    override fun onError(errorCode: Int, message: String) {
                        if (finished.compareAndSet(false, true)) {
                            generating = false
                            mainHandler.post {
                                onError("EXECUTORCH_$errorCode", message)
                            }
                        }
                    }
                })
            } catch (error: Throwable) {
                generating = false
                mainHandler.post {
                    onError(
                        "LLM_GENERATION_FAILED",
                        error.message ?: error.javaClass.simpleName,
                    )
                }
            }
        }
    }

    @Synchronized
    private fun ensureLoaded(
        modelPath: String,
        tokenizerPath: String,
        temperature: Float,
    ): LlmModule {
        module?.let { return it }

        val created = LlmModule(modelPath, tokenizerPath, temperature)
        val status = created.load()
        if (status != 0) {
            throw IllegalStateException("ExecuTorch model load failed with status $status")
        }
        module = created
        return created
    }

    fun stop() {
        try {
            module?.stop()
        } finally {
            generating = false
        }
    }

    fun close() {
        stop()
        executor.shutdownNow()
    }

    private fun modelDirectory(): File = File(appContext.filesDir, MODEL_DIRECTORY)

    private fun modelFile(): File = File(modelDirectory(), MODEL_FILE)

    private fun tokenizerFileOrNull(): File? = TOKENIZER_FILES
        .asSequence()
        .map { File(modelDirectory(), it) }
        .firstOrNull { it.isFile && it.length() > 0L }
}
