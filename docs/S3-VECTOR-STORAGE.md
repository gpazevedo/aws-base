# S3 Vector Storage + Amazon Bedrock Embeddings

Store and generate vector embeddings using S3 storage and Amazon Bedrock Titan models with your Lambda/AppRunner services.

---

## S3 Vector Quick Start

### 1. Verify Bootstrap

```bash
cd bootstrap
terraform output s3_vector_service_policy_arn
# Output: arn:aws:iam::ACCOUNT_ID:policy/${PROJECT_NAME}-s3-vector-service-access
```

### 2. Create Buckets

```bash
cd terraform
cp s3-vectors.tf.example s3-vectors.tf
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
# (See terraform/s3-vectors.tf.example for complete config)
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
    # Note: AWS_REGION is automatically provided by Lambda runtime
    # No need to set it explicitly

settings = Settings()
# AWS SDK automatically uses AWS_REGION environment variable
s3 = boto3.client("s3")

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

See [`terraform/s3-vectors.tf.example`](../terraform/s3-vectors.tf.example) for:

- Full bucket configuration with versioning, encryption, lifecycle
- Policy attachments for Lambda and AppRunner
- Environment variable setup
- Complete security settings

---

## Amazon Bedrock Embeddings Integration

### Overview

Generate embeddings using Amazon Bedrock Titan Text Embeddings V2 and store them in S3 for retrieval and semantic search.

**Key Advantages:**
- ✅ **No Infrastructure**: Serverless, no endpoints to manage
- ✅ **Pay-Per-Use**: Only pay for embeddings generated (~$2 per 1M)
- ✅ **High Quality**: 1024-dimensional vectors for superior semantic search
- ✅ **Instant Availability**: No deployment wait time
- ✅ **Auto-Scaling**: Handles any request volume automatically

```text
┌─────────────────────────────────────────────────────────────┐
│ Application Flow                                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Text Input                                                 │
│       │                                                     │
│       ├─> Amazon Bedrock Titan V2 (Generate Embedding)      │
│       │        │                                            │
│       │        └─> [0.1, 0.2, ..., 0.9] (1024 dims)         │
│       │                                                     │
│       └─> S3 Vector Bucket (Store Embedding)                │
│                │                                            │
│                └─> embeddings/{id}.json                     │
│                                                             │
│  Query                                                      │
│       │                                                     │
│       ├─> S3 Vector Bucket (Retrieve Embeddings)            │
│       │        │                                            │
│       │        └─> Calculate Similarity                     │
│       │                │                                    │
│       │                └─> Return Top K Results             │
└─────────────────────────────────────────────────────────────┘
```

### Bedrock Quick Start

#### 1. No Infrastructure Needed!

Bedrock is a fully managed service with no endpoint deployment required. The service is ready to use immediately.

#### 2. Use in Application

```python
import boto3
import json
import structlog
from pydantic_settings import BaseSettings

logger = structlog.get_logger()

class Settings(BaseSettings):
    bedrock_model_id: str = "amazon.titan-embed-text-v2:0"
    vector_bucket_name: str = ""
    # Note: AWS_REGION is automatically provided by Lambda runtime

settings = Settings()
# AWS SDK automatically uses AWS_REGION environment variable
bedrock = boto3.client("bedrock-runtime")
s3 = boto3.client("s3")

def generate_embedding(text: str) -> list[float]:
    """Generate embedding using Amazon Bedrock Titan."""
    response = bedrock.invoke_model(
        modelId=settings.bedrock_model_id,
        contentType="application/json",
        accept="application/json",
        body=json.dumps({"inputText": text})
    )

    result = json.loads(response["body"].read())
    embedding = result["embedding"]

    logger.info("embedding_generated", text_length=len(text), dimension=len(embedding))
    return embedding

def store_embedding(id: str, text: str, embedding: list[float]) -> None:
    """Store embedding in S3."""
    s3.put_object(
        Bucket=settings.vector_bucket_name,
        Key=f"embeddings/{id}.json",
        Body=json.dumps({
            "id": id,
            "text": text,
            "embedding": embedding,
            "dimension": len(embedding)
        }),
        ContentType="application/json"
    )
    logger.info("embedding_stored", id=id, dimension=len(embedding))

def generate_and_store_embedding(id: str, text: str) -> None:
    """Generate embedding and store in S3 (combined operation)."""
    embedding = generate_embedding(text)
    store_embedding(id, text, embedding)

def retrieve_embedding(id: str) -> list[float]:
    """Retrieve embedding from S3."""
    response = s3.get_object(
        Bucket=settings.vector_bucket_name,
        Key=f"embeddings/{id}.json"
    )
    data = json.loads(response["Body"].read())
    return data["embedding"]
