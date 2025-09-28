"""
Stitches per-chunk Whisper (or similar) transcription outputs into a single transcript.

What this Lambda does:
- Reads a chunk manifest (JSONL) from S3 describing each processed audio chunk.
- Locates each chunk’s transcription JSON in the results bucket.
- Merges chunk-relative segments into a global, monotonic, de-duplicated sequence.
- Writes final transcript artifacts to S3 in multiple formats: JSON, TXT, VTT, and SRT.
- For a later version updates a DynamoDB job record and publishes an SNS notification.

Usage notes:
- Designed to run as an AWS Lambda handler invoked by Step Functions.
- Safe to run locally with the CLI runner at the bottom (see `__main__`).

Important environment variables:
- JOB_TABLE_NAME        -> If set, enables DynamoDB status updates.
- SNS_TOPIC_ARN         -> If set, enables SNS notifications.
- OVERLAP_SECONDS       -> Expected chunk overlap used during merge (float, default "1.0").
- MIN_SEGMENT_SECONDS   -> Minimum allowed segment duration (float, default "0.06").

Inputs (event payload):
- manifest_bucket (str) : S3 bucket for the manifest JSONL.
- manifest_key    (str) : S3 key for the manifest JSONL, e.g. "manifests/<job-id>.jsonl".
- results_bucket  (str) : S3 bucket containing per-chunk outputs.
- language        (str) : Optional, passed through to final JSON.

Outputs:
- Writes to  s3://{results_bucket}/final/{job_id}/  : transcript.json/.txt/.vtt/.srt
- Returns a summary dict with job_id, outputs, segment count, and merge meta.
"""

# ─────────────────────────────────────────────
# Imports
# ─────────────────────────────────────────────
import argparse
import json
import os
from io import BytesIO
from typing import Any, Dict, List, Optional, Tuple

import boto3
from botocore.exceptions import ClientError


# ─────────────────────────────────────────────
# AWS clients & runtime toggles
# ─────────────────────────────────────────────
S3 = boto3.client("s3")
DDB = boto3.resource("dynamodb") if os.getenv("JOB_TABLE_NAME") else None
SNS = boto3.client("sns") if os.getenv("SNS_TOPIC_ARN") else None

# Tunables (read once at import time so invocations are consistent)
OVERLAP_SEC = float(os.getenv("OVERLAP_SECONDS", "1.0"))
MIN_SEGMENT_SEC = float(os.getenv("MIN_SEGMENT_SECONDS", "0.06"))
EPS = 1e-6  # small epsilon for floating-point comparisons


# ─────────────────────────────────────────────
# S3 I/O helpers
# ─────────────────────────────────────────────
def _read_s3_text(bucket: str, key: str) -> str:
    """Fetch an object from S3 and return it as a UTF-8 decoded string."""
    obj = S3.get_object(Bucket=bucket, Key=key)
    return obj["Body"].read().decode("utf-8")


def _read_s3_json(bucket: str, key: str) -> Dict[str, Any]:
    """Load JSON from an S3 object into a Python dict."""
    data = _read_s3_text(bucket, key)
    return json.loads(data)


def _put_s3_bytes(bucket: str, key: str, data: bytes, content_type: str) -> None:
    """Write raw bytes to S3 with an explicit Content-Type."""
    S3.put_object(Bucket=bucket, Key=key, Body=data, ContentType=content_type)


# ─────────────────────────────────────────────
# Time formatting helpers (for VTT/SRT)
# ─────────────────────────────────────────────
def _sec_to_hhmmss_msec_vtt(s: float) -> str:
    # Format seconds as "HH:MM:SS.mmm" for WebVTT
    # 00:00:00.000
    ms = int(round(s * 1000))
    hours = ms // 3_600_000
    ms -= hours * 3_600_000
    minutes = ms // 60_000
    ms -= minutes * 60_000
    seconds = ms // 1000
    ms -= seconds * 1000
    return f"{hours:02d}:{minutes:02d}:{seconds:02d}.{ms:03d}"


def _sec_to_hhmmss_msec_srt(s: float) -> str:
    # Format seconds as "HH:MM:SS,mmm" for SubRip (SRT)
    # 00:00:00,000
    ms = int(round(s * 1000))
    hours = ms // 3_600_000
    ms -= hours * 3_600_000
    minutes = ms // 60_000
    ms -= minutes * 60_000
    seconds = ms // 1000
    ms -= seconds * 1000
    return f"{hours:02d}:{minutes:02d}:{seconds:02d},{ms:03d}"


