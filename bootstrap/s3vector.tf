# =============================================================================
# S3 Vector Storage Infrastructure
# =============================================================================
# This file defines IAM policies for S3 vector storage buckets:
#   1. GitHub Actions S3 Vector Management Policy - Allows Terraform to create/manage S3 vector buckets
#   2. S3 Vector Service Access Policy - Reusable policy for Lambda/AppRunner to access vector buckets
#
# Pattern:
#   - Management permissions go to GitHub Actions roles (create/delete buckets)
#   - Service permissions are outputs that application terraform attaches to service roles
# =============================================================================

# =============================================================================
# 1. GitHub Actions S3 Vector Management Policy
# =============================================================================
# Purpose: Allow GitHub Actions to create and manage S3 buckets for vector storage
# Attached to: GitHub Actions deployment roles (dev, test, prod)
# Used by: Terraform during infrastructure deployment
#
# Permissions:
#   - Create/Delete S3 buckets with naming pattern: ${project_name}-{env}-vector-*
#   - Configure bucket settings (versioning, encryption, lifecycle, CORS, etc.)
#   - Manage bucket policies and public access blocks
#   - List all buckets (required for Terraform state reconciliation)
#
# Security:
#   - Resource constraints: Only buckets matching ${project_name}-*-vector-* pattern
#   - Follows least privilege principle
#   - Separated from application service permissions
# =============================================================================

resource "aws_iam_policy" "s3_vector_management" {
  count = var.enable_s3vector ? 1 : 0

  name        = "${var.project_name}-s3-vector-management"
  description = "Allows GitHub Actions to manage S3 vector storage buckets for ${var.project_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 Bucket Management - Creation, Deletion, and Configuration
      {
        Effect = "Allow"
        Action = [
          # Bucket lifecycle
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:ListBucket",
          "s3:GetBucketLocation",

          # Versioning
          "s3:GetBucketVersioning",
          "s3:PutBucketVersioning",

          # Bucket policies and permissions
          "s3:GetBucketPolicy",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy",
          "s3:GetBucketPolicyStatus",

          # Public access block settings
          "s3:GetBucketPublicAccessBlock",
          "s3:PutBucketPublicAccessBlock",

          # Tagging
          "s3:GetBucketTagging",
          "s3:PutBucketTagging",

          # Encryption configuration
          "s3:GetEncryptionConfiguration",
          "s3:PutEncryptionConfiguration",

          # CORS configuration (for browser-based access if needed)
          "s3:GetBucketCORS",
          "s3:PutBucketCORS",
          "s3:DeleteBucketCORS",

          # Lifecycle policies (for cost optimization)
          "s3:GetLifecycleConfiguration",
          "s3:PutLifecycleConfiguration",
          "s3:DeleteLifecycleConfiguration",

          # Logging
          "s3:GetBucketLogging",
          "s3:PutBucketLogging",

          # Object lock (for compliance if needed)
          "s3:GetBucketObjectLockConfiguration",
          "s3:PutBucketObjectLockConfiguration",

          # Replication (for disaster recovery if needed)
          "s3:GetReplicationConfiguration",
          "s3:PutReplicationConfiguration",

          # Metrics and analytics
          "s3:GetBucketNotification",
          "s3:PutBucketNotification",

          # Access control
          "s3:GetBucketAcl",
          "s3:PutBucketAcl"
        ]
        # Resource pattern: {project_name}-{env}-vector-* or {project_name}-vector-*
        # Examples: fin-advisor-dev-vector-embeddings, fin-advisor-prod-vector-store
        Resource = [
          "arn:aws:s3:::${var.project_name}-*-vector-*",
          "arn:aws:s3:::${var.project_name}-vector-*"
        ]
      },

      # List All Buckets - Required for Terraform state reconciliation
      {
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets",
          "s3:GetBucketLocation"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Purpose = "s3-vector-management"
      Layer   = "deployment"
    }
  )
}

# Attach to dev role
resource "aws_iam_role_policy_attachment" "dev_s3_vector_management" {
  count = var.enable_s3vector ? 1 : 0

  role       = aws_iam_role.github_actions_dev.name
  policy_arn = aws_iam_policy.s3_vector_management[0].arn
}

# Attach to test role
resource "aws_iam_role_policy_attachment" "test_s3_vector_management" {
  count = var.enable_s3vector && var.enable_test_environment ? 1 : 0

  role       = aws_iam_role.github_actions_test[0].name
  policy_arn = aws_iam_policy.s3_vector_management[0].arn
}

# Attach to prod role
resource "aws_iam_role_policy_attachment" "prod_s3_vector_management" {
  count = var.enable_s3vector ? 1 : 0

  role       = aws_iam_role.github_actions_prod.name
  policy_arn = aws_iam_policy.s3_vector_management[0].arn
}

