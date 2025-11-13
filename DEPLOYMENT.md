# Deployment Guide

Quick reference for deploying the Transaction Validator infrastructure.

## Prerequisites

- AWS CLI configured
- Terraform >= 1.8.0
- kubectl >= 1.30
- Helm >= 3.10
- Docker

## Step 1: Setup Terraform Backend

Create S3 buckets and DynamoDB tables for Terraform state:

```bash
./scripts/setup-terraform-backend.sh
```

This creates:
- S3 buckets: `transaction-validator-terraform-state-{env}`
- DynamoDB tables: `transaction-validator-terraform-locks-{env}`

## Step 2: Deploy Infrastructure

### Development

```bash
cd terraform/environments/dev

# Copy and edit tfvars
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars  # Update with your values

# Deploy
terraform init
terraform plan
terraform apply
```

### Production

```bash
cd terraform/environments/prod

# Copy and edit tfvars
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars  # Update with production values

# Deploy
terraform init
terraform plan
terraform apply
```

**⚠️ Review plan carefully before applying to production!**

## Step 3: Configure kubectl

```bash
# Get kubeconfig for EKS
aws eks update-kubeconfig --name transaction-validator-dev --region us-east-1

# Verify
kubectl get nodes
```

## Step 4: Install Prerequisites

### AWS Load Balancer Controller

```bash
# Add Helm repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Get IAM role ARN from Terraform
ROLE_ARN=$(cd terraform/environments/dev && terraform output -raw aws_load_balancer_controller_role_arn)

# Install
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=transaction-validator-dev \
  --set serviceAccount.create=true \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ROLE_ARN
```

### Cluster Autoscaler (Optional)

```bash
# Get IAM role ARN
ROLE_ARN=$(cd terraform/environments/dev && terraform output -raw cluster_autoscaler_role_arn)

# Install
kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml

# Add annotation
kubectl annotate serviceaccount cluster-autoscaler \
  -n kube-system \
  eks.amazonaws.com/role-arn=$ROLE_ARN
```

## Step 5: Deploy Application with Helm

### Get Secrets

First, get database and Redis endpoints from Terraform:

```bash
cd terraform/environments/dev
DB_ENDPOINT=$(terraform output -raw database_endpoint)
REDIS_ENDPOINT=$(terraform output -raw redis_endpoint)
```

### Install Helm Chart

```bash
# Get IAM role for app
ROLE_ARN=$(cd terraform/environments/dev && terraform output -raw app_secrets_role_arn)

# Install
helm install transaction-validator ./helm/transaction-validator \
  --namespace transaction-validator \
  --create-namespace \
  --values ./helm/transaction-validator/values-dev.yaml \
  --set image.repository=<YOUR_ECR_REGISTRY>/transaction-validator \
  --set image.tag=latest \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ROLE_ARN \
  --set secrets.databaseUrl="postgresql://user:pass@$DB_ENDPOINT:5432/transactionvalidator" \
  --set secrets.redisEndpoint="redis://$REDIS_ENDPOINT:6379"
```

### Verify Deployment

```bash
# Check pods
kubectl get pods -n transaction-validator

# Check services
kubectl get svc -n transaction-validator

# Check ingress (ALB takes ~3 minutes to provision)
kubectl get ingress -n transaction-validator
```

## Step 6: Test Application

```bash
# Port forward for local testing
kubectl port-forward -n transaction-validator svc/transaction-validator 8080:8080

# Test health endpoint
curl http://localhost:8080/health

# Or test via ALB (after DNS propagation)
curl https://api.transaction-validator.example.com/health
```

## Updating Deployment

### Update Configuration

```bash
# Edit values
nano helm/transaction-validator/values-dev.yaml

# Upgrade
helm upgrade transaction-validator ./helm/transaction-validator \
  --values ./helm/transaction-validator/values-dev.yaml
```

### Update Image

```bash
# Build and push new image
docker build -t <ECR_REGISTRY>/transaction-validator:v1.1.0 .
docker push <ECR_REGISTRY>/transaction-validator:v1.1.0

# Upgrade Helm release
helm upgrade transaction-validator ./helm/transaction-validator \
  --reuse-values \
  --set image.tag=v1.1.0
```

### Update Infrastructure

```bash
cd terraform/environments/dev

# Edit tfvars or module
nano terraform.tfvars

# Apply changes
terraform plan
terraform apply
```

## Rollback

### Application Rollback