```

### Bedrock Architecture

```text
GitHub Actions (Deployment)
  └─ Policy: s3_vector_management
      └─ Creates: S3 buckets matching ${PROJECT_NAME}-*-vector-*

S3 Buckets: ${PROJECT_NAME}-${ENV}-vector-${PURPOSE}
  ├─ Encryption: AES256/KMS
  ├─ Versioning: Enabled
  └─ Lifecycle: Archive old versions → Glacier

Amazon Bedrock: Fully Managed Service
  ├─ Model: Titan Text Embeddings V2
  ├─ Dimensions: 1024 (state-of-the-art quality)
  ├─ Max Tokens: 8,192 per request
  └─ Infrastructure: Fully managed, no deployment needed

Lambda/AppRunner (Runtime)
  ├─ Policy: s3_vector_service_access
  │   └─ Can: Get/Put/Delete objects in S3
  ├─ Policy: bedrock_invocation
  │   └─ Can: Invoke Bedrock foundation models
  └─ Cannot: Create/configure infrastructure
```

### Available Bedrock Models

| Model | Dimensions | Use Case | Quality |
|-------|-----------|----------|---------|
| Titan Text Embeddings V2 | 1024 | General purpose, high-quality semantic search | Excellent |
| Titan Text Embeddings V1 | 1536 | Legacy option, larger vectors | Very Good |

### Cost Information

#### Amazon Bedrock (Pay-Per-Use)

| Metric | Price | Example Cost |
|--------|-------|--------------|
| Per 1,000 input tokens | $0.00002 | 1M texts (100 tokens avg) = $2.00 |
| Per embedding request | $0.000002 | 1M requests = $2.00 |

**Advantages:**

- ✅ No hourly charges
- ✅ No cold starts
- ✅ Instant availability
- ✅ Auto-scaling to any volume
- ✅ Pay only for what you use

**Example monthly costs:**

- **1M embeddings/month:** $2.00
- **10M embeddings/month:** $20.00
- **100M embeddings/month:** $200.00

### Bedrock Integration Steps

#### Step 1: No Infrastructure Deployment Needed

Bedrock is a fully managed service - no endpoints to deploy or infrastructure to manage. The service is ready to use immediately!

#### Step 2: Attach Bedrock Invocation Policy

The bootstrap already created the policy. Just attach it to your service role:

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
resource "aws_iam_role_policy_attachment" "lambda_s3vector_bedrock" {
  role       = data.aws_iam_role.lambda_execution_s3vector.name
  policy_arn = data.terraform_remote_state.bootstrap.outputs.bedrock_invocation_policy_arn
}

# OR attach to AppRunner
resource "aws_iam_role_policy_attachment" "apprunner_runner_bedrock" {
  role       = aws_iam_role.apprunner_instance_runner.name
  policy_arn = data.terraform_remote_state.bootstrap.outputs.bedrock_invocation_policy_arn
}
```

#### Step 3: Set Environment Variables

```hcl
# Lambda - using locals block
locals {
  s3vector_config = {
    bedrock_model_id   = "amazon.titan-embed-text-v2:0"
    vector_bucket_name = "${var.project_name}-${var.environment}-vector-embeddings"
  }
}

resource "aws_lambda_function" "s3vector" {
  environment {
    variables = {
      BEDROCK_MODEL_ID   = local.s3vector_config.bedrock_model_id
      VECTOR_BUCKET_NAME = local.s3vector_config.vector_bucket_name
      # AWS_REGION is automatically provided by Lambda runtime
    }
  }
}

# AppRunner
resource "aws_apprunner_service" "runner" {
  source_configuration {
    image_repository {
      image_configuration {
        runtime_environment_variables = {
          BEDROCK_MODEL_ID   = "amazon.titan-embed-text-v2:0"
          VECTOR_BUCKET_NAME = aws_s3_bucket.embeddings_vector.id
          AWS_REGION         = var.aws_region  # AppRunner requires explicit region
        }
      }
    }
  }
}
```

### Complete Example: Semantic Search with Bedrock

