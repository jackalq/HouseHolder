#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
  cat <<'USAGE'
Usage:
  bash scripts/export_llama32_3b_android.sh \
    /path/to/executorch \
    /path/to/consolidated.00.pth \
    /path/to/params.json \
    /path/to/tokenizer.model \
    /path/to/output-directory

The output directory will contain:
  llama32-3b-instruct.pte
  tokenizer.model
  householder-export.yaml
USAGE
  exit 2
fi

EXECUTORCH_DIR="$(cd "$1" && pwd)"
CHECKPOINT="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
PARAMS="$(cd "$(dirname "$3")" && pwd)/$(basename "$3")"
TOKENIZER="$(cd "$(dirname "$4")" && pwd)/$(basename "$4")"
OUTPUT_DIR="$5"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
CONFIG="$OUTPUT_DIR/householder-export.yaml"

for file in "$CHECKPOINT" "$PARAMS" "$TOKENIZER"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing required file: $file" >&2
    exit 3
  fi
done

python3 - "$CHECKPOINT" "$PARAMS" "$TOKENIZER" "$OUTPUT_DIR" "$CONFIG" <<'PY'
import json
import sys
from pathlib import Path

checkpoint, params, tokenizer, output_dir, config_path = sys.argv[1:]
metadata = json.dumps('{"get_bos_id":128000,"get_eos_ids":[128009,128001]}')
q = json.dumps
content = f'''base:
  model_class: llama3_2
  checkpoint: {q(checkpoint)}
  params: {q(params)}
  tokenizer_path: {q(tokenizer)}
  metadata: {metadata}

model:
  use_kv_cache: true
  use_sdpa_with_kv_cache: true
  dtype_override: fp32

export:
  max_seq_length: 1024
  max_context_length: 1024
  output_dir: {q(output_dir)}
  output_name: llama32-3b-instruct.pte

quantization:
  qmode: 8da4w
  group_size: 128
  embedding_quantize: 4,32

backend:
  xnnpack:
    enabled: true
    extended_ops: true
'''
Path(config_path).write_text(content, encoding='utf-8')
PY

cd "$EXECUTORCH_DIR"

if ! python3 -c 'import executorch' >/dev/null 2>&1; then
  echo "ExecuTorch Python package is not available in this environment." >&2
  echo "Activate the ExecuTorch environment/setup before running this script." >&2
  exit 4
fi

if ! python3 -c 'import pytorch_tokenizers' >/dev/null 2>&1; then
  echo "pytorch_tokenizers is missing." >&2
  echo "From the ExecuTorch checkout run: pip install -e ./extension/llm/tokenizers/" >&2
  exit 5
fi

python3 -m extension.llm.export.export_llm --config "$CONFIG"

if [[ ! -f "$OUTPUT_DIR/llama32-3b-instruct.pte" ]]; then
  echo "Export finished but expected .pte was not found in $OUTPUT_DIR" >&2
  exit 6
fi

cp "$TOKENIZER" "$OUTPUT_DIR/tokenizer.model"

echo "HouseHolder model pack created:"
echo "  $OUTPUT_DIR/llama32-3b-instruct.pte"
echo "  $OUTPUT_DIR/tokenizer.model"
