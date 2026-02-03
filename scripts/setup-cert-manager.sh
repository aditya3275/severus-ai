#!/bin/bash
# setup-cert-manager.sh - Installs cert-manager on k3s/k3d

set -e

echo "🚀 Adding Jetstack Helm repository..."
helm repo add jetstack https://charts.jetstack.io
helm repo update

echo "📦 Installing/Upgrading cert-manager v1.14.4..."
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.14.4 \
  --set installCRDs=true \
  --set prometheus.enabled=true \
  --set prometheus.servicemonitor.enabled=true

echo "✅ cert-manager installed successfully!"
echo "⏳ Waiting for cert-manager pods to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=120s

echo "🌟 cert-manager is ready!"
