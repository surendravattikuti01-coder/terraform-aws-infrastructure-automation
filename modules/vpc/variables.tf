variable "project_name" {
  description = "Name of the project used as a prefix for all resources"
  type        = string
  validation {
    condition     = length(var.project_name) > 2 && length(var.project_name) <= 20
    error_message = "project_name must be between 3 and 20 characters."
  }
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones for multi-AZ deployment"
  type        = list(string)
  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones are required for HA."
  }
}

variable "enable_nat_gateway_ha" {
  description = "Deploy one NAT Gateway per AZ for high availability (increases cost)"
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs to CloudWatch for security auditing"
  type        = bool
  default     = true
}

variable "enable_vpc_endpoints" {
  description = "Enable gateway VPC endpoints for S3 and DynamoDB (reduces NAT costs)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
