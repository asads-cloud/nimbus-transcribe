# ☁️ Terraform Infrastructure — Nimbus Transcribe

This folder contains the complete **Infrastructure-as-Code (IaC)** stack for **Nimbus Transcribe**, built using **Terraform**.  
Every component of the transcription pipeline — from ingestion to GPU workloads — is provisioned automatically and reproducibly.  

No manual AWS console setup is required. The entire system can be deployed in a fresh account from scratch.

---

## ✨ Overview

The infrastructure provisions the following:

- **S3 Buckets**  
  - Ingest bucket for raw media uploads  
  - Results bucket for final transcripts (TXT, JSON, SRT, VTT formats)  

- **AWS Lambda Functions**  
  - `prepare-lambda` → Splits audio into overlapping 10-minute chunks (configured how you want) 
  - `stitcher-lambda` → Reassembles distributed outputs into a final transcript  

- **AWS Step Functions**  
  - Orchestrates the full pipeline using a **Distributed Map**, enabling scalable, fault-tolerant execution  

- **AWS Batch (GPU)**  
  - GPU-backed compute environment(g5.xlarge), job queue, and job definition for Whisper inference  
  - Powered by ECR images provisioned in `ecr_whisper.tf`  

- **Networking**  
  - Uses the **default AWS VPC** for simplicity  
  - Extensible to a dedicated VPC with custom subnets and security groups if required  
  - The networking design is modular — can be swapped for a dedicated VPC module with private subnets, NAT gateways, and security groups.  

---

## 📂 Structure

Each subfolder is an **independent Terraform stack** with its own state.  
They can be deployed individually, but together they form the complete *Nimbus Transcribe* pipeline.

```
terraform/
├── ecr_whisper.tf      # ECR repo + lifecycle policy for Whisper GPU images
├── prepare-lambda/     # Splits audio files into chunks (S3 ingest → Lambda)
├── batch/              # AWS Batch GPU environment + networking config
├── stepfunctions/      # State machine orchestrating the workflow
├── stitcher-lambda/    # Merges chunk results into final transcript
```

**Deployment order (fresh environment):**

1. `terraform/` (root provider + ECR repo)  
2. `prepare-lambda/`  
3. `batch/`  
4. `stepfunctions/`  
5. `stitcher-lambda/`  

---

## 🚀 Deployment

Initialize and apply in each module folder:

```bash
cd terraform
terraform init
terraform apply   # Root + ECR repo

cd prepare-lambda
terraform init
terraform apply   # Ingest bucket + Lambda

cd ../batch
terraform init
terraform apply   # Batch compute env + networking

cd ../stepfunctions
terraform init
terraform apply   # Workflow orchestration

cd ../stitcher-lambda
terraform init
terraform apply   # Final transcript assembly
```

After deployment, uploading an audio file to the **ingest S3 bucket** automatically triggers the complete transcription pipeline.

---

## 🛠️ State Management

- **Local state** (`terraform.tfstate`) is used for development.  
- For production environments, configure **remote state** (S3 backend + DynamoDB locking) to support collaboration and CI/CD pipelines.  

---

## 👨‍💻 Author

Designed and implemented by **Asad Rana**  
- 🎓 BSc Mathematics (Specialisation: Statistics), University of Manchester  
- 🌐 Focus: Cloud Architecture, Distributed Systems, Applied AI  

