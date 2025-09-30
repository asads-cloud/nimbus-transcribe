# ⚡ Scripts — Nimbus Transcribe

This folder contains **PowerShell helper scripts** that streamline the use of the Nimbus Transcribe pipeline.  
They provide a local developer/operator interface to the AWS infrastructure provisioned via Terraform.

---

## ✨ Overview of Scripts

### 1. `1-watch-ingest.ps1`
- Watches the local **`Nimbus Ingest`** folder on the Desktop.
- Detects when new audio/video files are dropped in.
- Ensures files are stable (fully written) before processing.
- Automatically invokes the uploader (`2-upload_audio.ps1`) for each detected file.
- Uses `.NET FileSystemWatcher` plus a light polling fallback for robustness.

### 2. `2-upload_audio.ps1`
- Uploads an audio/video file from the local ingest folder to the **S3 ingest bucket**.
- Waits for the `prepare-lambda` to produce a manifest file.
- Builds a **Step Functions input JSON** (UTF-8, no BOM).
- Starts the transcription **state machine execution**.
- Polls until completion.
- Downloads results (TXT + JSON) to the Desktop **`Nimbus Results`** folder.

### 3. `compress.ps1`
- Packages Lambda handlers (`prepare` and `stitcher`) into zip archives under `artifacts/lambda/`.
- Automatically re-deploys the corresponding Terraform stacks (`terraform/prepare-lambda`, `terraform/stitcher-lambda`).
- Provides a one-command workflow to rebuild and push updated Lambda code.

### 4. `submit_whisper_test.ps1`
- Submits a **test transcription job** directly to **AWS Batch** (bypassing Step Functions).
- Builds container overrides (vCPUs, memory, env vars, HuggingFace token, input/output URIs).
- Resolves latest ARNs for job queue + job definition.
- Submits the job and prints the Job ID.
- Verifies that the correct environment variables were injected into the job.

---

## 🚀 Usage

From repo root, run any script with PowerShell:

```powershell
# Start watching the ingest folder
.\scripts\1-watch-ingest.ps1

# Manually upload and process a file
.\scripts\2-upload_audio.ps1 -FileName "Lecture01_example.mp3"

# Repackage and deploy Lambdas
.\scripts\compress.ps1

# Submit a direct Batch job
.\scripts\submit_whisper_test.ps1
```

---

## 🛠️ Requirements

- **PowerShell 5+** (Windows) or **PowerShell Core** (cross-platform).
- **AWS CLI** configured with valid credentials and correct region.
- Terraform installed (for `compress.ps1`).
- The core **Nimbus Transcribe infrastructure** deployed via Terraform.

---

## 🌟 Notes

- Scripts assume a consistent **Desktop folder layout**:
  - `Desktop/Nimbus Transcriber/Nimbus Ingest`
  - `Desktop/Nimbus Transcriber/Nimbus Results`
- `1-watch-ingest.ps1` + `2-upload_audio.ps1` provide an end-to-end local UX: *drag a file into a folder → get back a transcript*.
- `compress.ps1` accelerates Lambda development by bundling and redeploying handlers with a single command.
- `submit_whisper_test.ps1` is intended for **advanced debugging/benchmarking** of Batch jobs.

---

✅ Together, these scripts turn the cloud-native pipeline into a **developer-friendly toolchain**, bridging local workflows with distributed AWS services.
