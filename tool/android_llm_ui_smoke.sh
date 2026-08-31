#!/bin/sh
set -eu

ARTIFACT_DIR="llm-ui-smoke-artifacts"
PACKAGE="com.householder.app"
ACTIVITY="$PACKAGE/.MainActivity"
MODEL_ID="qwen2.5-1.5b-instruct-q4_k_m"
MODEL_DIR="files/model-pack/$MODEL_ID"
MODEL_FILE="$MODEL_ID.gguf"

mkdir -p "$ARTIFACT_DIR"

adb install -r build/app/outputs/flutter-apk/app-debug.apk | tee "$ARTIFACT_DIR/adb-install.txt"
adb push smoke-model/qwen2.5-1.5b-instruct-q4_k_m.gguf /data/local/tmp/householder-smoke.gguf
adb shell "run-as $PACKAGE mkdir -p $MODEL_DIR"
adb shell "run-as $PACKAGE cp /data/local/tmp/householder-smoke.gguf $MODEL_DIR/$MODEL_FILE"
adb shell "run-as $PACKAGE sh -c 'printf %s $MODEL_ID > files/model-pack/active_model.txt'"
adb shell rm /data/local/tmp/householder-smoke.gguf

adb logcat -c
adb shell am force-stop "$PACKAGE"
adb shell am start -W -n "$ACTIVITY" | tee "$ARTIFACT_DIR/am-start.txt"
sleep 5

find_button() {
  adb shell uiautomator dump /sdcard/window.xml >/dev/null
  adb pull /sdcard/window.xml "$ARTIFACT_DIR/window.xml" >/dev/null
  grep -q 'content-desc="測試推理"' "$ARTIFACT_DIR/window.xml"
}

attempt=1
while [ "$attempt" -le 10 ]; do
  if find_button; then
    break
  fi
  adb shell input swipe 540 1750 540 600 450
  sleep 1
  attempt=$((attempt + 1))
done
find_button

python3 - "$ARTIFACT_DIR/window.xml" > "$ARTIFACT_DIR/tap.txt" <<'PY'
import re
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
for node in root.iter('node'):
    if node.attrib.get('content-desc') == '測試推理':
        m = re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.attrib.get('bounds', ''))
        if not m:
            raise SystemExit('button bounds missing')
        x1, y1, x2, y2 = map(int, m.groups())
        print((x1 + x2) // 2, (y1 + y2) // 2)
        break
else:
    raise SystemExit('test inference button not found')
PY

TAP_X=$(cut -d' ' -f1 "$ARTIFACT_DIR/tap.txt")
TAP_Y=$(cut -d' ' -f2 "$ARTIFACT_DIR/tap.txt")
adb shell input tap "$TAP_X" "$TAP_Y"

success=0
attempt=1
while [ "$attempt" -le 120 ]; do
  sleep 2
  adb shell uiautomator dump /sdcard/result.xml >/dev/null || true
  adb pull /sdcard/result.xml "$ARTIFACT_DIR/result.xml" >/dev/null || true
  if grep -q '推理失敗' "$ARTIFACT_DIR/result.xml" 2>/dev/null; then
    echo 'UI reported inference failure'
    break
  fi
  if grep -q '推理完成' "$ARTIFACT_DIR/result.xml" 2>/dev/null && \
     grep -q 'llama.cpp' "$ARTIFACT_DIR/result.xml" 2>/dev/null; then
    success=1
    break
  fi
  attempt=$((attempt + 1))
done

adb logcat -d -v threadtime > "$ARTIFACT_DIR/logcat.txt"
adb exec-out screencap -p > "$ARTIFACT_DIR/result.png"
adb shell dumpsys meminfo "$PACKAGE" > "$ARTIFACT_DIR/meminfo.txt"
adb shell "run-as $PACKAGE ls -lh $MODEL_DIR" > "$ARTIFACT_DIR/model-files.txt"

if [ "$success" -ne 1 ]; then
  echo 'No successful llama.cpp inference result appeared in the UI.'
  exit 1
fi

grep -q '推理完成' "$ARTIFACT_DIR/result.xml"
grep -q 'llama.cpp' "$ARTIFACT_DIR/result.xml"
if grep -q '推理失敗' "$ARTIFACT_DIR/result.xml"; then
  exit 1
fi
if grep -Eq 'FATAL EXCEPTION|Process: com\.householder\.app.*FATAL' "$ARTIFACT_DIR/logcat.txt"; then
  exit 1
fi

echo 'HouseHolder UI LLM inference smoke passed.'
