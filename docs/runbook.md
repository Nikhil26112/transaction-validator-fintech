# Operational Runbook

## Quick Reference

### Access

**AWS Console**: us-east-1 region  
**EKS Cluster**: `transaction-validator-{env}`

```bash
# Get kubectl access
aws eks update-kubeconfig --name transaction-validator-prod --region us-east-1
```

### Important URLs

- **Health Check**: `https://api.transaction-validator.example.com/health`
- **CloudWatch Dashboard**: Check Terraform outputs
- **PagerDuty**: [Link to your PagerDuty]

## Health Checks

### Check Application

```bash
# Pod status
kubectl get pods -n transaction-validator

# Application logs
kubectl logs -n transaction-validator -l app.kubernetes.io/name=transaction-validator --tail=50

# Test endpoint
curl https://api.transaction-validator.example.com/health
```

### Check Database

```bash
# Cluster status
aws rds describe-db-clusters \
  --db-cluster-identifier transaction-validator-prod-aurora-cluster \
  --region us-east-1 \
  --query 'DBClusters[0].Status'

# Expected: "available"
```

### Check Redis

```bash
# Cluster status
aws elasticache describe-replication-groups \
  --replication-group-id transaction-validator-prod-redis \
  --region us-east-1 \
  --query 'ReplicationGroups[0].Status'

# Expected: "available"
```

## Common Operations

### Scale Application

```bash
# Manual scaling
kubectl scale deployment transaction-validator -n transaction-validator --replicas=10

# Using Helm
helm upgrade transaction-validator ./helm/transaction-validator \
  --reuse-values \
  --set autoscaling.maxReplicas=30
```

### Update Configuration

```bash
# Edit values file
nano helm/transaction-validator/values-prod.yaml

# Apply with Helm
helm upgrade transaction-validator ./helm/transaction-validator \
  --values ./helm/transaction-validator/values-prod.yaml
```

### Restart Application

```bash
# Rolling restart
kubectl rollout restart deployment/transaction-validator -n transaction-validator

# Watch progress
kubectl rollout status deployment/transaction-validator -n transaction-validator
```

### View Logs

```bash
# Recent logs
kubectl logs -n transaction-validator -l app.kubernetes.io/name=transaction-validator --tail=100

# Follow logs
kubectl logs -f -n transaction-validator -l app.kubernetes.io/name=transaction-validator

# Specific pod
kubectl logs -n transaction-validator <pod-name>
```

## Troubleshooting

### High Latency

**Check pod metrics:**
```bash
kubectl top pods -n transaction-validator
```

**Check HPA status:**
```bash
kubectl get hpa -n transaction-validator
```

**Check database performance:**
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBClusterIdentifier,Value=transaction-validator-prod-aurora-cluster \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

**Solution:**
```bash
# Scale up if needed
kubectl scale deployment transaction-validator -n transaction-validator --replicas=15
```

### High Error Rate

**Check logs for errors:**
```bash
kubectl logs -n transaction-validator -l app.kubernetes.io/name=transaction-validator | grep ERROR
```

**Check pod status:**
```bash
kubectl get pods -n transaction-validator
kubectl describe pod <pod-name> -n transaction-validator
```

**If recent deployment caused issue:**
```bash
# Rollback with Helm
helm rollback transaction-validator -n transaction-validator
```

### Pod Crashes

**Check pod events:**
```bash
kubectl describe pod <pod-name> -n transaction-validator
```

**Check previous logs:**
```bash
kubectl logs <pod-name> -n transaction-validator --previous
```

**Check resource usage:**
```bash
kubectl top pod <pod-name> -n transaction-validator
```

**If OOM (Out of Memory):**
```bash
# Increase memory limits with Helm
helm upgrade transaction-validator ./helm/transaction-validator \
  --reuse-values \
  --set resources.limits.memory=2Gi
```

### Database Connection Issues

**Test connectivity from pod:**
```bash
kubectl exec -it <pod-name> -n transaction-validator -- sh
nc -zv <database-endpoint> 5432
```

**Check connection count:**
```sql
-- Connect to database
SELECT count(*) FROM pg_stat_activity;
```

**If too many connections:**
```sql
-- Kill idle connections
SELECT pg_terminate_backend(pid) 
FROM pg_stat_activity 
WHERE state = 'idle' 
AND state_change < now() - interval '5 minutes';
```

## Incident Response

### SEV1: Service Down

**Immediate actions (0-5 min):**
1. Check pod status
2. Check ALB health
3. Check database status

```bash
kubectl get pods -n transaction-validator
curl https://api.transaction-validator.example.com/health
aws rds describe-db-clusters --db-cluster-identifier transaction-validator-prod-aurora-cluster
```

**Investigation (5-15 min):**
```bash
# Check recent changes
helm history transaction-validator -n transaction-validator

# Check CloudWatch alarms
aws cloudwatch describe-alarms --state-value ALARM
```

**Resolution:**
- If recent deployment: Rollback with `helm rollback`
- If infrastructure issue: Restart services, scale up
- If database issue: Check Aurora failover status

### SEV2: Degraded Performance

1. Check metrics (CPU, memory, latency)
2. Scale up if needed
3. Investigate root cause
4. Monitor for improvement

## Rollback Procedures

### Application Rollback

```bash
# View deployment history
helm history transaction-validator -n transaction-validator

# Rollback to previous version
helm rollback transaction-validator -n transaction-validator

# Rollback to specific version
helm rollback transaction-validator <revision> -n transaction-validator

# Verify
kubectl rollout status deployment/transaction-validator -n transaction-validator
```

### Database Rollback

```bash
# Point-in-time recovery (creates new cluster)
aws rds restore-db-cluster-to-point-in-time \
  --source-db-cluster-identifier transaction-validator-prod-aurora-cluster \
  --db-cluster-identifier transaction-validator-prod-restored \
  --restore-to-time "2025-11-12T10:00:00Z"
```

## Maintenance

### Database Upgrade

```bash
# Schedule maintenance window in AWS Console
# Or use Terraform:
cd terraform/environments/prod
# Update engine_version in terraform.tfvars
terraform apply
```

### EKS Upgrade

```bash
# Upgrade control plane
cd terraform/environments/prod
# Update cluster_version in terraform.tfvars
terraform apply

# Upgrade node groups (rolling update)
# Nodes will be replaced automatically
```

### Certificate Rotation

```bash
# ACM certificates auto-renew
# No action needed for ALB certificates

# For application secrets
aws secretsmanager rotate-secret \
  --secret-id transaction-validator-prod-db-master-password
```

## Useful Commands

```bash
# Quick pod restart
kubectl delete pod <pod-name> -n transaction-validator

# Port forward for debugging
kubectl port-forward -n transaction-validator svc/transaction-validator 8080:8080

# Execute command in pod
kubectl exec -it <pod-name> -n transaction-validator -- /bin/sh

# Get events
kubectl get events -n transaction-validator --sort-by='.lastTimestamp'

# Watch resources
kubectl get pods -n transaction-validator -w
```

## Emergency Contacts

- **On-Call**: Check PagerDuty
- **DevOps Lead**: devops-lead@example.com
- **AWS Support**: Enterprise support via console

## Escalation

1. Primary On-Call → Secondary On-Call (5 min)
2. Secondary → Engineering Manager (15 min)
3. Manager → VP Engineering (30 min, SEV1 only)

---
