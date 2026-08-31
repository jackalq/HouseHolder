package com.householder.app

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
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
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private const val OCR_CHANNEL = "householder/ocr"
        private const val SPEECH_CHANNEL = "householder/speech"
        private const val LLM_CHANNEL = "family_butler/llm"
        private const val SYNC_TREE_CHANNEL = "householder/sync_tree"
        private const val AUDIO_PERMISSION_REQUEST = 7101
        private const val MODEL_FILE_REQUEST = 7201
        private const val TOKENIZER_FILE_REQUEST = 7202
        private const val MODEL_DIRECTORY = RecommendedModelPackDownloader.MODEL_DIRECTORY
        private const val MODEL_FILE = RecommendedModelPackDownloader.MODEL_FILE
        private const val TOKENIZER_FILE = RecommendedModelPackDownloader.TOKENIZER_FILE
    }

    private var speechRecognizer: SpeechRecognizer? = null
    private var pendingSpeechResult: MethodChannel.Result? = null
    private var pendingOnDeviceOnly = false
    private var pendingFilePickResult: MethodChannel.Result? = null
    private val fileExecutor = Executors.newSingleThreadExecutor()
    private lateinit var llamaEngine: LocalLlamaEngine
    private lateinit var recommendedDownloader: RecommendedModelPackDownloader
    private lateinit var syncTree: SafSyncTree

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        llamaEngine = LocalLlamaEngine(this)
        recommendedDownloader = RecommendedModelPackDownloader(this)
        syncTree = SafSyncTree(this)

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
                    "availableModels" -> result.success(llamaEngine.models().map { it.toMap() })
                    "selectModel" -> {
                        val modelId = call.argument<String>("modelId").orEmpty()
                        try {
                            result.success(llamaEngine.selectModel(modelId).toMap())
                        } catch (error: Throwable) {
                            result.error(
                                "MODEL_SELECTION_FAILED",
                                error.message ?: error.javaClass.simpleName,
                                modelId,
                            )
                        }
                    }
                    "recommendedModelInfo" -> result.success(recommendedDownloader.info())
                    "recommendedDownloadStatus" -> result.success(recommendedDownloader.status())
                    "downloadRecommendedModelPack" -> downloadRecommendedModelPack(result)
                    "pickModelFile" -> startModelFilePicker(MODEL_FILE_REQUEST, result)
                    "pickTokenizerFile" -> startModelFilePicker(TOKENIZER_FILE_REQUEST, result)
                    "deleteModelPack" -> {
                        llamaEngine.close()
                        File(filesDir, MODEL_DIRECTORY).deleteRecursively()
                        llamaEngine = LocalLlamaEngine(this)
                        result.success(llamaEngine.status().toMap())
                    }
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYNC_TREE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(syncTree.status())
                    "pickTree" -> syncTree.pickTree(result)
                    "clearTree" -> result.success(syncTree.clear())
                    "list" -> {
                        val prefix = call.argument<String>("prefix").orEmpty()
                        runFileTask(result) { syncTree.list(prefix) }
                    }
                    "readText" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("INVALID_SYNC_PATH", "path is required", null)
                        } else {
                            runFileTask(result) { syncTree.readText(path) }
                        }
                    }
                    "writeText" -> {
                        val path = call.argument<String>("path")
                        val content = call.argument<String>("content")
                        if (path.isNullOrBlank() || content == null) {
                            result.error("INVALID_SYNC_WRITE", "path and content are required", null)
                        } else {
                            runFileTask(result) {
                                syncTree.writeText(path, content)
                                null
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun downloadRecommendedModelPack(result: MethodChannel.Result) {
        llamaEngine.close()
        fileExecutor.execute {
            try {
                recommendedDownloader.downloadAndInstall()
                runOnUiThread {
                    llamaEngine = LocalLlamaEngine(this)
                    result.success(llamaEngine.status().toMap())
                }
            } catch (error: Throwable) {
                runOnUiThread {
                    llamaEngine = LocalLlamaEngine(this)
                    result.error(
                        "MODEL_DOWNLOAD_FAILED",
                        error.message ?: error.javaClass.simpleName,
                        recommendedDownloader.status(),
                    )
                }
            }
        }
    }

    private fun runFileTask(result: MethodChannel.Result, block: () -> Any?) {
        fileExecutor.execute {
            try {
                val value = block()
                runOnUiThread { result.success(value) }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error(
                        "SYNC_IO_FAILED",
                        error.message ?: error.javaClass.simpleName,
                        null,
                    )
                }
            }
        }
    }

    private fun startModelFilePicker(requestCode: Int, result: MethodChannel.Result) {
        if (pendingFilePickResult != null) {
            result.error("FILE_PICK_BUSY", "Another model file picker is already open", null)
            return
        }
        pendingFilePickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        startActivityForResult(intent, requestCode)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (::syncTree.isInitialized && syncTree.handleActivityResult(requestCode, resultCode, data)) return
        if (requestCode == MODEL_FILE_REQUEST || requestCode == TOKENIZER_FILE_REQUEST) {
            val callback = pendingFilePickResult
            pendingFilePickResult = null
            if (callback == null) return
            if (resultCode != Activity.RESULT_OK) {
                callback.success(false)
                return
            }
            val uri = data?.data
            if (uri == null) {
                callback.error("FILE_PICK_FAILED", "No document URI returned", null)
                return
            }
            copyModelDocument(uri, requestCode, callback)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun copyModelDocument(uri: Uri, requestCode: Int, callback: MethodChannel.Result) {
        val metadata = documentMetadata(uri)
        if (requestCode == MODEL_FILE_REQUEST &&
            metadata.first != null &&
            !metadata.first!!.lowercase(Locale.ROOT).endsWith(".pte")
        ) {
            callback.error("INVALID_MODEL_FILE", "Please choose an ExecuTorch .pte model", metadata.first)
            return
        }

        val targetDirectory = File(filesDir, MODEL_DIRECTORY).apply { mkdirs() }
        val target = File(
            targetDirectory,
            if (requestCode == MODEL_FILE_REQUEST) MODEL_FILE else TOKENIZER_FILE,
        )
        val expectedBytes = metadata.second
        if (expectedBytes != null && expectedBytes > 0 && targetDirectory.usableSpace < expectedBytes) {
            callback.error("INSUFFICIENT_SPACE", "Not enough free space for selected model file", expectedBytes)
            return
        }

        fileExecutor.execute {
            try {
                contentResolver.openInputStream(uri).use { input ->
                    requireNotNull(input) { "Unable to open selected document" }
                    val temporary = File(target.absolutePath + ".tmp")
                    temporary.outputStream().buffered().use { output -> input.copyTo(output) }
                    if (target.exists()) target.delete()
                    if (!temporary.renameTo(target)) {
                        temporary.copyTo(target, overwrite = true)
                        temporary.delete()
                    }
                }
                runOnUiThread {
                    llamaEngine.close()
                    llamaEngine = LocalLlamaEngine(this)
                    callback.success(true)
                }
            } catch (error: Throwable) {
                runOnUiThread {
                    callback.error(
                        "MODEL_COPY_FAILED",
                        error.message ?: error.javaClass.simpleName,
                        null,
                    )
                }
            }
        }
    }

    private fun documentMetadata(uri: Uri): Pair<String?, Long?> {
        var name: String? = null
        var size: Long? = null
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (nameIndex >= 0) name = cursor.getString(nameIndex)
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) size = cursor.getLong(sizeIndex)
            }
        }
        return name to size
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
        val recognizer = TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
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
                result.success(mapOf("fullText" to text.text, "blocks" to blocks))
            }
            .addOnFailureListener { error -> result.error("OCR_FAILED", error.message, null) }
            .addOnCompleteListener { recognizer.close() }
    }

    private fun beginSpeechRecognition(onDeviceOnly: Boolean, result: MethodChannel.Result) {
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
        fileExecutor.shutdownNow()
        super.onDestroy()
    }
}
