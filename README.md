# Nimbus Transcribe 🚀

**Nimbus Transcribe** is a next-generation **cloud-native transcription and automation platform**.  
Built on top of **AWS serverless services**, it delivers scalable, fault-tolerant, and high-performance pipelines for transforming audio into actionable data.  

By combining **serverless compute (Lambda, Step Functions)** with **GPU-powered parallel batch jobs** and **infrastructure automation (Terraform)**, Nimbus Transcribe enables true end-to-end orchestration of data and media workflows.

---

## ✨ Key Features

- ⚡ **Serverless Audio Processing**: Modular **AWS Lambda functions** for audio preparation, stitching, and transformation.  
- 🗂️ **S3-backed Data Lake**: Seamless ingestion and results buckets for reliable, cost-efficient storage.  
- 🔄 **Workflow Orchestration**: Automated pipelines via **AWS Step Functions** for parallel execution and error-resilient coordination.  
- 🐳 **Containerized Compute**: **Dockerized tools** for reproducible builds and **AWS Batch** for GPU-accelerated workloads.  
- 🛠️ **Infrastructure as Code**: End-to-end reproducibility with **Terraform**, enabling consistent environments across teams and regions.  
- 🤖 **Automation & CI/CD**: Pre-built **GitHub Actions workflows** for deployments, testing, and continuous integration.  

---

## 📂 Repository Structure

```
docker/       # Container images for AWS Batch & GPU-accelerated tools
lambdas/      # AWS Lambda functions (prepare, stitch, orchestrate, etc.)
terraform/    # Infrastructure as Code (state, modules, environments)
artifacts/    # Build outputs (local-only, gitignored)
scripts/      # All my helper powershell scripts
.github/      # CI/CD workflows, actions, issue/PR templates
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
