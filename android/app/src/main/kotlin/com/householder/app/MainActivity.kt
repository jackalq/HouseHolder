package com.householder.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.annotation.NonNull
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

class MainActivity : FlutterActivity() {
    companion object {
        private const val OCR_CHANNEL = "householder/ocr"
        private const val SPEECH_CHANNEL = "householder/speech"
        private const val LLM_CHANNEL = "family_butler/llm"
        private const val AUDIO_PERMISSION_REQUEST = 7101
    }

    private var speechRecognizer: SpeechRecognizer? = null
    private var pendingSpeechResult: MethodChannel.Result? = null
    private var pendingOnDeviceOnly = false
    private lateinit var llamaEngine: LocalLlamaEngine

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        llamaEngine = LocalLlamaEngine(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OCR_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "recognizeImage" -> {
                        val path = call.argument<String>("imagePath")
                        if (path.isNullOrBlank()) {
                            result.error("INVALID_IMAGE", "imagePath is required", null)
                        } else {
                            recognizeImage(path, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SPEECH_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isOnDeviceAvailable" -> {
                        val available = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                            SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
                        result.success(available)
                    }
                    "recognizeOnce" -> {
                        val onDeviceOnly = call.argument<Boolean>("onDeviceOnly") ?: false
                        beginSpeechRecognition(onDeviceOnly, result)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LLM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isModelReady" -> result.success(llamaEngine.status().ready)
                    "modelStatus" -> result.success(llamaEngine.status().toMap())
                    "stop" -> {
                        llamaEngine.stop()
                        result.success(null)
                    }
                    "generate" -> {
                        val prompt = call.argument<String>("prompt").orEmpty()
                        val maxTokens = call.argument<Number>("maxTokens")?.toInt() ?: 256
                        val temperature = call.argument<Number>("temperature")?.toFloat() ?: 0.2f
                        llamaEngine.generate(
                            prompt = prompt,
                            maxTokens = maxTokens,
                            temperature = temperature,
                            onSuccess = result::success,
                            onError = { code, message -> result.error(code, message, null) },
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun recognizeImage(imagePath: String, result: MethodChannel.Result) {
        val file = File(imagePath)
        if (!file.exists()) {
            result.error("IMAGE_NOT_FOUND", "Image does not exist", imagePath)
            return
        }

        val image = try {
            InputImage.fromFilePath(this, Uri.fromFile(file))
        } catch (error: Exception) {
            result.error("IMAGE_DECODE_FAILED", error.message, null)
            return
        }

        val recognizer = TextRecognition.getClient(
            ChineseTextRecognizerOptions.Builder().build()
        )

        recognizer.process(image)
            .addOnSuccessListener { text ->
                val blocks = text.textBlocks.map { block ->
                    val box = block.boundingBox
                    mapOf(
                        "text" to block.text,
                        "left" to box?.left?.toDouble(),
                        "top" to box?.top?.toDouble(),
                        "right" to box?.right?.toDouble(),
                        "bottom" to box?.bottom?.toDouble()
                    )
                }
                result.success(
                    mapOf(
                        "fullText" to text.text,
                        "blocks" to blocks
                    )
                )
            }
            .addOnFailureListener { error ->
                result.error("OCR_FAILED", error.message, null)
            }
            .addOnCompleteListener {
                recognizer.close()
            }
    }

    private fun beginSpeechRecognition(
        onDeviceOnly: Boolean,
        result: MethodChannel.Result
    ) {
        if (pendingSpeechResult != null) {
            result.error("SPEECH_BUSY", "Speech recognition is already running", null)
            return
        }

        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            result.error("SPEECH_UNAVAILABLE", "No speech recognition service is available", null)
            return
        }

        if (onDeviceOnly && (
                Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                    !SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
            )
        ) {
            result.error(
                "ON_DEVICE_UNAVAILABLE",
                "On-device speech recognition is not available on this device",
                null
            )
            return
        }

        pendingSpeechResult = result
        pendingOnDeviceOnly = onDeviceOnly

        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), AUDIO_PERMISSION_REQUEST)
            return
        }

        startRecognizer(onDeviceOnly)
    }

    private fun startRecognizer(onDeviceOnly: Boolean) {
        speechRecognizer?.destroy()
        speechRecognizer = if (onDeviceOnly && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
        } else {
            SpeechRecognizer.createSpeechRecognizer(this)
        }

        speechRecognizer?.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) = Unit
            override fun onBeginningOfSpeech() = Unit
            override fun onRmsChanged(rmsdB: Float) = Unit
            override fun onBufferReceived(buffer: ByteArray?) = Unit
            override fun onEndOfSpeech() = Unit
            override fun onPartialResults(partialResults: Bundle?) = Unit
            override fun onEvent(eventType: Int, params: Bundle?) = Unit

            override fun onError(error: Int) {
                finishSpeechError("SPEECH_ERROR_$error", "Speech recognition failed with code $error")
            }

            override fun onResults(results: Bundle?) {
                val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                val text = matches?.firstOrNull().orEmpty()
                val callback = pendingSpeechResult
                cleanupSpeech()
                callback?.success(mapOf("text" to text, "isFinal" to true))
            }
        })

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.TAIWAN.toLanguageTag())
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
        }
        speechRecognizer?.startListening(intent)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != AUDIO_PERMISSION_REQUEST) return

        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            startRecognizer(pendingOnDeviceOnly)
        } else {
            finishSpeechError("MIC_PERMISSION_DENIED", "Microphone permission was denied")
        }
    }

    private fun finishSpeechError(code: String, message: String) {
        val callback = pendingSpeechResult
        cleanupSpeech()
        callback?.error(code, message, null)
    }

    private fun cleanupSpeech() {
        speechRecognizer?.destroy()
        speechRecognizer = null
        pendingSpeechResult = null
        pendingOnDeviceOnly = false
    }

    override fun onDestroy() {
        cleanupSpeech()
        if (::llamaEngine.isInitialized) llamaEngine.close()
        super.onDestroy()
    }
}
