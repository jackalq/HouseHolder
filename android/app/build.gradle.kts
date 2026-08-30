plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val householderKeystorePath = System.getenv("HOUSEHOLDER_KEYSTORE_PATH")
val householderKeystorePassword = System.getenv("HOUSEHOLDER_KEYSTORE_PASSWORD")

android {
    namespace = "com.householder.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.householder.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val stableSigning = if (
        !householderKeystorePath.isNullOrBlank() &&
        !householderKeystorePassword.isNullOrBlank()
    ) {
        signingConfigs.create("householderStable") {
            storeFile = file(householderKeystorePath)
            storePassword = householderKeystorePassword
            keyAlias = "householder"
            keyPassword = householderKeystorePassword
        }
    } else {
        null
    }

    buildTypes {
        getByName("debug") {
            stableSigning?.let { signingConfig = it }
        }
        release {
            signingConfig = stableSigning ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Bundled OCR model: works without waiting for a Play Services download.
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")

    // Pin to ExecuTorch 1.3.x while validating the Android LLM Java API.
    implementation("org.pytorch:executorch-android:1.3.1")
}
