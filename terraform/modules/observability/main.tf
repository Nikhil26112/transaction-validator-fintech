# Observability Module - CloudWatch and SNS for Transaction Validator

# SNS Topic for Alerts
resource "aws_sns_topic" "alerts" {
  name              = "${var.project_name}-${var.environment}-alerts"
  display_name      = "Alerts for ${var.project_name} ${var.environment}"
  kms_master_key_id = var.kms_key_id

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-alerts"
    }
  )
}

# SNS Topic Policy
resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "cloudwatch.amazonaws.com",
            "events.amazonaws.com"
          ]
        }
        Action = [
          "SNS:Publish"
        ]
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}

# SNS Email Subscription
resource "aws_sns_topic_subscription" "alerts_email" {
  for_each = toset(var.alert_email_addresses)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "application" {
  name              = "/aws/application/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "audit" {
  name              = "/aws/audit/${var.project_name}-${var.environment}"
  retention_in_days = var.audit_log_retention_days

  tags = var.tags
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-${var.environment}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/EKS", "cluster_failed_node_count", { stat = "Average", period = 300 }],
            [".", "cluster_node_count", { stat = "Average", period = 300 }]
          ]
          period = 300
          region = var.region
          title  = "EKS Cluster Nodes"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", { stat = "Average", period = 300 }],
            [".", "DatabaseConnections", { stat = "Average", period = 300 }]
          ]
          period = 300
          region = var.region
          title  = "RDS Metrics"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ElastiCache", "CPUUtilization", { stat = "Average", period = 300 }],
            [".", "DatabaseMemoryUsagePercentage", { stat = "Average", period = 300 }]
          ]
          period = 300
          region = var.region
          title  = "ElastiCache Metrics"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type = "log"
        properties = {
          query  = "SOURCE '/aws/application/${var.project_name}-${var.environment}' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          region = var.region
          title  = "Recent Application Logs"
        }
      }
    ]
  })
}

# CloudWatch Metric Filters
resource "aws_cloudwatch_log_metric_filter" "error_count" {
  name           = "${var.project_name}-${var.environment}-error-count"
  log_group_name = aws_cloudwatch_log_group.application.name
  pattern        = "[timestamp, request_id, level = ERROR*, ...]"

  metric_transformation {
    name      = "ErrorCount"
    namespace = "${var.project_name}/${var.environment}"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "fatal_count" {
  name           = "${var.project_name}-${var.environment}-fatal-count"
  log_group_name = aws_cloudwatch_log_group.application.name
  pattern        = "[timestamp, request_id, level = FATAL*, ...]"

  metric_transformation {
    name      = "FatalCount"
    namespace = "${var.project_name}/${var.environment}"
    value     = "1"
  }
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  alarm_name          = "${var.project_name}-${var.environment}-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ErrorCount"
  namespace           = "${var.project_name}/${var.environment}"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.error_rate_threshold
  alarm_description   = "This metric monitors application error rate"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "fatal_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-fatal-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FatalCount"
  namespace           = "${var.project_name}/${var.environment}"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors fatal errors"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = var.tags
}

# CloudWatch Event Rule for EKS Events
resource "aws_cloudwatch_event_rule" "eks_events" {
  name        = "${var.project_name}-${var.environment}-eks-events"
  description = "Capture EKS events"

  event_pattern = jsonencode({
    source      = ["aws.eks"]
    detail-type = ["EKS Cluster State Change"]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "eks_events_sns" {
  rule      = aws_cloudwatch_event_rule.eks_events.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.alerts.arn
}

# CloudWatch Composite Alarm for Critical System Health
resource "aws_cloudwatch_composite_alarm" "critical_system_health" {
  alarm_name        = "${var.project_name}-${var.environment}-critical-system-health"
  alarm_description = "Composite alarm for critical system health"
  actions_enabled   = true
  alarm_actions     = [aws_sns_topic.alerts.arn]
  ok_actions        = [aws_sns_topic.alerts.arn]

  alarm_rule = "ALARM(${aws_cloudwatch_metric_alarm.high_error_rate.alarm_name}) OR ALARM(${aws_cloudwatch_metric_alarm.fatal_errors.alarm_name})"

  tags = var.tags
}

# IAM Role for CloudWatch to write logs
resource "aws_iam_role" "cloudwatch_logs" {
  name = "${var.project_name}-${var.environment}-cloudwatch-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "cloudwatch_logs" {
  name = "${var.project_name}-${var.environment}-cloudwatch-logs-policy"
  role = aws_iam_role.cloudwatch_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Log Insights Queries
resource "aws_cloudwatch_query_definition" "error_analysis" {
  name = "${var.project_name}-${var.environment}/error-analysis"

  log_group_names = [
    aws_cloudwatch_log_group.application.name
  ]

  query_string = <<-QUERY
    fields @timestamp, @message, level, error
    | filter level = "ERROR"
    | sort @timestamp desc
    | limit 100
  QUERY
}

resource "aws_cloudwatch_query_definition" "slow_queries" {
  name = "${var.project_name}-${var.environment}/slow-queries"

  log_group_names = [
    aws_cloudwatch_log_group.application.name
  ]

  query_string = <<-QUERY
    fields @timestamp, @message, duration_ms
    | filter duration_ms > 1000
    | sort duration_ms desc
    | limit 50
  QUERY
}

resource "aws_cloudwatch_query_definition" "transaction_stats" {
  name = "${var.project_name}-${var.environment}/transaction-stats"

  log_group_names = [
    aws_cloudwatch_log_group.application.name
  ]

  query_string = <<-QUERY
    fields @timestamp, transaction_id, status
    | stats count() by status
  QUERY
}

