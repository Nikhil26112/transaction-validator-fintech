#!/bin/bash
# Setup Terraform Backend (S3 + DynamoDB)
# This script creates the S3 bucket and DynamoDB table for Terraform state management

set -e

# Configuration
PROJECT_NAME="transaction-validator"
REGION="us-east-1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if user is authenticated
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials not configured. Run 'aws configure' first."
    exit 1
fi

print_info "Setting up Terraform backend for $PROJECT_NAME in $REGION"

# Function to create backend for an environment
setup_environment() {
    local ENV=$1
    local BUCKET_NAME="${PROJECT_NAME}-terraform-state-${ENV}"
    local LOCK_TABLE="${PROJECT_NAME}-terraform-locks-${ENV}"
    
    print_info "Setting up backend for environment: $ENV"
    
    # Create S3 bucket
    print_info "Creating S3 bucket: $BUCKET_NAME"
    if aws s3 ls "s3://${BUCKET_NAME}" 2>&1 | grep -q 'NoSuchBucket'; then
        aws s3api create-bucket \
            --bucket "$BUCKET_NAME" \
            --region "$REGION" \
            --create-bucket-configuration LocationConstraint="$REGION" 2>/dev/null || \
        aws s3api create-bucket \
            --bucket "$BUCKET_NAME" \
            --region "$REGION" 2>/dev/null
        
        # Enable versioning
        print_info "Enabling versioning on S3 bucket"
        aws s3api put-bucket-versioning \
            --bucket "$BUCKET_NAME" \
            --versioning-configuration Status=Enabled \
            --region "$REGION"
        
        # Enable encryption
        print_info "Enabling encryption on S3 bucket"
        aws s3api put-bucket-encryption \
            --bucket "$BUCKET_NAME" \
            --server-side-encryption-configuration '{
                "Rules": [{
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }]
            }' \
            --region "$REGION"
        
        # Block public access
        print_info "Blocking public access on S3 bucket"
        aws s3api put-public-access-block \
            --bucket "$BUCKET_NAME" \
            --public-access-block-configuration \
                BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
            --region "$REGION"
        
        # Add lifecycle policy to transition old versions
        print_info "Adding lifecycle policy to S3 bucket"
        aws s3api put-bucket-lifecycle-configuration \
            --bucket "$BUCKET_NAME" \
            --lifecycle-configuration '{
                "Rules": [{
                    "Id": "DeleteOldVersions",
                    "Status": "Enabled",
                    "NoncurrentVersionExpiration": {
                        "NoncurrentDays": 90
                    }
                }]
            }' \
            --region "$REGION"
        
        print_info "S3 bucket $BUCKET_NAME created successfully"
    else
        print_warning "S3 bucket $BUCKET_NAME already exists"
    fi
    
    # Create DynamoDB table for state locking
    print_info "Creating DynamoDB table: $LOCK_TABLE"
    if ! aws dynamodb describe-table --table-name "$LOCK_TABLE" --region "$REGION" &> /dev/null; then
        aws dynamodb create-table \
            --table-name "$LOCK_TABLE" \
            --attribute-definitions AttributeName=LockID,AttributeType=S \
            --key-schema AttributeName=LockID,KeyType=HASH \
            --billing-mode PAY_PER_REQUEST \
            --region "$REGION" \
            --tags Key=Project,Value="$PROJECT_NAME" Key=Environment,Value="$ENV" Key=ManagedBy,Value=Script \
            > /dev/null
        
        print_info "Waiting for DynamoDB table to be active..."
        aws dynamodb wait table-exists --table-name "$LOCK_TABLE" --region "$REGION"
        
        # Enable point-in-time recovery
        print_info "Enabling point-in-time recovery on DynamoDB table"
        aws dynamodb update-continuous-backups \
            --table-name "$LOCK_TABLE" \
            --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true \
            --region "$REGION" \
            > /dev/null
        
        print_info "DynamoDB table $LOCK_TABLE created successfully"
    else
        print_warning "DynamoDB table $LOCK_TABLE already exists"
    fi
    
    echo ""
}

# Setup backends for all environments
setup_environment "dev"
setup_environment "staging"
setup_environment "prod"

print_info "Terraform backend setup complete!"
echo ""
print_info "Next steps:"
echo "1. cd terraform/environments/dev (or staging/prod)"
echo "2. terraform init"
echo "3. terraform plan"
echo "4. terraform apply"
echo ""
print_info "Backend configuration:"
cat << EOF

terraform {
  backend "s3" {
    bucket         = "${PROJECT_NAME}-terraform-state-ENV"
    key            = "ENV/terraform.tfstate"
    region         = "${REGION}"
    encrypt        = true
    dynamodb_table = "${PROJECT_NAME}-terraform-locks-ENV"
  }
}

(Replace ENV with dev, staging, or prod)
EOF

