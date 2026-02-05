#!/bin/bash
# setup-cert-manager.sh - Installs cert-manager on k3s/k3d with certificate creation and validation

# Use HELM_BIN and KUBECTL_BIN if provided via environment, else default to standard commands
HELM=${HELM_BIN:-helm}
KUBECTL=${KUBECTL_BIN:-kubectl}

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    if [ "$2" == "success" ]; then
        echo -e "${GREEN}✅ $1${NC}"
    elif [ "$2" == "error" ]; then
        echo -e "${RED}❌ $1${NC}"
    else
        echo -e "${YELLOW}⏳ $1${NC}"
    fi
}

# =====================================================
# STEP 1: Install cert-manager
# =====================================================
echo ""
echo "========================================"
echo "STEP 1: Installing cert-manager"
echo "========================================"

echo "🚀 Adding Jetstack Helm repository..."
$HELM repo add jetstack https://charts.jetstack.io 2>/dev/null || true
$HELM repo update

echo "📦 Installing/Upgrading cert-manager v1.14.4..."
$HELM upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.14.4 \
  --set installCRDs=true \
  --set prometheus.enabled=true \
  --set prometheus.servicemonitor.enabled=true

print_status "cert-manager installed successfully!" "success"

echo "⏳ Waiting for cert-manager pods to be ready..."
$KUBECTL wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=120s

print_status "cert-manager pods are ready!" "success"

# =====================================================
# STEP 2: Create ClusterIssuers and Root CA
# =====================================================
echo ""
echo "========================================"
echo "STEP 2: Creating ClusterIssuers & Root CA"
echo "========================================"

# Create self-signed bootstrap issuer
echo "🔐 Creating self-signed bootstrap ClusterIssuer..."
cat <<EOF | $KUBECTL apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-bootstrap-issuer
spec:
  selfSigned: {}
EOF

# Wait for bootstrap issuer to be ready
sleep 2
$KUBECTL wait --for=condition=ready clusterissuer/selfsigned-bootstrap-issuer --timeout=60s 2>/dev/null || true

# Create Root CA certificate
echo "🏛️ Creating internal Root CA certificate..."
cat <<EOF | $KUBECTL apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: internal-root-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: internal-root-ca
  secretName: internal-root-ca-secret
  duration: 87600h # 10 years
  renewBefore: 720h # 30 days
  issuerRef:
    name: selfsigned-bootstrap-issuer
    kind: ClusterIssuer
EOF

# Wait for root CA to be issued
echo "⏳ Waiting for Root CA certificate to be issued..."
sleep 3
$KUBECTL wait --for=condition=ready certificate/internal-root-ca -n cert-manager --timeout=120s

# Create local CA issuer using the root CA
echo "📜 Creating local-ca-issuer ClusterIssuer..."
cat <<EOF | $KUBECTL apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: local-ca-issuer
spec:
  ca:
    secretName: internal-root-ca-secret
EOF

sleep 2
$KUBECTL wait --for=condition=ready clusterissuer/local-ca-issuer --timeout=60s 2>/dev/null || true

print_status "ClusterIssuers and Root CA created!" "success"

# =====================================================
# STEP 3: Create Application Certificates
# =====================================================
echo ""
echo "========================================"
echo "STEP 3: Creating Application Certificates"
echo "========================================"

# Create severus-ai TLS certificate
echo "🔒 Creating severus-ai TLS certificate..."
cat <<EOF | $KUBECTL apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: severus-ai-tls
  namespace: default
spec:
  secretName: severus-ai-tls-secret
  duration: 2160h # 90 days
  renewBefore: 360h # 15 days
  subject:
    organizations:
      - severus-ai
  commonName: severus-ai.default.svc.cluster.local
  dnsNames:
    - severus-ai.default.svc.cluster.local
    - severus-ai.local
    - localhost
  isCA: false
  privateKey:
    algorithm: RSA
    encoding: PKCS1
    size: 2048
  usages:
    - server auth
    - client auth
  issuerRef:
    name: local-ca-issuer
    kind: ClusterIssuer
EOF

echo "⏳ Waiting for application certificate to be issued..."
sleep 3
$KUBECTL wait --for=condition=ready certificate/severus-ai-tls -n default --timeout=120s

print_status "Application certificates created!" "success"

# =====================================================
# STEP 4: Validate Certificates
# =====================================================
echo ""
echo "========================================"
echo "STEP 4: Validating Certificates"
echo "========================================"

VALIDATION_FAILED=0

