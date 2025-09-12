#!/bin/bash

echo "🔍 WEBHOOK TROUBLESHOOTING SCRIPT"
echo "=================================="

# Get release name
RELEASE_NAME=$(helm list -q | head -1)
NAMESPACE=$(kubectl config view --minify --output 'jsonpath={..namespace}')

if [ -z "$RELEASE_NAME" ]; then
    echo "❌ No Helm release found. Please ensure argus is installed."
    exit 1
fi

echo "📋 Release: $RELEASE_NAME"
echo "📋 Namespace: $NAMESPACE"
echo ""

echo "🔍 STEP 1: Check if MutatingWebhookConfiguration exists"
echo "======================================================"
kubectl get mutatingwebhookconfiguration ${RELEASE_NAME}-webhook 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✅ MutatingWebhookConfiguration found"
    echo ""
    echo "📋 Webhook Configuration Details:"
    kubectl get mutatingwebhookconfiguration ${RELEASE_NAME}-webhook -o yaml | grep -A 10 -B 5 "service:\|path:\|caBundle:"
else
    echo "❌ MutatingWebhookConfiguration NOT found!"
    echo "   Check if webhook.enabled=true in values"
    exit 1
fi

echo ""
echo "🔍 STEP 2: Check webhook service"
echo "==============================="
kubectl get svc ${RELEASE_NAME}-webhook -n $NAMESPACE 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✅ Webhook service found"
    echo ""
    echo "📋 Service Details:"
    kubectl get svc ${RELEASE_NAME}-webhook -n $NAMESPACE -o wide
    echo ""
    echo "📋 Service Endpoints:"
    kubectl get endpoints ${RELEASE_NAME}-webhook -n $NAMESPACE
else
    echo "❌ Webhook service NOT found!"
fi

echo ""
echo "🔍 STEP 3: Check webhook deployment"
echo "=================================="
kubectl get deployment ${RELEASE_NAME}-webhook -n $NAMESPACE 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✅ Webhook deployment found"
    echo ""
    echo "📋 Deployment Status:"
    kubectl get deployment ${RELEASE_NAME}-webhook -n $NAMESPACE -o wide
    echo ""
    echo "📋 Pod Status:"
    kubectl get pods -l app.kubernetes.io/component=webhook -n $NAMESPACE
else
    echo "❌ Webhook deployment NOT found!"
fi

echo ""
echo "🔍 STEP 4: Check webhook pod logs"
echo "================================"
WEBHOOK_POD=$(kubectl get pods -l app.kubernetes.io/component=webhook -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ ! -z "$WEBHOOK_POD" ]; then
    echo "✅ Webhook pod found: $WEBHOOK_POD"
    echo ""
    echo "📋 Recent webhook logs:"
    kubectl logs $WEBHOOK_POD -n $NAMESPACE --tail=10
else
    echo "❌ No webhook pod found!"
fi

echo ""
echo "🔍 STEP 5: Check CA bundle"
echo "=========================="
CA_CONFIGMAP="${RELEASE_NAME}-webhook-ca"
kubectl get configmap $CA_CONFIGMAP -n $NAMESPACE 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✅ CA ConfigMap found"
    echo ""
    echo "📋 CA Bundle Size:"
    kubectl get configmap $CA_CONFIGMAP -n $NAMESPACE -o jsonpath='{.data.caBundle}' | wc -c
else
    echo "❌ CA ConfigMap NOT found!"
fi

echo ""
echo "🔍 STEP 6: Test webhook connectivity"
echo "===================================="
echo "Testing if API server can reach webhook service..."

# Port forward to test connectivity
kubectl port-forward svc/${RELEASE_NAME}-webhook 8443:443 -n $NAMESPACE &
PF_PID=$!
sleep 2

# Test health endpoint
curl -k -s https://localhost:8443/health
HEALTH_STATUS=$?

kill $PF_PID 2>/dev/null

if [ $HEALTH_STATUS -eq 0 ]; then
    echo ""
    echo "✅ Webhook service is reachable"
else
    echo ""
    echo "❌ Webhook service is NOT reachable"
fi

echo ""
echo "🔍 STEP 7: Test webhook with dummy deployment"
echo "============================================="
echo "Creating test deployment to trigger webhook..."

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webhook-test-deployment
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: webhook-test
  template:
    metadata:
      labels:
        app: webhook-test
    spec:
      containers:
      - name: argus
        image: nginx:alpine
EOF

echo ""
echo "📋 Checking webhook logs for the test deployment..."
sleep 2
kubectl logs -l app.kubernetes.io/component=webhook -n $NAMESPACE --tail=20 | grep -E "(mutate|webhook|test-deployment)" || echo "❌ No webhook logs found!"

echo ""
echo "Cleaning up test deployment..."
kubectl delete deployment webhook-test-deployment -n $NAMESPACE 2>/dev/null

echo ""
echo "🔍 DIAGNOSIS COMPLETE"
echo "===================="
echo "If webhook logs don't show any activity, the issue is likely:"
echo "1. MutatingWebhookConfiguration not properly configured"
echo "2. Service networking issue"  
echo "3. Certificate/TLS issue preventing API server from calling webhook"
echo ""
echo "Next steps:"
echo "- Check the actual webhook configuration with: kubectl get mutatingwebhookconfiguration ${RELEASE_NAME}-webhook -o yaml"
echo "- Verify certificate generation job completed successfully"
echo "- Check API server logs if webhook still not called"
