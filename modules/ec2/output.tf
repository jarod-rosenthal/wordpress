output "private_key" {
  value     = var.create_ssh_key ? tls_private_key.ssh_key[0].private_key_pem : null
  sensitive = true
}

output "db_password" {
  value     = var.db_password
  sensitive = true
}

output "ec2_security_group" {
  description = "The security group ID of the WordPress instance"
  value       = aws_security_group.wordpress[*].id
}

output "efs_security_group" {
  description = "The security group ID of the WordPress instance"
  value       = aws_security_group.efs_sg[*].id
}

output "instance_ids" {
  description = "IDs of the instances"
  value       = aws_instance.wordpress_instance.*.id
}

output "instance_ips" {
  description = "Public IPs of the instances"
  value       = aws_instance.wordpress_instance.*.public_ip
}
