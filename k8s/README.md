# Kubernetes Manifests

This directory contains Kubernetes manifests for deploying services to EKS (Elastic Kubernetes Service).

## Directory Structure

```
k8s/
├── README.md                    # This file
└── api/                         # API service manifests
    ├── deployment.yaml          # Deployment with health checks
    ├── service.yaml             # LoadBalancer service
    ├── hpa.yaml                 # Horizontal Pod Autoscaler
    ├── configmap.yaml           # Configuration
    └── ingress.yaml             # ALB Ingress (optional)
```

## Prerequisites

1. **EKS Cluster** - Must be created via bootstrap infrastructure
2. **kubectl** - Configured to access your EKS cluster
3. **AWS Load Balancer Controller** (optional, for Ingress)
4. **Metrics Server** (for HPA)

## Quick Start

### 1. Configure kubectl

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name my-project-dev
```

### 2. Create Namespace

```bash
kubectl create namespace dev
```

### 3. Deploy API Service

**Option A: Using GitHub Actions (Recommended)**

The `deploy-eks.yaml` workflow automatically applies these manifests:

```bash
# Trigger via GitHub Actions
# Actions → Deploy EKS → Run workflow
```

**Option B: Manual Deployment**

```bash
# Set environment variables
export NAMESPACE="dev"
export SERVICE_NAME="my-project-api"
export ENVIRONMENT="dev"
export IMAGE_URI="123456789012.dkr.ecr.us-east-1.amazonaws.com/my-project:api-dev-latest"

