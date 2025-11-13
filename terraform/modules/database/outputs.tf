output "cluster_id" {
  description = "The ID of the Aurora cluster"
  value       = aws_rds_cluster.main.id
}

output "cluster_endpoint" {
  description = "The cluster endpoint"
  value       = aws_rds_cluster.main.endpoint
}

output "reader_endpoint" {
  description = "The cluster reader endpoint"
  value       = aws_rds_cluster.main.reader_endpoint
}

output "cluster_port" {
  description = "The port the cluster is listening on"
  value       = aws_rds_cluster.main.port
}

output "database_name" {
  description = "The name of the default database"
  value       = aws_rds_cluster.main.database_name
}

output "master_username" {
  description = "The master username"
  value       = aws_rds_cluster.main.master_username
  sensitive   = true
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret containing database credentials"
  value       = aws_secretsmanager_secret.db_master_password.arn
}

output "cluster_resource_id" {
  description = "The Resource ID of the cluster"
  value       = aws_rds_cluster.main.cluster_resource_id
}

