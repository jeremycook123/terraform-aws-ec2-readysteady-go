variable "vpc_id" {
  type = string
}

variable "ami" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "key_name" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "user_data" {
  type = string
}

variable "region" {
  description = "AWS region EC2 host is deployed to"
  type        = string
  default     = "us-west-2"
}

variable "wait_for_instance_config" {
  type = object({
    ssm_timeout_secs   = number
    ready_timeout_secs = number
    poll_interval_secs = number
  })
  default = {
    ssm_timeout_secs   = 1800,
    ready_timeout_secs = 1800,
    poll_interval_secs = 10
  }
}

variable "ingress_ports" {
  description = "List of public TCP ports to allow"
  type        = list(number)

  default = [
    22,
    80
  ]
}

variable "additional_iam_actions" {
  description = "Additional IAM actions to append to the base policy"
  type        = list(string)
  default     = []
}

variable "create_security_group" {
  type    = bool
  default = true
}

variable "create_iam_resources" {
  type    = bool
  default = true
}

variable "iam_instance_profile" {
  description = "Existing instance profile to use instead of creating one"
  type        = string
  default     = null
}

variable "vpc_security_group_ids" {
  description = "Existing security groups to use instead of creating one"
  type        = list(string)
  default     = []
}

variable "security_group_name" {
  type    = string
  default = "secgrp-001"
}

variable "security_group_description" {
  type    = string
  default = "host security group"
}

variable "iam_role_name" {
  type    = string
  default = "role-001"
}

variable "instance_name" {
  type    = string
  default = "host-001"
}

variable "tags" {
  type    = map(string)
  default = {}
}
