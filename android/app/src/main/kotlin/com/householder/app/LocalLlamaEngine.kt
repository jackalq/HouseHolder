package com.householder.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import net.amazingapps.llama.android.core.AiChat
import net.amazingapps.llama.android.core.InferenceEngine
import org.pytorch.executorch.extension.llm.LlmCallback
import org.pytorch.executorch.extension.llm.LlmGenerationConfig
import org.pytorch.executorch.extension.llm.LlmModule
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Hybrid local LLM adapter.
 *
 * - ExecuTorch handles the original Llama 3.2 .pte pack.
 * - llama.cpp (through llama.android) handles GGUF packs such as Qwen2.5.
 *
 * The public API intentionally stays unchanged so the Flutter MethodChannel
 * does not need to know which native runtime is active.
 */
class LocalLlamaEngine(context: Context) {
    companion object {
        private const val MODEL_DIRECTORY = RecommendedModelPackDownloader.MODEL_DIRECTORY
        private const val ACTIVE_MODEL_FILE = "active_model.txt"

        const val LLAMA_MODEL_ID = "llama3.2-3b-instruct-spinquant-int4-eo8"
        const val QWEN_MODEL_ID = "qwen2.5-1.5b-instruct-q4_k_m"

        private const val LLAMA_MODEL_NAME = "Llama 3.2 3B Instruct SpinQuant INT4/EO8"
        private const val QWEN_MODEL_NAME = "Qwen2.5-1.5B-Instruct Q4_K_M"

        private const val QWEN_DIRECTORY = "qwen2.5-1.5b-instruct-q4_k_m"
        private const val QWEN_MODEL_FILE = "qwen2.5-1.5b-instruct-q4_k_m.gguf"
        private const val QWEN_TOKENIZER_FILE = "tokenizer.json"

        private val MODEL_FILES = listOf(
            RecommendedModelPackDownloader.MODEL_FILE,
            "llama32-3b-instruct.pte",
        )
        private val TOKENIZER_FILES = listOf(
            RecommendedModelPackDownloader.TOKENIZER_FILE,
            "tokenizer.bin",
        )
        private val OUTPUT_CONTROL_TOKENS = listOf(
            "<|eot_id|>",
            "<|end_of_text|>",
            "<|eom_id|>",
            "<|im_end|>",
            "<|endoftext|>",
        )
    }

    private val appContext = context.applicationContext
    private val execExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ggufScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val ggufEngineDelegate = lazy { AiChat.getInferenceEngine(appContext) }

    @Volatile private var module: LlmModule? = null
    @Volatile private var generating = false
    @Volatile private var ggufLoadedPath: String? = null
    @Volatile private var ggufJob: Job? = null

