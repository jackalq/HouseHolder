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

# UIAutomator is used while the app is idle to discover the real Flutter
# controls. Do not call it during native llama.cpp inference: Android test
# automation may try to suspend the CPU-bound native worker and abort the app
# if that suspension times out.
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

adb shell uiautomator dump /sdcard/typed.xml >/dev/null
adb pull /sdcard/typed.xml "$ARTIFACT_DIR/typed.xml" >/dev/null
python3 - "$ARTIFACT_DIR/typed.xml" > "$ARTIFACT_DIR/send-tap.txt" <<'PY'
import re
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
for node in root.iter('node'):
    if node.attrib.get('content-desc') == '送出':
        m = re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.attrib.get('bounds', ''))
        if not m:
            raise SystemExit('send button bounds missing')
        x1, y1, x2, y2 = map(int, m.groups())
        print((x1 + x2) // 2, (y1 + y2) // 2)
        break
else:
    raise SystemExit('household chat send button not found')
PY

SEND_X=$(cut -d' ' -f1 "$ARTIFACT_DIR/send-tap.txt")
SEND_Y=$(cut -d' ' -f2 "$ARTIFACT_DIR/send-tap.txt")
adb shell input tap "$SEND_X" "$SEND_Y"

# Wait using logcat only. The debug marker is emitted after the real local LLM
# result has been parsed, executed against the household repository, and added
# to the Flutter conversation state. This avoids touching accessibility while
# llama.cpp owns the CPU.
completed=0
attempt=1
while [ "$attempt" -le 180 ]; do
  sleep 2

  if ! adb shell pidof "$PACKAGE" >/dev/null 2>&1; then
    echo 'HouseHolder process died during local LLM inference.'
    break
  fi

  adb logcat -d -v brief > "$ARTIFACT_DIR/live-logcat.txt"
  if grep -q 'HOUSEHOLDER_CHAT_ERROR:' "$ARTIFACT_DIR/live-logcat.txt"; then
    echo 'Household conversation reported failure.'
    break
  fi
  if grep -q 'HOUSEHOLDER_CHAT_ASSISTANT:' "$ARTIFACT_DIR/live-logcat.txt"; then
    completed=1
    break
  fi
  attempt=$((attempt + 1))
done

# Only after the conversation completed do we inspect the Flutter hierarchy.
# This is the actual UI assertion required by the smoke test.
if [ "$completed" -eq 1 ]; then
  sleep 2
  adb shell uiautomator dump /sdcard/result.xml >/dev/null
  adb pull /sdcard/result.xml "$ARTIFACT_DIR/result.xml" >/dev/null
fi

adb logcat -d -v threadtime > "$ARTIFACT_DIR/logcat.txt"
adb exec-out screencap -p > "$ARTIFACT_DIR/result.png"
adb shell dumpsys meminfo "$PACKAGE" > "$ARTIFACT_DIR/meminfo.txt" 2>/dev/null || true
adb shell "run-as $PACKAGE ls -lh $MODEL_DIR" > "$ARTIFACT_DIR/model-files.txt" 2>/dev/null || true

if [ "$completed" -ne 1 ]; then
  echo 'Local household conversation did not complete.'
  exit 1
fi

success=0
if grep -q '查不到符合的課程' "$ARTIFACT_DIR/result.xml" 2>/dev/null || \
   grep -q '的課程：' "$ARTIFACT_DIR/result.xml" 2>/dev/null; then
  success=1
fi

if [ "$success" -ne 1 ]; then
  echo 'No grounded schedule answer appeared in the household chat UI.'
  exit 1
fi

if grep -Eq 'FATAL EXCEPTION|Fatal signal [0-9]+|SIGABRT|SIGSEGV|Process: com\.householder\.app.*FATAL' "$ARTIFACT_DIR/logcat.txt"; then
  echo 'Native or Java crash detected during household LLM smoke.'
  exit 1
fi

echo 'HouseHolder real household LLM schedule conversation smoke passed.'
