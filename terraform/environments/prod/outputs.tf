# Outputs for Production Environment

output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_id
}

output "database_endpoint" {
  description = "Aurora database endpoint"
  value       = module.database.cluster_endpoint
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = module.cache.configuration_endpoint_address
}

output "database_secret_arn" {
  description = "ARN of database credentials secret"
  value       = module.database.secret_arn
}

output "redis_secret_arn" {
  description = "ARN of Redis auth token secret"
  value       = module.cache.secret_arn
}

output "app_secrets_role_arn" {
  description = "ARN of IAM role for application secrets access"
  value       = aws_iam_role.app_secrets_access.arn
}

output "cluster_autoscaler_role_arn" {
  description = "ARN of cluster autoscaler IAM role"
  value       = module.eks.cluster_autoscaler_role_arn
}

output "aws_load_balancer_controller_role_arn" {
  description = "ARN of AWS Load Balancer Controller IAM role"
  value       = module.eks.aws_load_balancer_controller_role_arn
}

output "sns_topic_arn" {
  description = "ARN of SNS topic for alerts"
  value       = module.observability.sns_topic_arn
}

output "cloudwatch_dashboard_url" {
  description = "URL of CloudWatch dashboard"
  value       = module.observability.dashboard_url
}

