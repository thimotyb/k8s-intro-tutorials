#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MINIKUBE_BIN="${ROOT_DIR}/.bin/minikube"

if [[ ! -x "${MINIKUBE_BIN}" ]]; then
  echo "Missing minikube binary at ${MINIKUBE_BIN}. Run scripts/start-minikube.sh first." >&2
  exit 1
fi

kubectl() {
  "${MINIKUBE_BIN}" kubectl -- "$@"
}

kubectl apply --server-side --force-conflicts --field-manager=gateway-api-lab -f https://github.com/envoyproxy/gateway/releases/download/v1.8.1/install.yaml
kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available
kubectl apply --server-side --force-conflicts --field-manager=gateway-api-lab -f https://github.com/envoyproxy/gateway/releases/download/v1.8.1/quickstart.yaml -n default
kubectl get gatewayclass

kubectl apply -f "${ROOT_DIR}/manifests/namespace.yaml"
kubectl apply -f "${ROOT_DIR}/manifests/configmaps.yaml"
kubectl apply -f "${ROOT_DIR}/manifests/deployments.yaml"
kubectl apply -f "${ROOT_DIR}/manifests/services.yaml"
kubectl apply -f "${ROOT_DIR}/manifests/gateway.yaml"
kubectl apply -f "${ROOT_DIR}/manifests/httproute.yaml"
