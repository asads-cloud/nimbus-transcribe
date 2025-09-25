"""
transcribe.py — Single-file CLI to transcribe one audio file with faster-whisper.

Goals:
- Keep the logic simple and explicit.
- Be transparent about device/model choices and timings.
- Produce a stable, JSON-structured transcript you can parse downstream.

Usage (examples):
  python transcribe.py --audio sample.m4a --out out/transcript.json
  python transcribe.py --audio call.mp3 --out t.json --model large-v3 --language en --beam_size 5 --vad_filter

Environment knobs:
  WHISPER_DEVICE : 'cuda' | 'cpu' | 'auto' (fallback auto-detect if unset/invalid)
  WHISPER_CACHE  : where faster-whisper stores/downloads models (defaults to /root/.cache/whisper)
"""

# ── Stdlib deps ─────────────────────────────────────────────────────────────────
import argparse
import json
import os
import sys
import time
from datetime import datetime, timezone

# ── Speech-to-text deps ────────────────────────────────────────────────────────
from faster_whisper import WhisperModel
import ctranslate2


# ───────────────────────────────────────────────────────────────────────────────
# Device picking logic
# Prefer an explicit env override; otherwise pick CUDA if available, else CPU.
# Returns one of: 'cuda', 'cpu', or 'auto' (passed through if explicitly set).
# ───────────────────────────────────────────────────────────────────────────────
def pick_device():
    env = os.getenv("WHISPER_DEVICE")
    if env in {"cuda", "cpu", "auto"}:
        return env
    # If not explicitly set or invalid, detect CUDA presence via CTranslate2.
    return "cuda" if ctranslate2.get_cuda_device_count() > 0 else "cpu"


# ───────────────────────────────────────────────────────────────────────────────
# Main CLI entrypoint
# Parses flags, loads the model, runs transcription, and writes a JSON report.
# The JSON format is stable-ish and designed for downstream tooling.
# ───────────────────────────────────────────────────────────────────────────────
def main():
    # ---- CLI args -------------------------------------------------------------
    parser = argparse.ArgumentParser(description="Transcribe one audio file with faster-whisper.")
    parser.add_argument("--audio", required=True, help="Path to local audio file (wav/mp3/m4a/ogg/flac).")
    parser.add_argument("--out", required=True, help="Path to output JSON transcript.")
    parser.add_argument("--model", default="large-v3", help="Whisper model size (default: large-v3).")
    parser.add_argument("--language", default=None, help="Force language code (e.g., en). If unset, auto-detect.")
    parser.add_argument("--beam_size", type=int, default=5)
    parser.add_argument("--vad_filter", action="store_true", help="Enable VAD filtering.")
    parser.add_argument("--temperature", type=float, default=0.0)
    parser.add_argument("--compute_type", default="int8_float16", help="CTranslate2 compute type.")
    parser.add_argument("--max_new_tokens", type=int, default=None)
    parser.add_argument("--initial_prompt", default=None, help="Optional prepend prompt for chunk continuity.")
    args = parser.parse_args()

    audio_path = args.audio
    out_path   = args.out

    # ---- Input validation -----------------------------------------------------
    if not os.path.exists(audio_path):
        # Keep error path explicit and non-throwing; exit code 2 is a common CLI convention for misuse.
        print(f"[error] audio not found: {audio_path}", file=sys.stderr)
        sys.exit(2)

    # ---- Device + model selection summary ------------------------------------
    device = pick_device()
    print(f"[info] device={device} model={args.model} compute_type={args.compute_type}", flush=True)

    # ---- Model init (timed) ---------------------------------------------------
    t0 = time.time()
    # Note: download_root controls where CTranslate2 model files are stored.
    # Using an env var lets us redirect cache for containers/CI.
    model = WhisperModel(
        args.model,
        device=device,
        compute_type=args.compute_type,
        download_root=os.getenv("WHISPER_CACHE", "/root/.cache/whisper")
    )

    # ---- Transcription (streaming generator) ---------------------------------
    # segments: iterable of segment objects with .start/.end/.text etc.
    # info: run metadata (duration, detected language/probability).
    segments, info = model.transcribe(
        audio_path,
        language=args.language,       # None = auto language detection
        beam_size=args.beam_size,     # Search width; higher is slower but can improve quality
        vad_filter=args.vad_filter,   # Optional voice-activity detection to trim silences/noise
        temperature=args.temperature, # Sampling temperature; 0.0 = greedy
        initial_prompt=args.initial_prompt, # Helpful for multi-part continuity (proper nouns, context)
        max_new_tokens=args.max_new_tokens  # Upper bound for generated tokens per segment/chunk
    )
    load_and_cfg_s = time.time() - t0  # Time to init model + parse flags before first token

    # ---- Normalize segments into JSON-friendly dicts --------------------------
    seg_list = []
    for i, seg in enumerate(segments):
        # getattr() guards keep the JSON schema stable across faster-whisper versions.
        seg_list.append({
            "id": i,
            "start": seg.start,
            "end": seg.end,
            "text": seg.text,
            "avg_logprob": getattr(seg, "avg_logprob", None),
            "no_speech_prob": getattr(seg, "no_speech_prob", None),
            "temperature": args.temperature,
        })

    # ---- Build output payload -------------------------------------------------
    out = {
        "version": "1.0",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "input": {
            "audio_path": audio_path,
            "language": args.language,
            "initial_prompt": args.initial_prompt
        },
        "engine": {
            "impl": "faster-whisper",
            "model": args.model,
            "device": device,
            "ctranslate2_compute_type": args.compute_type,
            "beam_size": args.beam_size,
            "vad_filter": args.vad_filter,
        },
        "detected": {
            # If language is forced, these may still be present from the model metadata.
            "language": getattr(info, "language", None),
            "language_probability": getattr(info, "language_probability", None),
            "duration": getattr(info, "duration", None),
        },
        "timing": {
            "total_s": time.time() - t0,
            "init_and_config_s": load_and_cfg_s
        },
        "segments": seg_list,
    }

    # ---- Write JSON (pretty-printed, UTF-8) ----------------------------------
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)

    # ---- Console summary ------------------------------------------------------
    # "Realtime factor" ~ how many times faster than audio duration we ran.
    # x1.0 means real-time; x2.0 means 2x faster-than-real-time; etc.
    rt_factor = (out["detected"]["duration"] or 0) / max(out["timing"]["total_s"], 1e-6)
    print(
        f"[done] wrote {out_path} | "
        f"duration={out['detected']['duration']}s | "
        f"wall={out['timing']['total_s']:.2f}s | "
        f"x{rt_factor:.2f} realtime"
    )


# ───────────────────────────────────────────────────────────────────────────────
# Standard Python entrypoint guard so the file can be imported without side-effects.
# ───────────────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    main()
