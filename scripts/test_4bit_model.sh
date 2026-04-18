#!/usr/bin/env bash
set -euo pipefail

# Sample script to verify 4-bit model functionality in this package.
# It runs focused integration tests and optional CLI generation smoke checks.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

RUN_CLI_SMOKE=1
TEXT="4 bit model smoke test"

usage() {
  cat <<'USAGE'
Usage: scripts/test_4bit_model.sh [options]

Options:
  --tests-only         Run only integration tests (skip CLI generation smoke checks)
  --text "..."         Text used for CLI smoke generation
  -h, --help           Show this help message

Notes:
  - This script enables F5TTS_RUN_INTEGRATION=1.
  - First run may download model files from Hugging Face.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tests-only)
      RUN_CLI_SMOKE=0
      shift
      ;;
    --text)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --text"
        exit 1
      fi
      TEXT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

echo "[1/3] Running 4-bit integration test (Swift-side quantization path)..."
F5TTS_RUN_INTEGRATION=1 swift test --filter F5TTSIntegrationTests/testFromPretrainedConfigFullPrecisionAndSwift4BitPaths

echo "[2/3] Running 4-bit integration test (dedicated 4-bit repo path)..."
F5TTS_RUN_INTEGRATION=1 swift test --filter F5TTSIntegrationTests/testFromPretrainedConfigDedicated4BitRepoPath

if [[ "$RUN_CLI_SMOKE" -eq 1 ]]; then
  CLI_OUT_DIR="$ROOT_DIR/.build/f5tts-4bit-smoke"
  mkdir -p "$CLI_OUT_DIR"

  echo "[3/3] Running CLI smoke checks for both 4-bit load paths..."

  echo " - Swift-side quantization (--q 4)"
  swift run f5-tts-generate \
    --text "$TEXT" \
    --q 4 \
    --steps 2 \
    --method euler \
    --cfg 1.0 \
    --sway 0.0 \
    --outputPath "$CLI_OUT_DIR/swift_quantized_4bit.wav"

  echo " - Dedicated 4-bit repo (--model alandao/f5-tts-mlx-4bit)"
  swift run f5-tts-generate \
    --text "$TEXT" \
    --model alandao/f5-tts-mlx-4bit \
    --steps 2 \
    --method euler \
    --cfg 1.0 \
    --sway 0.0 \
    --outputPath "$CLI_OUT_DIR/repo_4bit.wav"

  echo "Smoke outputs written to: $CLI_OUT_DIR"
else
  echo "Skipped CLI smoke checks (--tests-only)."
fi

echo "4-bit verification script completed successfully."
