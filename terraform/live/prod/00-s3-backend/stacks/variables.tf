# Previously written as single-line with semicolons:
# variable "region" { type = string; default = "us-east-1" }
# Expanded to multi-line — semicolons are not valid HCL syntax

variable "environment" {
  type = string
}

variable "project" {
  type = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}
