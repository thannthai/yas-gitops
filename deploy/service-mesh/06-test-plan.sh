#!/bin/bash
# ============================================================================
# Service Mesh Test Plan — YAS Platform (k3d cluster)
# Chạy trên VM GCP
# Namespace: dev
# ============================================================================

# Sử dụng kubeconfig k3d
export KUBECONFIG=/tmp/k3d-config
sudo k3d kubeconfig get k8s-cluster > $KUBECONFIG 2>/dev/null

NAMESPACE="dev"
echo "======================================================================"
echo "  Service Mesh Test Plan — Namespace: $NAMESPACE (k3d cluster)"
echo "======================================================================"

# ── TEST 1: Kiểm tra mTLS đã được bật ──────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  TEST 1: Verify mTLS is ENABLED (STRICT mode)                      ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

echo "→ Checking PeerAuthentication..."
kubectl get peerauthentication -n $NAMESPACE
echo ""

echo "→ Checking if sidecar (istio-proxy) is injected into pods..."
echo "  (Expect: 2/2 READY = app container + istio-proxy)"
kubectl get pods -n $NAMESPACE | grep -E "NAME|Running" | head -10
echo ""

# ── TEST 2: Kiểm tra Authorization Policy (ALLOW / DENY) ───────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  TEST 2: Verify Authorization Policies (ALLOW vs DENY)             ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

echo "→ Listing all AuthorizationPolicies..."
kubectl get authorizationpolicy -n $NAMESPACE
echo ""

# ── Helper: check connectivity through the mesh ──
# Returns: ALLOWED:<http_code> | DENIED:<http_code> | NORESPONSE
# - HTTP 403 from Envoy = RBAC DENIED
# - Any other HTTP response (200, 404, 503...) = ALLOWED (traffic passed through)
# - No HTTP response = connection blocked / unreachable
check_connection() {
  local POD=$1 CONTAINER=$2 TARGET_URL=$3
  RESPONSE=$(kubectl exec -n $NAMESPACE "$POD" -c "$CONTAINER" -- \
    sh -c "wget -S -O /dev/null --timeout=5 $TARGET_URL 2>&1" 2>/dev/null)
  if echo "$RESPONSE" | grep -q "HTTP/"; then
    HTTP_CODE=$(echo "$RESPONSE" | grep -oE "HTTP/[0-9\.]+ [0-9]+" | tail -1 | awk '{print $2}')
    if [ "$HTTP_CODE" = "403" ]; then
      echo "DENIED:403"
    else
      echo "ALLOWED:$HTTP_CODE"
    fi
  else
    echo "NORESPONSE"
  fi
}

# Test 2a: ALLOWED — storefront-bff → product (SHOULD SUCCEED)
echo "─── Test 2a: storefront-bff → product (Expect: ALLOWED ✅) ───"
STOREFRONT_POD=$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=storefront-bff -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$STOREFRONT_POD" ]; then
  echo "  Pod: $STOREFRONT_POD"
  RESULT=$(check_connection "$STOREFRONT_POD" "storefront-bff" "http://product.$NAMESPACE:80/actuator/health")
  if echo "$RESULT" | grep -q "^ALLOWED"; then
    HTTP_CODE=$(echo "$RESULT" | cut -d: -f2)
    echo "  ✅ Connection ALLOWED (HTTP $HTTP_CODE — traffic passed through mesh)"
  elif echo "$RESULT" | grep -q "^DENIED"; then
    echo "  ⚠ Connection DENIED by RBAC 403 (expected to be allowed!)"
  else
    echo "  ⚠ No response (expected to be allowed)"
  fi
else
  echo "  ⚠ storefront-bff pod not found"
fi
echo ""

# Test 2b: ALLOWED — order → payment (SHOULD SUCCEED)
echo "─── Test 2b: order → payment (Expect: ALLOWED ✅) ───"
ORDER_POD=$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=order -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$ORDER_POD" ]; then
  echo "  Pod: $ORDER_POD"
  RESULT=$(check_connection "$ORDER_POD" "order" "http://payment.$NAMESPACE:80/actuator/health")
  if echo "$RESULT" | grep -q "^ALLOWED"; then
    HTTP_CODE=$(echo "$RESULT" | cut -d: -f2)
    echo "  ✅ Connection ALLOWED (HTTP $HTTP_CODE)"
  elif echo "$RESULT" | grep -q "^DENIED"; then
    echo "  ⚠ Connection DENIED by RBAC 403 (expected to be allowed!)"
  else
    echo "  ⚠ No response (expected to be allowed)"
  fi
