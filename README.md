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

Transcribing **hours of multilingual, long-form audio** requires balancing **speed, cost, and accuracy**.  

This architecture is designed for **flexibility**:  
- **Parallelism:** Scale out to dozens of GPU workers to process hours of content in minutes.  
- **Cost Efficiency:** Scale down for lower throughput when budget is the priority.  
- **Configurable trade-offs:** Your choice of instance types, job concurrency, and Whisper model size determines the balance between speed and cost.  

Rather than being locked into a fixed throughput target, the system gives users the **levers to tune performance** — whether that means maximum throughput for a media pipeline, or cost-sensitive batch jobs for research.  

**Example:**  
- Running on **6× g5.xlarge GPUs in parallel** → ~10 hours of audio transcribed in ~20 minutes (higher cost, maximum speed).  
- Running on **1× g5.xlarge GPU** → the same workload completes overnight (lower cost, slower turnaround).  
 

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

## 📈 Performance & Cost  

This system is built to be **configurable**, letting you choose between **maximum throughput** or **cost savings** depending on your workload.  

- **Parallelism:** Run jobs across multiple GPUs for faster turnaround, or restrict concurrency for lower cost.  
- **Performance Example:**  
  - ~30× real-time transcription on `g5.xlarge` (A10G) GPUs when running at high concurrency.  
  - 10h audio → ~20 minutes wall-clock with ~16 GPUs in parallel.  
- **Cost Example:**  
  - High-throughput mode: ~$12–15 in GPU compute + ~$1–2 in supporting AWS services (S3, Lambda, Step Functions).  
  - Cost-sensitive mode: run on fewer GPUs for longer wall-clock times but significantly reduced spend.  

⚖️ **Trade-off:** You control the balance between **speed** and **cost** by tuning instance types, job concurrency, and model configuration.  


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

## 🚀 Deployment  

Deploy infrastructure with Terraform using the modular structure provided.  
See [terraform/README.md](./terraform/README.md) for step-by-step details on provisioning individual components.

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
