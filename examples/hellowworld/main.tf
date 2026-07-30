terraform {
  required_version = ">=1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.30"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.8"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_availability_zones" "available" {}

data "aws_key_pair" "lab" {
  key_name = "EC2-KEYNAME"
}

#====================================

locals {
  name        = "cloudacademydevops"
  environment = "prod"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 2)

  ide = {
    ami_id        = "ami-0f36b97632dcd923b"
    instance_type = "m5.large"
  }
}

#====================================

resource "aws_iam_access_key" "student" {
  user   = "student"
  status = "Active"
}

#====================================

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]
  intra_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 52)]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  manage_default_network_acl    = true
  manage_default_route_table    = true
  manage_default_security_group = true

  default_network_acl_tags = {
    Name = "${local.name}-default"
  }

  default_route_table_tags = {
    Name = "${local.name}-default"
  }

  default_security_group_tags = {
    Name = "${local.name}-default"
  }

  tags = {
    Name        = "${local.name}-eks"
    Environment = local.environment
  }
}

resource "random_password" "ide_login" {
  length  = 20
  special = false
}

# EC2 VM - with wait script integrated
# Terraform checks/waits for userdata script to complete before returning
module "host-001" {
  source = "../.."

  vpc_id        = module.vpc.vpc_id
  subnet_id     = module.vpc.public_subnets[0]
  ami           = local.ide.ami_id
  instance_type = local.ide.instance_type
  key_name      = data.aws_key_pair.lab.key_name

  ingress_ports = [
    22,
    80
  ]

  additional_iam_actions = [
    "s3:ListBucket",
    "s3:GetObject"
  ]

  user_data = <<-EOT
    #!/usr/bin/env bash
    set -x

    echo "Hello World"

    IDE_PASSWORD=${random_password.ide_login.result}
    echo "Random password: $IDE_PASSWORD"

    #Terraform will not return until this script completes
  EOT

  tags = {
    Environment = "lab"
  }
}

output "public_ip" {
  value = module.host-001.public_ip
}