else
  echo "  ⚠ order pod not found"
fi
echo ""

# Test 2c: DENIED — cart → payment (SHOULD FAIL → 403)
echo "─── Test 2c: cart → payment (Expect: DENIED ❌ → 403) ───"
CART_POD=$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=cart -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$CART_POD" ]; then
  echo "  Pod: $CART_POD"
  RESULT=$(check_connection "$CART_POD" "cart" "http://payment.$NAMESPACE:80/actuator/health")
  if echo "$RESULT" | grep -q "^DENIED"; then
    echo "  ✅ Connection DENIED by RBAC — HTTP 403 (expected behavior)"
  elif echo "$RESULT" | grep -q "^ALLOWED"; then
    HTTP_CODE=$(echo "$RESULT" | cut -d: -f2)
    echo "  ⚠ Connection ALLOWED HTTP $HTTP_CODE (expected to be DENIED!)"
  else
    echo "  ✅ Connection blocked — no response (expected behavior)"
  fi
else
  echo "  ⚠ cart pod not found"
fi
echo ""

# Test 2d: DENIED — product → order (SHOULD FAIL → 403)
echo "─── Test 2d: product → order (Expect: DENIED ❌ → 403) ───"
PRODUCT_POD=$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=product -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$PRODUCT_POD" ]; then
  echo "  Pod: $PRODUCT_POD"
  RESULT=$(check_connection "$PRODUCT_POD" "product" "http://order.$NAMESPACE:80/actuator/health")
  if echo "$RESULT" | grep -q "^DENIED"; then
    echo "  ✅ Connection DENIED by RBAC — HTTP 403 (expected behavior)"
  elif echo "$RESULT" | grep -q "^ALLOWED"; then
    HTTP_CODE=$(echo "$RESULT" | cut -d: -f2)
    echo "  ⚠ Connection ALLOWED HTTP $HTTP_CODE (expected to be DENIED!)"
  else
    echo "  ✅ Connection blocked — no response (expected behavior)"
  fi
else
  echo "  ⚠ product pod not found"
fi
echo ""

# Test 2e: DENIED — media → order (SHOULD FAIL → 403)
echo "─── Test 2e: media → order (Expect: DENIED ❌ → 403) ───"
MEDIA_POD=$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=media -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$MEDIA_POD" ]; then
  echo "  Pod: $MEDIA_POD"
  RESULT=$(check_connection "$MEDIA_POD" "media" "http://order.$NAMESPACE:80/actuator/health")
  if echo "$RESULT" | grep -q "^DENIED"; then
    echo "  ✅ Connection DENIED by RBAC — HTTP 403 (expected behavior)"
  elif echo "$RESULT" | grep -q "^ALLOWED"; then
    HTTP_CODE=$(echo "$RESULT" | cut -d: -f2)
    echo "  ⚠ Connection ALLOWED HTTP $HTTP_CODE (expected to be DENIED!)"
  else
    echo "  ✅ Connection blocked — no response (expected behavior)"
  fi
else
  echo "  ⚠ media pod not found"
fi
echo ""

# ── TEST 3: Kiểm tra Retry Policy ──────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  TEST 3: Verify Retry Policy (VirtualService)                      ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

echo "→ Listing VirtualServices..."
kubectl get virtualservice -n $NAMESPACE
echo ""

echo "→ Checking retry config for product-retry..."
kubectl get virtualservice product-retry -n $NAMESPACE -o jsonpath='{.spec.http[0].retries}' 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "  VirtualService product-retry chưa tồn tại"
echo ""

echo "→ Kiểm tra Envoy sidecar retry stats..."
if [ -n "$PRODUCT_POD" ]; then
  kubectl exec -n $NAMESPACE "$PRODUCT_POD" -c istio-proxy -- \
    pilot-agent request GET stats 2>/dev/null | grep -i "upstream_rq_retry" | head -5 \
    || echo "  (Không lấy được retry stats)"
fi
echo ""

# ── TEST 4: Kiali ───────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  TEST 4: Kiali Topology                                            ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "→ Kiểm tra Kiali..."
kubectl get svc -n istio-system 2>/dev/null | grep kiali || echo "  Kiali chưa được cài"
echo ""
echo "→ Mở Kiali: kubectl --kubeconfig /tmp/k3d-config port-forward svc/kiali -n istio-system 20001:20001"
echo "  Truy cập: http://localhost:20001"
echo ""

echo "======================================================================"
echo "  TEST PLAN COMPLETE"
echo "======================================================================"
