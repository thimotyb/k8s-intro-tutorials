#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${ROOT_DIR}/.bin"
TMP_DIR="${ROOT_DIR}/.tmp"
MINIKUBE_BIN="${BIN_DIR}/minikube"
KUBERNETES_VERSION="${KUBERNETES_VERSION:-v1.35.1}"
MINIKUBE_DRIVER="${MINIKUBE_DRIVER:-}"

mkdir -p "${BIN_DIR}" "${TMP_DIR}"

if [[ -z "${MINIKUBE_DRIVER}" ]]; then
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    MINIKUBE_DRIVER="docker"
  else
    echo "No supported Minikube driver found. Install Docker or set MINIKUBE_DRIVER explicitly." >&2
    exit 1
  fi
fi

if [[ ! -x "${MINIKUBE_BIN}" ]]; then
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"

  case "${arch}" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *)
      echo "Unsupported architecture for automatic minikube download: ${arch}" >&2
      exit 1
      ;;
  esac

  case "${os}" in
    linux)
      minikube_url="https://storage.googleapis.com/minikube/releases/latest/minikube-linux-${arch}"
      ;;
    darwin)
      minikube_url="https://storage.googleapis.com/minikube/releases/latest/minikube-darwin-${arch}"
      ;;
    *)
      echo "Unsupported operating system for automatic minikube download: ${os}" >&2
      exit 1
      ;;
  esac

  curl -fsSL "${minikube_url}" -o "${MINIKUBE_BIN}"
  chmod +x "${MINIKUBE_BIN}"
fi

"${MINIKUBE_BIN}" start --driver="${MINIKUBE_DRIVER}" --kubernetes-version="${KUBERNETES_VERSION}"
"${MINIKUBE_BIN}" kubectl -- config use-context minikube >/dev/null
