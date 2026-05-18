# S3 staging bucket for the amazon.aws.aws_ssm Ansible connection plugin.
#
# Spec: specs/003-ansible-node-exporter/research.md Finding 2 (IAM/S3 gaps
#       are preconditions for the Ansible layer) and plan.md §Decision 3.
#
# Lifecycle decisions:
#   - Versioning OFF: payloads are ephemeral, no point retaining them.
#   - 1-day expiry: SSM uploads + downloads happen within seconds; anything
#                   older than a day is leftover and should be reaped.
#   - Block all public access.
#   - SSE-S3 default encryption (AES256). KMS is overkill for ephemeral
#     payloads and complicates the SSM agent's IAM grant.

locals {
  # One bucket per (account, region, versionmesh). Blue/green cutovers keep
  # their staging surfaces independent; each mesh's instance-profile role
  # only ever sees its own bucket.
  bucket_name = "compute-ansible-${var.account_id}-${var.region}-${var.versionmesh}-ansible-ssm"
}

resource "aws_s3_bucket" "ssm_staging" {
  bucket        = local.bucket_name
  force_destroy = true # ephemeral staging — safe to destroy with contents

  tags = merge(var.tags, {
    Name    = local.bucket_name
    Purpose = "ansible-ssm-staging"
  })
}

# Explicit versioning = OFF (cheaper, and we never need history of ephemeral payloads)
resource "aws_s3_bucket_versioning" "ssm_staging" {
  bucket = aws_s3_bucket.ssm_staging.id

  versioning_configuration {
    status = "Disabled"
  }
}

# Block all public access (defense in depth — the bucket policy below
# explicitly only grants two principals)
resource "aws_s3_bucket_public_access_block" "ssm_staging" {
  bucket = aws_s3_bucket.ssm_staging.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Server-side encryption (SSE-S3 / AES256)
resource "aws_s3_bucket_server_side_encryption_configuration" "ssm_staging" {
  bucket = aws_s3_bucket.ssm_staging.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle: expire any object older than 1 day. SSM staging payloads should
# never live longer than the run that created them.
resource "aws_s3_bucket_lifecycle_configuration" "ssm_staging" {
  bucket = aws_s3_bucket.ssm_staging.id

  rule {
    id     = "expire-ephemeral-ssm-payloads"
    status = "Enabled"

    filter {} # apply to all objects in the bucket

    expiration {
      days = 1
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# Bucket policy: allow the EC2 instance-profile role (so the SSM agent on
# each target host can stage/retrieve payloads during a playbook run).
#
# Note: The OIDC role (which the GitHub Actions runner assumes) is NOT
# granted here — it already has s3:* on `compute-ansible-*` buckets via
# the existing `s3_data_buckets` policy in aws/terraform/modules/oidc/main.tf.
# Adding it again here would be a no-op at best and a confusing duplicate
# at worst.
data "aws_iam_policy_document" "ssm_staging" {
  statement {
    sid    = "AllowEc2InstanceProfileForSsmAgent"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [var.ec2_instance_role_arn]
    }

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]

    resources = [
      aws_s3_bucket.ssm_staging.arn,
      "${aws_s3_bucket.ssm_staging.arn}/*",
    ]
  }
}

resource "aws_s3_bucket_policy" "ssm_staging" {
  bucket = aws_s3_bucket.ssm_staging.id
  policy = data.aws_iam_policy_document.ssm_staging.json

  # The public-access-block must be applied first or the policy attach can
  # race with it.
  depends_on = [aws_s3_bucket_public_access_block.ssm_staging]
}
