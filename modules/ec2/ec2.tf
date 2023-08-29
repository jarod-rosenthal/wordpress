# Security Group for WordPress instances
resource "aws_security_group" "wordpress" {
  count  = length(var.domains)
  name   = var.domains[count.index]
  vpc_id = var.vpc_id

  # Allow HTTP and HTTPS traffic
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = var.domains[count.index]
  }
}

# Allow SSH access if SSH key is created
resource "aws_security_group_rule" "ssh_access" {
  count             = var.create_ssh_key ? length(var.domains) : 0
  security_group_id = aws_security_group.wordpress[count.index].id
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

# Security Group for EFS
resource "aws_security_group" "efs_sg" {
  name   = "efs-sg"
  vpc_id = var.vpc_id

  # Allow NFS traffic from WordPress instances
  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    security_groups = flatten([aws_security_group.wordpress.*.id])
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "EFS Security Group"
  }
}

# IAM Instance Profile for WordPress instances
resource "aws_iam_instance_profile" "instance_profile" {
  count = length(var.domains)
  name  = var.domains[count.index]
  role  = aws_iam_role.instance_role[count.index].name
}

# IAM Role for WordPress instances
resource "aws_iam_role" "instance_role" {
  count = length(var.domains)
  name  = "${var.domains[count.index]}-instance-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

# Attach necessary policies to the IAM Role
resource "aws_iam_role_policy_attachment" "ssm_policy_attachment" {
  count      = length(var.domains)
  role       = aws_iam_role.instance_role[count.index].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_policy_attachment" {
  count      = length(var.domains)
  role       = aws_iam_role.instance_role[count.index].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "efs_file_system" {
  count      = length(var.domains)
  role       = aws_iam_role.instance_role[count.index].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonElasticFileSystemFullAccess"
}

# SSH Key Pair for WordPress instances
resource "tls_private_key" "ssh_key" {
  count      = var.create_ssh_key ? length(var.domains) : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "deployer" {
  count      = var.create_ssh_key ? length(var.domains) : 0
  key_name   = var.domains[count.index]
  public_key = tls_private_key.ssh_key[count.index].public_key_openssh
}

resource "aws_eip" "wordpress_eip" {
  count      = length(var.domains)
  instance   = aws_instance.wordpress_instance[count.index].id
  domain     = "vpc"
  depends_on = [aws_instance.wordpress_instance]

  lifecycle {
    prevent_destroy = true
  }
  tags = {
    Name = var.domains[count.index]
  }
}

resource "aws_eip_association" "wordpress_eip_association" {
  count      = length(var.domains)
  instance_id = aws_instance.wordpress_instance[count.index].id
  allocation_id = aws_eip.wordpress_eip[count.index].id
}

# WordPress EC2 instances
resource "aws_instance" "wordpress_instance" {
  count         = length(var.domains)
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.create_ssh_key ? aws_key_pair.deployer[0].key_name : ""
  iam_instance_profile = aws_iam_instance_profile.instance_profile[count.index].name
  user_data     = base64encode(templatefile("${path.module}/userdata.tpl", {
    domain      = var.domains[count.index],
    db_name     = var.db_name,
    db_user     = var.db_user,
    db_password = var.db_password,
    db_endpoint = var.db_endpoint,
    efs_file_system = var.efs_dns,
    email       = var.email
    dry_run     = var.dry_run 
  }))

  vpc_security_group_ids = [aws_security_group.wordpress[count.index].id]
  subnet_id = var.public_subnets[count.index % length(var.public_subnets)]

  lifecycle {
    create_before_destroy = true
  }

  dynamic "instance_market_options" {
    for_each = var.use_spot ? [1] : []
    content {
      market_type = "spot"

      spot_options {
        max_price          = ""
        spot_instance_type = "one-time"
      }
    }
  }

  tags = {
    Name = "${var.domains[count.index]}-${count.index}"
  }
}

resource "aws_cloudwatch_metric_alarm" "webserver_health_alarm" {
  alarm_name          = "Webserver-Health-Check-Failure"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"
  alarm_description   = "This metric checks the health of the webserver."
  alarm_actions       = [aws_sns_topic.instance_failure.arn]

  dimensions = {
    HealthCheckId = aws_route53_health_check.webserver_health_check.id
  }
}

resource "aws_route53_health_check" "webserver_health_check" {
  fqdn            = length(var.domains)
  port            = 443
  type            = "HTTPS"
  resource_path   = "/"
  failure_threshold = 3  
  request_interval  = 30 
  measure_latency   = true
}

# IAM Role and Policy for Lambda function
resource "aws_iam_role" "lambda_ec2_role" {
  name = "lambda_ec2_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      }
    ]
  })
}

# Attach necessary policies to the IAM Role
resource "aws_iam_role_policy_attachment" "lambda_ec2_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"  # Basic Lambda execution policy
  role       = aws_iam_role.lambda_ec2_role.name
}

resource "aws_iam_role_policy_attachment" "ec2_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"  # EC2 full access policy
  role       = aws_iam_role.lambda_ec2_role.name
}

resource "aws_iam_role_policy_attachment" "efs_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonElasticFileSystemFullAccess"  # EFS full access policy
  role       = aws_iam_role.lambda_ec2_role.name
}

# Allow the Lambda function to be invoked by SNS
resource "aws_lambda_permission" "sns_permission" {
  statement_id  = "AllowSNSInvokeLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.replace_instance.function_name
  principal     = "sns.amazonaws.com"
}

# Create a zip archive of the Lambda function
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function_payload.py"
  output_path = "${path.module}/lambda_function_payload.zip"
}

resource "aws_lambda_function" "replace_instance" {
  function_name    = "replace_instance"
  handler          = "lambda_function_payload.handler"
  runtime          = "python3.10"
  role             = aws_iam_role.lambda_ec2_role.arn
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  vpc_config {
    subnet_ids         = var.private_subnets
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      ami_id            = var.ami_id
      instance_type     = var.instance_type
      key_name          = var.create_ssh_key ? aws_key_pair.deployer[0].key_name : ""
      user_data         = "efs:/mnt/efs/${var.domains[0]}.sh" 
    }
  }
}

# Lambda Security Group
resource "aws_security_group" "lambda_sg" {
  name   = "lambda-sg"
  vpc_id = var.vpc_id

  # Allow outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# SNS topic for auto recovery
resource "aws_sns_topic" "instance_failure" {
  name = "instance-failure"
}

# SNS subscription to trigger Lambda function
resource "aws_sns_topic_subscription" "lambda_sns_subscription" {
  topic_arn = aws_sns_topic.instance_failure.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.replace_instance.arn
}

# Permission for SNS to trigger Lambda
resource "aws_lambda_permission" "allow_sns_to_trigger_lambda" {
  statement_id  = "AllowSNSToTriggerLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.replace_instance.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.instance_failure.arn
}
