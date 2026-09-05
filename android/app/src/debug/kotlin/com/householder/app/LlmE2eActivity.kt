package com.householder.app

import android.app.Activity
import android.os.Bundle
import android.view.WindowManager
import android.widget.TextView
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Debug-only E2E harness. It deliberately exercises the same downloader and
 * LocalLlamaEngine used by the app, without depending on Android instrumentation.
 */
class LlmE2eActivity : Activity() {
    private lateinit var statusView: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        statusView = TextView(this).apply {
            textSize = 18f
            setPadding(32, 64, 32, 32)
            text = "HouseHolder LLM E2E starting…"
        }
        setContentView(statusView)
        writeStatus("STARTING")

        Thread({ runE2e() }, "householder-llm-e2e").start()
    }

    private fun runE2e() {
        var engine: LocalLlamaEngine? = null
        try {
            val modelDirectory = File(
                filesDir,
                RecommendedModelPackDownloader.MODEL_DIRECTORY,
            )
            modelDirectory.deleteRecursively()
            update("DOWNLOADING", "Downloading and verifying recommended model pack…")

            val install = RecommendedModelPackDownloader(this).downloadAndInstall()
            require(install["installed"] == true) { "Recommended model pack was not installed" }

            engine = LocalLlamaEngine(this)
            val modelStatus = engine.status()
            require(modelStatus.ready) { "Downloaded model pack is not ready" }
            require(modelStatus.modelBytes > 0L) { "Downloaded model file is empty" }
            require(!modelStatus.tokenizerPath.isNullOrBlank()) { "Tokenizer is missing" }
            update("MODEL_READY", "Model verified. Loading ExecuTorch and generating…")

            val latch = CountDownLatch(1)
            var response = ""
            var generationError: String? = null

            val prompt = """
                <|begin_of_text|><|start_header_id|>system<|end_header_id|>

                You are a deterministic smoke-test assistant.<|eot_id|><|start_header_id|>user<|end_header_id|>

                Reply with exactly HOUSEHOLDER_OK and nothing else.<|eot_id|><|start_header_id|>assistant<|end_header_id|>

            """.trimIndent()

            engine.generate(
                prompt = prompt,
                maxTokens = 16,
                temperature = 0.0f,
                onSuccess = {
                    response = it.trim()
                    latch.countDown()
                },
                onError = { code, message ->
                    generationError = "$code: $message"
                    latch.countDown()
                },
            )

            require(latch.await(15, TimeUnit.MINUTES)) { "LLM generation timed out" }
            generationError?.let { error(it) }
            require(response == "HOUSEHOLDER_OK") {
                "Expected exact HOUSEHOLDER_OK, got: $response"
            }

            evidenceFile("llm-e2e-output.txt").writeText(
                buildString {
                    appendLine("model=${modelStatus.modelPath}")
                    appendLine("modelBytes=${modelStatus.modelBytes}")
                    appendLine("tokenizer=${modelStatus.tokenizerPath}")
                    appendLine("response=$response")
                }
            )
            update("SUCCESS", "HOUSEHOLDER_OK")
        } catch (error: Throwable) {
            val detail = buildString {
                append(error.javaClass.name)
                append(": ")
                append(error.message ?: "unknown error")
                error.stackTrace.take(30).forEach { append("\n  at $it") }
            }
            evidenceFile("llm-e2e-output.txt").writeText("error=$detail\n")
            update("FAILED", detail)
        } finally {
            engine?.close()
        }
    }

    private fun update(stage: String, detail: String) {
        writeStatus("$stage\n$detail")
        runOnUiThread { statusView.text = "$stage\n\n$detail" }
    }

    private fun writeStatus(value: String) {
        evidenceFile("llm-e2e-status.txt").writeText(value)
    }

    private fun evidenceFile(name: String): File {
        val directory = requireNotNull(getExternalFilesDir(null))
        directory.mkdirs()
        return File(directory, name)
    }
}
