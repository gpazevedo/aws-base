# S3 Vector Integration Tests

Comprehensive integration tests for the S3 vector embedding functionality that use **real AWS services** (Amazon Bedrock and S3).

## Test Coverage

✅ **13 Integration Tests** - All tests use actual AWS infrastructure

### Tests Included

1. **Configuration Validation** - Verifies AWS services are properly configured
2. **Basic Embedding Generation** - Tests Bedrock API for generating embeddings
3. **Full Workflow** - Complete cycle: Generate → Store → Retrieve → Delete
4. **Store Pre-computed Embeddings** - Tests storing custom embedding vectors
5. **Delete Embedding** - Tests deleting embeddings from S3
6. **Retrieve Non-existent Embedding** - Error handling for missing embeddings
7. **Delete Non-existent Embedding** - Error handling when deleting missing embeddings
8. **Missing Embedding ID** - Validation when storing without ID
9. **Empty Text Validation** - Request validation for empty input
10. **Performance Testing** - Ensures embeddings generate in reasonable time
11-13. **Variable Text Sizes** - Tests short, medium, and long text inputs

## Prerequisites

Before running the tests, ensure:

1. **AWS Credentials Configured**
   ```bash
   # Via environment variables
   export AWS_ACCESS_KEY_ID=your-key
   export AWS_SECRET_ACCESS_KEY=your-secret
   export AWS_REGION=us-east-1

   # Or via ~/.aws/credentials
   ```

2. **S3 Vector Bucket Created**
   ```bash
   # Should be created via bootstrap terraform
   cd bootstrap
   terraform apply
   ```

3. **Bedrock Access Enabled**
   - Amazon Titan Embed Text v2 model must be enabled in your AWS account
   - IAM permissions for `bedrock:InvokeModel`

4. **Environment Variables Set**
   ```bash
   export VECTOR_BUCKET_NAME=gustavo-vector-embeddings  # Your bucket name
   export RUN_INTEGRATION_TESTS=true                     # Enable integration tests
   ```

## Running the Tests

### Get Bucket Name from Terraform

```bash
cd bootstrap
terraform output -json | jq -r '.s3_vector_bucket_ids.value["vector-embeddings"]'
```

### Run All Integration Tests

```bash
cd backend/vector

# Run all tests (with S3 bucket configured)
RUN_INTEGRATION_TESTS=true \
VECTOR_BUCKET_NAME=gustavo-vector-embeddings \
uv run pytest tests/test_s3vector.py -v

# Run Bedrock-only tests (without S3 bucket)
# S3-dependent tests will be skipped
RUN_INTEGRATION_TESTS=true \
uv run pytest tests/test_s3vector.py -v

# Run with detailed output
RUN_INTEGRATION_TESTS=true \
VECTOR_BUCKET_NAME=gustavo-vector-embeddings \
uv run pytest tests/test_s3vector.py -v -s
```

### Run Specific Test

```bash
# Run only the full workflow test
RUN_INTEGRATION_TESTS=true \
VECTOR_BUCKET_NAME=gustavo-vector-embeddings \
uv run pytest tests/test_s3vector.py::test_full_embedding_workflow -v -s

# Run only performance test
RUN_INTEGRATION_TESTS=true \
VECTOR_BUCKET_NAME=gustavo-vector-embeddings \
uv run pytest tests/test_s3vector.py::test_embedding_generation_performance -v -s
```

### Run Tests with Coverage

```bash
RUN_INTEGRATION_TESTS=true \
VECTOR_BUCKET_NAME=gustavo-vector-embeddings \
uv run pytest tests/test_s3vector.py --cov=. --cov-report=html
```

## Test Results

### With S3 Bucket Configured

Expected output when all tests pass:

```
============================= test session starts ==============================
tests/test_s3vector.py::test_aws_configuration PASSED                    [  7%]
tests/test_s3vector.py::test_generate_embedding_basic PASSED             [ 15%]
tests/test_s3vector.py::test_full_embedding_workflow PASSED              [ 23%]
tests/test_s3vector.py::test_store_precomputed_embedding PASSED          [ 30%]
tests/test_s3vector.py::test_delete_embedding PASSED                     [ 38%]
tests/test_s3vector.py::test_retrieve_nonexistent_embedding PASSED       [ 46%]
tests/test_s3vector.py::test_delete_nonexistent_embedding PASSED         [ 53%]
tests/test_s3vector.py::test_generate_with_missing_embedding_id PASSED   [ 61%]
tests/test_s3vector.py::test_generate_with_empty_text PASSED             [ 69%]
tests/test_s3vector.py::test_embedding_generation_performance PASSED     [ 76%]
tests/test_s3vector.py::test_embedding_different_text_sizes[10-short text] PASSED [ 84%]
tests/test_s3vector.py::test_embedding_different_text_sizes[100-medium text] PASSED [ 92%]
tests/test_s3vector.py::test_embedding_different_text_sizes[500-long text] PASSED [100%]

============================== 13 passed in 9.71s ==============================
```

### Without S3 Bucket (Bedrock-only tests)

When `VECTOR_BUCKET_NAME` is not set, S3-dependent tests are automatically skipped:

```
============================= test session starts ==============================
tests/test_s3vector.py::test_aws_configuration PASSED                    [  7%]
tests/test_s3vector.py::test_generate_embedding_basic PASSED             [ 15%]
tests/test_s3vector.py::test_full_embedding_workflow SKIPPED             [ 23%]
tests/test_s3vector.py::test_store_precomputed_embedding SKIPPED         [ 30%]
tests/test_s3vector.py::test_delete_embedding SKIPPED                    [ 38%]
tests/test_s3vector.py::test_retrieve_nonexistent_embedding SKIPPED      [ 46%]
tests/test_s3vector.py::test_delete_nonexistent_embedding SKIPPED        [ 53%]
tests/test_s3vector.py::test_generate_with_missing_embedding_id PASSED   [ 61%]
tests/test_s3vector.py::test_generate_with_empty_text PASSED             [ 69%]
tests/test_s3vector.py::test_embedding_generation_performance PASSED     [ 76%]
tests/test_s3vector.py::test_embedding_different_text_sizes[10-short text] PASSED [ 84%]
tests/test_s3vector.py::test_embedding_different_text_sizes[100-medium text] PASSED [ 92%]
tests/test_s3vector.py::test_embedding_different_text_sizes[500-long text] PASSED [100%]

============================== 8 passed, 5 skipped in 3.86s ==============================
```

This allows testing Bedrock functionality without requiring S3 infrastructure.

## What the Tests Verify

### Full Workflow Test (Most Important)

This test verifies the complete embedding lifecycle:

1. **Generate**: Uses Amazon Bedrock to generate a 1024-dimension embedding
2. **Store**: Saves the embedding to S3 as JSON
3. **Retrieve**: Fetches the embedding back from S3
4. **Verify**: Confirms data integrity (text, embedding vector, dimensions all match)
5. **Delete**: Removes the embedding from S3 (automatic cleanup)

Example output:
```
=== Step 1: Generate and store embedding (ID: test-embedding-1765591953561) ===
✓ Generated embedding: 1024 dimensions
✓ Stored in S3: embeddings/test-embedding-1765591953561.json
✓ Processing time: 257.19ms

=== Step 2: Retrieve embedding from S3 ===

=== Step 3: Verify data integrity ===
✓ Embedding ID matches: test-embedding-1765591953561
✓ Text matches: 'This is a test sentence for vector embeddings.'
✓ Embedding vector matches exactly (1024 dimensions)
✓ Dimension matches: 1024
✓ All embedding values are numeric

✅ Full workflow test PASSED
```

## Performance Metrics

Typical performance (from test runs):

- **Embedding Generation**: 250-280ms (Bedrock API call)
- **S3 Storage**: <50ms
- **S3 Retrieval**: <100ms
- **Total Round-trip**: <300ms for generate+store+retrieve

## Cleanup

Tests automatically clean up S3 objects after completion using the `cleanup_embedding` fixture, which calls the **DELETE /embeddings/{id}** endpoint. This means:

- ✅ Tests don't need to know the bucket name for cleanup
- ✅ Cleanup uses the same API that users will use
- ✅ Tests verify the delete endpoint works correctly
- ✅ Test embeddings use unique IDs (`test-embedding-{timestamp}`) to avoid collisions

## Troubleshooting

### Tests Skipped

If you see "Integration tests disabled", ensure:
```bash
export RUN_INTEGRATION_TESTS=true
```

### S3 Tests Skipped

If you see tests marked as "SKIPPED" with reason "VECTOR_BUCKET_NAME not set":

```
tests/test_s3vector.py::test_full_embedding_workflow SKIPPED
tests/test_s3vector.py::test_store_precomputed_embedding SKIPPED
...
```

This is **expected behavior** - S3-dependent tests are automatically skipped when `VECTOR_BUCKET_NAME` is not set.

**To run all tests including S3 tests:**
```bash
export VECTOR_BUCKET_NAME=gustavo-vector-embeddings
```

**To run Bedrock-only tests (current behavior):**
```bash
# Don't set VECTOR_BUCKET_NAME - S3 tests will be skipped automatically
RUN_INTEGRATION_TESTS=true uv run pytest tests/test_s3vector.py -v
```

### Bedrock Access Denied

```
ClientError: An error occurred (AccessDeniedException)
```

Solution: Enable Bedrock model access in AWS Console
1. Go to Amazon Bedrock console
2. Navigate to "Model access"
3. Request access to "Amazon Titan Embed Text v2"

### S3 Access Denied

```
ClientError: An error occurred (AccessDenied) when calling the PutObject operation
```

Solution: Verify IAM permissions for S3 bucket access

## CI/CD Integration

To run these tests in GitHub Actions, add to your workflow:

```yaml
- name: Run S3 Vector Integration Tests
  env:
    RUN_INTEGRATION_TESTS: true
    VECTOR_BUCKET_NAME: ${{ secrets.VECTOR_BUCKET_NAME }}
    AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
    AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    AWS_REGION: us-east-1
  run: |
    cd backend/vector
    uv run pytest tests/test_s3vector.py -v
```

## Related Documentation

- [S3 Vector Storage Guide](../../docs/S3-VECTOR-STORAGE.md) - Infrastructure setup
- [Service Creation Guide](../../docs/CREATE-SERVICE-QUICKSTART.md) - Adding embeddings to services
- [Main Service Code](main.py) - Implementation reference

## Test File Location

[`tests/test_s3vector.py`](tests/test_s3vector.py)
