# Transaction Validator - Architecture Diagram

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│                            Internet / Users                                  │
│                                                                             │
└────────────────────────────┬────────────────────────────────────────────────┘
                             │
                             │ HTTPS
                             ▼
                    ┌────────────────┐
                    │   AWS WAF      │  ◄── Rate limiting, SQL injection
                    │                │      protection, geo-blocking
                    └────────┬───────┘
                             │
                             ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                          AWS Cloud (VPC: 10.0.0.0/16)                      │
│                                                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │                         Public Subnets                                │ │
│  │  (10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24)                             │ │
│  │                                                                       │ │
│  │  ┌──────────────────┐        ┌──────────────────┐                   │ │
│  │  │ Application Load │        │   NAT Gateway    │                   │ │
│  │  │    Balancer      │        │   (us-east-1a)   │                   │ │
│  │  │  (SSL/TLS Term)  │        └──────────────────┘                   │ │
│  │  └────────┬─────────┘        ┌──────────────────┐                   │ │
│  │           │                  │   NAT Gateway    │                   │ │
│  │           │                  │   (us-east-1b)   │                   │ │
│  │           │                  └──────────────────┘                   │ │
│  │           │                  ┌──────────────────┐                   │ │
│  │           │                  │   NAT Gateway    │                   │ │
│  │           │                  │   (us-east-1c)   │                   │ │
│  │           │                  └──────────────────┘                   │ │
│  └───────────┼───────────────────────────────────────────────────────┘ │
│              │                                                           │
│              │                                                           │
│  ┌───────────▼──────────────────────────────────────────────────────┐  │
│  │                      Private Subnets                              │  │
│  │        (10.0.11.0/24, 10.0.12.0/24, 10.0.13.0/24)                │  │
│  │                                                                   │  │
│  │  ┌───────────────────────────────────────────────────────────┐  │  │
│  │  │              EKS Cluster (Kubernetes 1.28)                 │  │  │
│  │  │                                                            │  │  │
│  │  │  ┌──────────┐  ┌──────────┐  ┌──────────┐               │  │  │
│  │  │  │  Worker  │  │  Worker  │  │  Worker  │               │  │  │
│  │  │  │  Node 1  │  │  Node 2  │  │  Node 3  │  ◄─ Autoscale │  │  │
│  │  │  │(AZ-1a)   │  │(AZ-1b)   │  │(AZ-1c)   │     (2-10)    │  │  │
│  │  │  └─────┬────┘  └─────┬────┘  └─────┬────┘               │  │  │
│  │  │        │             │             │                     │  │  │
│  │  │  ┌─────▼─────────────▼─────────────▼──────────┐         │  │  │
│  │  │  │     Transaction Validator Pods              │         │  │  │
│  │  │  │  (3-20 replicas with HPA)                   │         │  │  │
│  │  │  │                                              │         │  │  │
│  │  │  │  • Non-root user (UID: 1000)                │         │  │  │
│  │  │  │  • Read-only root filesystem                │         │  │  │
│  │  │  │  • Resource limits: 2 CPU / 1Gi RAM         │         │  │  │
│  │  │  │  • Liveness/Readiness probes                │         │  │  │
│  │  │  │  • Pod anti-affinity across AZs             │         │  │  │
│  │  │  └─────┬────────────────────┬──────────────────┘         │  │  │
│  │  │        │                    │                            │  │  │
│  │  │        │ IRSA (IAM)         │                            │  │  │
│  │  │        │ Secrets Access     │                            │  │  │
│  │  │        │                    │                            │  │  │
│  │  └────────┼────────────────────┼────────────────────────────┘  │  │
│  └───────────┼────────────────────┼───────────────────────────────┘  │
│              │                    │                                   │
│              │                    │                                   │
│  ┌───────────▼────────────────────▼───────────────────────────────┐  │
│  │                    Database Subnets                             │  │
│  │       (10.0.21.0/24, 10.0.22.0/24, 10.0.23.0/24)               │  │
│  │                                                                 │  │
│  │  ┌────────────────────────────────────────────────────────┐   │  │
│  │  │        Aurora PostgreSQL Cluster (Multi-AZ)            │   │  │
│  │  │                                                         │   │  │
│  │  │  ┌──────────┐  ┌──────────┐  ┌──────────┐            │   │  │
│  │  │  │  Writer  │  │  Reader  │  │  Reader  │            │   │  │
│  │  │  │ Instance │  │ Instance │  │ Instance │            │   │  │
│  │  │  │ (AZ-1a)  │  │ (AZ-1b)  │  │ (AZ-1c)  │            │   │  │
│  │  │  └──────────┘  └──────────┘  └──────────┘            │   │  │
│  │  │                                                         │   │  │
│  │  │  • Encrypted at rest (KMS)                             │   │  │
│  │  │  • Automated backups (7 days)                          │   │  │
│  │  │  • Performance Insights enabled                        │   │  │
│  │  │  • Parameter group: OLTP optimized                     │   │  │
│  │  └─────────────────────────────────────────────────────────┘  │  │
│  │                                                                 │  │
│  │  ┌────────────────────────────────────────────────────────┐   │  │
│  │  │      ElastiCache Redis Cluster (Multi-AZ)              │   │  │
│  │  │                                                         │   │  │
│  │  │  ┌──────────┐  ┌──────────┐  ┌──────────┐            │   │  │
│  │  │  │  Primary │  │ Replica  │  │ Replica  │            │   │  │
│  │  │  │   Node   │  │  Node    │  │  Node    │            │   │  │
│  │  │  │ (AZ-1a)  │  │ (AZ-1b)  │  │ (AZ-1c)  │            │   │  │
│  │  │  └──────────┘  └──────────┘  └──────────┘            │   │  │
│  │  │                                                         │   │  │
│  │  │  • Encrypted at rest & in transit                      │   │  │
│  │  │  • Auth token enabled                                  │   │  │
│  │  │  • Automatic failover                                  │   │  │
│  │  │  • Session caching & rate limiting                     │   │  │
│  │  └─────────────────────────────────────────────────────────┘  │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                        │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │                    AWS Services Layer                           │  │
│  │                                                                 │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │  │
│  │  │   Secrets    │  │  CloudWatch  │  │     SNS      │        │  │
│  │  │   Manager    │  │   Logs &     │  │   Alerts     │        │  │
│  │  │              │  │   Metrics    │  │              │        │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘        │  │
│  │                                                                 │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │  │
│  │  │     KMS      │  │     ECR      │  │   Route 53   │        │  │
│  │  │  Encryption  │  │   Container  │  │     DNS      │        │  │
│  │  │     Keys     │  │   Registry   │  │              │        │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘        │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

