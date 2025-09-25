#!/usr/bin/env python3
"""
handler.py — AWS Lambda handler that prepares long audio for downstream transcription.

What it does:
- Triggered by an S3 Put event for an input audio object.
- Detects audio duration with ffprobe.
- Splits the audio into overlapping chunks with ffmpeg (default: 10-min chunks, 1s overlap).
- Uploads each chunk back to S3 under a predictable prefix.
- Writes a JSONL manifest describing all chunks (URIs + time windows).
- Returns a small summary payload (job_id, manifest URI, chunk list, etc).

Environment variables (with sane defaults):
  INGEST_BUCKET        : S3 bucket receiving the chunks + manifest (default: "whisper-xcribe-ingest")
  CHUNK_PREFIX_BASE    : Prefix for chunk objects (default: "chunks")
  MANIFEST_PREFIX_BASE : Prefix for manifest objects (default: "manifests")
  CHUNK_LEN_SEC        : Chunk length in seconds (default: 600)
  OVERLAP_SEC          : Overlap between consecutive chunks in seconds (default: 1)
  CHUNK_EXT            : Output audio extension: "wav" or "mp3" (default: "wav")
  FFMPEG_PATH          : Optional absolute/path or binary name override
  FFPROBE_PATH         : Optional absolute/path or binary name override
  LOG_LEVEL            : Python logging level (default: INFO)

Notes:
- ffmpeg/ffprobe are discovered from a small list of candidates; you can also supply
  explicit paths via FFMPEG_PATH/FFPROBE_PATH or a Lambda layer.
- Overlap helps the ASR handle words at boundaries without truncation.
"""

# ── Standard library imports ──────────────────────────────────────────────────
import os
import json
import math
import uuid
import shutil
import logging
import tempfile
import pathlib
import argparse
import subprocess
from typing import List, Dict, Tuple

# ── External deps ─────────────────────────────────────────────────────────────
import boto3

# ── Logging setup ─────────────────────────────────────────────────────────────
log = logging.getLogger(__name__)
logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"))

# ── Config (envs with sensible defaults) ─────────────────────────────────────
INGEST_BUCKET = os.environ.get("INGEST_BUCKET", "whisper-xcribe-ingest")
CHUNK_PREFIX_BASE = os.environ.get("CHUNK_PREFIX_BASE", "chunks")
MANIFEST_PREFIX_BASE = os.environ.get("MANIFEST_PREFIX_BASE", "manifests")

CHUNK_LEN_SEC = int(os.environ.get("CHUNK_LEN_SEC", "600"))      # 10 minutes
OVERLAP_SEC = int(os.environ.get("OVERLAP_SEC", "1"))            # 1 second
CHUNK_EXT = os.environ.get("CHUNK_EXT", "wav")                   # "wav" or "mp3"

FFMPEG_CANDIDATES = [
    os.environ.get("FFMPEG_PATH"),
    "/opt/bin/ffmpeg", "/opt/ffmpeg/ffmpeg", "ffmpeg", "ffmpeg.exe"
]
FFPROBE_CANDIDATES = [
    os.environ.get("FFPROBE_PATH"),
    "/opt/bin/ffprobe", "/opt/ffmpeg/ffprobe", "ffprobe", "ffprobe.exe"
]

# Single S3 client reused across handler invocations (when container is warm)
s3 = boto3.client("s3")


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────
def which_first(candidates: List[str]) -> str:
    """
    Return the first existing executable path from a list of candidate names/paths.
    Accepts either absolute paths or bare binary names (resolved via PATH).
    Raises FileNotFoundError if none are found.
    """
    for c in candidates:
        if not c:
            continue
        # If candidate looks like a bare name, use shutil.which; otherwise check path exists.
        p = shutil.which(c) if os.path.basename(c) == c else (c if os.path.exists(c) else None)
        if p:
            return p
    raise FileNotFoundError(
        "ffmpeg/ffprobe not found. Provide FFMPEG_PATH/FFPROBE_PATH envs or use a Lambda layer."
    )


