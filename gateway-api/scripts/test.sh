#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MINIKUBE_BIN="${ROOT_DIR}/.bin/minikube"
PORT="${PORT:-8888}"
HOST="${HOST:-demo.local}"
SERVICE_NAMESPACE="${SERVICE_NAMESPACE:-envoy-gateway-system}"
GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-gateway-demo}"
GATEWAY_NAME="${GATEWAY_NAME:-demo-gateway}"
ROUTE_NAME="${ROUTE_NAME:-demo-route}"

cleanup() {
  if [[ -n "${PF_PID:-}" ]] && kill -0 "${PF_PID}" >/dev/null 2>&1; then
    kill "${PF_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "$1 is required but was not found in PATH" >&2
    exit 1
  }
}

need curl

if [[ ! -x "${MINIKUBE_BIN}" ]]; then
  echo "Missing minikube binary at ${MINIKUBE_BIN}. Run scripts/start-minikube.sh first." >&2
  exit 1
fi

kubectl() {
  "${MINIKUBE_BIN}" kubectl -- "$@"
}

if ! kubectl get namespace "${GATEWAY_NAMESPACE}" >/dev/null 2>&1; then
  echo "Missing namespace ${GATEWAY_NAMESPACE}. Run scripts/bootstrap-gateway-api.sh first." >&2
  exit 1
fi

echo "Checking Gateway API resources..."
kubectl get gatewayclass eg >/dev/null
kubectl get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" >/dev/null
kubectl get httproute "${ROUTE_NAME}" -n "${GATEWAY_NAMESPACE}" >/dev/null
kubectl rollout status deployment/blue -n "${GATEWAY_NAMESPACE}" --timeout=5m >/dev/null
kubectl rollout status deployment/green -n "${GATEWAY_NAMESPACE}" --timeout=5m >/dev/null

service_name="$(
  kubectl get svc -n "${SERVICE_NAMESPACE}" \
    --selector=gateway.envoyproxy.io/owning-gateway-namespace="${GATEWAY_NAMESPACE}",gateway.envoyproxy.io/owning-gateway-name="${GATEWAY_NAME}" \
    -o jsonpath='{.items[0].metadata.name}'
)"

if [[ -z "${service_name}" ]]; then
  echo "Could not find the Envoy service for gateway ${GATEWAY_NAME}" >&2
  exit 1
fi

kubectl -n "${SERVICE_NAMESPACE}" port-forward "service/${service_name}" "${PORT}:80" >/dev/null 2>&1 &
PF_PID=$!

for _ in $(seq 1 30); do
  if curl -sS "http://127.0.0.1:${PORT}/" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -sS "http://127.0.0.1:${PORT}/" >/dev/null 2>&1; then
  echo "Port-forward on ${PORT} did not become ready in time" >&2
  exit 1
fi

fetch() {
  curl -fsS -H "Host: ${HOST}" "http://127.0.0.1:${PORT}$1"
}

blue_body="$(fetch /)"
green_body="$(fetch /green)"

if ! grep -q "blue backend" <<<"${blue_body}"; then
  echo "Expected / to route to blue backend" >&2
  exit 1
fi

if ! grep -q "green backend" <<<"${green_body}"; then
  echo "Expected /green to route to green backend" >&2
  exit 1
fi

blue_hits=0
green_hits=0

for _ in $(seq 1 20); do
  body="$(fetch /split)"
  if grep -q "blue backend" <<<"${body}"; then
    blue_hits=$((blue_hits + 1))
  fi
  if grep -q "green backend" <<<"${body}"; then
    green_hits=$((green_hits + 1))
  fi
done

if [[ "${blue_hits}" -eq 0 || "${green_hits}" -eq 0 ]]; then
  echo "Expected both backends to appear in split traffic, got blue=${blue_hits}, green=${green_hits}" >&2
  exit 1
fi

echo "Gateway API checks passed."
echo "Blue hits: ${blue_hits}"
echo "Green hits: ${green_hits}"
