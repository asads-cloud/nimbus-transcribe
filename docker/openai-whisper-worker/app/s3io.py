"""
s3io.py — Minimal S3 file transfer helper.

Supports two commands:
  - get : download an S3 object to a local file
  - put : upload a local file to an S3 object

Usage:
  python s3io.py get s3://bucket/key LOCAL
  python s3io.py put LOCAL s3://bucket/key

Dependencies:
  - boto3 (AWS SDK for Python)
  - AWS credentials must be configured in environment or via ~/.aws/credentials

Notes:
  - Exits with code 2 on bad input/usage.
  - Creates local directories automatically when downloading.
"""

# ── Stdlib imports ─────────────────────────────────────────────────────────────
import sys
import os
import urllib.parse as up

# ── External deps ─────────────────────────────────────────────────────────────
import boto3


# ──────────────────────────────────────────────────────────────────────────────
# parse_s3(uri: str) -> (bucket, key)
# Utility function to validate and parse an S3 URI into bucket and key parts.
# Raises ValueError if the URI is invalid or missing components.
# ──────────────────────────────────────────────────────────────────────────────
def parse_s3(uri: str):
    if not uri.startswith("s3://"):
        raise ValueError("Not an S3 URI")

    p = up.urlparse(uri)
    bucket, key = p.netloc, p.path.lstrip("/")

    if not bucket or not key:
        raise ValueError(f"Bad S3 URI: {uri}")

    return bucket, key


# ──────────────────────────────────────────────────────────────────────────────
# main()
# Command-line entrypoint.
# Expects one of:
#   s3io.py get s3://bucket/key LOCAL
#   s3io.py put LOCAL s3://bucket/key
# Uses boto3 under the hood for S3 transfer.
# ──────────────────────────────────────────────────────────────────────────────
def main():
    if len(sys.argv) < 2:
        print(
            "usage: s3io.py [get s3://b/k LOCAL] | [put LOCAL s3://b/k]",
            file=sys.stderr
        )
        sys.exit(2)

    cmd = sys.argv[1]
    s3 = boto3.client("s3")

    if cmd == "get":
        if len(sys.argv) != 4:
            print("usage: s3io.py get s3://bucket/key LOCAL", file=sys.stderr)
            sys.exit(2)

        s3_uri, local = sys.argv[2], sys.argv[3]
        b, k = parse_s3(s3_uri)

        # Ensure parent directory exists before writing
        os.makedirs(os.path.dirname(local) or ".", exist_ok=True)

        s3.download_file(b, k, local)
        print(f"[s3io] downloaded {s3_uri} -> {local}")

    elif cmd == "put":
        if len(sys.argv) != 4:
            print("usage: s3io.py put LOCAL s3://bucket/key", file=sys.stderr)
            sys.exit(2)

        local, s3_uri = sys.argv[2], sys.argv[3]
        b, k = parse_s3(s3_uri)

        s3.upload_file(local, b, k)
        print(f"[s3io] uploaded {local} -> {s3_uri}")

    else:
        print("unknown command", file=sys.stderr)
        sys.exit(2)


# ──────────────────────────────────────────────────────────────────────────────
# Standard Python entrypoint guard
# ──────────────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    main()
