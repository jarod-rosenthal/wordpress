output "ec2_instance_ids" {
  description = "Instance IDs from the EC2 module"
  value       = module.ec2.instance_ids
}

output "ssm_connect" {
  value = "aws ssm start-session --target ${module.ec2.instance_ids[0]}"
}

output "ssm_log" {
  value = "aws ssm start-session --target ${module.ec2.instance_ids[0]} --document-name AWS-StartInteractiveCommand --parameters command='tail -f /var/log/userdata.log'"
}

output "alias_connect" {
  value = "alias connect='$(terraform output -raw ssm_connect)'"
}

output "db_password" {
  value     = module.ec2.db_password
  sensitive = true
}
