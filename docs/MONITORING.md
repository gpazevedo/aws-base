# Monitoring and Observability Guide

This guide covers monitoring, logging, and observability for all deployment options: Lambda, App Runner, and EKS.

---

## 📚 Table of Contents

- [Overview](#overview)
- [Lambda Monitoring](#lambda-monitoring)
- [App Runner Monitoring](#app-runner-monitoring)
- [EKS Monitoring](#eks-monitoring)
- [Application Metrics](#application-metrics)
- [Custom Dashboards](#custom-dashboards)
- [Alerting](#alerting)
- [Cost Monitoring](#cost-monitoring)

---

## Overview

All deployment options provide built-in monitoring via AWS CloudWatch, but each has specific tools and best practices.

### Quick Comparison

| Feature | Lambda | App Runner | EKS |
|---------|--------|------------|-----|
| **Logs** | CloudWatch Logs | CloudWatch Logs | CloudWatch Logs / Fluentd |
| **Metrics** | CloudWatch Metrics | CloudWatch Metrics | CloudWatch Container Insights |
| **Traces** | X-Ray | X-Ray | X-Ray / Jaeger |
| **Dashboards** | CloudWatch | CloudWatch | CloudWatch / Grafana |
| **Cost** | Low | Low | Medium |
| **Setup** | Automatic | Automatic | Manual |

---

## Lambda Monitoring

### CloudWatch Logs

**Automatic logging** - All Lambda output goes to CloudWatch Logs.

**View logs:**
```bash
# Via AWS CLI
aws logs tail /aws/lambda/my-project-dev-api --follow

# Via AWS Console
# CloudWatch → Log groups → /aws/lambda/my-project-dev-api
```

**Search logs:**
```bash
# Search for errors
aws logs filter-log-events \
  --log-group-name /aws/lambda/my-project-dev-api \
  --filter-pattern "ERROR"

# Get last 100 lines
aws logs tail /aws/lambda/my-project-dev-api --since 1h
```

### CloudWatch Metrics

**Built-in metrics:**
- Invocations
- Errors
- Duration
- Throttles
- Concurrent executions
- Iterator age (for stream-based invocations)

**View metrics:**
```bash
# Get invocation count
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=my-project-dev-api \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

### X-Ray Tracing

**Enable X-Ray** in Lambda function:

```hcl
# terraform/resources/lambda-functions.tf
resource "aws_lambda_function" "api" {
  # ... other config

  tracing_config {
    mode = "Active"
  }
}
```

**Add X-Ray SDK** to application:

```python
# backend/api/main.py
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.ext.fastapi.middleware import XRayMiddleware

app.add_middleware(XRayMiddleware)

@xray_recorder.capture('greet_function')
async def greet(name: str):
    # ... function code
```

**Update dependencies:**
```toml
# backend/api/pyproject.toml
dependencies = [
    # ... existing
    "aws-xray-sdk>=2.12.0,<3.0.0",
]
```

### Custom Metrics

**Publish custom metrics:**

```python
import boto3

cloudwatch = boto3.client('cloudwatch')

def publish_metric(metric_name: str, value: float):
    cloudwatch.put_metric_data(
        Namespace='MyApp',
        MetricData=[
            {
                'MetricName': metric_name,
                'Value': value,
                'Unit': 'Count'
            }
        ]
    )

# Usage in endpoint
@app.get("/greet")
async def greet(name: str):
    publish_metric('GreetingsServed', 1)
    return {"message": f"Hello, {name}!"}
```

---

## App Runner Monitoring

### CloudWatch Logs

**Automatic logging** - All container output goes to CloudWatch Logs.

**View logs:**
```bash
# Get log group name
SERVICE_ARN=$(aws apprunner list-services \
  --query "ServiceSummaryList[?ServiceName=='my-project-dev-api'].ServiceArn" \
  --output text)

LOG_GROUP="/aws/apprunner/${SERVICE_ARN}/application"

# Tail logs
aws logs tail "$LOG_GROUP" --follow
```

### CloudWatch Metrics

**Built-in metrics:**
- Active instances
- CPU utilization
- Memory utilization
- Requests
- Status 2xx/4xx/5xx
- Response time

**View in console:**
```
App Runner → Services → my-project-dev-api → Metrics
```

### Health Checks

App Runner automatically monitors health using FastAPI endpoints:

```python
# backend/api/main.py - Already configured!
@app.get("/health")
async def health_check():
    return {"status": "healthy"}
```

**Configure health check** in Terraform:

```hcl
resource "aws_apprunner_service" "api" {
  # ... other config

  health_check_configuration {
    protocol            = "HTTP"
    path                = "/health"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 1
    unhealthy_threshold = 5
  }
}
```

---

## EKS Monitoring

### Container Insights

**Enable Container Insights:**

```bash
# Install CloudWatch agent
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluentd-quickstart.yaml

# Verify installation
kubectl get daemonset cloudwatch-agent -n amazon-cloudwatch
kubectl get daemonset fluentd-cloudwatch-logs -n amazon-cloudwatch
```

**View metrics in CloudWatch:**
```
CloudWatch → Container Insights → Performance monitoring
```

**Metrics available:**
- Node CPU/Memory
- Pod CPU/Memory
- Container CPU/Memory
- Network I/O
- Disk I/O

### Prometheus + Grafana (Recommended)

**Install Prometheus:**

```bash
# Add Prometheus Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
```

**Access Grafana:**
```bash
# Get Grafana password
kubectl get secret --namespace monitoring prometheus-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode ; echo

# Port forward
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Open: http://localhost:3000
# Username: admin
# Password: (from above)
```

**Pre-built dashboards:**
- Kubernetes Cluster Monitoring
- Node Exporter Full
- Pod Monitoring

### Application Metrics with Prometheus

**Add Prometheus client** to FastAPI:

```python
# backend/api/main.py
from prometheus_client import Counter, Histogram, make_asgi_app
from fastapi import FastAPI

# Create metrics
requests_total = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint'])
request_duration = Histogram('http_request_duration_seconds', 'HTTP request duration')

app = FastAPI()

# Mount Prometheus metrics endpoint
metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)

@app.middleware("http")
async def prometheus_middleware(request, call_next):
    with request_duration.time():
        response = await call_next(request)
        requests_total.labels(method=request.method, endpoint=request.url.path).inc()
        return response
```

**Update dependencies:**
```toml
# backend/api/pyproject.toml
dependencies = [
    # ... existing
    "prometheus-client>=0.19.0,<1.0.0",
]
```

**Create ServiceMonitor:**

```yaml
# k8s/api/servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: api-metrics
  namespace: dev
spec:
  selector:
    matchLabels:
      app: api
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
```

### Logging with Fluentd

**Already installed** with Container Insights.

**Custom log parsing:**

```yaml
# k8s/fluentd-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentd-config
  namespace: amazon-cloudwatch
data:
  fluent.conf: |
    <match **>
      @type cloudwatch_logs
      log_group_name /aws/eks/my-project/application
      log_stream_name ${tag}
      auto_create_stream true
    </match>
```

### Distributed Tracing with X-Ray

**Install X-Ray daemon:**

```bash
kubectl apply -f https://github.com/aws/aws-xray-daemon/raw/master/kubernetes/xray-daemonset.yaml
```

**Configure application:**

```python
# Same as Lambda X-Ray configuration above
from aws_xray_sdk.ext.fastapi.middleware import XRayMiddleware
app.add_middleware(XRayMiddleware)
```

---

## Application Metrics

### FastAPI Built-in Metrics

The FastAPI application exposes health check endpoints for monitoring:

**Endpoints:**
- `/health` - Comprehensive health with uptime
- `/liveness` - Kubernetes liveness probe
- `/readiness` - Kubernetes readiness probe

**Example health response:**
```json
{
  "status": "healthy",
  "timestamp": "2025-01-20T12:34:56.789012+00:00",
  "uptime_seconds": 123.45,
  "version": "0.1.0"
}
```

### Custom Application Metrics

**Add business metrics:**

```python
from prometheus_client import Counter, Gauge

# Business metrics
greetings_served = Counter('greetings_served_total', 'Total greetings served')
active_users = Gauge('active_users', 'Number of active users')

@app.get("/greet")
async def greet(name: str):
    greetings_served.inc()
    # ... rest of code
```

---

## Custom Dashboards

### CloudWatch Dashboard

**Create dashboard:**

```bash
# Create dashboard JSON
cat > dashboard.json <<'EOF'
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          [ "AWS/Lambda", "Invocations", { "stat": "Sum" } ],
          [ ".", "Errors", { "stat": "Sum" } ],
          [ ".", "Duration", { "stat": "Average" } ]
        ],
        "period": 300,
        "stat": "Average",
        "region": "us-east-1",
        "title": "Lambda Metrics"
      }
    }
  ]
}
EOF

# Create dashboard
aws cloudwatch put-dashboard \
  --dashboard-name MyAppDashboard \
  --dashboard-body file://dashboard.json
```

### Grafana Dashboard (EKS)

**Import pre-built dashboards:**

1. Access Grafana (port forward as shown above)
2. Click "+" → Import
3. Enter dashboard ID:
   - **15759** - Kubernetes Cluster Monitoring
   - **15760** - Kubernetes Pod Monitoring
   - **15761** - Kubernetes Node Monitoring

**Create custom dashboard** for FastAPI:

```json
{
  "dashboard": {
    "title": "FastAPI Application Metrics",
    "panels": [
      {
        "title": "Request Rate",
        "targets": [
          {
            "expr": "rate(http_requests_total[5m])"
          }
        ]
      },
      {
        "title": "Request Duration",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))"
          }
        ]
      }
    ]
  }
}
```

---

## Alerting

### CloudWatch Alarms

**Lambda error alert:**

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name lambda-high-errors \
  --alarm-description "Alert when Lambda error rate is high" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=FunctionName,Value=my-project-dev-api \
  --alarm-actions arn:aws:sns:us-east-1:123456789012:my-alerts
```