```python
import boto3
import json
import numpy as np
from typing import List, Tuple

class EmbeddingService:
    """Service for generating and managing embeddings with Amazon Bedrock."""

    def __init__(self, bucket_name: str, region: str = "us-east-1", model_id: str = "amazon.titan-embed-text-v2:0"):
        self.bucket_name = bucket_name
        self.model_id = model_id
        self.bedrock = boto3.client("bedrock-runtime", region_name=region)
        self.s3 = boto3.client("s3", region_name=region)

    def generate_embedding(self, text: str) -> List[float]:
        """Generate embedding for text using Amazon Bedrock."""
        body = json.dumps({"inputText": text})

        response = self.bedrock.invoke_model(
            modelId=self.model_id,
            contentType="application/json",
            accept="application/json",
            body=body
        )

        result = json.loads(response["body"].read())
        return result["embedding"]

    def store_document(self, doc_id: str, text: str, metadata: dict = None) -> None:
        """Generate and store document embedding."""
        embedding = self.generate_embedding(text)

        document = {
            "id": doc_id,
            "text": text,
            "embedding": embedding,
            "metadata": metadata or {},
            "dimension": len(embedding)
        }

        self.s3.put_object(
            Bucket=self.bucket_name,
            Key=f"embeddings/{doc_id}.json",
            Body=json.dumps(document),
            ContentType="application/json"
        )

    def cosine_similarity(self, a: List[float], b: List[float]) -> float:
        """Calculate cosine similarity between two vectors."""
        a_np = np.array(a)
        b_np = np.array(b)
        return float(np.dot(a_np, b_np) / (np.linalg.norm(a_np) * np.linalg.norm(b_np)))

    def search(self, query: str, top_k: int = 5) -> List[Tuple[str, float, str]]:
        """Search for similar documents."""
        # Generate query embedding
        query_embedding = self.generate_embedding(query)

        # List all embeddings in S3
        response = self.s3.list_objects_v2(
            Bucket=self.bucket_name,
            Prefix="embeddings/"
        )

        # Calculate similarities
        results = []
        for obj in response.get("Contents", []):
            # Retrieve document
            doc_response = self.s3.get_object(
                Bucket=self.bucket_name,
                Key=obj["Key"]
            )
            doc = json.loads(doc_response["Body"].read())

            # Calculate similarity
            similarity = self.cosine_similarity(query_embedding, doc["embedding"])
            results.append((doc["id"], similarity, doc["text"]))

        # Sort by similarity and return top K
        results.sort(key=lambda x: x[1], reverse=True)
        return results[:top_k]

# Usage
service = EmbeddingService(
    bucket_name="fin-advisor-dev-vector-documents"
)

# Index documents
service.store_document("doc1", "Python is a programming language", {"category": "tech"})
service.store_document("doc2", "Machine learning uses algorithms", {"category": "tech"})
service.store_document("doc3", "Cats are popular pets", {"category": "animals"})

# Search
results = service.search("coding in python", top_k=2)
for doc_id, similarity, text in results:
    print(f"{doc_id}: {similarity:.3f} - {text}")
```

### Permissions Reference

#### Bootstrap Policies (Automatic)

| Policy | Attached To | Permissions |
|--------|-------------|-------------|
| `bedrock_invocation` | Manual (see below) | Invoke Bedrock models |
| `s3_vector_management` | GitHub Actions | Create/delete buckets |
| `s3_vector_service_access` | Manual (see below) | Read/write objects |

#### Service Role Attachments (Manual in terraform/)

```hcl
# Attach S3 and Bedrock policies to service roles
resource "aws_iam_role_policy_attachment" "service_s3_vectors" {
  role       = aws_iam_role.service.name
  policy_arn = data.terraform_remote_state.bootstrap.outputs.s3_vector_service_policy_arn
}

resource "aws_iam_role_policy_attachment" "service_bedrock" {
  role       = aws_iam_role.service.name
  policy_arn = data.terraform_remote_state.bootstrap.outputs.bedrock_invocation_policy_arn
}
```

### Bedrock Troubleshooting

#### Invocation Access Denied

**Error**: `AccessDeniedException: User is not authorized to perform: bedrock:InvokeModel`

**Cause**: Service role missing `bedrock_invocation` policy

**Fix**:

```bash
# Verify policy attached
aws iam list-attached-role-policies --role-name ${PROJECT_NAME}-${ENV}-lambda-api-role

# If missing, check terraform configuration has policy attachment
terraform apply -var-file=environments/${ENV}.tfvars
```

#### Model Not Available

**Error**: `ValidationException: The provided model identifier is invalid`

**Cause**: Model not available in your AWS region or account doesn't have access

**Fix**:

```bash
# Check available models in your region
aws bedrock list-foundation-models --region us-east-1

# Ensure Bedrock model access is enabled in AWS Console
# Go to Amazon Bedrock console → Model access → Request access
```

---

**Related**: [AWS Services Integration](AWS-SERVICES-INTEGRATION.md) · [Adding Services](ADDING-SERVICES.md)
