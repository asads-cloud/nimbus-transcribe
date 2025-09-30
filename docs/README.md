# 📚 Nimbus Transcribe — Documentation

This folder contains **system-level documentation** for the Nimbus Transcribe platform.  
It is intended for auditors, recruiters, and contributors to quickly understand the **overall architecture** and how the different infrastructure components interact.

---

## 🏗 Contents

- **`architecture-diagram.png`**
  - High-level visual overview of the Nimbus Transcribe pipeline.
  - Shows how **S3, Lambda, Step Functions, AWS Batch (GPU), and ECR** integrate into a fully automated transcription workflow.

- **`architecture-diagram.txt`**
  - Textual reference of the architecture diagram (helpful for quick grep/search or if images cannot be rendered).

---

## 🖼 Architecture Overview

The diagram illustrates the end-to-end workflow:

1. **Audio Upload**
   - User places media files into the **Ingest S3 bucket**.

2. **Prepare Stage**
   - A **Lambda function (`Prepare`)** splits audio into overlapping chunks and generates a manifest.

3. **Distributed Processing**
   - **Step Functions (Distributed Map)** orchestrates per-chunk transcription jobs in parallel.
   - **AWS Batch GPU Fleet** runs Whisper containers pulled from ECR.

4. **Partial Outputs**
   - Each GPU job writes per-chunk transcripts to the **Results S3 bucket**.

5. **Stitch Stage**
   - A **Lambda function (`Stitcher`)** merges outputs into final transcripts (`.txt`, `.json`, `.vtt`, `.srt`).

6. **Final Outputs**
   - Results are written back to S3 under a predictable `final/` prefix.
   - Optional integrations (DynamoDB, SNS, alarms) can be added.

---

## 🔍 How to Use This Documentation

- **Recruiters & Auditors** → Quickly see the professional-grade, production-style architecture of Nimbus Transcribe.  
- **Developers** → Use the diagram and text reference as a map when working with Terraform modules, Lambdas, and helper scripts.  
- **Future extensions** → The dashed arrows in the diagram show where optional features (manual start triggers, DynamoDB job tracking, SNS notifications, CloudWatch alarms) can be integrated.

---

✅ This documentation complements the Terraform code (`/terraform`), Lambda handlers (`/lambdas`), and helper scripts (`/scripts`).  
Together, they demonstrate a **modular, production-ready transcription pipeline** built entirely on AWS.