**EKS pod crash alert:**

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name eks-pod-crashes \
  --alarm-description "Alert when pods are crashing" \
  --metric-name pod_number_of_container_restarts \
  --namespace ContainerInsights \
  --statistic Average \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=ClusterName,Value=my-project-dev Name=Namespace,Value=dev
```

### Prometheus Alerts (EKS)

**Create PrometheusRule:**

```yaml
# k8s/prometheus-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: api-alerts
  namespace: monitoring
spec:
  groups:
  - name: api
    interval: 30s
    rules:
    - alert: HighErrorRate
      expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.05
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "High error rate detected"
        description: "Error rate is {{ $value }} requests/sec"

    - alert: HighResponseTime
      expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 1
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High response time detected"
        description: "95th percentile response time is {{ $value }} seconds"
```

---

## Cost Monitoring

### Cost Explorer

**View costs by service:**
```
AWS Console → Cost Explorer → Cost & Usage Reports
Filter by: Service, Tag, Resource
```

### Tagged Resources

**Tag resources for cost tracking:**

```hcl
# In Terraform
resource "aws_lambda_function" "api" {
  tags = {
    Environment = "dev"
    Project     = "my-project"
    ManagedBy   = "terraform"
    CostCenter  = "engineering"
  }
}
```

### Budget Alerts

**Create budget:**
```bash
aws budgets create-budget \
  --account-id 123456789012 \
  --budget file://budget.json \
  --notifications-with-subscribers file://notifications.json
