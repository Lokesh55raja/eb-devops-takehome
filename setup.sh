#!/usr/bin/env bash
# One-command local setup:
#   kind cluster "demo" -> ingress-nginx -> build image -> kind load -> helm release "demo" in ns "demo"
# Safe to re-run: every step checks state or uses upgrade --install.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-demo}"
RELEASE="${RELEASE:-demo}"
NAMESPACE="${NAMESPACE:-demo}"
IMAGE_NAME="${IMAGE_NAME:-eb-demo-app}"
IMAGE_TAG="${IMAGE_TAG:-0.1.0}"
INGRESS_NGINX_CHART_VERSION="${INGRESS_NGINX_CHART_VERSION:-4.11.3}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

TMP_FILES=()
cleanup() { [ "${#TMP_FILES[@]}" -gt 0 ] && rm -f "${TMP_FILES[@]}"; return 0; }
trap cleanup EXIT

log() { printf '\n==> %s\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

for tool in docker kind kubectl helm curl; do
  command -v "$tool" >/dev/null 2>&1 || die "missing required tool: $tool"
done

# 1. Cluster
log "kind cluster '${CLUSTER_NAME}'"
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "cluster already exists, reusing it"
else
  kind_cfg="$(mktemp)"; TMP_FILES+=("$kind_cfg")
  cat > "$kind_cfg" <<'KINDCFG'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
KINDCFG
  kind create cluster --name "$CLUSTER_NAME" --config "$kind_cfg" --wait 120s
fi
kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null

# 2. ingress-nginx (kind flavour: hostPort on the ingress-ready control-plane node)
log "ingress-nginx chart ${INGRESS_NGINX_CHART_VERSION}"
ingress_values="$(mktemp)"; TMP_FILES+=("$ingress_values")
cat > "$ingress_values" <<'VALUES'
controller:
  hostPort:
    enabled: true
  service:
    type: NodePort
  publishService:
    enabled: false
  ingressClassResource:
    default: true
  nodeSelector:
    ingress-ready: "true"
  tolerations:
    - key: node-role.kubernetes.io/control-plane
      operator: Equal
      effect: NoSchedule
VALUES
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update >/dev/null
helm repo update ingress-nginx >/dev/null
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --version "$INGRESS_NGINX_CHART_VERSION" \
  --namespace ingress-nginx --create-namespace \
  --values "$ingress_values" \
  --wait --timeout 5m

# 3. Image
log "build ${IMAGE}"
docker build -t "$IMAGE" "$HERE/service"

log "load ${IMAGE} into kind"
kind load docker-image "$IMAGE" --name "$CLUSTER_NAME"

# 4. Chart
log "helm release '${RELEASE}' in namespace '${NAMESPACE}'"
helm upgrade --install "$RELEASE" "$HERE/chart" \
  --namespace "$NAMESPACE" --create-namespace \
  --set image.repository="$IMAGE_NAME" \
  --set image.tag="$IMAGE_TAG" \
  --wait --timeout 3m

# 5. Smoke check: warn, don't fail, so re-runs stay green while the Ingress warms up
log "smoke check"
for _ in $(seq 1 15); do
  if curl -fsS -H 'Host: demo.local' http://localhost/ 2>/dev/null; then
    echo
    echo "OK: service reachable via ingress (Host: demo.local)"
    exit 0
  fi
  sleep 2
done
echo "WARNING: service not reachable via ingress yet. Check: kubectl -n ${NAMESPACE} get ingress,pods" >&2