# ─────────────────────────────────────────────
# Manifest parsing & job id derivation
# ─────────────────────────────────────────────
def _derive_job_id_from_manifest_key(manifest_key: str) -> str:
    # Extract "<job-id>" from a manifest key like "manifests/<job-id>.jsonl"
    name = os.path.basename(manifest_key)
    if name.endswith(".jsonl"):
        return name[:-6]
    return name


def _parse_manifest_jsonl(text: str) -> List[Dict[str, Any]]:
    """
    Parse a JSONL manifest. Each line must contain:
      {"index": int, "start_sec": float, "end_sec": float}
    Returns a list of normalized entries sorted by "index".
    """
    entries: List[Dict[str, Any]] = []
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        obj = json.loads(line)
        # normalize keys
        entry = {
            "index": int(obj["index"]),
            "start_sec": float(obj["start_sec"]),
            "end_sec": float(obj["end_sec"]),
        }
        entries.append(entry)
    entries.sort(key=lambda x: x["index"])
    return entries


# ─────────────────────────────────────────────
# Result discovery & loading
# ─────────────────────────────────────────────
def _s3_key_exists(bucket: str, key: str) -> bool:
    """Return True if the given S3 key exists, False if 404/NotFound, else re-raise."""
    try:
        S3.head_object(Bucket=bucket, Key=key)
        return True
    except ClientError as e:
        if e.response["ResponseMetadata"]["HTTPStatusCode"] == 404 or e.response["Error"]["Code"] in ("404", "NotFound", "NoSuchKey"):
            return False
        raise


def _guess_chunk_key(results_bucket: str, job_id: str, index: int) -> Optional[str]:
    """
    Only accept per-index outputs:
      chunks/{job_id}/{index:05d}/out.json  or  chunks/{job_id}/{index}/out.json
    Ignore any root-level chunks/{job_id}/out.json.
    """
    exact = [
        f"chunks/{job_id}/{index:05d}/out.json",
        f"chunks/{job_id}/{index}/out.json",
    ]
    for k in exact:
        if _s3_key_exists(results_bucket, k):
            return k

    # Enumerate immediate subfolders and match exact index
    prefix = f"chunks/{job_id}/"
    resp = S3.list_objects_v2(Bucket=results_bucket, Prefix=prefix, Delimiter="/")
    for cp in resp.get("CommonPrefixes", []):
        pfx = cp.get("Prefix") or ""
        leaf = pfx.rstrip("/").split("/")[-1]
        if leaf == f"{index:05d}" or leaf == f"{index}":
            k = pfx + "out.json"
            if _s3_key_exists(results_bucket, k):
                return k

    return None


def _load_chunk_segments(results_bucket: str, chunk_key: str) -> List[Dict[str, Any]]:
    """Load and normalize per-chunk segments from 'out.json'."""
    data = _read_s3_json(results_bucket, chunk_key)
    segs = data.get("segments", [])
    # normalize
    norm: List[Dict[str, Any]] = []
    for s in segs:
        start = float(s.get("start", 0.0))
        end = float(s.get("end", 0.0))
        text = (s.get("text") or "").strip()
        if text == "":
            continue
        if end - start <= EPS:
            continue
        norm.append({"start": start, "end": end, "text": text})
    return norm


