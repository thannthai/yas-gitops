#!/bin/bash
# ============================================================================
# Script cài đặt Istio + Kiali trên k3d cluster
# Chạy trên VM GCP, cần chuyển kubeconfig sang k3d trước
# ============================================================================

set -e

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  BƯỚC 0: Chuẩn bị kubeconfig cho k3d cluster                       ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"

# Lấy kubeconfig k3d
export KUBECONFIG=/tmp/k3d-config
sudo k3d kubeconfig get k8s-cluster > $KUBECONFIG 2>/dev/null
echo "✅ Đã chuyển kubeconfig sang k3d cluster"
kubectl get ns | head -5
echo ""

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  BƯỚC 1: Tải và cài đặt Istio                                      ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"

# Tải istioctl nếu chưa có
if ! command -v istioctl &> /dev/null; then
  echo "→ Đang tải istioctl..."
  curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.22.0 sh -
  export PATH=$PWD/istio-1.22.0/bin:$PATH
  echo "✅ Đã tải istioctl"
else
  echo "✅ istioctl đã có sẵn"
fi

# Cài Istio với profile demo (nhẹ, có sẵn addons)
echo "→ Đang cài Istio lên k3d cluster..."
istioctl install --set profile=demo -y
echo "✅ Đã cài Istio"
echo ""

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  BƯỚC 2: Cài đặt Kiali + Prometheus (để vẽ topology)               ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"

ISTIO_VERSION="1.22.0"
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.22/samples/addons/prometheus.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.22/samples/addons/kiali.yaml
echo "✅ Đã cài Kiali + Prometheus"
echo ""

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  BƯỚC 3: Label namespace dev + staging để inject sidecar            ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"

kubectl label namespace dev istio-injection=enabled --overwrite
kubectl label namespace staging istio-injection=enabled --overwrite
echo "✅ Đã bật istio-injection cho dev và staging"
echo ""

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  BƯỚC 4: Restart pods để inject Istio sidecar                       ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"

echo "→ Restart tất cả deployment trong namespace dev..."
kubectl rollout restart deployment -n dev
echo "→ Restart tất cả deployment trong namespace staging..."
kubectl rollout restart deployment -n staging
echo "✅ Đã restart, chờ pods khởi động lại..."
echo ""

echo "→ Đợi pods sẵn sàng (tối đa 5 phút)..."
kubectl wait --for=condition=ready pod --all -n dev --timeout=300s 2>/dev/null || echo "⚠ Một số pod chưa sẵn sàng"
echo ""

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  BƯỚC 5: Verify                                                     ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"

echo "→ Kiểm tra Istio system pods..."
kubectl get pods -n istio-system
echo ""

echo "→ Kiểm tra pods dev có 2/2 (có sidecar)..."
kubectl get pods -n dev
echo ""

echo "======================================================================"
echo "  CÀI ĐẶT ISTIO HOÀN TẤT!"
echo "  Tiếp theo: chạy ./01-apply-service-mesh.sh để cấu hình mTLS, retry, authz"
echo "======================================================================"
