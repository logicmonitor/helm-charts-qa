#!/bin/bash

echo "🧪 WEBHOOK ENVIRONMENT VARIABLE TEST"
echo "===================================="

# Build and load webhook image
echo "📦 Building webhook image..."
cd charts/argus/webhook
docker build -t test-mutating-webhook:latest .
echo "✅ Webhook image built"

# Load image into kind cluster (if using kind)
# Uncomment if using kind: kind load docker-image test-mutating-webhook:latest

echo ""
echo "🔄 Updating webhook deployment..."
cd ..
kubectl rollout restart deployment lmc-argus-webhook -n lm-portal
kubectl rollout status deployment lmc-argus-webhook -n lm-portal --timeout=60s

echo ""
echo "📋 Waiting for webhook to be ready..."
sleep 10

echo ""
echo "🧪 Testing webhook with fresh deployment..."

# Delete test deployment if it exists
kubectl delete deployment test-argus-webhook -n lm-portal --ignore-not-found=true
sleep 2

# Watch webhook logs in background
echo "📊 Starting log monitoring..."
kubectl logs -f -l app.kubernetes.io/component=webhook -n lm-portal &
LOG_PID=$!
sleep 2

# Create test deployment
echo "🚀 Creating test deployment..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-argus-webhook
  namespace: lm-portal
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-argus-webhook
  template:
    metadata:
      labels:
        app: test-argus-webhook
    spec:
      containers:
      - name: argus  # Must be named "argus" for webhook to process
        image: nginx:alpine
        ports:
        - containerPort: 80
EOF

echo ""
echo "⏳ Waiting for deployment to be processed..."
sleep 5

# Stop log monitoring
kill $LOG_PID 2>/dev/null

echo ""
echo "🔍 Checking deployment environment variables..."
kubectl get deployment test-argus-webhook -n lm-portal -o yaml | grep -A 20 "env:" || echo "No env section found"

echo ""
echo "🔍 Checking pod environment variables..."
POD_NAME=$(kubectl get pods -l app=test-argus-webhook -n lm-portal -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ ! -z "$POD_NAME" ]; then
    echo "Pod: $POD_NAME"
    kubectl get pod $POD_NAME -n lm-portal -o yaml | grep -A 20 "env:" || echo "No env section found in pod"
    
    echo ""
    echo "🔍 Environment variables inside pod:"
    kubectl exec $POD_NAME -n lm-portal -- env | grep -E "(TEST_|COMPANY_|USER_)" || echo "No webhook-injected env vars found"
else
    echo "❌ No pod found for test deployment"
fi

echo ""
echo "🔍 Recent webhook logs:"
kubectl logs -l app.kubernetes.io/component=webhook -n lm-portal --tail=20 | grep -E "(Generated|Patch|Adding|Container|mutate|env)"

echo ""
echo "🧹 Cleaning up..."
kubectl delete deployment test-argus-webhook -n lm-portal

echo ""
echo "🎯 Test completed!"
echo "Expected to see:"
echo "  ✅ 'Generated X patches' in webhook logs"
echo "  ✅ 'Adding environment variable: TEST_HOOK=asdfsd' in webhook logs"
echo "  ✅ Environment variables in deployment and pod specs"
