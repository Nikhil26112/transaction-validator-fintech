# Design Decisions

## Architecture Overview

This infrastructure is designed for a fintech startup payment validation service with focus on security, reliability, and cost-effectiveness.

## Key Decisions

### 1. Kubernetes (EKS) over ECS

**Choice**: Amazon EKS

**Reasons**:
- Industry standard with large ecosystem
- Vendor neutrality and portability
- Rich tooling (Helm, operators, service mesh)
- Better for future microservices expansion

**Trade-off**: Higher complexity vs ECS, but better long-term flexibility

### 2. Instance Types

| Component | Dev | Prod | Rationale |
|-----------|-----|------|-----------|
| EKS Nodes | t3.medium | t3.large | Burstable for variable load, cost-effective |
| Aurora | db.t4g.medium | db.r6g.large | Graviton for price/performance, r6g for memory-intensive DB |
| Redis | cache.t4g.small | cache.r7g.large | t4g for dev savings, r7g for production cache performance |

**Cost Consideration**: Using Graviton (ARM) instances saves ~20% vs x86 equivalent.

### 3. Database Strategy

**Aurora PostgreSQL Configuration**:
- Multi-AZ deployment for HA
- Automated backups (7 days retention)
- OLTP-optimized parameter groups
- Connection pooling at application level (10 connections/pod)

**Connection Pooling**: 
- Max pods: 20
- Connections per pod: 10
- Total: 200 connections (well below Aurora's 5000 limit)

### 4. Caching Strategy

**Redis Use Cases**:
1. **Session Cache**: Authentication tokens (TTL: 24h)
2. **Rate Limiting**: Per-user counters (TTL: 1m)
3. **Validation Rules**: Business rules (TTL: 5m)
4. **Result Cache**: Recent validations (TTL: 1h)

**Eviction Policy**: `allkeys-lru` (Least Recently Used)

### 5. Security Measures

**Network Security**:
- Private subnets for all compute/data
- Security groups with least privilege
- Network policies in Kubernetes
- WAF for API protection

**Access Control**:
- IRSA for AWS API access (no long-lived credentials)
- RBAC for Kubernetes
- MFA for production access

**Data Protection**:
- KMS encryption at rest (Aurora, Redis, EBS)
- TLS 1.2+ in transit
- Secrets Manager for credentials

**Container Security**:
- Non-root user (UID 1000)
- Read-only root filesystem
- No privilege escalation
- Security scanning in CI/CD

### 6. High Availability

**Multi-AZ Design**:
- 3 availability zones in us-east-1
- Pod anti-affinity spreads across AZs
- Aurora with automatic failover
- Redis with replica promotion

**Auto-Scaling**:
- HPA: 3-20 pods based on CPU/memory
- Cluster Autoscaler for nodes
- Aurora read replicas can be added

**Zero-Downtime Deployments**:
- Rolling updates with maxUnavailable=0
- PodDisruptionBudget ensures min 2 pods available
- Health checks prevent bad pod traffic

## Cost Analysis

### Monthly Costs

| Environment | Cost | Key Savings |
|-------------|------|-------------|
| **Dev** | ~$400 | Single NAT, t3/t4g instances, 1 DB instance |
| **Prod** | ~$1,800 | Multi-AZ NAT, production instances, HA setup |

**Production Breakdown**:
- EKS: $373 (cluster + nodes)
- Aurora: $518 (3x db.r6g.large)
- Redis: $428 (3x cache.r7g.large)
- Networking: $142 (NAT gateways)
- Other: $339 (ALB, storage, monitoring)

**Optimization Opportunities**:
- Reserved Instances: Save ~40% ($700/month)
- Savings Plans: Save ~30% ($500/month)
- Right-sizing after analysis: Save ~$150/month

### 10x Traffic Scaling

**Current**: 5,000 TPS  
**10x**: 50,000 TPS

**Required Changes**:
1. **Application**: Scale to 100 pods (vs 20)
2. **Database**: Upgrade to db.r6g.4xlarge, add 5 read replicas
3. **Cache**: Scale to cache.r7g.4xlarge with 6 nodes
4. **Network**: Upgrade ALB capacity, add CloudFront CDN
5. **Cost Impact**: ~$15,000-20,000/month

## Trade-Offs

### What We Optimized For

**Priority**: Reliability > Cost > Performance

**Rationale**: Payment processing requires high reliability. Downtime costs more than infrastructure.

### With Unlimited Budget

1. **Multi-Region**: Deploy in us-west-2 for DR (RTO: 5 min)
2. **Observability**: Datadog/New Relic instead of CloudWatch
3. **Service Mesh**: Istio for advanced traffic management
4. **Larger Instances**: r6i.xlarge for headroom
5. **Aurora Global Database**: Cross-region replication
6. **AWS Shield Advanced**: Enhanced DDoS protection

## Disaster Recovery

| Scenario | RTO | RPO | Strategy |
|----------|-----|-----|----------|
| Pod failure | 1 min | 0 | Auto-healing |
| Node failure | 5 min | 0 | Auto-scaling |
| AZ failure | 10 min | 0 | Multi-AZ failover |
| Region failure | 30 min | 5 min | Manual failover (Phase 2: cross-region) |

**Backup Strategy**:
- Aurora: Automated backups every 5 min
- Snapshots: Daily at 3 AM UTC
- Retention: 7 days
- Point-in-time recovery available

## Production Readiness

### ✅ Implemented

- Infrastructure as Code (Terraform)
- Multi-AZ deployment
- Encryption everywhere
- Automated backups
- Monitoring and alerting
- Security scanning
- Automated deployments
- Health checks
- Auto-scaling

### ⏳ Phase 2

- Cross-region DR
- Advanced observability (Datadog)
- Service mesh (Istio)
- GitOps (ArgoCD)
- Chaos engineering
- Load testing results
- Penetration testing

## Compliance (PCI-DSS)

| Control | Implementation |
|---------|----------------|
| **Access Control** | IRSA, RBAC, MFA |
| **Encryption** | KMS (rest), TLS 1.2+ (transit) |
| **Audit Logging** | CloudTrail, CloudWatch logs |
| **Vulnerability Mgmt** | Trivy, Checkov in CI/CD |
| **Network Security** | VPC isolation, security groups, network policies |
| **Monitoring** | CloudWatch metrics and alarms |

## Known Limitations

1. **Single Region**: No cross-region DR yet (planned Phase 2)
2. **Manual Secret Rotation**: Quarterly manual rotation (automate in Phase 2)
3. **Limited Observability**: CloudWatch only (add APM in Phase 2)
4. **No Service Mesh**: Direct pod communication (add Istio in Phase 2)

## Technology Choices

**Helm over Kustomize**:
- Industry standard for package management
- Version control and rollback built-in
- Better for templating complex configs
- Easier team adoption

**GitHub Actions**:
- Native integration with GitHub
- Simple YAML configuration
- Free for public repos, cost-effective for private
- Built-in OIDC for AWS

**Aurora over RDS**:
- Better HA with automatic failover
- Better performance at scale
- Compatible with PostgreSQL
- Lower operational overhead

## Summary

This design balances startup needs (cost-effective) with production requirements (reliable, secure). It's production-ready for day 1 while providing clear path to scale and enhance over time.

**Key Strengths**:
- Security-first approach
- Cost-optimized for startup
- Production-grade reliability
- Well-documented and automated
- Clear scalability path

---

