# Nimbus Transcribe

GPU-accelerated, serverless AWS pipeline for high-throughput
transcription.

Nimbus Transcribe is a cloud-native, distributed transcription platform
that processes long-form, multilingual audio using Lambda, S3, ECR (**OpenAI Whisper**), Step
Functions (Distributed Map), AWS Batch (GPU), and Terraform.

It demonstrates real-world platform engineering, distributed compute,
cost-aware design, and IaC-driven automation on AWS.

## 🎯 Why This Project Matters

This system shows I can:

-   Design production-aligned cloud architectures using AWS serverless +
    containerised GPU workloads
-   Build massively parallel pipelines using Step Functions Distributed
    Map
-   Operate GPU Batch compute with Dockerised Whisper
-   Apply Terraform-first IaC across accounts/regions
-   Build CI/CD pipelines for packaging, deployment, and automation
-   Balance throughput vs cost using real architectural trade-offs

> **Note:** The Terraform structure is currently undergoing a refactor
> to align with improved module patterns and environment separation i've been learning.

## 🎥 Demo Video

[![Watch the video](https://img.youtube.com/vi/wtgcypmLKQU/maxresdefault.jpg)](https://youtu.be/wtgcypmLKQU)

## ✨ Highlights

###  Parallel Audio Processing

Modular Lambda functions split long recordings into manageable segments,
prepare metadata, and stitch results.

###  Distributed Orchestration

AWS Step Functions Distributed Map processes hundreds-thousands of
segments in parallel with retries, timeouts, and DLQs.

###  GPU Acceleration

Dockerised Whisper runs on AWS Batch (g5.xlarge) GPU compute for ≈30×
real-time transcription at scale.

###  Serverless Data Flow

S3 ingestion → Lambda prepare → Distributed Map → GPU Batch → Lambda
stitch → S3 results.

###  Terraform-first Deployment

Reproducible infrastructure with Terraform: buckets, Lambdas, Batch
compute, IAM, state machine, logging.

###  CI/CD

GitHub Actions for automated image builds, packaging, and deploy
workflows.

## 🧠 Problem my System Solves

Long-form audio transcription at scale has three competing constraints:

-   **Speed** (parallel GPU throughput)
-   **Cost** (number of GPU workers & instance types)
-   **Accuracy** (Whisper model size/configuration)

Nimbus Transcribe exposes these controls explicitly so users can tune:

-   number of GPUs
-   instance type
-   concurrency
-   Whisper model size

**Examples:**

**High-throughput mode:**\
\~10 hours of audio in \~20 minutes using 6-16 GPU workers

**Cost-sensitive mode:**\
1 GPU → slower, ultra-low-cost processing

## 🏗 Architecture Overview

### Flow

-   S3 Ingest
-   Lambda Prepare → chunking, config
-   Step Functions Distributed Map → parallel job fan-out
-   AWS Batch (GPU) → Whisper transcription
-   Lambda Stitch → merge transcripts
-   S3 Results

### Core Components

-   Lambdas: prepare, stitch
-   Batch job: Dockerised Whisper
-   S3 buckets: ingest + results
-   Step Functions map state
-   ECR: Whisper GPU image
-   Terraform modules (refactor in progress)

## 📈 Performance & Cost

### Performance

-   \~30× real-time transcription on g5.xlarge (A10G)
-   Highly parallel fan-out through Distributed Map
-   Designed for predictable scaling

### Cost

-   **High-throughput:** \~\$12-\$17 per 10h workload
-   **Cost-saving:** run 1-2 GPUs for lower spend
-   Pay-only-for-what-you-use model (serverless control plane)

## 📂 Repository Structure

    docker/       # GPU Batch job image (Whisper)
    lambdas/      # prepare, stitch functions
    terraform/    # IaC (refactor in progress)
    scripts/      # helper scripts (PowerShell)
    .github/      # CI/CD workflows
    docs/         # diagrams + notes
    artifacts/    # demo outputs, runs, videos

## 🚀 Quick Start

> Deploy infrastructure with Terraform using the modular structure provided.  
> See [terraform/README.md](./terraform/README.md) for step-by-step details on provisioning individual components.

``` bash
git clone https://github.com/asads-cloud/nimbus-transcribe.git
cd nimbus-transcribe

# Build tools container
docker build -t nimbus-tools ./docker

# Deploy infra
terraform init
terraform apply
```

## 👤 Author

Designed and built by **Asad Rana**\
Cloud & Platform Engineer | AWS, Terraform, GitOps, CI/CD
