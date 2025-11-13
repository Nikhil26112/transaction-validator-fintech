terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "transaction-validator-terraform-state-staging"
    key            = "staging/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "transaction-validator-terraform-locks-staging"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "transaction-validator"
      ManagedBy   = "terraform"
    }
  }
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# Networking Module
module "networking" {
  source = "../../modules/networking"

  environment           = var.environment
  project_name          = var.project_name
  vpc_cidr              = var.vpc_cidr
  availability_zones    = var.availability_zones
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
  enable_nat_gateway    = var.enable_nat_gateway
  single_nat_gateway    = var.single_nat_gateway
  enable_dns_hostnames  = var.enable_dns_hostnames
  enable_dns_support    = var.enable_dns_support
  enable_flow_logs      = var.enable_flow_logs
}

# Security Groups Module
module "security_groups" {
  source = "../../modules/security-groups"

  environment  = var.environment
  project_name = var.project_name
  vpc_id       = module.networking.vpc_id
  vpc_cidr     = var.vpc_cidr
}

# Database Module
module "database" {
  source = "../../modules/database"

  environment                  = var.environment
  project_name                 = var.project_name
  vpc_id                       = module.networking.vpc_id
  database_subnet_ids          = module.networking.database_subnet_ids
  security_group_ids           = [module.security_groups.aurora_security_group_id]
  engine_version               = var.db_engine_version
  instance_class               = var.db_instance_class
  instance_count               = var.db_instance_count
  database_name                = var.db_database_name
  master_username              = var.db_master_username
  backup_retention_period      = var.db_backup_retention_period
  preferred_backup_window      = var.db_preferred_backup_window
  preferred_maintenance_window = var.db_preferred_maintenance_window
  deletion_protection          = var.db_deletion_protection
  skip_final_snapshot          = var.db_skip_final_snapshot
  apply_immediately            = var.db_apply_immediately
  auto_minor_version_upgrade   = var.db_auto_minor_version_upgrade
}

# Cache Module
module "cache" {
  source = "../../modules/cache"

  environment                = var.environment
  project_name               = var.project_name
  vpc_id                     = module.networking.vpc_id
  subnet_ids                 = module.networking.private_subnet_ids
  security_group_ids         = [module.security_groups.redis_security_group_id]
  node_type                  = var.redis_node_type
  num_cache_nodes            = var.redis_num_cache_nodes
  parameter_group_family     = var.redis_parameter_group_family
  engine_version             = var.redis_engine_version
  port                       = var.redis_port
  snapshot_retention_limit   = var.redis_snapshot_retention_limit
  snapshot_window            = var.redis_snapshot_window
  maintenance_window         = var.redis_maintenance_window
  automatic_failover_enabled = var.redis_automatic_failover_enabled
  multi_az_enabled           = var.redis_multi_az_enabled
  auto_minor_version_upgrade = var.redis_auto_minor_version_upgrade
}

# EKS Module
module "eks" {
  source = "../../modules/eks"

  environment                     = var.environment
  project_name                    = var.project_name
  vpc_id                          = module.networking.vpc_id
  private_subnet_ids              = module.networking.private_subnet_ids
  cluster_version                 = var.eks_cluster_version
  node_instance_types             = var.eks_node_instance_types
  node_desired_size               = var.eks_node_desired_size
  node_min_size                   = var.eks_node_min_size
  node_max_size                   = var.eks_node_max_size
  node_disk_size                  = var.eks_node_disk_size
  cluster_endpoint_private_access = var.eks_cluster_endpoint_private_access
  cluster_endpoint_public_access  = var.eks_cluster_endpoint_public_access
  enable_irsa                     = var.eks_enable_irsa

  # Security
  cluster_security_group_id = module.security_groups.eks_cluster_security_group_id
  node_security_group_id    = module.security_groups.eks_node_security_group_id
}

# Observability Module
module "observability" {
  source = "../../modules/observability"

  environment        = var.environment
  project_name       = var.project_name
  log_retention_days = var.cloudwatch_log_retention_days
  alert_email        = var.alert_email

  # Resource ARNs for monitoring
  eks_cluster_name  = module.eks.cluster_name
  aurora_cluster_id = module.database.cluster_id
  redis_cluster_id  = module.cache.cluster_id
}

# IAM Role for Application to Access Secrets Manager
resource "aws_iam_role" "app_secrets_role" {
  name = "${local.name_prefix}-app-secrets-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${module.eks.oidc_provider}:sub" = "system:serviceaccount:transaction-validator:transaction-validator"
            "${module.eks.oidc_provider}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-app-secrets-role"
  }
}

resource "aws_iam_role_policy" "app_secrets_policy" {
  name = "${local.name_prefix}-app-secrets-policy"
  role = aws_iam_role.app_secrets_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          module.database.master_password_secret_arn,
          "${module.database.master_password_secret_arn}*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

