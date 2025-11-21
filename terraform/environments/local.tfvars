# =============================================================================
# Application Infrastructure - local Environment
# =============================================================================
# Configuration for local development with direct access
# Use this when testing locally without API Gateway
# =============================================================================

project_name = "aws-ai"
environment  = "local"
aws_region   = "us-east-1"
github_repo  = "gpazevedo/aws-ai"

# ECR Repository (created by bootstrap)
ecr_repository_name = "aws-ai"

# Lambda Configuration
lambda_memory_size  = 512
lambda_timeout      = 30
lambda_architecture = "arm64"

# =============================================================================
# Local Development Configuration
# =============================================================================
# Enable direct access for local testing

enable_api_gateway_standard = false  # Skip API Gateway for local
enable_direct_access        = true   # Enable Lambda Function URLs

# CORS (open for local development)
cors_allow_origins = ["*"]
cors_allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
cors_allow_headers = ["Content-Type", "Authorization", "X-Requested-With"]

# Additional tags
additional_tags = {
  Environment = "local"
  Developer   = "true"
}
