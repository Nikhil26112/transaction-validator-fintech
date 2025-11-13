variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "transaction-validator"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

# Networking Variables
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.2.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.2.11.0/24", "10.2.12.0/24", "10.2.13.0/24"]
}

variable "database_subnet_cidrs" {
  description = "CIDR blocks for database subnets"
  type        = list(string)
  default     = ["10.2.21.0/24", "10.2.22.0/24", "10.2.23.0/24"]
}

variable "single_nat_gateway" {
  description = "Use single NAT gateway (not recommended for prod)"
  type        = bool
  default     = false # Multi-AZ NAT for production
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs"
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access EKS API"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Database Variables
variable "database_name" {
  description = "Name of the database"
  type        = string
  default     = "transactionvalidator"
}

variable "database_master_username" {
  description = "Master username for database"
  type        = string
  default     = "dbadmin"
}

variable "aurora_engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "15.4"
}

variable "aurora_instance_class" {
  description = "Instance class for Aurora"
  type        = string
  default     = "db.r6g.large" # Production-grade
}

variable "aurora_instance_count" {
  description = "Number of Aurora instances"
  type        = number
  default     = 3 # Multi-AZ for HA
}

variable "database_backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
}

variable "database_deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = true # Enabled for production
}

variable "database_skip_final_snapshot" {
  description = "Skip final snapshot on deletion"
  type        = bool
  default     = false # Take final snapshot in production
}

# Cache Variables
variable "redis_engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.0"
}

variable "redis_node_type" {
  description = "Redis node type"
  type        = string
  default     = "cache.r7g.large" # Production-grade
}

variable "redis_num_cache_nodes" {
  description = "Number of cache nodes"
  type        = number
  default     = 3 # Multi-AZ for HA
}

variable "redis_multi_az_enabled" {
  description = "Enable Multi-AZ for Redis"
  type        = bool
  default     = true # Enabled for production
}

variable "redis_snapshot_retention_limit" {
  description = "Number of days to retain snapshots"
  type        = number
  default     = 7
}

# EKS Variables
variable "eks_cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

variable "eks_cluster_endpoint_public_access" {
  description = "Enable public access to EKS endpoint"
  type        = bool
  default     = true
}

variable "eks_cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to access EKS endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "eks_node_groups" {
  description = "EKS node group configurations"
  type = map(object({
    desired_size   = number
    max_size       = number
    min_size       = number
    instance_types = list(string)
    capacity_type  = string
    disk_size      = number
    labels         = map(string)
    taints = list(object({
      key    = string
      value  = string
      effect = string
    }))
  }))
  default = {
    general = {
      desired_size   = 5
      max_size       = 10
      min_size       = 3
      instance_types = ["t3.large"] # Production-grade
      capacity_type  = "ON_DEMAND"
      disk_size      = 50
      labels         = {}
      taints         = []
    }
  }
}

# Observability Variables
variable "alert_email_addresses" {
  description = "Email addresses for alerts"
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "Log retention in days"
  type        = number
  default     = 30 # Longer retention for production
}

variable "audit_log_retention_days" {
  description = "Audit log retention in days"
  type        = number
  default     = 90
}

