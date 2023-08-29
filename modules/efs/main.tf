# EFS for WordPress
resource "aws_efs_file_system" "wordpress_efs" {
  creation_token = var.db_name
  encrypted = true
}

resource "aws_efs_mount_target" "wordpress_efs_mount" {
  count           = length(var.private_subnets)
  file_system_id  = aws_efs_file_system.wordpress_efs.id
  subnet_id       = var.private_subnets[count.index]
  security_groups = var.efs_sg
}
