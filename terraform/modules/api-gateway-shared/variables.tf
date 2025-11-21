# =============================================================================
# API Gateway Shared Module - Variables
# =============================================================================

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
}

variable "api_name" {
  description = "Name of the API Gateway REST API"
  type        = string
}

# =============================================================================
# Rate Limiting / Throttling
# =============================================================================

variable "enable_rate_limiting" {
  description = "Enable rate limiting for API Gateway"
  type        = bool
  default     = true
}

variable "throttle_burst_limit" {
  description = "API Gateway throttle burst limit (requests)"
  type        = number
  default     = 5000
}

variable "throttle_rate_limit" {
  description = "API Gateway throttle rate limit (requests per second)"
  type        = number
  default     = 10000
}

# =============================================================================
# Logging and Monitoring
# =============================================================================

variable "log_retention_days" {
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

variable "enable_data_trace" {
  description = "Enable full request/response data logging (verbose)"
  type        = bool
  default     = false
}

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing for API Gateway"
  type        = bool
  default     = false
}

# =============================================================================
# Caching
# =============================================================================

variable "enable_caching" {
  description = "Enable API Gateway caching"
  type        = bool
  default     = false
}

# =============================================================================
# Tags
# =============================================================================

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
