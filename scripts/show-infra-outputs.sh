#!/bin/bash
# Print current Terraform outputs for every nonprod stack (read-only).
# Use this instead of copying IDs by hand — values change on every cluster rebuild.
#
# Usage: ./scripts/show-infra-outputs.sh [env]     (default: nonprod)
# Requires: terraform and AWS credentials with read access to the state bucket.
# Sensitive outputs are hidden by Terraform; nothing here writes or applies anything.

ENV="${1:-nonprod}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)/terraform/live/${ENV}"

[ -d "$ROOT" ] || { echo "No such environment: $ROOT" >&2; exit 1; }
command -v terraform >/dev/null || { echo "terraform not found in PATH" >&2; exit 1; }

for stack in "$ROOT"/*/; do
  name="$(basename "$stack")"
  dir="${stack}stacks"
  [ -d "$dir" ] || continue
  echo "════ ${name} ════"
  # 00-s3-backend bootstraps the remote state itself (local state) — never re-init it here.
  if [ "$name" != "00-s3-backend" ] && [ -f "${stack}backends/backend.hcl" ]; then
    terraform -chdir="$dir" init -input=false -reconfigure \
      -backend-config="../backends/backend.hcl" >/dev/null 2>&1 \
      || { echo "  (terraform init failed — skipping)"; echo; continue; }
  fi
  terraform -chdir="$dir" output 2>&1 || true
  echo
done
