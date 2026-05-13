variable "public_key_path" {
  description = "path for SSH key"
  type        = string
}

variable "aws_region" {
  description = "region AWS"
  type        = string
}

variable "ip_host" {
  description = "Ip host for ingress security"
  type        = string
}
