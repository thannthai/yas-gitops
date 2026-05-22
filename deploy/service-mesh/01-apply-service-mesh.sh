#!/bin/bash
# ============================================================================
# Apply tất cả Service Mesh config lên k3d cluster
# Chạy trên VM GCP SAU KHI đã cài Istio (00-install-istio.sh)
# ============================================================================

set -e

# Sử dụng kubeconfig k3d
export KUBECONFIG=/tmp/k3d-config
sudo k3d kubeconfig get k8s-cluster > $KUBECONFIG 2>/dev/null

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Apply Service Mesh Configuration                                   ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

echo "→ 1/4 Applying mTLS PeerAuthentication (STRICT)..."
kubectl apply -f "$SCRIPT_DIR/02-mtls-peer-auth.yaml"
echo "✅ mTLS enabled"
echo ""

echo "→ 2/4 Applying DestinationRules (client-side mTLS)..."
kubectl apply -f "$SCRIPT_DIR/03-destination-rules.yaml"
echo "✅ DestinationRules applied"
echo ""

echo "→ 3/4 Applying Retry Policies (VirtualService)..."
kubectl apply -f "$SCRIPT_DIR/04-retry-policy.yaml"
echo "✅ Retry policies applied"
echo ""

echo "→ 4/4 Applying Authorization Policies (deny-all + ALLOW rules)..."
kubectl apply -f "$SCRIPT_DIR/05-authz-policy.yaml"
echo "✅ Authorization policies applied"
echo ""

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Verification                                                       ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

echo "→ PeerAuthentication:"
kubectl get peerauthentication -n dev
echo ""

echo "→ DestinationRules:"
kubectl get destinationrule -n dev
echo ""

echo "→ VirtualServices:"
kubectl get virtualservice -n dev
echo ""

echo "→ AuthorizationPolicies:"
kubectl get authorizationpolicy -n dev
echo ""

echo "======================================================================"
echo "  SERVICE MESH CONFIG APPLIED!"
echo "  Tiếp theo: chạy bash 06-test-plan.sh để test"
echo "======================================================================"
