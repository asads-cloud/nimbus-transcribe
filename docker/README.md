# 🐳 Docker — OpenAI Whisper Worker (Nimbus Transcribe)

This folder contains the **GPU-accelerated worker image** used by AWS Batch to run Whisper inference at scale.  
The container wraps **faster-whisper (CTranslate2)** with a small, explicit CLI and S3 helpers for clean I/O.

---

## 🔧 Image Summary

- **Base:** `nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04`
- **Python:** system `python3` via apt (Ubuntu 22.04)
- **Audio tools:** `ffmpeg`
- **Libraries:** `ctranslate2==4.6.0`, `faster-whisper==1.2.0`, `boto3==1.34.162`
- **Entrypoint:** `/app/run.sh`
- **Model cache:** `/root/.cache/whisper` (override with `WHISPER_CACHE`)

File layout in the image:
```
/app/
├─ run.sh           # Orchestrates I/O + calls transcribe.py
├─ s3io.py          # Tiny boto3-based S3 helper (get/put)
└─ transcribe.py    # Single-file CLI wrapping faster-whisper
```

---

## 🏗 Build

From the repo root (where the Dockerfile path resolves as shown below):

```bash
# Build with a friendly tag
docker build -t openai-whisper-worker -f docker/Dockerfile .
```

> Requires **NVIDIA Container Toolkit** on the build host if you plan to run with GPUs locally. Building itself does not require a GPU, only runtime does.

---

## ▶️ Local Run (GPU)

Transcribe a local file and write JSON next to it:

```bash
# Linux with NVIDIA runtime
docker run --rm --gpus all   -e IN_URI="/data/input.wav"   -e OUT_URI="/data/out/transcript.json"   -e MODEL="large-v3"   -e BEAM_SIZE="5"   -e COMPUTE_TYPE="int8_float16"   -v "$PWD/samples:/data"   openai-whisper-worker
```

Using S3 as input/output:

```bash
docker run --rm --gpus all   -e IN_URI="s3://nimbus-transcribe-ingest-<acct>-<region>/chunks/task-0002/001.wav"   -e OUT_URI="s3://nimbus-transcribe-results-<acct>-<region>/chunks/task-0002/out.json"   -e MODEL="large-v3"   -e COMPUTE_TYPE="int8_float16"   -e AWS_REGION="eu-west-1"   -e AWS_ACCESS_KEY_ID="..." -e AWS_SECRET_ACCESS_KEY="..."   openai-whisper-worker
```

> The container uses `s3io.py` (boto3) for transfers; provide credentials via env vars, AWS profile volume, or an IAM role when running on AWS.

---

## ☁️ Push to Amazon ECR

```bash
AWS_REGION=eu-west-1
ACCOUNT_ID=123456789012
REPO=openai-whisper-faster

# Create repo (once)
aws ecr create-repository --repository-name "$REPO" 2>/dev/null || true

# Authenticate Docker to ECR
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

# Tag & push
docker tag openai-whisper-worker "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO:latest"
docker push "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO:latest"
```

> The ECR repository is defined in Terraform as `openai-whisper-faster` (see `terraform/ecr_whisper.tf`).

---

## 🧵 Runtime Contract (env vars)

`run.sh` expects the following environment variables:

- `IN_URI` *(required)* — input audio (`/path/file.wav` or `s3://bucket/key`)
- `OUT_URI` *(required)* — output JSON target (`/path/out.json` or `s3://bucket/key`)
- `MODEL` — Whisper model size (default `large-v3`)
- `LANGUAGE` — two-letter code to force language (optional)
- `BEAM_SIZE` — integer beam width (default `5`)
- `COMPUTE_TYPE` — CTranslate2 type (default `int8_float16`), e.g. `float16`, `int8_float16`, `int8`, `int16`
- `VAD` — set to `"1"` to enable VAD
- `INITIAL_PROMPT` — optional prompt for continuity
- `MAX_NEW_TOKENS` — optional cap per segment

Additional knobs respected by `transcribe.py`:
- `WHISPER_DEVICE` — `cuda|cpu|auto` (auto-detect default)
- `WHISPER_CACHE` — model cache directory (default `/root/.cache/whisper`)

---

## 🧪 AWS Batch: Example container overrides

When submitting a job (manually or via Step Functions), pass env vars like:

```json
{
  "vcpus": 4,
  "memory": 10000,
  "environment": [
    { "name": "MODEL", "value": "large-v3" },
    { "name": "COMPUTE_TYPE", "value": "int8_float16" },
    { "name": "IN_URI", "value": "s3://.../chunks/task-0002/001.wav" },
    { "name": "OUT_BUCKET", "value": "nimbus-transcribe-results-<acct>-eu-west-1" },
    { "name": "OUT_PREFIX", "value": "chunks/task-0002/" },
    { "name": "OUT_URI", "value": "s3://.../chunks/task-0002/out.json" }
  ]
}
```

> Your repo includes `scripts/submit_whisper_test.ps1` to streamline this process.

---

## 📈 Performance tips

- **Compute type:** `int8_float16` offers strong speed/cost balance on Ampere GPUs (e.g., g5.xlarge). Try `float16` for best quality if you have headroom.
- **Model cache warmup:** Mount or reuse `/root/.cache/whisper` across jobs to avoid repeated downloads.
- **VAD:** Enabling `--vad_filter` can trim silence and reduce tokens; helpful for meetings or noisy audio.
- **Beam size:** Start at `5`; increase for quality at some cost to speed.

---

## 🧰 Troubleshooting

- `CUDA driver not found` → install **NVIDIA Container Toolkit** and run with `--gpus all`; ensure host driver >= CUDA 12.4 compatible.
- `AccessDenied` on S3 → verify AWS credentials/role; for Batch, attach an instance role with S3 permissions.
- Slow first run → model weights download on first use; subsequent runs are faster with a warm cache.
- Audio decode errors → confirm `ffmpeg` can read the format; consider re-encoding to WAV 16kHz mono for stability.

---

## 📄 Dockerfile

```dockerfile
FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive     PIP_NO_CACHE_DIR=1     PYTHONUNBUFFERED=1     WHISPER_CACHE=/root/.cache/whisper

RUN apt-get update && apt-get install -y --no-install-recommends     python3 python3-pip python3-venv ffmpeg ca-certificates &&     rm -rf /var/lib/apt/lists/*

RUN python3 -m pip install --upgrade pip &&     pip install "ctranslate2==4.6.0" "faster-whisper==1.2.0" "boto3==1.34.162"

WORKDIR /app
COPY docker/openai-whisper-worker/app/ /app/
RUN chmod +x /app/run.sh

ENTRYPOINT ["/app/run.sh"]
```

---

## ✅ License & attribution

- `faster-whisper` is MIT-licensed. Check the upstream project for details.
- CUDA images are provided by NVIDIA and subject to their terms.
- This repository’s container code is © you; adapt licenses as appropriate for your distribution.