    data class ModelStatus(
        val ready: Boolean,
        val modelPath: String,
        val tokenizerPath: String?,
        val modelBytes: Long,
        val modelId: String,
        val modelName: String,
        val runtime: String,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "ready" to ready,
            "modelPath" to modelPath,
            "tokenizerPath" to tokenizerPath,
            "modelBytes" to modelBytes,
            "modelId" to modelId,
            "modelName" to modelName,
            "runtime" to runtime,
        )
    }

    fun status(): ModelStatus {
        val llama = llamaStatus()
        val qwen = qwenStatus()
        return when (requestedModelId()) {
            QWEN_MODEL_ID -> if (qwen.ready) qwen else llama
            LLAMA_MODEL_ID -> if (llama.ready) llama else qwen
            else -> if (qwen.ready) qwen else llama
        }
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
        synchronized(this) {
            if (generating) {
                onError("LLM_BUSY", "Local LLM generation is already running")
                return
            }
            generating = true
        }

        val currentStatus = status()
        if (!currentStatus.ready) {
            generating = false
            onError(
                "MODEL_NOT_INSTALLED",
                "Install a supported local model pack before generating.",
            )
            return
        }

        if (currentStatus.runtime == "llama.cpp") {
            generateGguf(currentStatus, prompt, maxTokens, onSuccess, onError)
        } else {
            generateExecuTorch(currentStatus, prompt, maxTokens, temperature, onSuccess, onError)
        }
    }

    private fun generateExecuTorch(
        currentStatus: ModelStatus,
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        onSuccess: (String) -> Unit,
        onError: (String, String) -> Unit,
    ) {
        val tokenizerPath = currentStatus.tokenizerPath
        if (tokenizerPath == null) {
            generating = false
            onError("MODEL_NOT_INSTALLED", "ExecuTorch tokenizer is missing.")
            return
        }

        execExecutor.execute {
            try {
                val llm = ensureExecuTorchLoaded(
                    currentStatus.modelPath,
                    tokenizerPath,
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
                            val cleanOutput = sanitizeGeneratedText(output.toString())
                            mainHandler.post { onSuccess(cleanOutput) }
                        }
                    }

                    override fun onError(errorCode: Int, message: String) {
                        if (finished.compareAndSet(false, true)) {
                            generating = false
                            mainHandler.post { onError("EXECUTORCH_$errorCode", message) }
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

    private fun generateGguf(
        currentStatus: ModelStatus,
        prompt: String,
        maxTokens: Int,
        onSuccess: (String) -> Unit,
        onError: (String, String) -> Unit,
    ) {
        ggufJob = ggufScope.launch {
            try {
                val engine = ensureGgufLoaded(currentStatus.modelPath)
                val output = StringBuilder()
                engine.sendUserPrompt(prompt, maxTokens.coerceIn(1, 1024)).collect { token ->
                    output.append(token)
                }
                generating = false
                val cleanOutput = sanitizeGeneratedText(output.toString())
                mainHandler.post { onSuccess(cleanOutput) }
            } catch (_: CancellationException) {
                generating = false
            } catch (error: Throwable) {
                generating = false
                mainHandler.post {
                    onError(
                        "LLAMA_CPP_GENERATION_FAILED",
                        error.message ?: error.javaClass.simpleName,
                    )
                }
            }
        }
    }

    private suspend fun ensureGgufLoaded(modelPath: String): InferenceEngine {
        val engine = ggufEngineDelegate.value
        val initializedState = engine.state.first { state ->
            state is InferenceEngine.State.Initialized ||
                state is InferenceEngine.State.ModelReady ||
                state is InferenceEngine.State.Error
        }
        if (initializedState is InferenceEngine.State.Error) throw initializedState.exception

        if (ggufLoadedPath != modelPath || engine.state.value !is InferenceEngine.State.ModelReady) {
            if (engine.state.value is InferenceEngine.State.ModelReady) engine.cleanUp()
            engine.loadModel(modelPath)
            ggufLoadedPath = modelPath
        }
        return engine
    }

    private fun sanitizeGeneratedText(raw: String): String {
        var result = raw
        for (token in OUTPUT_CONTROL_TOKENS) result = result.replace(token, "")
        return result.trim()
    }

    @Synchronized
    private fun ensureExecuTorchLoaded(
        modelPath: String,
        tokenizerPath: String,
        temperature: Float,
    ): LlmModule {
        module?.let { return it }
        val created = LlmModule(modelPath, tokenizerPath, temperature)
        created.load()
        module = created
        return created
    }

    fun stop() {
        try {
            module?.stop()
            ggufJob?.cancel()
        } finally {
            generating = false
        }
    }

    fun close() {
        stop()
        execExecutor.shutdownNow()
        ggufScope.cancel()
        if (ggufEngineDelegate.isInitialized()) {
            ggufEngineDelegate.value.destroy()
        }
    }

    private fun modelDirectory(): File = File(appContext.filesDir, MODEL_DIRECTORY)

    private fun llamaModelFile(): File {
        val directory = modelDirectory()
        return MODEL_FILES
            .asSequence()
            .map { File(directory, it) }
            .firstOrNull { it.isFile && it.length() > 0L }
            ?: File(directory, RecommendedModelPackDownloader.MODEL_FILE)
    }

    private fun llamaTokenizerFileOrNull(): File? = TOKENIZER_FILES
        .asSequence()
        .map { File(modelDirectory(), it) }
        .firstOrNull { it.isFile && it.length() > 0L }

    private fun llamaStatus(): ModelStatus {
        val model = llamaModelFile()
        val tokenizer = llamaTokenizerFileOrNull()
        return ModelStatus(
            ready = model.isFile && model.length() > 0L && tokenizer?.isFile == true,
            modelPath = model.absolutePath,
            tokenizerPath = tokenizer?.absolutePath,
            modelBytes = if (model.isFile) model.length() else 0L,
            modelId = LLAMA_MODEL_ID,
            modelName = LLAMA_MODEL_NAME,
            runtime = "executorch",
        )
    }

    private fun qwenStatus(): ModelStatus {
        val directory = File(modelDirectory(), QWEN_DIRECTORY)
        val model = File(directory, QWEN_MODEL_FILE)
        val tokenizer = File(directory, QWEN_TOKENIZER_FILE)
        return ModelStatus(
            ready = model.isFile && model.length() > 0L,
            modelPath = model.absolutePath,
            tokenizerPath = tokenizer.takeIf { it.isFile && it.length() > 0L }?.absolutePath,
            modelBytes = if (model.isFile) model.length() else 0L,
            modelId = QWEN_MODEL_ID,
            modelName = QWEN_MODEL_NAME,
            runtime = "llama.cpp",
        )
    }

    private fun requestedModelId(): String? {
        val selection = File(modelDirectory(), ACTIVE_MODEL_FILE)
        if (!selection.isFile) return null
        return selection.readText().trim().takeIf {
            it == LLAMA_MODEL_ID || it == QWEN_MODEL_ID
        }
    }
}
