variable "aws_region" {
  description = "AWS region containing the existing VPC."
  type        = string
  nullable    = false
}

variable "aws_account_id" {
  description = "Explicit intended 12-digit AWS account ID. The provider rejects credentials for a different account."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id)) && var.aws_account_id != "000000000000"
    error_message = "Set the real intended 12-digit AWS account ID, not the all-zero placeholder."
  }
}

variable "name" {
  description = "Name prefix; validated by the shared module."
  type        = string
  default     = "foundry-rtsp-tcp"
  nullable    = false
}

variable "vpc_id" {
  description = "Existing VPC containing the AWS client/server interface."
  type        = string
  nullable    = false
}

variable "aws_role" {
  description = "server: remote client pulls from AWS; client: AWS pulls from a remote server. Choose the role of this interface."
  type        = string
  default     = "server"
  nullable    = false
}

variable "peer_ipv4_cidrs" {
  description = "Explicit peer IPv4 networks; use verified /32 addresses where possible. No world-open CIDRs."
  type        = set(string)
  nullable    = false
}

variable "rtsp_port" {
  description = "TCP destination port on the RTSP server."
  type        = number
  default     = 554
  nullable    = false
}

variable "tags" {
  description = "Additional resource tags."
  type        = map(string)
  default     = {}
  nullable    = false
}
