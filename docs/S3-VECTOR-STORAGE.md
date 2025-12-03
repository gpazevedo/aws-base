# S3 Vector Storage Integration

Store vector embeddings (OpenAI, Anthropic, etc.) in S3 with your Lambda/AppRunner services.

---

## Quick Start

### 1. Verify Bootstrap

```bash
cd bootstrap
terraform output s3_vector_service_policy_arn
# Output: arn:aws:iam::ACCOUNT_ID:policy/${PROJECT_NAME}-s3-vector-service-access
```

### 2. Create Buckets

```bash
cd terraform
cp s3-vectors-example.tf.example s3-vectors.tf
terraform apply -var-file=environments/${ENV}.tfvars
```

### 3. Use in Application

```python
import boto3
s3 = boto3.client("s3")

# Store vector
s3.put_object(
    Bucket="${PROJECT_NAME}-${ENV}-vector-${PURPOSE}",
    Key=f"embeddings/{id}.json",
    Body=json.dumps({"embedding": [0.1, 0.2, ...]})
)

# Retrieve vector
response = s3.get_object(Bucket=bucket, Key=f"embeddings/{id}.json")
embedding = json.loads(response["Body"].read())["embedding"]
```

---

## Architecture

```text
GitHub Actions (Deployment)
  ├─ Policy: s3_vector_management
  ├─ Creates: S3 buckets matching ${PROJECT_NAME}-*-vector-*
  └─ Cannot: Access objects

S3 Buckets: ${PROJECT_NAME}-${ENV}-vector-${PURPOSE}
  ├─ Encryption: AES256/KMS
  ├─ Versioning: Enabled
  └─ Lifecycle: Archive old versions → Glacier

Lambda/AppRunner (Runtime)
  ├─ Policy: s3_vector_service_access
  ├─ Can: Get/Put/Delete objects
  └─ Cannot: Create/configure buckets
```

---

## Two-Layer Permissions

### Layer 1: Deployment (GitHub Actions)

**Policy**: `s3_vector_management` (auto-attached in `bootstrap/s3vector.tf`)

| Permission | Resource Pattern | Purpose |
|------------|------------------|---------|
| Create/Delete buckets | `${PROJECT_NAME}-*-vector-*` | Infrastructure deployment |
| Configure encryption/lifecycle | Same | Bucket settings |
| **No object access** | N/A | Security boundary |

### Layer 2: Runtime (Services)

**Policy**: `s3_vector_service_access` (attach in `terraform/s3-vectors.tf`)

| Permission | Resource Pattern | Purpose |
|------------|------------------|---------|
| GetObject, PutObject | `${PROJECT_NAME}-*-vector-*/*` | Read/write embeddings |
| DeleteObject, ListBucket | Same | Manage embeddings |
| **No bucket creation** | N/A | Security boundary |

---

## Integration Steps

### Step 1: Create Buckets (terraform/s3-vectors.tf)

```hcl
resource "aws_s3_bucket" "${SERVICE}_embeddings_vector" {
  bucket = "${var.project_name}-${var.environment}-vector-${SERVICE}-embeddings"
}

# Enable versioning + encryption + public access block
# (See terraform/s3-vectors-example.tf.example for complete config)
```

### Step 2: Attach Policy to Service Role

```hcl
# Reference bootstrap outputs
data "terraform_remote_state" "bootstrap" {
  backend = "s3"
  config = {
    bucket = var.terraform_state_bucket
    key    = "bootstrap/terraform.tfstate"
    region = var.aws_region
  }
}

# Attach to Lambda
resource "aws_iam_role_policy_attachment" "lambda_${SERVICE}_s3_vectors" {
  role       = aws_iam_role.lambda_${SERVICE}.name
  policy_arn = data.terraform_remote_state.bootstrap.outputs.s3_vector_service_policy_arn
}

# OR attach to AppRunner
resource "aws_iam_role_policy_attachment" "apprunner_${SERVICE}_s3_vectors" {
  role       = aws_iam_role.apprunner_instance_${SERVICE}.name
  policy_arn = data.terraform_remote_state.bootstrap.outputs.s3_vector_service_policy_arn
}
```

### Step 3: Set Environment Variables

```hcl
# Lambda
resource "aws_lambda_function" "${SERVICE}" {
  environment {
    variables = {
      VECTOR_BUCKET_NAME = aws_s3_bucket.${SERVICE}_embeddings_vector.id
    }
  }
}

# AppRunner
resource "aws_apprunner_service" "${SERVICE}" {
  source_configuration {
    image_repository {
      image_configuration {
        runtime_environment_variables = {
          VECTOR_BUCKET_NAME = aws_s3_bucket.${SERVICE}_embeddings_vector.id
        }
      }
    }
  }
}
```

