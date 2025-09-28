**Nimbus Transcribe** is a next-generation **cloud-native transcription and automation platform**.  
Built on top of **AWS serverless services**, it delivers scalable, fault-tolerant, and high-performance pipelines for transforming audio into actionable data.  

By combining **serverless compute (Lambda, Step Functions)** with **GPU-powered parallel batch jobs** and **infrastructure automation (Terraform)**, Nimbus Transcribe enables true end-to-end orchestration of data and media workflows.

---

## ✨ Key Features

- ⚡ **Serverless Audio Processing**: Modular **AWS Lambda functions** for audio preparation, stitching, and transformation.  
- 🗂️ **S3-backed Data Lake**: Seamless ingestion and results buckets for reliable, cost-efficient storage.  
- 🔄 **Workflow Orchestration**: Automated pipelines via **AWS Step Functions (Distributed Map)** for parallel execution and error-resilient coordination.  
- 🐳 **Containerized Compute**: **Dockerized tools** for reproducible builds and **AWS Batch (GPU)** for ultra-fast Whisper transcription.  
- 🛠️ **Infrastructure as Code**: End-to-end reproducibility with **Terraform**, enabling consistent environments across teams and regions.  
- 🤖 **Automation & CI/CD**: Pre-built **GitHub Actions workflows** for deployments, testing, and continuous integration.  

---

## 📊 Problem Statement

Transcribe **long-form, multilingual audio** quickly and cost-effectively:
- **Target:** 10 hours of audio in ≤20 minutes wall-clock  
- **Accuracy:** Whisper large-v3 via Faster-Whisper/CTranslate2 (`compute_type=int8_float16`)  
- **Scale:** Handle workloads across research, media, and enterprise automation.  

---

## 🏗️ Architecture Overview  

![Architecture Diagram](docs/architecture-diagram.png)

**Data Flow:**  
S3 (ingest) → Lambda (Prepare: 10m chunks + 1s overlap) → Step Functions (Distributed Map) → AWS Batch (GPU workers) → Lambda (Stitcher: merge JSON/TXT/SRT/VTT) → S3 (results)  

**Core Components:**  
- **Buckets:** `nimbus-ingest-<acct>-<region>`, `nimbus-results-<acct>-<region>`  
- **State Machine:** `nimbus-transcribe-map` (configurable MaxConcurrency)  
- **Batch Job:** `nimbus-transcribe-job` running `whisper-faster:latest`  
- **Lambdas:** Prepare, Stitcher, Orchestrate  

---

## 📈 SLA Math (Example)

- Total audio: `T_total = 10h`  
- Chunking: `~10 min` per chunk (+1s overlap) ⇒ `~60 chunks per 10h`  
- Per-GPU throughput (× real-time): `R_gpu = TBD`  
- GPU count: `N = TBD` (e.g., 10–16 g5.xlarge)  
- Aggregate throughput: `R_agg = N × R_gpu`  
- Expected wall-clock: `T_total / R_agg + overhead(prepare+stitch)`  
- **Observed demo:** TBD  

---

## 💰 Cost Estimate (Rough)

- **GPU:** g5.xlarge (A10G) × `N` × runtime ≈ `TBD`  
- **Other services:** EBS / ECR / S3 / Step Functions / Lambda ≈ `TBD`  
- **Run total:** ~`$15` per 10h transcription (replace with measured values)  

---

## 📂 Repository Structure

```
docker/       # Container images for AWS Batch & GPU-accelerated tools
lambdas/      # AWS Lambda functions (prepare, stitch, orchestrate, etc.)
terraform/    # Infrastructure as Code (state, modules, environments)
artifacts/    # Build outputs (local-only, gitignored)
scripts/      # All my helper powershell scripts
.github/      # CI/CD workflows, actions, issue/PR templates
docs/ # Architecture diagrams, notes, design docs
```

---

## 🚀 Getting Started

Clone the repository:

```bash
git clone https://github.com/asads-cloud/nimbus-transcribe.git
cd nimbus-transcribe
```

Build the dev container:

```bash
docker build -t nimbus-tools ./docker
```

Deploy infrastructure:

```bash
cd terraform
terraform init
terraform apply
```
