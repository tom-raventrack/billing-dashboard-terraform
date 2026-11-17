variable "name" {
  description = "Name prefix; repositories are created as <name>/<repository>."
  type        = string
}

variable "repositories" {
  description = "Repository short names."
  type        = set(string)
  default     = ["app", "nginx"]
}

variable "force_delete" {
  description = "Allow the repositories to be deleted while they still contain images."
  type        = bool
  default     = false
}

variable "keep_image_count" {
  description = "Number of images the lifecycle policy keeps per repository."
  type        = number
  default     = 30
}
