# Argus Mutating Webhook

This directory contains a Go-based mutating admission webhook that replaces the functionality of the post-install job for the Argus Helm chart.

## Overview

The webhook intercepts Deployment creation/update requests for the Argus application and automatically:

1. **Adds environment variables** based on secret data (COMPANY_DOMAIN, ETCD_DISCOVERY_TOKEN, proxy settings)
2. **Sets the correct replica count** 
3. **Replaces the post-install job functionality** for environment variable injection

## Kubernetes Compatibility

- **API Version**: Uses `admissionregistration.k8s.io/v1` (Kubernetes 1.16+)
- **Admission Review Versions**: Supports both v1 and v1beta1 admission review formats for maximum compatibility
- **Backward Compatibility**: The webhook server handles both API versions automatically

## Features

- **Environment Variable Injection**: Automatically adds required environment variables from user-defined secrets
- **Dynamic Configuration**: Reads configuration from Kubernetes secrets and ConfigMaps
- **TLS Security**: Uses auto-generated TLS certificates for secure communication
- **Failure Tolerance**: Configurable failure policy (Ignore/Fail)

## Building the Webhook

### Prerequisites

- Go 1.21+
- Docker
- Access to a container registry

### Build Steps

1. **Build the Docker image**:
   ```bash
   cd charts/argus/webhook
   docker build -t logicmonitor/argus-webhook:latest .
   ```

2. **Push to registry**:
   ```bash
   docker push logicmonitor/argus-webhook:latest
   ```

3. **Update values.yaml** with the correct image details:
   ```yaml
   webhook:
     enabled: true
     image:
       repository: logicmonitor
       name: argus-webhook
       tag: latest
   ```

## Usage

### Enable the Webhook

In your `values.yaml`:

```yaml
webhook:
  enabled: true  # This disables the post-install job and enables the webhook
  
  # Optional: Custom image configuration
  image:
    registry: ""
    repository: logicmonitor
    name: argus-webhook
    tag: "latest"
    
  # Optional: Resource limits
  resources:
    limits:
      cpu: 500m
      memory: 256Mi
    requests:
      cpu: 100m
      memory: 128Mi
```

### Deploy

```bash
helm install argus . --values values.yaml
```

## How It Works

1. **ServiceAccount & RBAC**: Created first with pre-install hook (weight -15)
2. **Webhook Service**: Created with pre-install hook (weight -10)
3. **Certificate Generation**: Pre-install job generates TLS certificates (weight -9)
4. **Webhook Configuration**: MutatingWebhookConfiguration created with CA bundle (weight -8)
5. **Webhook Deployment**: Deployed with pre-install hook (weight -5)
6. **Readiness Check**: Job waits for webhook to be ready (weight 0)
7. **Main Install**: Argus deployment created (webhook is ready to mutate it)
8. **ConfigMap Update**: Post-install job updates ConfigMap with kube-state-metrics URL

**Automatic Mutation**: When the argus deployment is created, the webhook:
   - Checks if it's the Argus deployment (by container name)
   - Reads the user-defined secret for configuration
   - Adds appropriate environment variables
   - Sets the correct replica count

## Environment Variables Handled

The webhook automatically adds these environment variables when appropriate:

- `COMPANY_DOMAIN`: From secret or default value
- `ETCD_DISCOVERY_TOKEN`: From secret if present
- `PROXY_USER`: From secret if present (checks both `argusProxyUser` and `proxyUser`)
- `PROXY_PASS`: From secret if present (checks both `argusProxyPass` and `proxyPass`)

## Configuration

The webhook reads configuration from:

- `USER_DEFINED_SECRET`: Name of the secret containing user credentials
- `COMPANY_DOMAIN`: Default company domain if not in secret
- `DESIRED_REPLICAS`: Target replica count for the deployment
- `RELEASE_NAME`: Helm release name for secret naming

## Security

- Uses TLS for all communication
- Validates webhook configuration with CA bundle
- Follows least-privilege RBAC principles
- Configurable failure policy for high availability

## Troubleshooting

### Check webhook logs:
```bash
kubectl logs -l app.kubernetes.io/component=webhook -n <namespace>
```

### Verify certificates:
```bash
kubectl get secret <release-name>-webhook-certs -o yaml
```

### Check webhook configuration:
```bash
kubectl get mutatingadmissionwebhook <release-name>-webhook -o yaml
```

### Webhook not working:
1. Ensure webhook pod is running
2. Check certificate validity
3. Verify RBAC permissions
4. Check webhook service endpoints

### "illegal base64 data" error in MutatingWebhookConfiguration:
This error occurs when the CA bundle is malformed. The fix ensures proper base64 encoding:

**Check certificate generation logs**:
```bash
kubectl logs -l app.kubernetes.io/component=webhook-cert-generator
```

**Verify CA bundle in ConfigMap**:
```bash
kubectl get configmap <release-name>-webhook-ca -o yaml
```

**Manual verification** (the CA bundle should be valid base64):
```bash
kubectl get configmap <release-name>-webhook-ca -o jsonpath='{.data.caBundle}' | base64 -d
```

The certificate generation job now includes validation to ensure clean base64 encoding.

### "TLS handshake error" or "bad certificate" in webhook:
This error occurs when the webhook certificate doesn't match what Kubernetes expects:

**Check webhook logs for certificate details**:
```bash
kubectl logs -l app.kubernetes.io/component=webhook
```

**Check certificate generation logs**:
```bash
kubectl logs -l app.kubernetes.io/component=webhook-cert-generator
```

