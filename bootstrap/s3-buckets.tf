# =============================================================================
# S3 Vector Storage Buckets
# =============================================================================
# This file creates S3 buckets for vector embeddings storage at the bootstrap level.
# Multiple buckets can be created using the bucket_suffixes variable.
#
# Pattern:
#   - Buckets are created per environment: {project}-{suffix} (e.g., gustavo-vector-embeddings)
#   - Bootstrap creates the bucket infrastructure
#   - Application terraform references buckets via remote state outputs
#
# Security:
#   - Versioning enabled for data protection
#   - Encryption at rest (AES256)
#   - Public access blocked
#   - Lifecycle policies for cost optimization
# =============================================================================

# 1. Base Bucket Creation (using for_each for multiple buckets)
resource "aws_s3_bucket" "vector" {
  for_each = var.enable_s3vector ? var.bucket_suffixes : []

  bucket = "${var.project_name}-${each.key}"

  tags = merge(
    local.common_tags,
    {
      Name    = "${var.project_name}-${each.key}"
      Service = "s3vector"
      Purpose = "vector-storage"
    }
  )
}

# 2. Enable Versioning (protects against accidental deletions)
resource "aws_s3_bucket_versioning" "vector" {
  for_each = var.enable_s3vector ? var.bucket_suffixes : []

  bucket = aws_s3_bucket.vector[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

# 3. Enable Encryption at Rest
resource "aws_s3_bucket_server_side_encryption_configuration" "vector" {
  for_each = var.enable_s3vector ? var.bucket_suffixes : []

  bucket = aws_s3_bucket.vector[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 4. Block Public Access
resource "aws_s3_bucket_public_access_block" "vector" {
  for_each = var.enable_s3vector ? var.bucket_suffixes : []

  bucket = aws_s3_bucket.vector[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 5. Lifecycle Policy for Cost Optimization
resource "aws_s3_bucket_lifecycle_configuration" "vector" {
  for_each = var.enable_s3vector ? var.bucket_suffixes : []

  bucket = aws_s3_bucket.vector[each.key].id

  # Transition old versions to cheaper storage
  rule {
    id     = "archive-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 180
    }
  }

  # Clean up incomplete multipart uploads
  rule {
    id     = "cleanup-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
