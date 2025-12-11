# S3 Vector Storage + Amazon Bedrock Embeddings

Store and generate vector embeddings using S3 storage and Amazon Bedrock Titan models.

---

## Quick Start

### 1. Enable in Bootstrap

Edit `bootstrap/terraform.tfvars`:

```hcl
enable_s3vector = true
bucket_suffixes = ["vector-embeddings"]  # Add more as needed
```

Apply:

```bash
cd bootstrap
terraform apply
```

Creates:

- S3 buckets: `{project}-vector-embeddings`
- IAM policies for S3 + Bedrock
- Auto-attached to GitHub Actions roles

### 2. Configure Service

In `terraform/lambda-api.tf`:

```hcl
# Get bootstrap outputs
data "terraform_remote_state" "bootstrap" {
  backend = "s3"
  config = {
    bucket = "{project}-terraform-state-{account_id}"
    key    = "bootstrap/terraform.tfstate"
    region = "us-east-1"
  }
}

# Attach policies
resource "aws_iam_role_policy_attachment" "api_s3_vectors" {
  role       = aws_iam_role.lambda_api.name
  policy_arn = data.terraform_remote_state.bootstrap.outputs.s3_vector_service_policy_arn
}

resource "aws_iam_role_policy_attachment" "api_bedrock" {
  role       = aws_iam_role.lambda_api.name
  policy_arn = data.terraform_remote_state.bootstrap.outputs.bedrock_invocation_policy_arn
}

# Set environment
resource "aws_lambda_function" "api" {
  environment {
    variables = {
      VECTOR_BUCKET_NAME = data.terraform_remote_state.bootstrap.outputs.s3_vector_bucket_ids["vector-embeddings"]
      BEDROCK_MODEL_ID   = "amazon.titan-embed-text-v2:0"
    }
  }
}
```

### 3. Add Code to Service

See [Complete Implementation](#add-to-existing-service) below.

---

## Create New S3 Vector Bucket

**Option 1**: Add suffix to bootstrap

Edit `bootstrap/terraform.tfvars`:

```hcl
bucket_suffixes = ["vector-embeddings", "vector-api-cache"]  # Add new suffix
```

Apply:

```bash
cd bootstrap
terraform apply
```

**Option 2**: Use existing bucket

Just reference it in terraform:

```hcl
VECTOR_BUCKET_NAME = data.terraform_remote_state.bootstrap.outputs.s3_vector_bucket_ids["vector-embeddings"]
```

---

## Add to Existing Service

Add these to your `backend/{service}/main.py`:

### 1. Dependencies

```python
import boto3
import json
from botocore.exceptions import ClientError
```

### 2. Settings

```python
from pydantic import BaseModel, Field

class Settings(BaseSettings):
    # ...existing settings...
    bedrock_model_id: str = "amazon.titan-embed-text-v2:0"
    vector_bucket_name: str = ""

settings = Settings()
```

### 3. AWS Clients

```python
class AWSClients:
    _bedrock = None
    _s3 = None

    @property
    def bedrock(self):
        if self._bedrock is None:
            self._bedrock = boto3.client("bedrock-runtime")
        return self._bedrock

    @property
    def s3(self):
        if self._s3 is None:
            self._s3 = boto3.client("s3")
        return self._s3

aws_clients = AWSClients()
```

### 4. Models

```python
class EmbeddingRequest(BaseModel):
    text: str = Field(..., min_length=1)
    store_in_s3: bool = False
    embedding_id: str | None = None

class EmbeddingResponse(BaseModel):
    embedding: list[float]
    dimension: int
    processing_time_ms: float
    stored_in_s3: bool = False
    s3_key: str | None = None
```

### 5. Endpoints

```python
@app.post("/embeddings/generate", response_model=EmbeddingResponse)
async def generate_embedding(request: EmbeddingRequest):
    """Generate embedding using Bedrock."""
    start_time = time.time()

    # Generate embedding
    response = aws_clients.bedrock.invoke_model(
        modelId=settings.bedrock_model_id,
        contentType="application/json",
        accept="application/json",
        body=json.dumps({"inputText": request.text})
    )

    result = json.loads(response["body"].read())
    embedding = result["embedding"]

    # Optionally store in S3
    s3_key = None
    if request.store_in_s3 and request.embedding_id:
        s3_key = f"embeddings/{request.embedding_id}.json"
        aws_clients.s3.put_object(
            Bucket=settings.vector_bucket_name,
            Key=s3_key,
            Body=json.dumps({
                "id": request.embedding_id,
                "text": request.text,
                "embedding": embedding,
                "dimension": len(embedding)
            }),
            ContentType="application/json"
        )

    return EmbeddingResponse(
        embedding=embedding,
        dimension=len(embedding),
        processing_time_ms=(time.time() - start_time) * 1000,
        stored_in_s3=bool(s3_key),
        s3_key=s3_key
    )

@app.get("/embeddings/{embedding_id}")
async def retrieve_embedding(embedding_id: str):
    """Retrieve embedding from S3."""
    try:
        response = aws_clients.s3.get_object(
            Bucket=settings.vector_bucket_name,
            Key=f"embeddings/{embedding_id}.json"
        )
        return json.loads(response["Body"].read())
    except aws_clients.s3.exceptions.NoSuchKey:
        raise HTTPException(404, f"Embedding not found: {embedding_id}")
```

**Full example**: [backend/s3vector/main.py](../backend/s3vector/main.py)

---

## Architecture

```text
Bootstrap (bootstrap/)
  ├─ S3 Buckets: {project}-{suffix}
  ├─ IAM Policies: Auto-attached to GitHub Actions
  └─ Outputs: Bucket IDs/ARNs, Policy ARNs

Service Terraform (terraform/)
  ├─ References: Bootstrap outputs via remote state
  ├─ Attaches: Policies to service roles
  └─ Sets: VECTOR_BUCKET_NAME, BEDROCK_MODEL_ID

Service Code (backend/{service}/)
  ├─ boto3: S3 + Bedrock clients
  └─ Endpoints: /embeddings/generate, /embeddings/{id}
```

---

## Usage Examples

### Generate Embedding

```bash
curl -X POST /embeddings/generate \
  -H "Content-Type: application/json" \
  -d '{"text": "Hello world", "store_in_s3": true, "embedding_id": "doc1"}'
```

Response:

```json
{
  "embedding": [0.1, 0.2, ..., 0.9],
  "dimension": 1024,
  "processing_time_ms": 45.2,
  "stored_in_s3": true,
  "s3_key": "embeddings/doc1.json"
}
```

### Retrieve Embedding

```bash
curl /embeddings/doc1
```

Response:

```json
{
  "id": "doc1",
  "text": "Hello world",
  "embedding": [0.1, 0.2, ..., 0.9],
  "dimension": 1024
}
```

---

## Reference

**Bedrock Model**: `amazon.titan-embed-text-v2:0` (1024 dimensions)

**Cost**: ~$2 per 1M embeddings

**Bucket Pattern**: `{project}-{suffix}` (e.g., `gustavo-vector-embeddings`)

**IAM Policies**:

- `s3_vector_management` - Auto-attached to GitHub Actions
- `s3_vector_service_access` - Attach to service roles
- `bedrock_invocation` - Attach to service roles

---

**Related**: [AWS Services Integration](AWS-SERVICES-INTEGRATION.md) · [Adding Services](ADDING-SERVICES.md)
