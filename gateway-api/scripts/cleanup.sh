#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DELETE_MINIKUBE="${DELETE_MINIKUBE:-false}"
MINIKUBE_BIN="$(command -v minikube || true)"

if [[ -z "${MINIKUBE_BIN}" ]]; then
  echo "Missing minikube in PATH. Install it or make sure it is reachable before running cleanup." >&2
  exit 1
fi

kubectl() {
  "${MINIKUBE_BIN}" kubectl -- "$@"
}

echo "Removing advanced Gateway API resources..."
kubectl delete -f "${ROOT_DIR}/manifests/advanced/policies.yaml" --ignore-not-found=true
kubectl delete -f "${ROOT_DIR}/manifests/advanced/httproutes.yaml" --ignore-not-found=true
kubectl delete -f "${ROOT_DIR}/manifests/advanced/slow-backend.yaml" --ignore-not-found=true

echo "Removing basic Gateway API resources..."
kubectl delete -f "${ROOT_DIR}/manifests/httproute.yaml" --ignore-not-found=true
kubectl delete -f "${ROOT_DIR}/manifests/gateway.yaml" --ignore-not-found=true
kubectl delete -f "${ROOT_DIR}/manifests/services.yaml" --ignore-not-found=true
kubectl delete -f "${ROOT_DIR}/manifests/deployments.yaml" --ignore-not-found=true
kubectl delete -f "${ROOT_DIR}/manifests/configmaps.yaml" --ignore-not-found=true
kubectl delete -f "${ROOT_DIR}/manifests/namespace.yaml" --ignore-not-found=true

echo "Removing TLS Gateway API example..."
kubectl delete -f "${ROOT_DIR}/manifests/tls/httproute.yaml" --ignore-not-found=true
kubectl delete -f "${ROOT_DIR}/manifests/tls/gateway.yaml" --ignore-not-found=true
kubectl delete secret demo-tls -n gateway-demo --ignore-not-found=true

echo "Removing Envoy Gateway quickstart and controller..."
kubectl delete gateway eg -n default --ignore-not-found=true
kubectl delete httproute backend -n default --ignore-not-found=true
kubectl delete service backend -n default --ignore-not-found=true
kubectl delete deployment backend -n default --ignore-not-found=true
kubectl delete serviceaccount backend -n default --ignore-not-found=true
kubectl delete gatewayclass eg --ignore-not-found=true
kubectl delete ns envoy-gateway-system --ignore-not-found=true

if command -v helm >/dev/null 2>&1; then
  helm uninstall eg -n envoy-gateway-system >/dev/null 2>&1 || true
fi

if [[ "${DELETE_MINIKUBE}" == "true" ]]; then
  echo "Deleting the Minikube cluster..."
  "${MINIKUBE_BIN}" delete
fi

echo "Cleanup complete."
