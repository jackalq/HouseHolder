#!/usr/bin/env bash
set -euo pipefail

ARTIFACT_DIR="llm-e2e-artifacts"
PACKAGE="com.householder.app"
REMOTE_DIR="/sdcard/Android/data/${PACKAGE}/files"
APK="build/app/outputs/flutter-apk/app-debug.apk"

mkdir -p "$ARTIFACT_DIR"
adb install -r "$APK" | tee "$ARTIFACT_DIR/adb-install.txt"
adb logcat -c
adb shell am start -W -n "$PACKAGE/.LlmE2eActivity" | tee "$ARTIFACT_DIR/am-start.txt"

deadline=$((SECONDS + 2100))
while (( SECONDS < deadline )); do
  if adb shell test -f "$REMOTE_DIR/llm-e2e-status.txt"; then
    adb pull "$REMOTE_DIR/llm-e2e-status.txt" "$ARTIFACT_DIR/llm-e2e-status.txt" >/dev/null
    stage="$(head -n 1 "$ARTIFACT_DIR/llm-e2e-status.txt" | tr -d '\r')"
    echo "LLM E2E stage: $stage"
    if [[ "$stage" == "SUCCESS" ]]; then
      break
    fi
    if [[ "$stage" == "FAILED" ]]; then
      adb pull "$REMOTE_DIR/llm-e2e-output.txt" "$ARTIFACT_DIR/llm-e2e-output.txt" || true
      adb logcat -d -v threadtime > "$ARTIFACT_DIR/logcat.txt"
      cat "$ARTIFACT_DIR/llm-e2e-status.txt"
      exit 1
    fi
  fi
  sleep 15
done

adb pull "$REMOTE_DIR/llm-e2e-status.txt" "$ARTIFACT_DIR/llm-e2e-status.txt"
grep -q '^SUCCESS' "$ARTIFACT_DIR/llm-e2e-status.txt"
adb pull "$REMOTE_DIR/llm-e2e-output.txt" "$ARTIFACT_DIR/llm-e2e-output.txt"
adb logcat -d -v threadtime > "$ARTIFACT_DIR/logcat.txt"
adb exec-out screencap -p > "$ARTIFACT_DIR/llm-e2e-screen.png" || true

grep -q 'HOUSEHOLDER_OK' "$ARTIFACT_DIR/llm-e2e-output.txt"
if grep -Eq 'FATAL EXCEPTION|Process: com\.householder\.app.*FATAL' "$ARTIFACT_DIR/logcat.txt"; then
  echo 'HouseHolder crashed during LLM E2E smoke test.'
  exit 1
fi

cat "$ARTIFACT_DIR/llm-e2e-output.txt"
