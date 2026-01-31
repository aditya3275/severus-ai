# Performance Evaluation Scripts

This directory contains scripts for performance testing and evaluation of the Severus AI application.

## Scripts

### `stress_pod.sh`

A comprehensive Bash script for load testing Kubernetes-deployed applications.

**Features:**
- Configurable HTTP request load generation
- Concurrent request execution
- Multiple test runs with configurable intervals
- Real-time resource monitoring (CPU/memory via `kubectl top`)
- Pod health validation
- Request verification via pod logs
- Detailed performance reports

**Usage:**

```bash
./stress_pod.sh -t <target_url> [-t <target_url> ...] \
                -tr <total_requests> -c <concurrency> \
                [-r <runs>] [-s <sleep_seconds>] \
                [-p <pod_label> ...]
```

**Parameters:**

| Flag | Description | Required | Default |
|------|-------------|----------|---------|
| `-t` | Target URL(s) to test | Yes | - |
| `-tr` | Total requests per run | No | 100 |
| `-c` | Concurrent requests | No | 5 |
| `-r` | Number of runs | No | 1 |
| `-s` | Sleep between runs (seconds) | No | 0 |
| `-p` | Pod label(s) for validation | No | - |

**Example:**

```bash
# Light load test
./stress_pod.sh \
  -t http://severus-ai.local \
  -tr 50 \
  -c 5 \
  -r 1 \
  -p "app.kubernetes.io/name=severus-ai"

# Heavy load test with multiple runs
./stress_pod.sh \
  -t http://severus-ai.local \
  -tr 1000 \
  -c 50 \
  -r 3 \
  -s 10 \
  -p "app.kubernetes.io/name=severus-ai"
```

**Output:**

The script generates:
- Real-time progress updates
- Success/failure request counts
- Peak CPU and memory usage per pod
- Pod validation results
- Request verification from pod logs
- Total execution time

**Requirements:**

- `kubectl` configured and connected to cluster
- Kubernetes Metrics Server installed
- `curl` for HTTP requests
- `awk` for data processing
- Bash 4.0+

## CI/CD Integration

This script is automatically executed by the Jenkins pipeline in the **Performance Evaluation** stage when enabled in `values.yaml`.

Configuration is managed via Helm values:

```yaml
performanceTest:
  enabled: true
  targets:
    - "http://severus-ai.local"
  totalRequests: 100
  concurrency: 5
  runs: 1
  sleepBetweenRuns: 0
  podLabels:
    - "app.kubernetes.io/name=severus-ai"
```

## Local Testing

To test locally before running in CI/CD:

```bash
# Ensure kubectl is configured
kubectl get pods

# Ensure Metrics Server is running
kubectl top nodes

# Run the script
cd /path/to/severus-ai
./scripts/stress_pod.sh -t http://severus-ai.local -tr 10 -c 2
```

## Troubleshooting

**"No resource metrics captured"**
- Ensure Metrics Server is installed: `kubectl get deployment metrics-server -n kube-system`
- Wait a few minutes after pod startup for metrics to become available

**"No running pods found for label"**
- Verify pod labels: `kubectl get pods --show-labels`
- Check pod status: `kubectl get pods -l app.kubernetes.io/name=severus-ai`

**"Target not ready"**
- Check ingress configuration: `kubectl get ingress`
- Verify service endpoints: `kubectl get endpoints severus-ai`
- Test connectivity: `curl http://severus-ai.local`

## Best Practices

1. **Start small**: Begin with low request counts to establish baseline
2. **Monitor resources**: Watch cluster resources during tests
3. **Set limits**: Configure resource limits in deployment to prevent node exhaustion
4. **Use staging**: Run heavy tests in staging environments first
5. **Archive results**: Keep performance reports for trend analysis
