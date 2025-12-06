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

variable "integration_ids" {
  description = "List of integration IDs to trigger redeployment"
  type        = list(string)
  default     = []
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

# =============================================================================
# Caching
# =============================================================================

variable "enable_caching" {
  description = "Enable API Gateway caching"
  type        = bool
  default     = false
}

# =============================================================================
# API Key Authentication
# =============================================================================

variable "enable_api_key" {
  description = "Enable API Key authentication"
  type        = bool
  default     = false
}

variable "api_key_name" {
  description = "Name for the API Key (if enabled)"
  type        = string
  default     = ""
}

variable "usage_plan_quota_limit" {
  description = "Maximum number of requests per period (0 = unlimited)"
  type        = number
  default     = 0
}

variable "usage_plan_quota_period" {
  description = "Time period for quota (DAY, WEEK, MONTH)"
  type        = string
  default     = "MONTH"
}

# =============================================================================
# Per-Service API Keys (Inter-Service Communication)
# =============================================================================

variable "service_api_keys" {
  description = "Map of services that need API keys for inter-service communication"
  type = map(object({
    quota_limit  = number       # Quota limit (0 = unlimited)
    quota_period = string       # DAY, WEEK, or MONTH
    description  = string       # Description of the service
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.service_api_keys :
      contains(["DAY", "WEEK", "MONTH"], v.quota_period)
    ])
    error_message = "All quota_period values must be DAY, WEEK, or MONTH"
  }

  validation {
    condition = alltrue([
      for k, v in var.service_api_keys :
      v.quota_limit >= 0
    ])
    error_message = "quota_limit must be non-negative (0 = unlimited)"
  }
}

# =============================================================================
# Tags
# =============================================================================

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