# ─────────────────────────────────────────────
# Segment merging
# ─────────────────────────────────────────────
def _merge_segments(manifest: List[Dict[str, Any]], results_bucket: str, job_id: str) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    """
    Merge chunk-relative segments into global time.
    Returns:
      segments: list of {"id", "start", "end", "text"} in strict, monotonic order
      meta:     counters for chunks processed and drops (short/overlap)
    """
    merged: List[Dict[str, Any]] = []
    seg_id = 0
    last_end = 0.0
    meta = {"chunks": 0, "dropped_short": 0, "dropped_overlap": 0}

    for entry in manifest:
        idx = entry["index"]
        c_start = entry["start_sec"]
        c_end = entry["end_sec"]

        chunk_key = _guess_chunk_key(results_bucket, job_id, idx)
        if not chunk_key:
            # No chunk present — skip but continue
            continue

        segs = _load_chunk_segments(results_bucket, chunk_key)

        # --- NEW: lightweight text-similarity helpers for overlap de-dup ---
        from difflib import SequenceMatcher
        def _similar(a: str, b: str) -> float:
            return SequenceMatcher(None, a, b).ratio()

        DEDUP_BACK_WINDOW = max(OVERLAP_SEC, 2.0)  # seconds to look back near boundary
        DEDUP_SIM_THRESH  = 0.85                   # consider >= 85% as duplicate
        # -------------------------------------------------------------------

        for s in segs:
            gs = s["start"] + c_start
            ge = s["end"] + c_start

            # clamp to chunk window (defensive)
            if ge < c_start + EPS or gs > c_end - EPS:
                continue
            gs = max(gs, c_start)
            ge = min(ge, c_end)

            # --- NEW: de-dup by text across the overlap window ---------------
            dup = False
            k = len(merged) - 1
            while k >= 0 and merged[k]["start"] >= (gs - DEDUP_BACK_WINDOW):
                if _similar(merged[k]["text"], s["text"]) >= DEDUP_SIM_THRESH:
                    dup = True
                    break
                k -= 1
            if dup:
                meta["dropped_overlap"] += 1
                continue
            # -----------------------------------------------------------------

            # de-dupe by time against previous global end
            if ge <= last_end + EPS:
                meta["dropped_overlap"] += 1
                continue
            if gs < last_end:
                gs = last_end  # trim left edge into the non-overlap

            # enforce min duration
            if ge - gs < MIN_SEGMENT_SEC:
                meta["dropped_short"] += 1
                continue

            merged.append({"id": seg_id, "start": round(gs, 3), "end": round(ge, 3), "text": s["text"]})
            seg_id += 1
            last_end = ge

        meta["chunks"] += 1

    # enforce strict monotonicity + fill micro-gaps (snap next start to last end)
    fixed: List[Dict[str, Any]] = []
    last = 0.0
    for seg in merged:
        s, e = seg["start"], seg["end"]
        if s < last:
            s = last
        # If there is a tiny gap, eliminate it by snapping start to last
        if s - last > 0:
            s = max(last, s)
        if e - s < MIN_SEGMENT_SEC:
            continue
        fixed.append({"id": len(fixed), "start": round(s, 3), "end": round(e, 3), "text": seg["text"]})
        last = e

    return fixed, meta