**Verify certificate SANs include the service name**:
```bash
kubectl get secret <release-name>-webhook-certs -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout | grep -A 10 "Subject Alternative Name"
```

**Expected SANs should include**:
- `<release-name>-webhook.<namespace>.svc.cluster.local`
- `<release-name>-webhook.<namespace>.svc`
- `<release-name>-webhook.<namespace>`
- `<release-name>-webhook`

The certificate generation now includes comprehensive SANs, IP addresses, and proper certificate validation.

### Webhook not being called (no "mutate webhook request" logs):
If the webhook server starts but you don't see mutation logs, the MutatingWebhookConfiguration may not be targeting deployments correctly:

**Check if webhook configuration exists**:
```bash
kubectl get mutatingwebhookconfiguration <release-name>-webhook -o yaml
```

**Verify webhook is targeting correct namespace and resources**:
```bash
kubectl get mutatingwebhookconfiguration <release-name>-webhook -o jsonpath='{.webhooks[0].rules}'
```

**Test webhook manually** (if reachable):
```bash
kubectl port-forward svc/<release-name>-webhook 8443:443
curl -k https://localhost:8443/health
```

**Check webhook server logs for startup messages**:
```bash
kubectl logs -l app.kubernetes.io/component=webhook | grep "Starting webhook server"
```

**Debug logs are now comprehensive - look for these patterns**:
- 🎯 = Webhook request received and processed
- 🔍 = Mutation logic and deployment analysis  
- 🩺 = Health check requests

**Check if webhook is receiving ANY requests**:
```bash
kubectl logs -l app.kubernetes.io/component=webhook | grep "🎯"
```

**Check if webhook is processing argus deployments**:
```bash
kubectl logs -l app.kubernetes.io/component=webhook | grep "🔍.*argus"
```

**Check health checks are working**:
```bash
kubectl logs -l app.kubernetes.io/component=webhook | grep "🩺"
```

**Force webhook call by creating test deployment**:
```bash
kubectl create deployment test-deployment --image=nginx
kubectl delete deployment test-deployment
```

**Expected log flow for working webhook**:
1. `🎯 WEBHOOK MUTATE REQUEST RECEIVED!` - Request arrives
2. `🔍 === MUTATE DEPLOYMENT FUNCTION ===` - Processing starts
3. `🔍 Container X: argus` - Found argus container (for argus deployment)
4. `🔍 Generated X patches` - Patches created
5. `🎯 WEBHOOK MUTATE REQUEST COMPLETED!` - Response sent

If you see step 1 but not step 2, there's a parsing issue.
If you see steps 1-2 but deployment isn't argus, webhook correctly ignores it.
If webhook logs don't appear at all, the MutatingWebhookConfiguration isn't working.

### Certificate generation fails with permission or missing tools:
The certificate generation job requires both `kubectl` and `openssl`. By default, it uses `alpine/k8s:1.28.13` which includes kubectl and automatically installs openssl if needed. Common errors and solutions:

**"kubectl: not found"** or **"openssl: not found"**:
```yaml
webhook:
  certJob:
    image: alpine/k8s:1.28.13  # Includes kubectl, auto-installs openssl
```

**"Permission denied"** when installing packages:
The job runs as root to install missing tools and manage certificates. This is expected and secure within the job context.

**Alternative images you can try**:
- `alpine/k8s:1.28.13` (recommended - lightweight Alpine with kubectl)
- `google/cloud-sdk:alpine` (includes kubectl, auto-installs openssl)
- `bitnami/kubectl:latest` (kubectl only, auto-installs openssl)
- Custom image with both kubectl and openssl pre-installed

**Manual installation approach** (if using a different image):
```yaml
webhook:
  certJob:
    image: your-custom-image
    # Script will auto-detect and install missing tools
```

## Migration from Post-Install Job

When migrating from the post-install job approach:

1. Set `webhook.enabled: true` in values.yaml
2. The post-install job will be automatically disabled
3. Existing deployments will be updated on next restart
4. New deployments will be automatically mutated

## Development

### Local Testing

```bash
# Run tests
go test ./...

# Build locally
go build -o webhook main.go

# Run with environment variables
export USER_DEFINED_SECRET=my-secret
export COMPANY_DOMAIN=example.com
export DESIRED_REPLICAS=1
./webhook
```

### Debug Mode

Add verbose logging by setting the log level in the deployment:

```yaml
env:
  - name: LOG_LEVEL
    value: "debug"
```

## Testing

### Test Webhook Functionality

1. **Deploy with webhook enabled**:
   ```bash
   helm install argus . --set webhook.enabled=true
   ```

2. **Create a test deployment**:
   ```bash
   kubectl apply -f webhook/test-webhook.yaml
   ```

3. **Verify environment variables were injected**:
   ```bash
   kubectl get deployment test-argus-deployment -o yaml
   ```

4. **Check webhook logs**:
   ```bash
   kubectl logs -l app.kubernetes.io/component=webhook
   ```

### Verify API Version Compatibility

The webhook supports both v1 and v1beta1 admission review formats. You can verify this by:

1. Checking the webhook configuration:
   ```bash
   kubectl get mutatingadmissionwebhookconfigurations -o yaml
   ```

2. Looking for `admissionReviewVersions: ["v1", "v1beta1"]` in the configuration

3. Checking webhook logs to see which version is being used:
   ```bash
   kubectl logs -l app.kubernetes.io/component=webhook | grep "Processing admission request"
   ```
