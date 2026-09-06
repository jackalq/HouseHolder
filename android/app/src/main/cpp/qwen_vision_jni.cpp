#include <jni.h>
#include <string>

#include "llama.h"
#include "mtmd.h"

namespace {

jstring native_runtime_version(JNIEnv * env, jobject) {
    const char * marker = mtmd_default_marker();
    std::string value = "llama.cpp/mtmd";
    if (marker != nullptr && marker[0] != '\0') {
        value += ":";
        value += marker;
    }
    return env->NewStringUTF(value.c_str());
}

jstring analyze_image(
    JNIEnv * env,
    jobject,
    jstring,
    jstring,
    jstring,
    jstring,
    jint,
    jfloat
) {
    jclass ex = env->FindClass("java/lang/UnsupportedOperationException");
    env->ThrowNew(ex, "Qwen3-VL native library is linked; inference pipeline is not enabled until the mtmd decode path passes native smoke validation");
    return nullptr;
}

static const JNINativeMethod METHODS[] = {
    {const_cast<char *>("runtimeVersion"), const_cast<char *>("()Ljava/lang/String;"), reinterpret_cast<void *>(native_runtime_version)},
    {const_cast<char *>("analyzeImage"), const_cast<char *>("(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;IF)Ljava/lang/String;"), reinterpret_cast<void *>(analyze_image)},
};

} // namespace

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM * vm, void *) {
    JNIEnv * env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6) != JNI_OK) return JNI_ERR;
    jclass clazz = env->FindClass("com/householder/app/QwenVisionNative");
    if (clazz == nullptr) return JNI_ERR;
    if (env->RegisterNatives(clazz, METHODS, sizeof(METHODS) / sizeof(METHODS[0])) != JNI_OK) return JNI_ERR;
    return JNI_VERSION_1_6;
}
