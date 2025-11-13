output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.networking.vpc_id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.networking.private_subnet_ids
}

output "database_subnet_ids" {
  description = "List of database subnet IDs"
  value       = module.networking.database_subnet_ids
}

output "eks_cluster_id" {
  description = "The name/id of the EKS cluster"
  value       = module.eks.cluster_id
}

output "eks_cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "eks_oidc_provider_arn" {
  description = "ARN of the OIDC Provider for EKS"
  value       = module.eks.oidc_provider_arn
}

output "aurora_cluster_endpoint" {
  description = "Writer endpoint for the Aurora cluster"
  value       = module.database.cluster_endpoint
}

output "aurora_reader_endpoint" {
  description = "Reader endpoint for the Aurora cluster"
  value       = module.database.reader_endpoint
}

output "aurora_database_name" {
  description = "Name of the default database"
  value       = module.database.database_name
}

output "aurora_master_username" {
  description = "Master username for the Aurora cluster"
  value       = module.database.master_username
  sensitive   = true
}

output "aurora_secret_arn" {
  description = "ARN of the Secrets Manager secret containing database credentials"
  value       = module.database.master_password_secret_arn
}

output "redis_endpoint" {
  description = "Endpoint for the Redis cluster"
  value       = module.cache.primary_endpoint
}

output "app_secrets_role_arn" {
  description = "ARN of the IAM role for application to access secrets"
  value       = aws_iam_role.app_secrets_role.arn
}

