variable "name" {
  description = "Resource name prefix, 3–20 lowercase letters, numbers or hyphens; begin and end with a letter or number."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,18}[a-z0-9]$", var.name)) && !startswith(var.name, "internal-") && !startswith(var.name, "sg-")
    error_message = "name must be 3–20 lowercase alphanumeric/hyphen characters, with no leading/trailing hyphen or AWS-reserved internal- or sg- prefix."
  }
}

variable "vpc_id" {
  description = "Existing VPC containing the ALB subnets and the backend ENIs."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^vpc-([0-9a-f]{8}|[0-9a-f]{17})$", var.vpc_id))
    error_message = "vpc_id must be an AWS VPC ID."
  }
}

variable "subnet_ids" {
  description = "At least two existing ALB subnets, exactly one per Availability Zone, all in vpc_id."
  type        = set(string)
  nullable    = false

  validation {
    condition = length(var.subnet_ids) >= 2 && alltrue([
      for id in var.subnet_ids : can(regex("^subnet-([0-9a-f]{8}|[0-9a-f]{17})$", id))
    ])
    error_message = "Provide at least two distinct, valid subnet IDs."
  }
}

variable "foundry_source_cidrs" {
  description = "Verified source IPv4 CIDRs as observed by the ALB; not assumed to be Palantir-published ranges. Use the narrowest practical ranges."
  type        = set(string)
  nullable    = false

  validation {
    condition = length(var.foundry_source_cidrs) > 0 && alltrue([
      for cidr in var.foundry_source_cidrs : try(
        can(cidrnetmask(cidr)) && tonumber(split("/", cidr)[1]) > 0 &&
        cidr == "${cidrhost(cidr, 0)}/${tonumber(split("/", cidr)[1])}", false
      )
    ])
    error_message = "Provide nonempty canonical IPv4 network CIDRs; invalid CIDRs, host bits, IPv6, and /0 are not supported."
  }
}

variable "certificate_arn" {
  description = "Existing, issued ACM certificate ARN in the ALB's AWS account and region; its names must match the client-facing DNS name."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^arn:aws(-us-gov|-cn)?:acm:[a-z0-9-]+:[0-9]{12}:certificate/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.certificate_arn))
    error_message = "certificate_arn must be an ACM certificate ARN, not a certificate/key value."
  }
}

variable "internal" {
  description = "Use an internal ALB by default. Setting false requires public subnet routing and an explicit exposure review."
  type        = bool
  default     = true
  nullable    = false
}

variable "backend_protocol" {
  description = "HTTP or HTTPS between ALB and targets. HTTPS encrypts traffic but ALB does not validate target certificates."
  type        = string
  default     = "HTTP"
  nullable    = false

  validation {
    condition     = contains(["HTTP", "HTTPS"], var.backend_protocol)
    error_message = "backend_protocol must be HTTP or HTTPS; ALB cannot forward raw RTSP/UDP."
  }
}

variable "backend_port" {
  description = "Single target and health-check destination port. Default HTTP/8080; set 8443 explicitly if your HTTPS backend uses it."
  type        = number
  default     = 8080
  nullable    = false

  validation {
    condition     = var.backend_port >= 1 && var.backend_port <= 65535 && var.backend_port == floor(var.backend_port)
    error_message = "backend_port must be an integer from 1 through 65535."
  }
}

variable "health_check_path" {
  description = "Unauthenticated HTTP(S) health endpoint returning HTTP 200 on the backend port; never put secrets in the path."
  type        = string
  default     = "/health"
  nullable    = false

  validation {
    condition     = can(regex("^/[^[:space:]]*$", var.health_check_path)) && length(var.health_check_path) <= 1024
    error_message = "health_check_path must start with /, contain no whitespace, and be at most 1024 characters."
  }
}

variable "target_ips" {
  description = "Optional stable-name => RFC1918/RFC6598 IPv4 target map. Targets must be reachable ENIs with the backend security group. Empty by default; workload infrastructure can register its own IPs."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for ip in values(var.target_ips) : can(cidrnetmask("${ip}/32")) && can(regex("^(10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|100\\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\\.)", ip))
    ])
    error_message = "target_ips must contain IPv4 addresses (not CIDRs) in RFC1918 or RFC6598 ranges; public IP targets are not supported by this scaffold."
  }

  validation {
    condition     = length(distinct(values(var.target_ips))) == length(var.target_ips)
    error_message = "Register each target IP only once."
  }
}

variable "enable_outbound_client" {
  description = "Create a separate security group for an AWS client initiating HTTPS to verified Foundry destination CIDRs. Does not attach it to a workload."
  type        = bool
  default     = false
  nullable    = false
}

variable "foundry_destination_cidrs" {
  description = "Verified destination IPv4 CIDRs for optional AWS-client HTTPS egress. Must be empty when the outbound-client group is disabled."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for cidr in var.foundry_destination_cidrs : try(
        can(cidrnetmask(cidr)) && tonumber(split("/", cidr)[1]) > 0 &&
        cidr == "${cidrhost(cidr, 0)}/${tonumber(split("/", cidr)[1])}", false
      )
    ])
    error_message = "Destination entries must be canonical IPv4 network CIDRs with a nonzero prefix; host bits, /0 and IPv6 are not supported."
  }

  validation {
    condition     = var.enable_outbound_client ? length(var.foundry_destination_cidrs) > 0 : length(var.foundry_destination_cidrs) == 0
    error_message = "Enable outbound_client only with nonempty destination CIDRs; leave destinations empty when the feature is disabled."
  }
}

variable "access_log_bucket" {
  description = "Optional existing S3 bucket name for ALB access logs. Operator must configure its same-region delivery permissions and supported encryption before enabling. No bucket or policy is created."
  type        = string
  default     = null

  validation {
    condition     = var.access_log_bucket == null ? true : can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.access_log_bucket))
    error_message = "access_log_bucket must be null or a 3–63 character S3 bucket name, not an ARN or URL."
  }
}

variable "access_log_prefix" {
  description = "S3 access-log prefix; AWSLogs is appended by ALB and must not be included here."
  type        = string
  default     = "foundry-video"
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9/_-]*$", var.access_log_prefix)) && !strcontains(var.access_log_prefix, "AWSLogs") && !endswith(var.access_log_prefix, "/")
    error_message = "Use a nonempty relative log prefix with letters, digits, /, _, or -; no trailing slash or AWSLogs."
  }
}

variable "deletion_protection" {
  description = "Keep ALB deletion protection enabled; deliberately disable and apply before an approved teardown."
  type        = bool
  default     = true
  nullable    = false
}

variable "tags" {
  description = "Nonsecret resource tags. Name tags are assigned by the module."
  type        = map(string)
  default     = {}
  nullable    = false
}
