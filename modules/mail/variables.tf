variable "name" {
  description = "Name prefix."
  type        = string
}

variable "domain" {
  description = "Domain mail is sent from. Its SES identity is verified outside Terraform."
  type        = string
}
