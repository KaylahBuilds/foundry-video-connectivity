variable "name" {
  description = "Name prefix for a new security group. No existing group is modified."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,39}$", var.name)) && !startswith(var.name, "sg-")
    error_message = "Use 3-40 lowercase letters, numbers, or hyphens, starting with a letter; the AWS-reserved sg- prefix is not allowed."
  }
}

variable "vpc_id" {
  description = "Existing VPC containing the AWS client or server network interface."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^vpc-([0-9a-f]{8}|[0-9a-f]{17})$", var.vpc_id))
    error_message = "Supply an existing VPC ID."
  }
}

variable "aws_role" {
  description = "server: a remote client pulls from AWS. client: AWS pulls from a remote server."
  type        = string
  nullable    = false

  validation {
    condition     = contains(["server", "client"], var.aws_role)
    error_message = "aws_role must be server or client; choose only the role this AWS interface performs."
  }
}

variable "transport" {
  description = "tcp uses interleaved media on the control connection; udp uses separate negotiated media receiver ports."
  type        = string
  nullable    = false

  validation {
    condition     = contains(["tcp", "udp"], var.transport)
    error_message = "transport must be tcp or udp."
  }
}

variable "peer_ipv4_cidrs" {
  description = "1-20 explicit peer IPv4 CIDRs visible at the AWS interface after any translation. Prefer verified /32 peers."
  type        = set(string)
  nullable    = false

  validation {
    condition = length(var.peer_ipv4_cidrs) >= 1 && length(var.peer_ipv4_cidrs) <= 20 && alltrue([
      for cidr in var.peer_ipv4_cidrs : try(
        can(cidrnetmask(cidr)) && tonumber(split("/", cidr)[1]) >= 1 &&
        tonumber(split("/", cidr)[1]) <= 32 &&
        cidr == "${cidrhost(cidr, 0)}/${tonumber(split("/", cidr)[1])}", false
      )
    ])
    error_message = "Use 1-20 canonical IPv4 network CIDRs with prefix /1 through /32. Empty lists, IPv6, host bits, and 0.0.0.0/0 are not allowed."
  }
}

variable "rtsp_port" {
  description = "TCP destination port on the RTSP server. Interleaved media shares this connection."
  type        = number
  default     = 554
  nullable    = false

  validation {
    condition     = var.rtsp_port >= 1 && var.rtsp_port <= 65535 && floor(var.rtsp_port) == var.rtsp_port
    error_message = "rtsp_port must be an integer from 1 through 65535."
  }
}

variable "client_rtp_ports" {
  description = "UDP destination range on the client receiving RTP; ignored in tcp mode. Match application configuration or negotiation."
  type        = object({ from = number, to = number })
  default     = { from = 5004, to = 5004 }
  nullable    = false

  validation {
    condition = try(
      var.client_rtp_ports.from >= 1 && var.client_rtp_ports.to <= 65535 &&
      floor(var.client_rtp_ports.from) == var.client_rtp_ports.from &&
      floor(var.client_rtp_ports.to) == var.client_rtp_ports.to &&
      var.client_rtp_ports.to >= var.client_rtp_ports.from &&
      var.client_rtp_ports.to - var.client_rtp_ports.from < 32, false
    )
    error_message = "client_rtp_ports must be an ascending integer range within 1-65535 spanning no more than 32 ports."
  }
}

variable "client_rtcp_ports" {
  description = "UDP destination range on the client receiving RTCP; not inferred from RTP plus one. Ignored in tcp mode."
  type        = object({ from = number, to = number })
  default     = { from = 5005, to = 5005 }
  nullable    = false

  validation {
    condition = try(
      var.client_rtcp_ports.from >= 1 && var.client_rtcp_ports.to <= 65535 &&
      floor(var.client_rtcp_ports.from) == var.client_rtcp_ports.from &&
      floor(var.client_rtcp_ports.to) == var.client_rtcp_ports.to &&
      var.client_rtcp_ports.to >= var.client_rtcp_ports.from &&
      var.client_rtcp_ports.to - var.client_rtcp_ports.from < 32, false
    )
    error_message = "client_rtcp_ports must be an ascending integer range within 1-65535 spanning no more than 32 ports."
  }
}

variable "server_rtcp_ports" {
  description = "UDP destination range on the server receiving client RTCP feedback; ignored in tcp mode."
  type        = object({ from = number, to = number })
  default     = { from = 6001, to = 6001 }
  nullable    = false

  validation {
    condition = try(
      var.server_rtcp_ports.from >= 1 && var.server_rtcp_ports.to <= 65535 &&
      floor(var.server_rtcp_ports.from) == var.server_rtcp_ports.from &&
      floor(var.server_rtcp_ports.to) == var.server_rtcp_ports.to &&
      var.server_rtcp_ports.to >= var.server_rtcp_ports.from &&
      var.server_rtcp_ports.to - var.server_rtcp_ports.from < 32, false
    )
    error_message = "server_rtcp_ports must be an ascending integer range within 1-65535 spanning no more than 32 ports."
  }
}

variable "tags" {
  description = "Additional resource tags; module ownership tags take precedence."
  type        = map(string)
  default     = {}
  nullable    = false
}