# =============================================================================
# 2. S3 Vector Service Access Policy (Reusable Template)
# =============================================================================
# Purpose: Allow Lambda/AppRunner services to read and write vector embeddings
# Attached to: Service execution roles in application terraform (NOT in bootstrap)
# Used by: Application services that need to access vector storage
#
# Usage Pattern in Application Terraform:
#   1. Create specific S3 vector bucket(s) in terraform/s3-vectors.tf
#   2. Reference this policy ARN from bootstrap outputs
#   3. Attach to service-specific IAM roles
#   4. Pass bucket name(s) via environment variables
#
# Permissions:
#   - Read: GetObject, ListBucket (for retrieving vectors)
#   - Write: PutObject, DeleteObject (for storing/updating vectors)
#   - Multipart: For large vector file uploads
#
# Security:
#   - Resource constraints: Only buckets matching ${project_name}-*-vector-* pattern
#   - Read/Write access only (no bucket configuration changes)
#   - Suitable for service execution, not deployment
#
# Example Application Terraform Usage:
#   # In terraform/lambda-api.tf or terraform/apprunner-api.tf
#   resource "aws_iam_role_policy_attachment" "api_s3_vectors" {
#     role       = aws_iam_role.lambda_api.name
#     policy_arn = data.terraform_remote_state.bootstrap.outputs.s3_vector_service_policy_arn
#   }
#
#   # Set environment variable with specific bucket name
#   environment {
#     variables = {
#       VECTOR_BUCKET_NAME = aws_s3_bucket.embeddings_vector.id
#     }
#   }
# =============================================================================

resource "aws_iam_policy" "s3_vector_service_access" {
  count = var.enable_s3vector ? 1 : 0

  name        = "${var.project_name}-s3-vector-service-access"
  description = "Allows services to read/write vector embeddings to S3 buckets for ${var.project_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Object Operations - Read and Write
      {
        Effect = "Allow"
        Action = [
          # Read operations
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetObjectAttributes",
          "s3:GetObjectVersionAttributes",

          # Write operations
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion",

          # Multipart upload (for large vector files)
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts",

          # Metadata
          "s3:GetObjectTagging",
          "s3:PutObjectTagging"
        ]
        # Resource pattern: All objects in vector buckets
        # Examples: fin-advisor-dev-vector-embeddings/*, fin-advisor-prod-vector-store/*
        Resource = [
          "arn:aws:s3:::${var.project_name}-*-vector-*/*",
          "arn:aws:s3:::${var.project_name}-vector-*/*"
        ]
      },

      # Bucket Operations - List and Query
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning",
          "s3:ListBucketVersions",
          "s3:ListBucketMultipartUploads"
        ]
        # Resource pattern: Vector buckets only
        Resource = [
          "arn:aws:s3:::${var.project_name}-*-vector-*",
          "arn:aws:s3:::${var.project_name}-vector-*"
        ]
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Purpose = "s3-vector-service-access"
      Layer   = "execution"
    }
  )
}

# =============================================================================
# 3. Bedrock Model Access Policy
# =============================================================================
# Purpose: Allow services to invoke Bedrock foundation models
# Attached to: Service execution roles in application terraform (NOT in bootstrap)
# Used by: Application services that need to generate embeddings
#
# Permissions:
#   - Invoke Bedrock models (Titan Text Embeddings V2)
#   - List available foundation models
#
# Security:
#   - No infrastructure to manage (serverless)
#   - Pay-per-use pricing model
#   - No endpoint creation/deletion needed
# =============================================================================

resource "aws_iam_policy" "bedrock_invocation" {
  count = var.enable_s3vector ? 1 : 0

  name        = "${var.project_name}-bedrock-invocation"
  description = "Allows services to invoke Bedrock models for ${var.project_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Bedrock Model Invocation
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        # Allow invocation of Titan embedding models
        Resource = [
          "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0",
          "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v1"
        ]
      },

      # List Available Models (optional, for discovery)
      {
        Effect = "Allow"
        Action = [
          "bedrock:ListFoundationModels",
          "bedrock:GetFoundationModel"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Purpose = "bedrock-invocation"
      Layer   = "execution"
    }
  )
}

