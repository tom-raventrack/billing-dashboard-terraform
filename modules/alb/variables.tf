variable "name" {
  description = "Name prefix."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  description = "VPC CIDR; the ALB may only send traffic to targets inside it."
  type        = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "certificate_arn" {
  description = "ARN of an issued ACM certificate in this account and region covering the dashboard's domain name."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:acm:[a-z0-9-]+:[0-9]{12}:certificate/[0-9a-f-]+$", var.certificate_arn))
    error_message = "certificate_arn must be a full ACM certificate ARN."
  }
}

variable "target_port" {
  description = "Port the nginx container listens on."
  type        = number
  default     = 80
}

variable "health_check_path" {
  type    = string
  default = "/up"
}

variable "test_listener_port" {
  description = "Port of the blue/green test listener."
  type        = number
  default     = 8443
}

variable "test_listener_allowed_cidrs" {
  description = "IPv4 CIDRs allowed to reach the test listener. Empty keeps it closed."
  type        = list(string)
  default     = []
}

variable "ssl_policy" {
  type    = string
  default = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "enable_deletion_protection" {
  type    = bool
  default = true
}
