# Nimbus Transcribe  

**Nimbus Transcribe** is a **cloud-native transcription platform** engineered to transform long-form audio into accurate, structured text at scale.  

Built entirely on **AWS serverless and GPU-powered infrastructure**, it demonstrates how to deliver **production-ready, massively parallel pipelines** for data-heavy media workflows.  

This project showcases expertise in **distributed systems, applied machine learning, and infrastructure as code** — designed and implemented end-to-end by *Asad Rana (BSc Mathematics, University of Manchester)*.  

---

## ✨ Highlights  

- **⚡ Scalable Audio Processing**  
  - Prepare, stitch, and transform audio using modular **AWS Lambda functions**.  
- **☁️ Cloud-Native Data Lake**  
  - **S3 ingestion and results buckets** ensure reliable, cost-efficient storage.  
- **🔄 Distributed Orchestration**  
  - **AWS Step Functions (Distributed Map)** orchestrates thousands of parallel jobs with built-in retries and error handling.  
- **🖥️ GPU Acceleration**  
  - **AWS Batch with Dockerised Whisper** models delivers ≈30× real-time transcription (TBC).  
- **📦 Infrastructure as Code**  
  - Fully reproducible deployments with **Terraform** across regions and accounts.  
- **🤖 CI/CD Automation**  
  - **GitHub Actions** for testing, packaging, and seamless deployment.  

---

## 🎯 Problem Statement  

Transcribing **hours of multilingual, long-form audio** quickly, reliably, and at low cost:  

- **Target throughput:** 10 hours of audio in ≤20 minutes wall-clock  
- **Accuracy:** OpenAI Whisper Large-v3 via Faster-Whisper/CTranslate2 (`compute_type=int8_float16`)  
- **Scalability:** Designed for research labs, media houses, and enterprise automation.  

---

## 🏗️ Architecture Overview  

![Architecture Diagram](docs/architecture-diagram.png)  

**Data Flow:**  
1. **S3 (Ingest)** →  
2. **Lambda (Prepare):** e.g. configuration: split into 10-minute chunks (+1s overlap) →  
3. **Step Functions (Distributed Map):** orchestrate jobs as many jobs needed →  
4. **AWS Batch (GPU Workers):** run Whisper via ECR →  
5. **Lambda (Stitcher):** merge JSON/TXT/SRT/VTT →  
6. **S3 (Results)**  

**Core Components:**  
- **Buckets:** `nimbus-trasncribe-ingest-<acct>-<region>`, `nimbus-transcribe-results-<acct>-<region>`  
- **State Machine:** `oepnai-whisper-transcribe-map` (configurable concurrency)  
- **Batch Job:** `openai-whisper-transcribe-job` (`openai-whisper-faster:latest`)  
- **Lambdas:** Prepare, Stitcher  

---

## 📈 Performance & Cost (TBC)  

- **Throughput:** ~30× real-time transcription on g5.xlarge (A10G) GPUs  
- **Example SLA:**  
  - 10h audio → ~20 minutes wall-clock (N≈16 GPUs)  
- **Estimated Cost:**  
  - GPU compute: ~$12–15 per 10h transcription  
  - Supporting services (S3, Lambda, Step Functions): ~$1–2  
  - **Total:** ~`$15` for 10h audio (to be confirmed with final benchmark)  

---

## 📂 Repository Structure  

```
docker/       # Container images for GPU-powered Batch jobs
lambdas/      # Lambda functions (prepare, stitch, orchestrate)
terraform/    # IaC: state, modules, environments
scripts/      # Helper PowerShell utilities
.github/      # CI/CD workflows and automation
docs/         # Architecture diagrams and notes
artifacts/    # video + output run throughs
```  

---

## 🚀 Quick Start  

Clone the repository:  

```bash
git clone https://github.com/asads-cloud/nimbus-transcribe.git
cd nimbus-transcribe
```

Build the dev container:  

```bash
docker build -t nimbus-tools ./docker
```

Deploy infrastructure with Terraform on individual modules(check terraform/README.md for details):  

```bash
cd terraform/...
terraform init
terraform apply
```

Package & push the GPU worker image:  

```powershell
# docker build / tag / push commands here
```

Update Lambda functions:  

```powershell
# zip prepare & stitcher, update Lambda functions
```

---

## 👨‍💻 Author  

Designed and built by **Asad Rana**  
- 🎓 BSc Mathematics (Specialisation: Statistics), University of Manchester  
- 🌐 Focus: Cloud architecture, distributed systems, and applied AI  
