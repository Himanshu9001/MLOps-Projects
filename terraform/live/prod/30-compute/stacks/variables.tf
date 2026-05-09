variable "environment" {
  type = string
}

variable "project" {
  type = string
}

variable "region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "ec2_instance_type" {
  type = string
}

variable "mlflow_port" {
  type = number
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "eks_oidc_provider_arn" {
  type    = string
  default = ""
}

variable "eks_oidc_provider_url" {
  type    = string
  default = ""
}
