plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val householderKeystorePath = System.getenv("HOUSEHOLDER_KEYSTORE_PATH")
val householderKeystorePassword = System.getenv("HOUSEHOLDER_KEYSTORE_PASSWORD")
val householderCiGenericX86 = System.getenv("HOUSEHOLDER_CI_GENERIC_X86") == "1"

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
        // llama.android v0.0.4 requires API 30. This still covers modern Android
        // devices while keeping the GGUF runtime in-process and fully offline.
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        externalNativeBuild {
            cmake {
                cppFlags += listOf("-std=c++17", "-fexceptions", "-frtti")
            }
        }
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

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            if (householderCiGenericX86) {
                excludes += setOf(
                    "**/libggml-cpu-sse42.so",
                    "**/libggml-cpu-sandybridge.so",
                    "**/libggml-cpu-ivybridge.so",
                    "**/libggml-cpu-haswell.so",
                    "**/libggml-cpu-skylakex.so",
                    "**/libggml-cpu-icelake.so",
                    "**/libggml-cpu-alderlake.so",
                )
            }
        }
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
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
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
    implementation("org.pytorch:executorch-android:1.3.1")
    implementation("com.github.1opp0-org:llama.android:v0.0.4")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
}
