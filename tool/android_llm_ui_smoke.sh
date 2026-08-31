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

adb shell uiautomator dump /sdcard/window.xml >/dev/null
adb pull /sdcard/window.xml "$ARTIFACT_DIR/window.xml" >/dev/null

python3 - "$ARTIFACT_DIR/window.xml" > "$ARTIFACT_DIR/input-tap.txt" <<'PY'
import re
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
for node in root.iter('node'):
    cls = node.attrib.get('class', '')
    if cls.endswith('EditText'):
        m = re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.attrib.get('bounds', ''))
        if not m:
            continue
        x1, y1, x2, y2 = map(int, m.groups())
        print((x1 + x2) // 2, (y1 + y2) // 2)
        break
else:
    raise SystemExit('household chat input not found')
PY

TAP_X=$(cut -d' ' -f1 "$ARTIFACT_DIR/input-tap.txt")
TAP_Y=$(cut -d' ' -f2 "$ARTIFACT_DIR/input-tap.txt")
adb shell input tap "$TAP_X" "$TAP_Y"
adb shell input text 'What%sis%smy%sschedule%stomorrow?'
adb shell input keyevent 66

success=0
attempt=1
while [ "$attempt" -le 150 ]; do
  sleep 2
  adb shell uiautomator dump /sdcard/result.xml >/dev/null || true
  adb pull /sdcard/result.xml "$ARTIFACT_DIR/result.xml" >/dev/null || true
  if grep -q '這次沒有處理成功' "$ARTIFACT_DIR/result.xml" 2>/dev/null || \
     grep -q '處理失敗' "$ARTIFACT_DIR/result.xml" 2>/dev/null; then
    echo 'Household conversation reported failure.'
    break
  fi
  if grep -q '查不到符合的課程' "$ARTIFACT_DIR/result.xml" 2>/dev/null || \
     grep -q '的課程：' "$ARTIFACT_DIR/result.xml" 2>/dev/null; then
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
  echo 'No grounded schedule answer appeared in the household chat UI.'
  exit 1
fi

if grep -Eq 'FATAL EXCEPTION|Process: com\.householder\.app.*FATAL' "$ARTIFACT_DIR/logcat.txt"; then
  exit 1
fi

echo 'HouseHolder real household LLM schedule conversation smoke passed.'
