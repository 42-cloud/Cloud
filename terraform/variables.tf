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

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "instance_type" {
  description = "type of instance"
  type        = string
}

variable "instance_names" {
  description = "List all instance name"
  type        = list(string)
}

variable "duck_domains" {
    type = list(string)
}

variable "lb_instance_name" {
  description = "Name of the instance acting as Angie load balancer (must be in instance_names)"
  type        = string
}
