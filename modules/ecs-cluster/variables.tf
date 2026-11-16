variable "name" {
  description = "Cluster name and name prefix."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "alb_security_group_id" {
  type = string
}

variable "web_port" {
  description = "Port the nginx container listens on."
  type        = number
  default     = 80
}
