#!/usr/bin/env bash
###############################################################################
# run.sh — Wrapper script to run the Whisper transcription worker
#
# What this script does:
# - Validates required input/output URIs
# - Downloads input audio (from S3 or local path)
# - Runs transcription via transcribe.py with configurable options
# - Uploads the resulting JSON transcript (to S3 or local path)
#
# Environment variables:
#   IN_URI          (required) Input audio file path (local or s3://)
#   OUT_URI         (required) Destination for output JSON (local or s3://)
#   MODEL           Whisper model size (default: large-v3)
#   LANGUAGE        Force language (optional, default: auto-detect)
#   BEAM_SIZE       Beam search width (default: 5)
#   COMPUTE_TYPE    CTranslate2 compute type (default: int8_float16)
#   VAD             Set to "1" to enable VAD filtering (optional)
#   INITIAL_PROMPT  Optional prompt to improve continuity
#   MAX_NEW_TOKENS  Max new tokens per segment (optional)
###############################################################################

set -euo pipefail

echo "[run] starting whisper worker"

# ── Validate required inputs ────────────────────────────────────────────────
: "${IN_URI:?set IN_URI}"     # Input audio must be set
: "${OUT_URI:?set OUT_URI}"   # Output destination must be set

# ── Defaults and optionals ──────────────────────────────────────────────────
MODEL="${MODEL:-large-v3}"
LANGUAGE="${LANGUAGE:-}"
BEAM_SIZE="${BEAM_SIZE:-5}"
COMPUTE_TYPE="${COMPUTE_TYPE:-int8_float16}"
VAD="${VAD:-}"
INITIAL_PROMPT="${INITIAL_PROMPT:-}"
MAX_NEW_TOKENS="${MAX_NEW_TOKENS:-}"

# ── Working directory & temp paths ──────────────────────────────────────────
mkdir -p /work
IN_LOCAL="/work/in.audio"
OUT_LOCAL="/work/out.json"

# ── Step 1: Fetch input audio ───────────────────────────────────────────────
if [[ "$IN_URI" == s3://* ]]; then
  echo "[run] downloading $IN_URI"
  python3 /app/s3io.py get "$IN_URI" "$IN_LOCAL"
else
  echo "[run] using local input $IN_URI"
  cp "$IN_URI" "$IN_LOCAL"
fi

# ── Step 2: Build transcription arguments ───────────────────────────────────
ARGS=(--audio "$IN_LOCAL" --out "$OUT_LOCAL" --model "$MODEL" --beam_size "$BEAM_SIZE" --compute_type "$COMPUTE_TYPE")
[[ -n "$LANGUAGE"       ]] && ARGS+=(--language "$LANGUAGE")
[[ -n "$INITIAL_PROMPT" ]] && ARGS+=(--initial_prompt "$INITIAL_PROMPT")
[[ -n "$MAX_NEW_TOKENS" ]] && ARGS+=(--max_new_tokens "$MAX_NEW_TOKENS")
[[ "$VAD" == "1"        ]] && ARGS+=(--vad_filter)

# ── Step 3: Run transcription ───────────────────────────────────────────────
echo "[run] transcribing... (${ARGS[*]})"
python3 /app/transcribe.py "${ARGS[@]}"

# ── Step 4: Deliver output transcript ───────────────────────────────────────
if [[ "$OUT_URI" == s3://* ]]; then
  echo "[run] uploading -> $OUT_URI"
  python3 /app/s3io.py put "$OUT_LOCAL" "$OUT_URI"
else
  echo "[run] writing local -> $OUT_URI"
  mkdir -p "$(dirname "$OUT_URI")"
  cp "$OUT_LOCAL" "$OUT_URI"
fi

# ── Done ────────────────────────────────────────────────────────────────────
echo "[run] done."