```

---

## Best Practices

### Lambda
- ✅ Enable X-Ray for distributed tracing
- ✅ Set appropriate log retention (7-30 days)
- ✅ Use structured logging (JSON)
- ✅ Monitor cold starts
- ✅ Track custom business metrics

### App Runner
- ✅ Configure health check endpoints
- ✅ Monitor instance scaling metrics
- ✅ Set up auto-scaling based on load
- ✅ Use CloudWatch Insights
- ✅ Monitor request latency

### EKS
- ✅ Enable Container Insights
- ✅ Deploy Prometheus + Grafana
- ✅ Configure log aggregation
- ✅ Set up distributed tracing
- ✅ Use ServiceMonitors for app metrics
- ✅ Configure HPA based on custom metrics
- ✅ Monitor node and pod resources

### All Platforms
- ✅ Set up alerting for critical metrics
- ✅ Create custom dashboards
- ✅ Monitor costs regularly
- ✅ Use health check endpoints
- ✅ Implement structured logging
- ✅ Track SLOs/SLIs

---

## Next Steps

1. **Enable monitoring** for your deployment type
2. **Create dashboards** for key metrics
3. **Set up alerts** for critical issues
4. **Implement logging** best practices
5. **Monitor costs** and optimize resources
6. **Document runbooks** for common issues

---

## Resources

- [CloudWatch Documentation](https://docs.aws.amazon.com/cloudwatch/)
- [Container Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [AWS X-Ray](https://docs.aws.amazon.com/xray/)
- [FastAPI Monitoring](https://fastapi.tiangolo.com/advanced/middleware/)
