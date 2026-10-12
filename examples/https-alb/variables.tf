variable "aws_region" {
  description = "AWS region containing the existing VPC, subnets and ACM certificate."
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "Expected deployment account ID. The provider rejects credentials for another account."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id)) && var.aws_account_id != "000000000000"
    error_message = "Provide the intended 12-digit nonzero AWS account ID."
  }
}

variable "name" {
  description = "Short name for this example's resources."
  type        = string
  default     = "foundry-video-lab"
}

variable "vpc_id" {
  description = "Existing VPC ID."
  type        = string
}

variable "subnet_ids" {
  description = "Existing subnets in at least two distinct Availability Zones in this VPC."
  type        = set(string)
}

variable "foundry_source_cidrs" {
  description = "Actual IPv4 source CIDRs observed from the Foundry worker, agent or approved gateway."
  type        = set(string)
}

variable "certificate_arn" {
  description = "Existing regional ACM certificate ARN matching the hostname the client uses."
  type        = string
}

variable "internal" {
  description = "Keep private unless internet exposure and routing were explicitly approved."
  type        = bool
  default     = true
}

variable "backend_protocol" {
  description = "HTTP or HTTPS. HTTPS encrypts the backend hop but ALB does not validate the target certificate."
  type        = string
  default     = "HTTP"
}

variable "backend_port" {
  description = "Same destination port for application requests and health checks."
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "An unauthenticated, minimally informative application health path."
  type        = string
  default     = "/health"
}

variable "target_ips" {
  description = "Optional stable names mapped to backend IPv4 addresses; their ENIs must carry the backend SG."
  type        = map(string)
  default     = {}
}

variable "enable_outbound_client" {
  description = "Create a separate SG for an AWS client initiating HTTPS to supplied Foundry destination CIDRs."
  type        = bool
  default     = false
}

variable "foundry_destination_cidrs" {
  description = "Explicit remote IPv4 destination CIDRs for the optional outbound HTTPS client."
  type        = set(string)
  default     = []
}

variable "access_log_bucket" {
  description = "Optional existing S3 bucket configured for ALB log delivery; this module does not manage its policy."
  type        = string
  default     = null
}

variable "access_log_prefix" {
  description = "Prefix within the existing ALB access log bucket."
  type        = string
  default     = "foundry-video"
}

variable "deletion_protection" {
  description = "Keep enabled until a reviewed cleanup explicitly disables it."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Nonsecret resource tags."
  type        = map(string)
  default     = { Project = "foundry-video-connectivity", Environment = "lab" }
}
