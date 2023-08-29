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