# Check 1: Verify cert-manager pods
echo ""
echo "📋 Check 1: cert-manager Pod Status"
echo "-----------------------------------"
PODS_READY=$($KUBECTL get pods -n cert-manager -o jsonpath='{.items[*].status.phase}' | tr ' ' '\n' | grep -c "Running" || echo "0")
PODS_TOTAL=$($KUBECTL get pods -n cert-manager --no-headers | wc -l | tr -d ' ')

if [ "$PODS_READY" == "$PODS_TOTAL" ] && [ "$PODS_TOTAL" -gt 0 ]; then
    print_status "All cert-manager pods running ($PODS_READY/$PODS_TOTAL)" "success"
else
    print_status "Some pods not ready ($PODS_READY/$PODS_TOTAL)" "error"
    VALIDATION_FAILED=1
fi

# Check 2: Verify ClusterIssuers are ready
echo ""
echo "📋 Check 2: ClusterIssuer Status"
echo "---------------------------------"
for issuer in selfsigned-bootstrap-issuer local-ca-issuer; do
    ISSUER_READY=$($KUBECTL get clusterissuer $issuer -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    if [ "$ISSUER_READY" == "True" ]; then
        print_status "ClusterIssuer '$issuer' is Ready" "success"
    else
        print_status "ClusterIssuer '$issuer' is NOT Ready" "error"
        VALIDATION_FAILED=1
    fi
done

# Check 3: Verify Certificates are ready
echo ""
echo "📋 Check 3: Certificate Status"
echo "-------------------------------"
echo ""
echo "| Certificate | Namespace | Status | Expiry |"
echo "|------------|-----------|--------|--------|"

for ns in cert-manager default; do
    CERTS=$($KUBECTL get certificates -n $ns -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    for cert in $CERTS; do
        READY=$($KUBECTL get certificate $cert -n $ns -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
        EXPIRY=$($KUBECTL get certificate $cert -n $ns -o jsonpath='{.status.notAfter}' 2>/dev/null | cut -d'T' -f1)
        
        if [ "$READY" == "True" ]; then
            STATUS="✅ Ready"
        else
            STATUS="❌ Not Ready"
            VALIDATION_FAILED=1
        fi
        echo "| $cert | $ns | $STATUS | $EXPIRY |"
    done
done

# Check 4: Decode and verify certificate content
echo ""
echo "📋 Check 4: Certificate Content Verification"
echo "---------------------------------------------"

SECRET_EXISTS=$($KUBECTL get secret severus-ai-tls-secret -n default -o name 2>/dev/null || echo "")
if [ -n "$SECRET_EXISTS" ]; then
    # Get certificate details
    CERT_DATA=$($KUBECTL get secret severus-ai-tls-secret -n default -o jsonpath='{.data.tls\.crt}' | base64 -d)
    
    # Check if openssl is available
    if command -v openssl &> /dev/null; then
        SUBJECT=$(echo "$CERT_DATA" | openssl x509 -noout -subject 2>/dev/null | sed 's/subject=//')
        ISSUER=$(echo "$CERT_DATA" | openssl x509 -noout -issuer 2>/dev/null | sed 's/issuer=//')
        DATES=$(echo "$CERT_DATA" | openssl x509 -noout -dates 2>/dev/null)
        NOT_AFTER=$(echo "$DATES" | grep "notAfter" | sed 's/notAfter=//')
        
        echo "  Subject: $SUBJECT"
        echo "  Issuer:  $ISSUER"
        echo "  Expires: $NOT_AFTER"
        
        # Check if certificate is valid (not expired)
        openssl x509 -checkend 0 -noout <<< "$CERT_DATA" 2>/dev/null
        if [ $? -eq 0 ]; then
            print_status "Certificate is valid and not expired" "success"
        else
            print_status "Certificate is EXPIRED!" "error"
            VALIDATION_FAILED=1
        fi
    else
        print_status "OpenSSL not available - skipping content verification" "warning"
    fi
else
    print_status "Certificate secret 'severus-ai-tls-secret' not found!" "error"
    VALIDATION_FAILED=1
fi

# =====================================================
# Final Summary
# =====================================================
echo ""
echo "========================================"
echo "SUMMARY"
echo "========================================"

if [ $VALIDATION_FAILED -eq 0 ]; then
    print_status "All validations passed! Certificate infrastructure is healthy." "success"
    echo ""
    echo "🎉 cert-manager setup complete with:"
    echo "   - cert-manager v1.14.4 installed"
    echo "   - Self-signed bootstrap issuer created"
    echo "   - Internal Root CA created (10-year validity)"
    echo "   - Local CA Issuer configured"
    echo "   - Application TLS certificate issued"
    echo "   - All certificates validated successfully"
    exit 0
else
    print_status "Some validations failed! Please review the errors above." "error"
    exit 1
fi