# ─────────────────────────────────────────────
# Output formatters (JSON/TXT/VTT/SRT)
# ─────────────────────────────────────────────
def _to_transcript_json(job_id: str, language: Optional[str], segments: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Build the final JSON payload that mirrors the merged segments."""
    duration = segments[-1]["end"] if segments else 0.0
    return {
        "job_id": job_id,
        "language": language,
        "duration_sec": duration,
        "segments": segments,
    }


def _to_txt(segments: List[Dict[str, Any]]) -> str:
    # One line per segment (simple, lossless-ish)
    return "\n".join(s["text"] for s in segments) + ("\n" if segments else "")


def _to_vtt(segments: List[Dict[str, Any]]) -> str:
    lines = ["WEBVTT", ""]
    for s in segments:
        lines.append(f"{_sec_to_hhmmss_msec_vtt(s['start'])} --> {_sec_to_hhmmss_msec_vtt(s['end'])}")
        lines.append(s["text"])
        lines.append("")
    return "\n".join(lines)


def _to_srt(segments: List[Dict[str, Any]]) -> str:
    parts: List[str] = []
    for i, s in enumerate(segments, start=1):
        parts.append(str(i))
        parts.append(f"{_sec_to_hhmmss_msec_srt(s['start'])} --> {_sec_to_hhmmss_msec_srt(s['end'])}")
        parts.append(s["text"])
        parts.append("")
    return "\n".join(parts)


# ─────────────────────────────────────────────
# Later version place holder side-effects: DynamoDB + SNS
# ─────────────────────────────────────────────
def _update_job_status(job_id: str, status: str, outputs: Dict[str, str]) -> None:
    """
    If configured, update a DynamoDB row keyed by job_id with the latest status and outputs.
    No-op if JOB_TABLE_NAME is not set.
    """
    if not DDB:
        return
    table_name = os.getenv("JOB_TABLE_NAME")
    table = DDB.Table(table_name)
    table.update_item(
        Key={"job_id": job_id},
        UpdateExpression="SET #s = :s, outputs = :o, updated_at = :t",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={
            ":s": status,
            ":o": outputs,
            ":t": int(__import__("time").time()),
        },
    )


def _notify(job_id: str, status: str, outputs: Dict[str, str], meta: Dict[str, Any]) -> None:
    """
    If configured, publish a compact SNS notification with job status and output locations.
    No-op if SNS_TOPIC_ARN is not set.
    """
    if not SNS:
        return
    topic_arn = os.getenv("SNS_TOPIC_ARN")
    SNS.publish(
        TopicArn=topic_arn,
        Subject=f"Whisper stitcher: {job_id} {status}",
        Message=json.dumps({"job_id": job_id, "status": status, "outputs": outputs, "meta": meta}, ensure_ascii=False),
    )


# ─────────────────────────────────────────────
# Lambda entrypoint
# ─────────────────────────────────────────────
def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler.

    Expected event keys (from Step Functions input):
      - manifest_bucket
      - manifest_key     (e.g., 'manifests/<job-id>.jsonl')
      - results_bucket
      - language         (optional, pass-through)

    Returns:
      Dict with job_id, outputs (S3 URIs), segment count, and merge metadata.
    """
    manifest_bucket = event["manifest_bucket"]
    manifest_key = event["manifest_key"]
    results_bucket = event["results_bucket"]
    language = event.get("language")

    job_id = _derive_job_id_from_manifest_key(manifest_key)

    # 1) Read manifest.jsonl (list of chunk boundaries)
    manifest_text = _read_s3_text(manifest_bucket, manifest_key)
    manifest = _parse_manifest_jsonl(manifest_text)

    # 2) Merge segments across all chunks into global time
    segments, meta = _merge_segments(manifest, results_bucket, job_id)

    # 3) Build output payloads in multiple formats
    tjson = _to_transcript_json(job_id, language, segments)
    ttxt = _to_txt(segments)
    tvtt = _to_vtt(segments)
    tsrt = _to_srt(segments)

    # 4) Write to S3 under final/<job-id>/
    final_prefix = f"final/{job_id}/"
    out_json_key = final_prefix + "transcript.json"
    out_txt_key = final_prefix + "transcript.txt"
    out_vtt_key = final_prefix + "transcript.vtt"
    out_srt_key = final_prefix + "transcript.srt"

    _put_s3_bytes(results_bucket, out_json_key, json.dumps(tjson, ensure_ascii=False).encode("utf-8"), "application/json")
    _put_s3_bytes(results_bucket, out_txt_key, ttxt.encode("utf-8"), "text/plain; charset=utf-8")
    _put_s3_bytes(results_bucket, out_vtt_key, tvtt.encode("utf-8"), "text/vtt; charset=utf-8")
    _put_s3_bytes(results_bucket, out_srt_key, tsrt.encode("utf-8"), "application/x-subrip; charset=utf-8")

    outputs = {
        "json": f"s3://{results_bucket}/{out_json_key}",
        "txt": f"s3://{results_bucket}/{out_txt_key}",
        "vtt": f"s3://{results_bucket}/{out_vtt_key}",
        "srt": f"s3://{results_bucket}/{out_srt_key}",
    }

    # 5) Optional side-effects
    _update_job_status(job_id, "COMPLETED", outputs)
    _notify(job_id, "COMPLETED", outputs, meta)

    return {
        "job_id": job_id,
        "outputs": outputs,
        "segments": len(segments),
        "meta": meta,
    }


# ─────────────────────────────────────────────
# Local runner (for ad-hoc testing)
# ─────────────────────────────────────────────
def _load_event_json(path: str) -> Dict[str, Any]:
    """Read a local JSON file for use as a test event payload."""
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Local runner for stitcher Lambda")
    parser.add_argument("--event", type=str, help="Path to a JSON file with the Step Functions input", required=False)
    args = parser.parse_args()
    if args.event:
        evt = _load_event_json(args.event)
    else:
        # Example quick-start event for local testing; adjust bucket/key/job-id values as needed.
        evt = {
            "manifest_bucket": "seerahscribe-ingest-<acct>-eu-west-1",
            "manifest_key": "manifests/<job-id>.jsonl",
            "results_bucket": "seerahscribe-results-<acct>-eu-west-1",
            "language": "en",
        }
    res = handler(evt, context=None)
    print(json.dumps(res, indent=2))
