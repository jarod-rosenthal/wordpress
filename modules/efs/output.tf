output "efs_dns" {
    value = aws_efs_file_system.wordpress_efs.dns_name
}
