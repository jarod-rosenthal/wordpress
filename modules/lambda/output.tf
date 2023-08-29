output "sns_topic" {
    value = aws_sns_topic.instance_failure.arn
}
