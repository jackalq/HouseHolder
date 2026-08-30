package com.householder.app

import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LlmE2eSmokeTest {
    @Test
    fun downloadsInstallsAndGeneratesOneReply() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val modelDirectory = File(
            context.filesDir,
            RecommendedModelPackDownloader.MODEL_DIRECTORY,
        )
        modelDirectory.deleteRecursively()

        val downloader = RecommendedModelPackDownloader(context)
        val installResult = downloader.downloadAndInstall()
        assertTrue(installResult["installed"] == true)

        val engine = LocalLlamaEngine(context)
        val status = engine.status()
        assertTrue("Downloaded model pack should be ready", status.ready)
        assertTrue("Model file should be non-empty", status.modelBytes > 0L)
        assertTrue("Tokenizer should exist", !status.tokenizerPath.isNullOrBlank())

        val latch = CountDownLatch(1)
        var output = ""
        var error: String? = null

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
                output = it.trim()
                latch.countDown()
            },
            onError = { code, message ->
                error = "$code: $message"
                latch.countDown()
            },
        )

        val completed = latch.await(12, TimeUnit.MINUTES)
        try {
            assertTrue("LLM generation timed out", completed)
            if (error != null) fail("LLM generation failed: $error")
            assertTrue("LLM returned an empty response", output.isNotBlank())
            assertTrue(
                "Expected HOUSEHOLDER_OK in LLM response, got: $output",
                output.contains("HOUSEHOLDER_OK", ignoreCase = false),
            )

            val artifact = File(context.getExternalFilesDir(null), "llm-e2e-output.txt")
            artifact.writeText(
                buildString {
                    appendLine("model=${status.modelPath}")
                    appendLine("modelBytes=${status.modelBytes}")
                    appendLine("tokenizer=${status.tokenizerPath}")
                    appendLine("response=$output")
                }
            )
            Log.i("HouseHolderLlmE2E", "response=$output")
        } finally {
            engine.close()
        }
    }
}
