# =============================================================================
# Application Infrastructure - Variables
# =============================================================================

variable "project_name" {
  description = "Project name (must match bootstrap configuration)"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (org/repo)"
  type        = string
}

variable "ecr_repository_name" {
  description = "ECR repository name for Lambda container images"
  type        = string
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}

variable "lambda_architecture" {
  description = "Lambda function architecture (x86_64 or arm64)"
  type        = string
  default     = "arm64"
}

# =============================================================================
# API Gateway Configuration (Standard Mode)
# =============================================================================

variable "enable_api_gateway_standard" {
  description = "Enable API Gateway as standard entry point (recommended for cloud deployments)"
  type        = bool
  default     = true
}

variable "enable_direct_access" {
  description = "Enable direct access URLs (Lambda Function URLs, App Runner direct). Set to true for local development."
  type        = bool
  default     = false
}

# Legacy variable for backward compatibility
variable "enable_api_gateway" {
  description = "DEPRECATED: Use enable_api_gateway_standard instead. Enable API Gateway for Lambda functions"
  type        = bool
  default     = true
}

# Rate Limiting / Throttling
variable "api_throttle_burst_limit" {
  description = "API Gateway throttle burst limit (requests)"
  type        = number
  default     = 5000
}

variable "api_throttle_rate_limit" {
  description = "API Gateway throttle rate limit (requests per second)"
  type        = number
  default     = 10000
}

# Logging and Monitoring
variable "api_log_retention_days" {
  description = "CloudWatch log retention for API Gateway logs (days)"
  type        = number
  default     = 7
}

variable "api_logging_level" {
  description = "API Gateway logging level (OFF, ERROR, INFO)"
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["OFF", "ERROR", "INFO"], var.api_logging_level)
    error_message = "Logging level must be OFF, ERROR, or INFO"
  }
}

variable "enable_api_data_trace" {
  description = "Enable full request/response data logging (verbose, use with caution)"
  type        = bool
  default     = false
}

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing for API Gateway"
  type        = bool
  default     = false
}

# Caching
variable "enable_api_caching" {
  description = "Enable API Gateway caching"
  type        = bool
  default     = false
}

# CORS Configuration
variable "cors_allow_origins" {
  description = "CORS allowed origins"
  type        = list(string)
  default     = ["*"]
}

variable "cors_allow_methods" {
  description = "CORS allowed HTTP methods"
  type        = list(string)
  default     = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
}

variable "cors_allow_headers" {
  description = "CORS allowed headers"
  type        = list(string)
  default     = ["Content-Type", "Authorization", "X-Requested-With"]
}

# API Key Authentication
variable "enable_api_key" {
  description = "Enable API Key authentication for API Gateway"
  type        = bool
  default     = false
}

variable "api_key_name" {
  description = "Name for the API Key (if enabled)"
  type        = string
  default     = ""
}

variable "api_usage_plan_quota_limit" {
  description = "Maximum number of requests per period (0 = unlimited)"
  type        = number
  default     = 0
}

variable "api_usage_plan_quota_period" {
  description = "Time period for quota (DAY, WEEK, MONTH)"
  type        = string
  default     = "MONTH"

  validation {
    condition     = contains(["DAY", "WEEK", "MONTH"], var.api_usage_plan_quota_period)
    error_message = "Quota period must be DAY, WEEK, or MONTH"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
