resource "aws_security_group" "this" {
  count = var.create_security_group ? 1 : 0

  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.ingress_ports

    content {
      description = "allow tcp ${ingress.value}"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(
    {
      Name = var.security_group_name
    },
    var.tags
  )
}

resource "aws_iam_role" "this" {
  count = var.create_iam_resources ? 1 : 0

  name = var.iam_role_name
  path = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"

        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "this" {
  count = var.create_iam_resources ? 1 : 0

  name = "${var.iam_role_name}_policy"
  role = aws_iam_role.this[0].id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = concat(
          [
            "ec2:Describe*",
            "ec2messages:*",
            "ssm:*"
          ],
          var.additional_iam_actions
        )

        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "this" {
  count = var.create_iam_resources ? 1 : 0

  name = var.iam_role_name
  role = aws_iam_role.this[0].name
}

locals {
  effective_security_groups  = length(var.vpc_security_group_ids) > 0 ? var.vpc_security_group_ids : [aws_security_group.this[0].id]
  effective_instance_profile = var.iam_instance_profile != null ? var.iam_instance_profile : aws_iam_instance_profile.this[0].name
}

locals {
  cloud_init_complete_file = "/tmp/cloud-init-complete"

  user_data_footer = <<-EOT

echo --- done ---
touch ${local.cloud_init_complete_file}
EOT

  effective_user_data = "${trimspace(var.user_data)}${local.user_data_footer}"
}

resource "aws_instance" "this" {
  ami                         = var.ami
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  associate_public_ip_address = true

  iam_instance_profile   = local.effective_instance_profile
  vpc_security_group_ids = local.effective_security_groups

  user_data = local.effective_user_data

  credit_specification {
    cpu_credits = "standard"
  }

  tags = merge(
    {
      Name = var.instance_name
    },
    var.tags
  )
}

resource "terraform_data" "wait_for_instance" {
  provisioner "local-exec" {
    interpreter = ["bash", "-c"]

    command = <<-EOT
      #!/usr/bin/env bash

      set -euo pipefail

      REGION="${var.region}"
      INSTANCE_ID="${aws_instance.this.id}"
      echo "wait script started on: $INSTANCE_ID

      # Maximum time (seconds) to wait for SSM registration
      SSM_TIMEOUT=${var.wait_for_instance_config.ssm_timeout_secs}

      # Maximum time (seconds) to wait for lab readiness
      READY_TIMEOUT=SSM_TIMEOUT=${var.wait_for_instance_config.ready_timeout_secs}

      POLL_INTERVAL=${var.wait_for_instance_config.poll_interval_secs}

      echo "Waiting for SSM registration for instance: $INSTANCE_ID"

      ssm_start_time=$(date +%s)
      ping_status=""

      while true; do

        ping_status=$(
          aws ssm describe-instance-information \
            --region "$REGION" \
            --query "InstanceInformationList[?InstanceId=='$INSTANCE_ID'].PingStatus" \
            --output text \
            2>/dev/null || true
        )

        if [[ -z "$ping_status" ]]; then
          echo "PingStatus=<empty>"
        else
          echo "PingStatus=$ping_status"
        fi  

        if [[ "$ping_status" == "Online" ]]; then
          echo "SSM is online"
          break
        fi

        elapsed=$(( $(date +%s) - ssm_start_time ))

        if (( elapsed >= SSM_TIMEOUT )); then
          echo "ERROR: Timed out waiting for SSM registration after $SSM_TIMEOUT sec"
          exit 1
        fi

        sleep "$POLL_INTERVAL"
      done

      echo "Waiting for lab readiness marker..."

      ready_start_time=$(date +%s)

      while true; do

        elapsed=$(( $(date +%s) - ready_start_time ))

        if (( elapsed >= READY_TIMEOUT )); then
          echo "ERROR: Timed out waiting for ${local.cloud_init_complete_file} after $READY_TIMEOUT sec"
          exit 1
        fi

        cmd_id=$(
          aws ssm send-command \
            --region "$REGION" \
            --document-name AWS-RunShellScript \
            --instance-ids "$INSTANCE_ID" \
            --parameters 'commands=["test -f ${local.cloud_init_complete_file}"]' \
            --query 'Command.CommandId' \
            --output text \
            2>/dev/null || true
        )

        if [[ -z "$cmd_id" || "$cmd_id" == "None" ]]; then
          echo "SSM command unavailable, retrying..."
          sleep "$POLL_INTERVAL"
          continue
        fi

        sleep 5

        response=$(
          aws ssm get-command-invocation \
            --region "$REGION" \
            --command-id "$cmd_id" \
            --instance-id "$INSTANCE_ID" \
            --query ResponseCode \
            --output text \
            2>/dev/null || true
        )

        if [[ -z "$response" ]]; then
          echo "ResponseCode=<empty>"
        else
          echo "ResponseCode=$response"
        fi

        if [[ "$response" == "0" ]]; then
          echo "Lab readiness marker detected"
          break
        fi

        sleep "$POLL_INTERVAL"
      done

      echo "Instance ready"      
    EOT
  }

  depends_on = [
    aws_instance.this
  ]
}
