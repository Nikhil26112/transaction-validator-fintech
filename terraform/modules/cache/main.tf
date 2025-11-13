# ElastiCache Redis Module for Transaction Validator

# Subnet Group
resource "aws_elasticache_subnet_group" "main" {
  name        = "${var.project_name}-${var.environment}-redis-subnet-group"
  description = "Subnet group for ElastiCache Redis"
  subnet_ids  = var.subnet_ids

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-redis-subnet-group"
    }
  )
}

# Parameter Group
resource "aws_elasticache_parameter_group" "main" {
  name   = "${var.project_name}-${var.environment}-redis-params"
  family = var.parameter_group_family

  # Optimizations for session caching
  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  parameter {
    name  = "timeout"
    value = "300"
  }

  parameter {
    name  = "tcp-keepalive"
    value = "300"
  }

  tags = var.tags
}

# Replication Group (Cluster)
resource "aws_elasticache_replication_group" "main" {
  replication_group_id          = "${var.project_name}-${var.environment}-redis"
  replication_group_description = "Redis cluster for ${var.project_name} ${var.environment}"

  engine               = "redis"
  engine_version       = var.engine_version
  node_type            = var.node_type
  port                 = 6379
  parameter_group_name = aws_elasticache_parameter_group.main.name
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [var.security_group_id]

  # Cluster configuration
  num_cache_clusters         = var.num_cache_nodes
  automatic_failover_enabled = var.num_cache_nodes > 1 ? true : false
  multi_az_enabled           = var.num_cache_nodes > 1 ? var.multi_az_enabled : false

  # Encryption
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token_enabled         = true
  auth_token                 = random_password.redis_auth_token.result
  kms_key_id                 = var.kms_key_id

  # Maintenance and backup
  maintenance_window       = var.maintenance_window
  snapshot_window          = var.snapshot_window
  snapshot_retention_limit = var.snapshot_retention_limit

  # Auto minor version upgrade
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  # Notifications
  notification_topic_arn = var.notification_topic_arn

  # Logging
  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_slow_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_engine_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "engine-log"
  }

  # Apply changes immediately in non-prod
  apply_immediately = var.environment != "prod"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-redis"
    }
  )

  lifecycle {
    ignore_changes = [auth_token]
  }
}

# Random auth token for Redis
resource "random_password" "redis_auth_token" {
  length  = 32
  special = false # Redis auth token doesn't support special characters
}

# Store auth token in Secrets Manager
resource "aws_secretsmanager_secret" "redis_auth_token" {
  name        = "${var.project_name}-${var.environment}-redis-auth-token"
  description = "Auth token for Redis cluster"

  recovery_window_in_days = var.secret_recovery_window_days

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "redis_auth_token" {
  secret_id = aws_secretsmanager_secret.redis_auth_token.id
  secret_string = jsonencode({
    auth_token = random_password.redis_auth_token.result
    endpoint   = aws_elasticache_replication_group.main.configuration_endpoint_address
    port       = 6379
  })
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "redis_slow_log" {
  name              = "/aws/elasticache/${var.project_name}-${var.environment}/redis/slow-log"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "redis_engine_log" {
  name              = "/aws/elasticache/${var.project_name}-${var.environment}/redis/engine-log"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "redis_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-redis-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "This metric monitors Redis CPU utilization"
  alarm_actions       = var.alarm_actions

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.main.id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "redis_memory" {
  alarm_name          = "${var.project_name}-${var.environment}-redis-memory-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Average"
  threshold           = var.memory_alarm_threshold
  alarm_description   = "This metric monitors Redis memory utilization"
  alarm_actions       = var.alarm_actions

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.main.id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "redis_evictions" {
  alarm_name          = "${var.project_name}-${var.environment}-redis-evictions"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Evictions"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.evictions_alarm_threshold
  alarm_description   = "This metric monitors Redis evictions"
  alarm_actions       = var.alarm_actions

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.main.id
  }

  tags = var.tags
}