## Data Flow - Transaction Validation Request

```
┌──────┐
│Client│
└───┬──┘
    │ 1. HTTPS POST /api/validate
    ▼
┌───────────┐
│  AWS WAF  │  ◄── DDoS protection, rate limiting
└─────┬─────┘
      │ 2. Forward if rules pass
      ▼
┌──────────────┐
│     ALB      │  ◄── SSL/TLS termination, health checks
└──────┬───────┘
       │ 3. Route to healthy pod
       ▼
┌────────────────────┐
│  K8s Service       │
│  (ClusterIP)       │
└─────────┬──────────┘
          │ 4. Load balance to pod
          ▼
┌──────────────────────────┐
│ Transaction Validator    │
│ Pod                      │
│                          │
│  5. Authenticate request │
│  6. Rate limit check     │────────────┐
│     (Redis)              │            │ 6a. Check rate limit
└────────┬─────────────────┘            ▼
         │                        ┌──────────────┐
         │                        │    Redis     │
         │                        │    Cache     │
         │                        └──────────────┘
         │ 7. Validate transaction
         │    business rules
         │
         │ 8. Query validation     
         │    rules & history       
         ▼                         
┌──────────────────┐
│   PostgreSQL     │
│   Database       │
└──────────────────┘
         │
         │ 9. Return validation result
         ▼
┌────────────────────────┐
│ Transaction Validator  │
│ Pod                    │
│                        │
│  10. Cache result      │
│  11. Log metrics       │
│  12. Return response   │
└────────┬───────────────┘
         │
         │ 13. HTTP 200 OK + validation result
         ▼
    ┌──────┐
    │Client│
    └──────┘
```

