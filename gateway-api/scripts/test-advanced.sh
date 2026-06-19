#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MINIKUBE_BIN="${ROOT_DIR}/.bin/minikube"
PORT="${PORT:-8888}"
HOST="${HOST:-demo.local}"
SERVICE_NAMESPACE="${SERVICE_NAMESPACE:-envoy-gateway-system}"
GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-gateway-demo}"
GATEWAY_NAME="${GATEWAY_NAME:-demo-gateway}"

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

kubectl apply -f "${ROOT_DIR}/manifests/advanced/slow-backend.yaml"
kubectl apply -f "${ROOT_DIR}/manifests/advanced/httproutes.yaml"
kubectl apply -f "${ROOT_DIR}/manifests/advanced/policies.yaml"
kubectl rollout status deployment/slow-backend -n "${GATEWAY_NAMESPACE}" --timeout=5m >/dev/null

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

rate_limit_codes=()
for _ in 1 2 3 4; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' -H "Host: ${HOST}" "http://127.0.0.1:${PORT}/limited")"
  rate_limit_codes+=("${code}")
done

if [[ "${rate_limit_codes[0]}" != "200" || "${rate_limit_codes[1]}" != "200" || "${rate_limit_codes[2]}" != "200" || "${rate_limit_codes[3]}" != "429" ]]; then
  echo "Unexpected rate limit codes: ${rate_limit_codes[*]}" >&2
  exit 1
fi

slow_codes_file="$(mktemp)"
slow_pids=()
for _ in 1 2 3 4 5; do
  (
    curl -sS -o /dev/null -w '%{http_code}\n' -H "Host: ${HOST}" "http://127.0.0.1:${PORT}/slow" >> "${slow_codes_file}"
  ) &
  slow_pids+=("$!")
done
for pid in "${slow_pids[@]}"; do
  wait "${pid}"
done

if ! grep -q '^503$' "${slow_codes_file}"; then
  echo "Expected at least one circuit breaker 503 response" >&2
  rm -f "${slow_codes_file}"
  exit 1
fi
rm -f "${slow_codes_file}"

blue_hits=0
green_hits=0
for _ in $(seq 1 40); do
  body="$(curl -fsS -H "Host: ${HOST}" "http://127.0.0.1:${PORT}/shape")"
  if grep -q "blue backend" <<<"${body}"; then
    blue_hits=$((blue_hits + 1))
  fi
  if grep -q "green backend" <<<"${body}"; then
    green_hits=$((green_hits + 1))
  fi
done

if [[ "${blue_hits}" -eq 0 || "${green_hits}" -eq 0 ]]; then
  echo "Expected both backends in traffic shaping demo, got blue=${blue_hits}, green=${green_hits}" >&2
  exit 1
fi

echo "Advanced Gateway API checks passed."
echo "Rate limit codes: ${rate_limit_codes[*]}"
echo "Traffic shaping hits: blue=${blue_hits} green=${green_hits}"
