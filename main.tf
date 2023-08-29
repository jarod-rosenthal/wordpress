# Terraform Configuration for AWS Infrastructure Deployment

# Specify required providers and their versions
terraform {
  required_version = ">= 1.4.6" 

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.14.0"
    }
  }
  backend "local" {}  # Use local backend for state management
}

# AWS Provider Configuration
provider "aws" {
  region = var.region  # Set the AWS region from variable
}

# VPC Module: Creates a Virtual Private Cloud (VPC) for the infrastructure
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = var.db_name
  cidr = "10.10.0.0/16"
  azs             = var.az_map[var.region]
  private_subnets = ["10.10.1.0/24", "10.10.2.0/24"]
  public_subnets  = ["10.10.101.0/24", "10.10.102.0/24"]
  enable_nat_gateway = true
  single_nat_gateway  = true
  enable_vpn_gateway = true
  tags = {
    Terraform = true
  }
}

# EC2 Module: Manages EC2 instances for the application
module "ec2" {
  source = "./modules/ec2"
  depends_on = [module.vpc]
  domains = var.domain_names
  email = var.email
  ami_id = var.ami_map[var.region]
  use_spot = var.use_spot
  instance_type = var.instance_type
  create_ssh_key = var.create_ssh_key
  private_subnets = module.vpc.private_subnets
  public_subnets = module.vpc.public_subnets
  vpc_id = module.vpc.vpc_id
  db_name     = var.db_name
  db_user     = var.db_name
  db_password = local.db_password
  db_endpoint = module.rds.db_endpoint
  efs_dns     = module.efs.efs_dns
  dry_run     = var.dry_run
}

module "efs" {
  source = "./modules/efs"
  depends_on = [module.vpc]
  db_name     = var.db_name
  efs_sg      = module.ec2.efs_security_group
  private_subnets   = module.vpc.private_subnets
}

# RDS Module: Manages the Relational Database Service (RDS) for the application
module "rds" {
  source = "./modules/rds"
  depends_on = [module.vpc]
  vpc_id            = module.vpc.vpc_id
  private_subnets   = module.vpc.private_subnets
  allocated_storage = var.allocated_storage
  instance_class    = "db.t3.micro"
  engine            = "mariadb"
  engine_version    = "10.5"
  db_name           = var.db_name
  db_user           = var.db_name
  db_password       = local.db_password
  ec2_security_group = module.ec2.ec2_security_group
}

# Route53 Module: Manages DNS records for the application
module "route53" {
  source = "./modules/route53"
  depends_on = [module.vpc, module.ec2]
  domain_names = var.domain_names
  public_ips = module.ec2.instance_ips
}

# Local values for database user and password generation
locals {
  db_password = random_string.password.result
}

# Generate a random string for the database password
resource "random_string" "password" {
  length  = 18
  special = false
}