## Security Boundaries

```
┌─────────────────────────────────────────────────────────────┐
│                      Security Zones                          │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Public Zone (DMZ)                                  │    │
│  │  • ALB with WAF                                     │    │
│  │  • Public subnets                                   │    │
│  │  • Internet Gateway                                 │    │
│  └────────────────────────────────────────────────────┘    │
│                          │                                   │
│                          │ Security Group Rules              │
│                          ▼                                   │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Application Zone                                   │    │
│  │  • EKS worker nodes (private subnets)              │    │
│  │  • Network policies restrict pod-to-pod            │    │
│  │  • IRSA for AWS API access                         │    │
│  │  • No direct internet access (via NAT)             │    │
│  └────────────────────────────────────────────────────┘    │
│                          │                                   │
│                          │ Security Group Rules              │
│                          ▼                                   │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Data Zone                                          │    │
│  │  • Aurora PostgreSQL (private subnets)             │    │
│  │  • ElastiCache Redis (private subnets)             │    │
│  │  • No internet access                              │    │
│  │  • Encrypted at rest (KMS)                         │    │
│  │  • Encrypted in transit (TLS)                      │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Management Zone                                    │    │
│  │  • CloudWatch Logs                                  │    │
│  │  • Secrets Manager                                  │    │
│  │  • KMS                                              │    │
│  │  • Access via IAM roles only                        │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## Disaster Recovery Architecture

```
Primary Region (us-east-1)          DR Region (us-west-2)
┌────────────────────────┐         ┌────────────────────────┐
│                        │         │                        │
│  ┌──────────────────┐ │         │  ┌──────────────────┐ │
│  │  Aurora Primary  │ │         │  │  Aurora Read     │ │
│  │  Cluster         │ ├────────►│  │  Replica         │ │
│  │                  │ │         │  │  (Cross-region)  │ │
│  └──────────────────┘ │         │  └──────────────────┘ │
│                        │         │                        │
│  ┌──────────────────┐ │         │  ┌──────────────────┐ │
│  │  S3 Backups      │ ├────────►│  │  S3 Backups      │ │
│  │  (Daily)         │ │ Repl.  │  │  (Replicated)    │ │
│  └──────────────────┘ │         │  └──────────────────┘ │
│                        │         │                        │
│  ┌──────────────────┐ │         │  ┌──────────────────┐ │
│  │  Terraform State │ ├────────►│  │  Terraform State │ │
│  │  (S3 + DynamoDB) │ │ Repl.  │  │  (Replicated)    │ │
│  └──────────────────┘ │         │  └──────────────────┘ │
│                        │         │                        │
│  Active               │         │  Standby               │
│  RTO: N/A              │         │  RTO: 30 minutes       │
│  RPO: N/A              │         │  RPO: 5 minutes        │
└────────────────────────┘         └────────────────────────┘
```

## Network Topology

```
                    Internet Gateway
                           │
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
   ┌────▼────┐        ┌────▼────┐       ┌────▼────┐
   │Public   │        │Public   │       │Public   │
   │Subnet   │        │Subnet   │       │Subnet   │
   │AZ-1a    │        │AZ-1b    │       │AZ-1c    │
   │         │        │         │       │         │
   │ ALB     │        │ ALB     │       │ ALB     │
   │ NAT GW  │        │ NAT GW  │       │ NAT GW  │
   └────┬────┘        └────┬────┘       └────┬────┘
        │                  │                  │
   ┌────▼────┐        ┌────▼────┐       ┌────▼────┐
   │Private  │        │Private  │       │Private  │
   │Subnet   │        │Subnet   │       │Subnet   │
   │AZ-1a    │        │AZ-1b    │       │AZ-1c    │
   │         │        │         │       │         │
   │EKS Node │        │EKS Node │       │EKS Node │
   └────┬────┘        └────┬────┘       └────┬────┘
        │                  │                  │
   ┌────▼────┐        ┌────▼────┐       ┌────▼────┐
   │Database │        │Database │       │Database │
   │Subnet   │        │Subnet   │       │Subnet   │
   │AZ-1a    │        │AZ-1b    │       │AZ-1c    │
   │         │        │         │       │         │
   │Aurora   │        │Aurora   │       │Aurora   │
   │Redis    │        │Redis    │       │Redis    │
   └─────────┘        └─────────┘       └─────────┘