# =============================================================================
# Notes on Implementation Pattern
# =============================================================================
#
# Two-Layer Permission Model:
#
# Layer 1: GitHub Actions Management (This file)
#   - Purpose: Allow Terraform to create/manage S3 buckets
#   - Scope: Bucket-level operations (create, delete, configure)
#   - Attached to: GitHub Actions deployment roles
#   - Created in: bootstrap/ (this file)
#
# Layer 2: Service Access (Attached in application terraform)
#   - Purpose: Allow services to read/write vector data
#   - Scope: Object-level operations (get, put, delete objects)
#   - Attached to: Lambda/AppRunner service execution roles
#   - Referenced from: Application terraform via bootstrap outputs
#
# Workflow:
#   1. Bootstrap creates both policies
#   2. GitHub Actions roles get management policy automatically
#   3. Application terraform references service access policy ARN from outputs
#   4. Application terraform attaches service access policy to specific service roles
#   5. Application code uses bucket via environment variable
#
# Example Application Terraform:
#
#   # terraform/s3-vectors.tf
#   resource "aws_s3_bucket" "embeddings_vector" {
#     bucket = "${var.project_name}-${var.environment}-vector-embeddings"
#   }
#
#   # terraform/lambda-api.tf
#   data "terraform_remote_state" "bootstrap" {
#     backend = "s3"
#     config = { ... }
#   }
#
#   resource "aws_iam_role_policy_attachment" "api_s3_vectors" {
#     role       = aws_iam_role.lambda_api.name
#     policy_arn = data.terraform_remote_state.bootstrap.outputs.s3_vector_service_policy_arn
#   }
#
#   resource "aws_lambda_function" "api" {
#     environment {
#       variables = {
#         VECTOR_BUCKET_NAME = aws_s3_bucket.embeddings_vector.id
#       }
#     }
#   }
#
# Example Python Application Code:
#
#   import boto3
#   import structlog
#   from pydantic_settings import BaseSettings
#
#   class Settings(BaseSettings):
#       vector_bucket_name: str = ""
#       aws_region: str = "us-east-1"
#
#   settings = Settings()
#   logger = structlog.get_logger()
#   s3 = boto3.client("s3", region_name=settings.aws_region)
#
#   def store_vector_embedding(user_id: str, embedding: list[float]) -> None:
#       """Store vector embedding in S3."""
#       key = f"embeddings/{user_id}.json"
#       data = json.dumps({"user_id": user_id, "embedding": embedding})
#
#       s3.put_object(
#           Bucket=settings.vector_bucket_name,
#           Key=key,
#           Body=data,
#           ContentType="application/json"
#       )
#       logger.info("vector_stored", user_id=user_id, key=key)
#
#   def retrieve_vector_embedding(user_id: str) -> list[float]:
#       """Retrieve vector embedding from S3."""
#       key = f"embeddings/{user_id}.json"
#
#       response = s3.get_object(
#           Bucket=settings.vector_bucket_name,
#           Key=key
#       )
#
#       data = json.loads(response["Body"].read())
#       logger.info("vector_retrieved", user_id=user_id, key=key)
#       return data["embedding"]
#
# =============================================================================
# Security Best Practices
# =============================================================================
#
# 1. Bucket Naming Convention:
#    - Use pattern: ${project_name}-${environment}-vector-${purpose}
#    - Examples: fin-advisor-dev-vector-embeddings, fin-advisor-prod-vector-cache
#    - Benefits: Clear ownership, environment isolation, easy auditing
#
# 2. Encryption:
#    - Always enable server-side encryption (AES256 or KMS)
#    - Use KMS for production with customer-managed keys
#    - Example: sse_algorithm = "aws:kms"
#
# 3. Versioning:
#    - Enable versioning for vector storage buckets
#    - Protects against accidental deletions
#    - Allows rollback to previous embeddings
#
# 4. Lifecycle Policies:
#    - Transition old versions to cheaper storage (e.g., Glacier after 90 days)
#    - Set expiration for deleted markers
#    - Example: Expire non-current versions after 180 days
#
# 5. Access Logging:
#    - Enable S3 access logging for audit trails
#    - Store logs in separate bucket
#    - Useful for security analysis and compliance
#
# 6. Public Access:
#    - Block all public access by default
#    - Only use signed URLs for temporary access if needed
#    - Never make vector buckets publicly readable
#
# 7. CORS Configuration:
#    - Only enable if browser-based access is required
#    - Restrict allowed origins to specific domains
#    - Example: AllowedOrigins = ["https://app.example.com"]
#
# 8. Object Lock (Compliance):
#    - Enable for regulatory compliance requirements
#    - Prevents deletion/modification for retention period
#    - Example: Retention = 7 years for financial data
#
# 9. Monitoring:
#    - Set up CloudWatch metrics for bucket operations
#    - Create alarms for unexpected access patterns
#    - Monitor 4xx/5xx error rates
#
# 10. Cost Optimization:
#     - Use S3 Intelligent-Tiering for variable access patterns
#     - Compress vector data before storage
#     - Implement lifecycle policies to archive old embeddings
#
# =============================================================================
