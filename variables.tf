variable "region" {
  default = "us-east-2"
}

variable "use_spot" {
  default = true
}

variable "create_ssh_key" {
  default = false
}

variable "db_name" {
    default = "wordpress"
}

variable "allocated_storage" {
  default = 10
}

variable "instance_type" {
  default = "t3.micro"
}

variable "email" {
  default = "jarodrosenthal@protonmail.com"
}

variable "dry_run" {
  default = false
}

variable "domain_names" {
  description = "List of domain names"
  type        = list(string)
  default     = [
    "therealjarod.com"
  ]
}

variable "ami_map" {
  description = "AMI map for Amazon Linux 2023 in US regions"
  type        = map(string)

  default = {
    "us-east-1"      = "ami-051f7e7f6c2f40dc1" # N. Virginia
    "us-east-2"      = "ami-0cf0e376c672104d6" # Ohio
    "us-west-1"      = "ami-03f2f5212f24db70a" # N. California
    "us-west-2"      = "ami-002829755fa238bfa" # Oregon
  }
}

variable "az_map" {
  description = "AZ map for subnets in US regions"
  type        = map(list(string))

  default = {
    "us-east-1"      = ["us-east-1a", "us-east-1b"] # N. Virginia
    "us-east-2"      = ["us-east-2a", "us-east-2b"] # Ohio
    "us-west-1"      = ["us-west-1a", "us-west-1b"] # N. California
    "us-west-2"      = ["us-west-2a", "us-west-2b"] # Oregon
  }
}
