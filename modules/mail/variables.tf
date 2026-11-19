variable "name" {
  description = "Name prefix."
  type        = string
}

variable "domain" {
  description = "Domain mail is sent from, verified as an SES identity."
  type        = string
}
