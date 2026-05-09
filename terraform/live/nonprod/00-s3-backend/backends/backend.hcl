# ─────────────────────────────────────────────────────────────────────────────
# 00-s3-backend/backends/backend.hcl
#
# Bootstrap problem: this stack CREATES the S3 bucket that all other stacks
# use for remote state. But this stack itself needs somewhere to store ITS
# state before that bucket exists.
#
# Solution: this stack uses LOCAL state (terraform.tfstate on disk).
# All other stacks (10-network onward) use S3 remote state.
#
# After first apply:
#   - S3 bucket exists: churn-mlops-artifacts (reusing artifacts bucket)
#   - DynamoDB table exists: churn-mlops-nonprod-terraform-locks
#   - terraform.tfstate sits locally in this directory
#   - Commit terraform.tfstate to git OR manually back it up to S3
#     after the bucket is created.
#
# backend = local - no remote config needed here.
# ─────────────────────────────────────────────────────────────────────────────
