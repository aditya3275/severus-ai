#!/bin/bash
# setup-cert-manager.sh - Installs cert-manager on k3s/k3d

# Use HELM_BIN and KUBECTL_BIN if provided via environment, else default to standard commands
HELM=${HELM_BIN:-helm}
KUBECTL=${KUBECTL_BIN:-kubectl}

set -e

echo "🚀 Adding Jetstack Helm repository..."
$HELM repo add jetstack https://charts.jetstack.io
$HELM repo update

echo "📦 Installing/Upgrading cert-manager v1.14.4..."
$HELM upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.14.4 \
  --set installCRDs=true \
  --set prometheus.enabled=true \
  --set prometheus.servicemonitor.enabled=true

echo "✅ cert-manager installed successfully!"
echo "⏳ Waiting for cert-manager pods to be ready..."
$KUBECTL wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=120s

echo "🌟 cert-manager is ready!"
