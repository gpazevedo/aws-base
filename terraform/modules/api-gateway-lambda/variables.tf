# =============================================================================
# API Gateway Lambda Integration Module - Variables
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

variable "api_execution_arn" {
  description = "Execution ARN of the API Gateway REST API"
  type        = string
}

# Lambda Configuration
variable "lambda_function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "lambda_function_arn" {
  description = "ARN of the Lambda function"
  type        = string
}

variable "lambda_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
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

variable "request_parameters" {
  description = "Request parameters for the method"
  type        = map(bool)
  default     = {}
}

variable "integration_timeout_milliseconds" {
  description = "Integration timeout in milliseconds (50-29000)"
  type        = number
  default     = 29000
}

variable "permission_statement_id" {
  description = "Statement ID for Lambda permission"
  type        = string
  default     = "AllowAPIGatewayInvoke"
}

variable "enable_root_method" {
  description = "Enable root path (/) method"
  type        = bool
  default     = true
}

variable "api_key_required" {
  description = "Require API Key for requests"
  type        = bool
  default     = false
}
