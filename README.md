# Transaction Validator Infrastructure

Production-ready infrastructure for a payment transaction validation microservice.

## 🏗️ Architecture

- **AWS Infrastructure**: Terraform (VPC, EKS, Aurora PostgreSQL, ElastiCache Redis)
- **Kubernetes**: Helm charts for application deployment
- **CI/CD**: GitHub Actions with automated deployments
- **Environments**: Dev, Staging, Production

## 📁 Project Structure

```
.
├── terraform/
│   ├── modules/          # Reusable infrastructure modules
│   └── environments/     # Environment-specific configs (dev/staging/prod)
├── helm/
│   └── transaction-validator/  # Helm chart for application
├── .github/workflows/    # CI/CD pipeline
└── docs/                 # Documentation
```

## 🚀 Quick Start

### Prerequisites

- AWS CLI configured
- Terraform >= 1.8.0
- kubectl >= 1.30
- Helm >= 3.10

### 1. Setup Terraform Backend

```bash
./scripts/setup-terraform-backend.sh
```

### 2. Deploy Infrastructure

```bash
cd terraform/environments/dev
terraform init
terraform plan
terraform apply
```

### 3. Deploy Application with Helm

```bash
# Get kubeconfig
aws eks update-kubeconfig --name transaction-validator-dev --region us-east-1

# Get IAM role ARN
ROLE_ARN=$(cd terraform/environments/dev && terraform output -raw app_secrets_role_arn)

# Deploy with Helm
helm install transaction-validator ./helm/transaction-validator \
  --namespace transaction-validator \
  --create-namespace \
  --values ./helm/transaction-validator/values-dev.yaml \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ROLE_ARN
```

### 4. Verify Deployment

```bash
kubectl get pods -n transaction-validator
kubectl get svc -n transaction-validator
kubectl get ingress -n transaction-validator
```

## 🔧 Configuration

### Environment-Specific Values

- **Dev**: `helm/transaction-validator/values-dev.yaml`
- **Prod**: `helm/transaction-validator/values-prod.yaml`

### Helm Values

Key configuration in `helm/transaction-validator/values.yaml`:

```yaml
replicaCount: 3
image:
  repository: your-registry/transaction-validator
  tag: "v1.0.0"
resources:
  requests:
    cpu: 500m
    memory: 512Mi
autoscaling:
  minReplicas: 3
  maxReplicas: 20
```

## 📊 Infrastructure Components

| Component | Dev | Prod |
|-----------|-----|------|
| **EKS Nodes** | 2x t3.medium | 5x t3.large |
| **Aurora** | 1x db.t4g.medium | 3x db.r6g.large |
| **Redis** | 1x cache.t4g.small | 3x cache.r7g.large |
| **NAT Gateway** | 1 (shared) | 3 (per AZ) |
| **Estimated Cost** | ~$400/month | ~$1,800/month |

## 🔐 Security Features

- ✅ Multi-AZ deployment
- ✅ Encryption at rest and in transit
- ✅ IRSA for pod IAM permissions
- ✅ Network policies
- ✅ Non-root containers
- ✅ Security scanning in CI/CD

## 📈 Scaling

**Horizontal Pod Autoscaler**: Automatically scales pods based on CPU/memory (3-20 replicas)

```bash
kubectl get hpa -n transaction-validator
```

**Cluster Autoscaler**: Automatically adds/removes nodes based on demand

## 🔄 CI/CD Pipeline

- **Test & Build**: terraform fmt, tflint, kubeconform, helm lint, checkov, trivy
- **Infrastructure Deploy (Staging)**: Plan, manual approval, apply, smoke tests
- **Application Deploy (Staging)**: Deploy, integration tests, auto-rollback
- **Production Deploy**: Manual approval + blue-green deployment with auto-rollback

## 📚 Documentation

- **[Architecture](docs/architecture.md)**: System design and components
- **[Runbook](docs/runbook.md)**: Operational procedures
- **[Disaster Recovery](docs/disaster-recovery.md)**: Backup and failover procedures

## 🛠️ Common Operations

### Scale Application

```bash
# Manual scaling
kubectl scale deployment transaction-validator -n transaction-validator --replicas=10

# Update HPA
helm upgrade transaction-validator ./helm/transaction-validator \
  --reuse-values \
  --set autoscaling.maxReplicas=30
```

### Update Configuration

```bash
# Edit values
nano helm/transaction-validator/values-prod.yaml

# Apply changes
helm upgrade transaction-validator ./helm/transaction-validator \
  --values ./helm/transaction-validator/values-prod.yaml
```

### Rollback

```bash
helm rollback transaction-validator -n transaction-validator
```

### View Logs

```bash
kubectl logs -f -l app.kubernetes.io/name=transaction-validator -n transaction-validator
```

## 🆘 Troubleshooting

### Check Pod Status
```bash
kubectl get pods -n transaction-validator
kubectl describe pod <pod-name> -n transaction-validator
```

### Check Application Logs
```bash
kubectl logs -n transaction-validator <pod-name>
```

### Test Health Endpoint
```bash
kubectl port-forward -n transaction-validator svc/transaction-validator 8080:8080
curl http://localhost:8080/health
```

## 💰 Cost Optimization

- Use t3/t4g instances for cost savings
- Single NAT gateway in dev
- Right-sized resource limits
- Auto-scaling during low traffic

## 🔒 Security Best Practices

- No hardcoded credentials (use AWS Secrets Manager)
- IRSA for fine-grained permissions
- Read-only root filesystem
- Network policies enabled
- Regular security scanning