# Apply manifests
for file in k8s/api/*.yaml; do
  envsubst < "$file" | kubectl apply -f -
done
```

### 4. Verify Deployment

```bash
# Check deployment status
kubectl get deployments -n dev

# Check pods
kubectl get pods -n dev

# Check service
kubectl get svc -n dev

# Get LoadBalancer endpoint
kubectl get svc my-project-api -n dev \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### 5. Test API

```bash
# Get endpoint
ENDPOINT=$(kubectl get svc my-project-api -n dev \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test health endpoint
curl http://$ENDPOINT/health

# View interactive docs
open "http://$ENDPOINT/docs"
```

## Manifest Details

### deployment.yaml

**Features:**
- **Replicas:** 2 pods for high availability
- **Rolling updates:** Zero-downtime deployments
- **Health checks:**
  - Liveness probe: `/liveness` (restart if unhealthy)
  - Readiness probe: `/readiness` (remove from service if not ready)
  - Startup probe: `/health` (initial startup check)
- **Resource limits:** CPU and memory constraints
- **Security:** Non-root user, read-only filesystem

**Health Check Endpoints:**
```yaml
livenessProbe:
  httpGet:
    path: /liveness
    port: 8000

readinessProbe:
  httpGet:
    path: /readiness
    port: 8000
```

### service.yaml

**Features:**
- **Type:** LoadBalancer (creates AWS ELB)
- **Port:** 80 → 8000
- **Session affinity:** None (stateless)

### hpa.yaml (Horizontal Pod Autoscaler)

**Features:**
- **Min replicas:** 2
- **Max replicas:** 10
- **Metrics:**
  - CPU: Scale at 70% utilization
  - Memory: Scale at 80% utilization
- **Behavior:**
  - Scale up: Fast (100% increase every 15s)
  - Scale down: Slow (50% decrease after 5 min stabilization)

**Prerequisites:**
Metrics Server must be installed:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### configmap.yaml

**Features:**
- Application configuration
- Environment-specific settings
- Non-sensitive data only (use Secrets for sensitive data)

**Usage:**
Reference in deployment:
```yaml
envFrom:
- configMapRef:
    name: my-project-api-config
```

### ingress.yaml (Optional)

**Features:**
- **AWS ALB Integration** via AWS Load Balancer Controller
- **HTTPS/SSL** termination
- **Health checks** using `/health` endpoint
- **Path-based routing**

**Prerequisites:**

Install AWS Load Balancer Controller:
```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=my-project-dev \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

**Enable HTTPS:**
1. Create ACM certificate for your domain
2. Add annotation with certificate ARN:
   ```yaml
   alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:region:account:certificate/xxxxx
   ```

## Environment Variables

Required environment variables for manifest substitution:

| Variable | Example | Description |
|----------|---------|-------------|
| `NAMESPACE` | `dev` | Kubernetes namespace |
| `SERVICE_NAME` | `my-project-api` | Service name |
| `ENVIRONMENT` | `dev` | Environment (dev/test/prod) |
| `IMAGE_URI` | `123456789012.dkr.ecr.us-east-1.amazonaws.com/my-project:api-dev-latest` | Container image URI |

## Common Operations

### View Logs

```bash
# All pods
kubectl logs -n dev -l app=api --tail=100 -f

# Specific pod
kubectl logs -n dev my-project-api-xxxxx-yyyyy -f
```

### Scale Manually

```bash
# Scale to 5 replicas
kubectl scale deployment my-project-api -n dev --replicas=5
```

### Update Image

```bash
# Update to new image
kubectl set image deployment/my-project-api \
  -n dev \
  api=123456789012.dkr.ecr.us-east-1.amazonaws.com/my-project:api-dev-20250120

# Or use GitHub Actions workflow (recommended)
```

### Rollback

```bash
# View rollout history
kubectl rollout history deployment/my-project-api -n dev

# Rollback to previous version
kubectl rollout undo deployment/my-project-api -n dev

# Rollback to specific revision
kubectl rollout undo deployment/my-project-api -n dev --to-revision=2
```

### Debug Pod

```bash
# Exec into pod
kubectl exec -it my-project-api-xxxxx-yyyyy -n dev -- /bin/sh

# Port forward to local machine
kubectl port-forward -n dev svc/my-project-api 8000:80

# Then access: http://localhost:8000/docs
```

## Monitoring

### Check HPA Status

```bash
kubectl get hpa -n dev
kubectl describe hpa my-project-api -n dev
```

### View Metrics

```bash
# CPU/Memory usage
kubectl top pods -n dev
kubectl top nodes

# Events
kubectl get events -n dev --sort-by='.lastTimestamp'
```

## Best Practices

1. **Use namespaces** - Separate environments (dev, staging, prod)
2. **Set resource limits** - Prevent resource exhaustion
3. **Configure health checks** - Enable automatic recovery
4. **Use HPA** - Automatic scaling based on load
5. **Rolling updates** - Zero-downtime deployments
6. **Monitoring** - Track metrics and logs
7. **Security** - Non-root users, network policies
8. **Secrets management** - Use AWS Secrets Manager or Kubernetes Secrets
9. **GitOps** - Deploy via CI/CD (GitHub Actions)

## Troubleshooting

### Pod Not Starting

```bash
# Check pod status
kubectl describe pod my-project-api-xxxxx-yyyyy -n dev

# Common issues:
# - Image pull errors: Check ECR permissions
# - Crash loop: Check application logs
# - Resource limits: Increase memory/CPU
```

### Service Not Accessible

```bash
# Check service endpoints
kubectl get endpoints my-project-api -n dev

# Check if LoadBalancer is created
kubectl describe svc my-project-api -n dev

# Test from within cluster
kubectl run test-pod -n dev --rm -it --image=curlimages/curl -- \
  curl http://my-project-api/health
```

### HPA Not Scaling

```bash
# Check metrics server
kubectl get deployment metrics-server -n kube-system

# Check HPA status
kubectl describe hpa my-project-api -n dev

# Manual test
kubectl run load-generator -n dev --rm -it --image=busybox -- \
  /bin/sh -c "while true; do wget -q -O- http://my-project-api; done"
```

## Next Steps

1. **Add custom manifests** - Create service-specific configs
2. **Configure monitoring** - Prometheus, Grafana, CloudWatch
3. **Set up logging** - Fluentd, CloudWatch Logs
4. **Network policies** - Restrict pod-to-pod communication
5. **Service mesh** - Istio, Linkerd for advanced features
6. **Secrets management** - AWS Secrets Manager integration

## Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [Horizontal Pod Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
