# Architecture Overview

## High-Level Design

```
┌─────────────────────────────────────────────────────────────┐
│                    Internet / Users                          │
└────────────────────────┬────────────────────────────────────┘
                         │ HTTPS
                         ▼
                  ┌─────────────┐
                  │   AWS WAF   │
                  └──────┬──────┘
                         │
                         ▼
         ┌───────────────────────────────────────┐
         │   Application Load Balancer (ALB)     │
         └───────────────┬───────────────────────┘
                         │
                         ▼
         ┌───────────────────────────────────────┐
         │      EKS Cluster (3 AZs)              │
         │                                       │
         │  ┌─────────────────────────────────┐ │
         │  │  Transaction Validator Pods     │ │
         │  │  (3-20 replicas with HPA)       │ │
         │  └────┬────────────────┬───────────┘ │
         └───────┼────────────────┼─────────────┘
                 │                │
        ┌────────▼────────┐  ┌───▼──────────┐
        │  Aurora         │  │  ElastiCache │
        │  PostgreSQL     │  │  Redis       │
        │  (Multi-AZ)     │  │  (Multi-AZ)  │
        └─────────────────┘  └──────────────┘
```

## Components

### Network Layer
- **VPC**: Isolated network (10.0.0.0/16)
- **Subnets**: Public, Private, Database across 3 AZs
- **NAT Gateways**: Outbound internet for private subnets
- **Security Groups**: Fine-grained network access control

### Compute Layer
- **EKS Cluster**: Managed Kubernetes (v1.28)
- **Node Groups**: Auto-scaling worker nodes
- **Pods**: Application containers with health checks

### Data Layer
- **Aurora PostgreSQL**: Primary database (Multi-AZ)
  - Automated backups (7 days)
  - Encrypted at rest
  - Optimized for OLTP workload

- **ElastiCache Redis**: Caching layer
  - Session storage
  - Rate limiting
  - Validation rules cache

### Security
- **Encryption**: KMS for data at rest, TLS for transit
- **IAM**: IRSA for pod permissions
- **Secrets Manager**: Credential storage
- **WAF**: DDoS and injection protection

### Observability
- **CloudWatch**: Logs and metrics
- **SNS**: Alert notifications
- **Prometheus**: Application metrics

## Data Flow

1. User request → ALB (SSL termination)
2. ALB → Kubernetes Service → Pod
3. Pod checks Redis for cached data
4. If not cached, query PostgreSQL
5. Store result in Redis
6. Return response to user

## High Availability

- **Multi-AZ Deployment**: Resources across 3 availability zones
- **Auto-Scaling**: HPA for pods, Cluster Autoscaler for nodes
- **Health Checks**: Liveness, readiness, startup probes
- **Load Balancing**: ALB distributes traffic
- **Database Failover**: Aurora automatic failover < 1 minute

## Disaster Recovery

- **RTO**: 30 minutes (region failure)
- **RPO**: 5 minutes (data loss)
- **Backups**: Automated daily snapshots
- **Recovery**: Point-in-time restore capability

## Cost Optimization

### Development
- Single NAT gateway
- Smaller instances (t3/t4g)
- Minimal replicas
- **Cost**: ~$400/month

### Production
- Multi-AZ NAT gateways
- Production instances (r6g/r7g)
- High availability (3+ replicas)
- **Cost**: ~$1,800/month

## Scaling Strategy

### Horizontal Scaling
- **Application**: 3-20 pods via HPA
- **Database**: Add read replicas
- **Cache**: Add Redis nodes

### Vertical Scaling
- Increase pod resource limits
- Upgrade instance types
- Larger database instances

## Security Measures

1. **Network Security**
   - Private subnets for compute/data
   - Security groups with least privilege
   - Network policies in Kubernetes

2. **Access Control**
   - IRSA for AWS API access
   - RBAC for Kubernetes access
   - MFA for production access

3. **Data Protection**
   - Encryption at rest (KMS)
   - Encryption in transit (TLS 1.2+)
   - Regular backups

4. **Compliance**
   - Audit logging (CloudTrail)
   - Security scanning in CI/CD
   - PCI-DSS controls implemented

## Future Enhancements

- Multi-region deployment for DR
- Service mesh (Istio) for advanced routing
- Advanced observability (Datadog/New Relic)
- GitOps with ArgoCD

