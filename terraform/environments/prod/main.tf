# Production Environment Configuration for Transaction Validator

terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket         = "transaction-validator-terraform-state-prod"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "transaction-validator-terraform-locks-prod"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      CostCenter  = "Engineering"
    }
  }
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Networking Module
module "networking" {
  source = "../../modules/networking"

  project_name          = var.project_name
  environment           = var.environment
  vpc_cidr              = var.vpc_cidr
  availability_zones    = var.availability_zones
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
  single_nat_gateway    = var.single_nat_gateway
  enable_flow_logs      = var.enable_flow_logs

  tags = local.common_tags
}

# Security Groups Module
module "security_groups" {
  source = "../../modules/security-groups"

  project_name        = var.project_name
  environment         = var.environment
  vpc_id              = module.networking.vpc_id
  allowed_cidr_blocks = var.allowed_cidr_blocks

  tags = local.common_tags
}

# Observability Module
module "observability" {
  source = "../../modules/observability"

  project_name             = var.project_name
  environment              = var.environment
  region                   = var.aws_region
  alert_email_addresses    = var.alert_email_addresses
  log_retention_days       = var.log_retention_days
  audit_log_retention_days = var.audit_log_retention_days

  tags = local.common_tags
}

# Database Module
module "database" {
  source = "../../modules/database"

  project_name            = var.project_name
  environment             = var.environment
  subnet_ids              = module.networking.database_subnet_ids
  security_group_id       = module.security_groups.aurora_security_group_id
  availability_zones      = var.availability_zones
  database_name           = var.database_name
  master_username         = var.database_master_username
  engine_version          = var.aurora_engine_version
  instance_class          = var.aurora_instance_class
  instance_count          = var.aurora_instance_count
  backup_retention_period = var.database_backup_retention_period
  deletion_protection     = var.database_deletion_protection
  skip_final_snapshot     = var.database_skip_final_snapshot
  alarm_actions           = [module.observability.sns_topic_arn]

  tags = local.common_tags
}

# Cache Module
module "cache" {
  source = "../../modules/cache"

  project_name             = var.project_name
  environment              = var.environment
  subnet_ids               = module.networking.private_subnet_ids
  security_group_id        = module.security_groups.redis_security_group_id
  engine_version           = var.redis_engine_version
  node_type                = var.redis_node_type
  num_cache_nodes          = var.redis_num_cache_nodes
  multi_az_enabled         = var.redis_multi_az_enabled
  snapshot_retention_limit = var.redis_snapshot_retention_limit
  notification_topic_arn   = module.observability.sns_topic_arn
  alarm_actions            = [module.observability.sns_topic_arn]

  tags = local.common_tags
}

# EKS Module
module "eks" {
  source = "../../modules/eks"

  project_name                         = var.project_name
  environment                          = var.environment
  private_subnet_ids                   = module.networking.private_subnet_ids
  public_subnet_ids                    = module.networking.public_subnet_ids
  cluster_security_group_id            = module.security_groups.eks_cluster_security_group_id
  cluster_version                      = var.eks_cluster_version
  cluster_endpoint_public_access       = var.eks_cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.eks_cluster_endpoint_public_access_cidrs
  log_retention_days                   = var.log_retention_days
  node_groups                          = var.eks_node_groups

  tags = local.common_tags
}

# Create IAM role for application to access secrets
resource "aws_iam_role" "app_secrets_access" {
  name = "${var.project_name}-${var.environment}-app-secrets-access"

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
            "${replace(module.eks.oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:transaction-validator:transaction-validator-sa"
            "${replace(module.eks.oidc_provider_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "app_secrets_access" {
  name = "${var.project_name}-${var.environment}-app-secrets-access-policy"
  role = aws_iam_role.app_secrets_access.id

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
          module.database.secret_arn,
          module.cache.secret_arn
        ]
      }
    ]
  })
}

