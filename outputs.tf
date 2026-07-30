output "instance_id" {
  value = aws_instance.this.id
}

output "public_ip" {
  description = "Public IP address of the IDE EC2 instance"
  value       = aws_instance.this.public_ip
}

output "security_group_id" {
  value = try(aws_security_group.this[0].id, null)
}

output "instance_profile_name" {
  value = try(aws_iam_instance_profile.this[0].name, null)
}