### Step 4: Application Code

```python
import boto3
import json
import structlog
from botocore.exceptions import ClientError
from pydantic_settings import BaseSettings

logger = structlog.get_logger()

class Settings(BaseSettings):
    vector_bucket_name: str = ""
    aws_region: str = "us-east-1"

settings = Settings()
s3 = boto3.client("s3", region_name=settings.aws_region)

def store_embedding(id: str, embedding: list[float]) -> None:
    """Store vector embedding in S3."""
    try:
        s3.put_object(
            Bucket=settings.vector_bucket_name,
            Key=f"embeddings/{id}.json",
            Body=json.dumps({"id": id, "embedding": embedding}),
            ContentType="application/json"
        )
        logger.info("vector_stored", id=id, dimension=len(embedding))
    except ClientError as e:
        logger.error("vector_store_failed", id=id, error=e.response["Error"]["Code"])
        raise

def retrieve_embedding(id: str) -> list[float]:
    """Retrieve vector embedding from S3."""
    try:
        response = s3.get_object(
            Bucket=settings.vector_bucket_name,
            Key=f"embeddings/{id}.json"
        )
        data = json.loads(response["Body"].read())
        logger.info("vector_retrieved", id=id, dimension=len(data["embedding"]))
        return data["embedding"]
    except s3.exceptions.NoSuchKey:
        logger.warning("vector_not_found", id=id)
        raise
    except ClientError as e:
        logger.error("vector_retrieve_failed", id=id, error=e.response["Error"]["Code"])
        raise
```

---

## Security Best Practices

### Bucket Naming

```text
Pattern: ${PROJECT_NAME}-${ENV}-vector-${PURPOSE}

Examples:
  ${PROJECT_NAME}-dev-vector-user-embeddings
  ${PROJECT_NAME}-prod-vector-doc-embeddings
```

### Encryption

```hcl
# AES256 (default)
resource "aws_s3_bucket_server_side_encryption_configuration" "vector" {
  bucket = aws_s3_bucket.vector.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# KMS (production)
resource "aws_s3_bucket_server_side_encryption_configuration" "vector" {
  bucket = aws_s3_bucket.vector.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.vector.arn
    }
  }
}
```

### Lifecycle Policy

```hcl
resource "aws_s3_bucket_lifecycle_configuration" "vector" {
  bucket = aws_s3_bucket.vector.id

  rule {
    id     = "archive-old-versions"
    status = "Enabled"

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER_IR"  # 83% cost savings
    }

    noncurrent_version_expiration {
      noncurrent_days = 180
    }
  }
}
```

---

## Cost Optimization

### Storage Classes

| Class | Cost/GB/Month | Use Case |
|-------|---------------|----------|
| S3 Standard | $0.023 | Active embeddings |
| Glacier IR | $0.004 | Historical (83% savings) |

### Example Cost (1M users × 1536-dim vectors = 6GB)

- **S3 Standard**: $0.14/month
- **With Glacier lifecycle**: $0.02/month (86% savings)

### Compression

```python
import gzip

def store_compressed(id: str, embedding: list[float]) -> None:
    data = gzip.compress(json.dumps({"embedding": embedding}).encode())
    s3.put_object(
        Bucket=settings.vector_bucket_name,
        Key=f"embeddings/{id}.json.gz",
        Body=data,
        ContentEncoding="gzip"
    )
```

---

## Troubleshooting

### Access Denied

**Cause**: Service role missing `s3_vector_service_access` policy

**Fix**:

```bash
# Verify policy attached
aws iam list-attached-role-policies --role-name ${PROJECT_NAME}-${ENV}-lambda-${SERVICE}-role

# If missing, check terraform/s3-vectors.tf has policy attachment
terraform apply -var-file=environments/${ENV}.tfvars
```

### Cannot Create Bucket

**Cause**: GitHub Actions role missing `s3_vector_management` policy

**Fix**:

```bash
cd bootstrap
terraform output s3_vector_management_policy_arn
# If null, apply bootstrap
terraform apply
```

### NoSuchKey Error

**Cause**: Embedding doesn't exist

**Fix**:

```python
try:
    embedding = retrieve_embedding(id)
except s3.exceptions.NoSuchKey:
    embedding = generate_embedding(text)  # Generate new
    store_embedding(id, embedding)
```

---

## Complete Example

See [`terraform/s3-vectors-example.tf.example`](../terraform/s3-vectors-example.tf.example) for:

- Full bucket configuration with versioning, encryption, lifecycle
- Policy attachments for Lambda and AppRunner
- Environment variable setup
- Complete security settings

---

**Related**: [AWS Services Integration](AWS-SERVICES-INTEGRATION.md) · [Adding Services](ADDING-SERVICES.md)
