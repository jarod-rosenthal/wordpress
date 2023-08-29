resource "aws_db_subnet_group" "wordpress" {
  name       = "${var.db_name}-db-subnet-group"
  subnet_ids = var.private_subnets
  tags = {
    Name = "${var.db_name}-db-subnet-group"
  }
}

resource "aws_security_group" "rds_wordpress" {
  name   = "${var.db_name}-rds"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = var.ec2_security_group
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.db_name}-rds"
  }
}

resource "aws_db_instance" "wordpress" {
  depends_on = [aws_db_subnet_group.wordpress]
  allocated_storage    = var.allocated_storage
  storage_type         = "gp2"
  engine               = var.engine
  engine_version       = var.engine_version
  instance_class       = var.instance_class
  db_name              = var.db_name
  username             = var.db_user
  password             = var.db_password
  parameter_group_name = "default.mariadb10.5"
  skip_final_snapshot  = true
  vpc_security_group_ids = [aws_security_group.rds_wordpress.id]
  db_subnet_group_name   = aws_db_subnet_group.wordpress.name
  tags = {
    Name = "${var.db_name}-rds"
  }
}