def infer_job_id_from_key(key: str) -> str:
    """
    Infer a stable job identifier from an S3 key.

    Preference order:
      1) If the path contains '/audio/<job-id>/', use that segment as the job id.
      2) Else, use the first path segment if present.
      3) Else, derive a stable UUIDv5 from the full S3 URL (bucket + key).
    """
    parts = key.split("/")
    if "audio" in parts:
        idx = parts.index("audio")
        if idx + 1 < len(parts):
            return parts[idx + 1]
    if len(parts) > 1 and parts[0]:
        return parts[0]
    # deterministic UUID from key
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"s3://{INGEST_BUCKET}/{key}"))


def s3_uri(bucket: str, key: str) -> str:
    """Join bucket + key into an s3:// URI string."""
    return f"s3://{bucket}/{key}"


def ffprobe_duration(ffprobe_bin: str, input_path: str) -> float:
    """
    Use ffprobe to read the container/stream duration in seconds (float).
    Returns non-negative duration (clamped to 0.0).
    """
    cmd = [
        ffprobe_bin, "-v", "error", "-print_format", "json",
        "-show_entries", "format=duration", input_path
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    data = json.loads(result.stdout)
    dur = float(data["format"]["duration"])
    return max(0.0, dur)


def compute_chunks(
    duration: float,
    chunk_sec: int = CHUNK_LEN_SEC,
    overlap_sec: int = OVERLAP_SEC
) -> List[Tuple[int, float, float]]:
    """
    Compute [start, end) windows for chunking with an overlap between windows.

    N = ceil(duration / chunk_sec)
    For i in 0..N-1:
      start = max(0, i*chunk_sec - overlap_sec)   # 1s overlap (except first)
      end   = min(duration, (i+1)*chunk_sec)

    Example (duration=1800, chunk_sec=600, overlap=1):
      -> [0,600], [599,1200], [1199,1800]
    """
    if duration <= 0:
        return []
    n = math.ceil(duration / chunk_sec)
    windows = []
    for i in range(n):
        start = max(0.0, i * chunk_sec - (overlap_sec if i > 0 else 0))
        end = min(duration, (i + 1) * chunk_sec)
        if end <= start:
            continue
        windows.append((i, round(start, 3), round(end, 3)))
    return windows


def ffmpeg_cut(
    ffmpeg_bin: str,
    input_path: str,
    start: float,
    end: float,
    out_path: str,
    ext: str
):
    """
    Cut a time window from input_path into out_path, re-encoding to mono 16kHz.

    ext:
      - "wav" -> pcm_s16le @ 16kHz mono
      - "mp3" -> libmp3lame @ 16kHz mono, ~128kbps
    """
    duration = max(0.0, end - start)
    if duration <= 0:
        raise ValueError("Non-positive cut duration")

    # Select codec/options based on desired output extension.
    if ext.lower() == "wav":
        acodec = ["-acodec", "pcm_s16le", "-ar", "16000", "-ac", "1"]
    elif ext.lower() == "mp3":
        acodec = ["-acodec", "libmp3lame", "-ar", "16000", "-ac", "1", "-b:a", "128k"]
    else:
        raise ValueError(f"Unsupported CHUNK_EXT: {ext}")

    cmd = [
        ffmpeg_bin, "-hide_banner", "-nostdin",
        "-ss", str(start), "-i", input_path,
        "-t", str(duration),
        *acodec,
        "-y", out_path
    ]
    subprocess.run(cmd, check=True)


def parse_s3_event(event: dict) -> Tuple[str, str]:
    """
    Extract (bucket, key) from a typical S3 Put event.
    This is a minimal single-record parser (assumes one record).
    """
    rec = event["Records"][0]
    bucket = rec["s3"]["bucket"]["name"]
    key = rec["s3"]["object"]["key"]
    return bucket, key


# ─────────────────────────────────────────────────────────────────────────────
# Lambda entrypoint
# ─────────────────────────────────────────────────────────────────────────────
def lambda_handler(event, context):
    """
    AWS Lambda handler:
    - Resolves ffmpeg/ffprobe binaries.
    - Downloads the source audio from the trigger event.
    - Computes chunk windows and generates audio chunks via ffmpeg.
    - Uploads chunks + a JSONL manifest to S3.
    - Returns a summary dict (job_id, manifest URI, chunk list, counts, duration).
    """
    ffmpeg_bin = which_first(FFMPEG_CANDIDATES)
    ffprobe_bin = which_first(FFPROBE_CANDIDATES)
    log.info(f"Using ffmpeg={ffmpeg_bin}, ffprobe={ffprobe_bin}")

    src_bucket, src_key = parse_s3_event(event)
    job_id = infer_job_id_from_key(src_key)
    log.info(f"Source: s3://{src_bucket}/{src_key} | job_id={job_id}")

    # Download source to a temp working directory
    src_name = pathlib.Path(src_key).name
    workdir = pathlib.Path(tempfile.mkdtemp(prefix="prepare-"))
    local_in = str(workdir / src_name)
    s3.download_file(src_bucket, src_key, local_in)

    # Probe duration (seconds)
    duration = ffprobe_duration(ffprobe_bin, local_in)
    log.info(f"Duration(s)={duration}")

    # Compute time windows for chunking
    windows = compute_chunks(duration)
    if not windows:
        raise RuntimeError("No chunks computed (empty/invalid audio?)")

    # Cut chunks and upload to S3
    chunk_keys: List[str] = []
    for idx, start, end in windows:
        nnn = f"{idx:03d}"
        out_name = f"{nnn}.{CHUNK_EXT}"
        local_out = str(workdir / out_name)
        ffmpeg_cut(ffmpeg_bin, local_in, start, end, local_out, CHUNK_EXT)

        chunk_key = f"{CHUNK_PREFIX_BASE}/{job_id}/{out_name}"
        content_type = "audio/wav" if CHUNK_EXT.lower() == "wav" else "audio/mpeg"
        s3.upload_file(local_out, INGEST_BUCKET, chunk_key, ExtraArgs={"ContentType": content_type})
        chunk_keys.append(chunk_key)
        log.info(f"Uploaded chunk: {s3_uri(INGEST_BUCKET, chunk_key)}")

    # Build and upload manifest (JSON Lines)
    manifest_key = f"{MANIFEST_PREFIX_BASE}/{job_id}.jsonl"
    manifest_path = workdir / "manifest.jsonl"
    with open(manifest_path, "w", encoding="utf-8") as f:
        for idx, start, end in windows:
            line = {
                "s3_uri": s3_uri(INGEST_BUCKET, f"{CHUNK_PREFIX_BASE}/{job_id}/{idx:03d}.{CHUNK_EXT}"),
                "start_sec": start,
                "end_sec": end,
                "index": idx,
                "job_id": job_id,
                "source_bucket": src_bucket,
                "source_key": src_key,
            }
            f.write(json.dumps(line, ensure_ascii=False) + "\n")

    s3.upload_file(str(manifest_path), INGEST_BUCKET, manifest_key, ExtraArgs={"ContentType": "application/json"})
    log.info(f"Uploaded manifest: {s3_uri(INGEST_BUCKET, manifest_key)}")

    # Best-effort cleanup of temp workspace
    try:
        shutil.rmtree(workdir)
    except Exception:
        pass

    return {
        "job_id": job_id,
        "manifest": s3_uri(INGEST_BUCKET, manifest_key),
        "chunks": [s3_uri(INGEST_BUCKET, k) for k in chunk_keys],
        "chunk_count": len(chunk_keys),
        "duration_sec": duration
    }


# ─────────────────────────────────────────────────────────────────────────────
# Local dry-run (no S3 I/O; just windowing math)
# Useful for quick verification of the chunking logic from the CLI.
# ─────────────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Dry-run windowing for Prepare Lambda")
    parser.add_argument("--duration", type=float, default=1800.0, help="Audio duration in seconds")
    args = parser.parse_args()

    wins = compute_chunks(args.duration)
    print(json.dumps({
        "duration": args.duration,
        "chunk_len_sec": CHUNK_LEN_SEC,
        "overlap_sec": OVERLAP_SEC,
        "windows": [{"index": i, "start": s, "end": e, "t": round(e - s, 3)} for i, s, e in wins],
        "count": len(wins)
    }, indent=2))
