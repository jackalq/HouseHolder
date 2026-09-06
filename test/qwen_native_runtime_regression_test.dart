import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android build wires the Qwen3-VL mtmd JNI library', () {
    final cmake = File('android/app/src/main/cpp/CMakeLists.txt').readAsStringSync();
    final native = File('android/app/src/main/cpp/qwen_vision_jni.cpp').readAsStringSync();
    final kotlin = File('android/app/src/main/kotlin/com/householder/app/QwenVisionEngine.kt').readAsStringSync();

    expect(cmake, contains('LLAMA_BUILD_MTMD ON'));
    expect(cmake, contains('add_library(householder_qwen_vl SHARED'));
    expect(cmake, contains('target_link_libraries(householder_qwen_vl PRIVATE llama mtmd'));
    expect(native, contains('JNI_OnLoad'));
    expect(native, contains('RegisterNatives'));
    expect(native, contains('mtmd_default_marker'));
    expect(kotlin, contains('System.loadLibrary("householder_qwen_vl")'));
    expect(kotlin, contains('runtimeVersionOrNull'));
  });
}