```bash
# List releases
helm history transaction-validator -n transaction-validator

# Rollback to previous
helm rollback transaction-validator -n transaction-validator

# Rollback to specific revision
helm rollback transaction-validator 3 -n transaction-validator
```

### Infrastructure Rollback

```bash
cd terraform/environments/dev

# Revert code changes
git revert <commit-hash>

# Apply
terraform apply
```

## Cleanup

**⚠️ This will destroy all resources!**

```bash
# Delete Helm release
helm uninstall transaction-validator -n transaction-validator

# Wait for ALB to be deleted (check AWS Console)

# Destroy infrastructure
cd terraform/environments/dev
terraform destroy
```

## CI/CD Deployment

The GitHub Actions pipeline automatically deploys:

- **develop branch** → dev → staging environments (automated)
- **main branch** → production environment (manual approval + canary deployment)

### Setup CI/CD

1. **Configure GitHub Secrets**:
   - `AWS_ROLE_TO_ASSUME`: Build/test IAM role ARN
   - `AWS_ROLE_TO_ASSUME_DEV`: Dev environment role ARN
   - `AWS_ROLE_TO_ASSUME_STAGING`: Staging environment role ARN
   - `AWS_ROLE_TO_ASSUME_PROD`: Production environment role ARN

2. **Configure GitHub Environments**:
   
   **Settings → Environments → Create**
   
   - **development**: No protection rules
   - **staging**: No protection rules
   - **production**: 
     - ✅ Required reviewers: **2 minimum**
     - ✅ Add senior engineers as approvers
     - ✅ Optional: Wait timer (5 minutes)

3. **Push changes**:
   ```bash
   # Deploy to dev → staging (automated)
   git push origin develop
   
   # Deploy to production (requires manual approval)
   git push origin main
   # → Go to Actions tab
   # → Click "Review deployments"
   # → 2 reviewers must approve
   # → Canary deployment begins automatically
   ```

### Production Deployment Strategy

**Blue-Green Deployment Process:**

1. **Manual Approval** (2 reviewers required)
2. **Deploy GREEN** environment (new version) alongside BLUE (current)
3. **Health Checks** on GREEN (6 comprehensive checks)
4. **Stability Monitoring** (2 minutes)
5. **Traffic Switch** from BLUE to GREEN (instant cutover)
6. **Verification** and cleanup
7. **Automatic Rollback** (if any step fails)

**Health Checks:**
- Pod status (Running)
- Container restarts (0)
- Readiness probes (passing)
- Error log analysis (< 5 errors)
- HTTP health endpoint (200 OK)
- All replicas ready

**Advantages:**
- Zero downtime deployment
- Instant rollback capability (< 2 minutes)
- Full environment testing before traffic switch
- Simple and reliable

See [CI/CD Setup Guide](docs/ci-cd-setup.md) and [Blue-Green Strategy](docs/blue-green-deployment.md) for detailed information.

## Troubleshooting

### Terraform Issues

```bash
# Refresh state
terraform refresh

# Fix state drift
terraform plan
terraform apply

# Force unlock if locked
terraform force-unlock <lock-id>
```

### Helm Issues

```bash
# Check release status
helm status transaction-validator -n transaction-validator

# Get values
helm get values transaction-validator -n transaction-validator

# Debug template
helm template transaction-validator ./helm/transaction-validator --debug
```

### Kubectl Issues

```bash
# Check pod logs
kubectl logs -n transaction-validator <pod-name>

# Describe pod
kubectl describe pod -n transaction-validator <pod-name>

# Get events
kubectl get events -n transaction-validator --sort-by='.lastTimestamp'
```

## Best Practices

1. **Always test in dev first** before deploying to production
2. **Review Terraform plans** carefully before applying
3. **Use version tags** for images, not `latest` in production
4. **Take snapshots** before major changes
5. **Monitor deployments** and have rollback ready
6. **Document changes** in commit messages
7. **Test rollback procedures** regularly

## Support

- **Documentation**: See `docs/` directory
- **Issues**: Create GitHub issue
- **Email**: devops@example.com

---

**Quick Commands**:

```bash
# Deploy everything (dev)
./scripts/setup-terraform-backend.sh
cd terraform/environments/dev && terraform init && terraform apply
helm install transaction-validator ./helm/transaction-validator -n transaction-validator --create-namespace

# Check status
kubectl get all -n transaction-validator

# Scale up
helm upgrade transaction-validator ./helm/transaction-validator --reuse-values --set replicaCount=10

# Rollback
helm rollback transaction-validator -n transaction-validator
```

