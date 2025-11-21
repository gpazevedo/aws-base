# =============================================================================
# API Gateway App Runner Integration Module - Variables
# =============================================================================

# API Gateway Configuration
variable "api_id" {
  description = "ID of the API Gateway REST API"
  type        = string
}

variable "api_root_resource_id" {
  description = "Root resource ID of the API Gateway REST API"
  type        = string
}

# App Runner Configuration
variable "apprunner_service_url" {
  description = "URL of the App Runner service (without https://)"
  type        = string
}

# Resource Configuration
variable "path_part" {
  description = "Path part for the proxy resource"
  type        = string
  default     = "{proxy+}"
}

variable "http_method" {
  description = "HTTP method for the API Gateway method"
  type        = string
  default     = "ANY"
}

variable "authorization_type" {
  description = "Authorization type for the API Gateway method"
  type        = string
  default     = "NONE"
}

variable "connection_type" {
  description = "Integration connection type (INTERNET or VPC_LINK)"
  type        = string
  default     = "INTERNET"

  validation {
    condition     = contains(["INTERNET", "VPC_LINK"], var.connection_type)
    error_message = "Connection type must be INTERNET or VPC_LINK"
  }
}

variable "integration_timeout_milliseconds" {
  description = "Integration timeout in milliseconds (50-29000)"
  type        = number
  default     = 29000
}

variable "enable_root_method" {
  description = "Enable root path (/) method"
  type        = bool
  default     = true
}
