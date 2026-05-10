variable "environment" {
  type = string
  validation {
    condition     = contains(["nonprod", "prod"], var.environment)
    error_message = "environment must be 'nonprod' or 'prod'."
  }
}

variable "project" {
  type = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "repositories" {
  type        = list(string)
  description = "List of ECR repository names to create."
}

variable "image_tag_mutability" {
  type        = string
  description = "Whether image tags can be overwritten."
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "keep_image_count" {
  type        = number
  description = "Number of tagged images to keep per repo."
  default     = 10
}

variable "untagged_expiry_days" {
  type        = number
  description = "Days to keep untagged images before expiry."
  default     = 1
}

variable "scan_on_push" {
  type        = bool
  description = "Enable ECR Basic Scanning on every push."
  default     = true
}

variable "additional_tags" {
  type    = map(string)
  default = {}
}

variable "force_delete" {
  # Allow destroying repo even when it contains images.
  # Set true for nonprod (safe cleanup), false for prod (prevent accidental loss).
  type        = bool
  description = "Force delete repo even if it contains images."
  default     = false
}

variable "force_delete" {
  # Allow destroying repo even when it contains images.
  # Set true for nonprod (safe cleanup), false for prod (prevent accidental loss).
  type        = bool
  description = "Force delete repo even if it contains images."
  default     = false
}