```

## CI/CD Architecture

```
┌──────────────┐
│   GitHub     │
│  Repository  │
└──────┬───────┘
       │ git push
       ▼
┌──────────────────────────────────────────┐
│       GitHub Actions Pipeline            │
│                                          │
│  1. Test & Build                         │
│     ├─ Lint Terraform                    │
│     ├─ Validate K8s                      │
│     ├─ Security Scan (Checkov/Trivy)    │
│     └─ Build Docker Image                │
│                                          │
│  2. Deploy to Staging                    │
│     ├─ Terraform Apply                   │
│     ├─ Deploy to EKS                     │
│     └─ Integration Tests                 │
│                                          │
│  3. Deploy to Production (Manual)        │
│     ├─ Terraform Apply                   │
│     ├─ Canary Deploy (20%)               │
│     ├─ Monitor (5 min)                   │
│     ├─ Full Deploy (100%)                │
│     └─ Health Checks                     │
└───────────┬──────────────────────────────┘
            │
            ▼
    ┌───────────────┐
    │  AWS ECR      │
    │  Docker       │
    │  Registry     │
    └───────────────┘
            │
            ▼
    ┌───────────────┐
    │  EKS Cluster  │
    │  (Staging/    │
    │   Prod)       │
    └───────────────┘
```

## Monitoring & Observability

```
┌────────────────────────────────────────────────────────────┐
│                   Application Layer                         │
│  ┌──────────────────────────────────────────────────┐      │
│  │  Transaction Validator Pods                       │      │
│  │  • Prometheus metrics endpoint (/metrics)         │      │
│  │  • Application logs (JSON format)                 │      │
│  │  • Distributed tracing (OpenTelemetry ready)     │      │
│  └──────────────┬───────────────────────────────────┘      │
└─────────────────┼──────────────────────────────────────────┘
                  │
         ┌────────┼────────┬────────────┐
         │        │        │            │
         ▼        ▼        ▼            ▼
    ┌────────┐ ┌─────┐ ┌──────┐  ┌──────────┐
    │CloudWtch│ │Prom.│ │Fluentd│  │  X-Ray   │
    │ Logs   │ │     │ │/Fluent │  │ (Future) │
    └────┬───┘ └──┬──┘ │  Bit   │  └──────────┘
         │       │     └────────┘
         │       │
         ▼       ▼
    ┌──────────────────┐
    │  CloudWatch      │
    │  Dashboard       │
    └────────┬─────────┘
             │
             ▼
    ┌──────────────────┐
    │   SNS Alerts     │
    │   • Email        │
    │   • Slack        │
    │   • PagerDuty    │
    └──────────────────┘
```

## Legend

- `─`, `│`, `┌`, `┐`, `└`, `┘`: Box drawing characters
- `▼`, `►`: Data flow direction
- `◄──`: Reference/annotation

