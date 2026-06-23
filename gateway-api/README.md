# Working with Kubernetes Gateway API

The purpose of this exercise is to demonstrate the modern Kubernetes replacement for classic Ingress routing:
Gateway API.

Gateway API is an official Kubernetes project for L4/L7 routing. It is not built into core Kubernetes as a default
feature, so you install the CRDs plus a Gateway controller. In this tutorial we use Envoy Gateway because it has a
simple local quickstart and supports the Gateway API resources used here.

## Compatibility Note

Gateway API resources such as `Gateway`, `GatewayClass`, and `HTTPRoute` are stable, but the project itself only
supports the most recent 5 Kubernetes minor versions. The old tutorial baseline in the root README,
`minikube start --kubernetes-version v1.12.1`, is far too old for this exercise.

Use a recent Minikube/Kubernetes release before you begin. The helper script in this folder defaults to Kubernetes
`v1.35.1`, which was supported by the Minikube release used during verification here.

## Index

* [The Manifests](#the-manifests)
* [Implementing Gateway API](#implementing-gateway-api)
* [TLS and HTTPS](#tls-and-https)
* [Advanced Traffic Controls](#advanced-traffic-controls)
* [Official Sources](#official-sources)
* [Cleaning Up](#cleaning-up)

---

## The Manifests

The exercise uses the following resources:

* `manifests/namespace.yaml` - Namespace for the demo app
* `manifests/configmaps.yaml` - Different content for the blue and green backends
* `manifests/deployments.yaml` - Two nginx deployments that serve different content
* `manifests/services.yaml` - ClusterIP Services for the deployments
* `manifests/gateway.yaml` - A Gateway that listens on HTTP port 80
* `manifests/httproute.yaml` - Host/path routing, URL rewrite, and a weighted split route
* `manifests/tls/gateway.yaml` - An HTTPS Gateway listener that terminates a self-signed certificate
* `manifests/tls/httproute.yaml` - A route that serves the blue backend over HTTPS

---

## Implementing Gateway API

This walkthrough assumes you already have `kubectl`, `minikube`, and `helm` available.

If you need to install them first, these commands work on Linux with `amd64` or `arm64`:

```bash
MINIKUBE_VERSION=v1.35.1
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
esac
curl -LO "https://storage.googleapis.com/minikube/releases/${MINIKUBE_VERSION}/minikube-linux-${ARCH}"
sudo install minikube-linux-${ARCH} /usr/local/bin/minikube
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

If you want a one-command local bootstrap, use the helper script in this folder:

```bash
bash scripts/start-minikube.sh
bash scripts/bootstrap-gateway-api.sh
```

**Step 1:** Start Minikube with a recent Kubernetes version.

```bash
minikube start --kubernetes-version v1.35.1
```

**Step 2:** Install the Gateway API CRDs and Envoy Gateway controller.

```bash
helm install eg oci://docker.io/envoyproxy/gateway-helm --version v1.8.1 -n envoy-gateway-system --create-namespace
kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available
```

**Step 3:** Bootstrap the example `GatewayClass` and the upstream quickstart resources once.

This gives the cluster the `eg` GatewayClass used by the manifests in this folder.

```bash
kubectl apply -f https://github.com/envoyproxy/gateway/releases/download/v1.8.1/quickstart.yaml -n default
kubectl get gatewayclass
```

**Step 4:** Create the demo namespace and workloads from this exercise.

```bash
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/configmaps.yaml
kubectl apply -f manifests/deployments.yaml
kubectl apply -f manifests/services.yaml
```

Wait for the Deployments to become ready.

```bash
kubectl rollout status deployment/blue -n gateway-demo
kubectl rollout status deployment/green -n gateway-demo
```

**Step 5:** Apply the Gateway and HTTPRoute resources.

```bash
kubectl apply -f manifests/gateway.yaml
kubectl apply -f manifests/httproute.yaml
```

Check that the Gateway has an address and that the HTTPRoute is accepted.

```bash
kubectl get gateway -n gateway-demo
kubectl get httproute -n gateway-demo
kubectl describe gateway demo-gateway -n gateway-demo
```

**Step 6:** Port-forward the Envoy service created for the Gateway.

```bash
export ENVOY_SERVICE=$(kubectl get svc -n envoy-gateway-system --selector=gateway.envoyproxy.io/owning-gateway-namespace=gateway-demo,gateway.envoyproxy.io/owning-gateway-name=demo-gateway -o jsonpath='{.items[0].metadata.name}')
kubectl -n envoy-gateway-system port-forward service/${ENVOY_SERVICE} 8888:80
```

Leave this terminal open while you test the routes in another shell.

**Step 7:** Test the main Gateway API routing features.

The `Host` header selects the Gateway hostname. The path selects the backend or the split rule.

```bash
curl -H "Host: demo.local" http://localhost:8888/
curl -H "Host: demo.local" http://localhost:8888/green
curl -H "Host: demo.local" http://localhost:8888/split
```

To see the weighted split in action, run the same request multiple times.

```bash
for i in $(seq 1 10); do curl -s -H "Host: demo.local" http://localhost:8888/split; echo; done
```

You should see responses from both the blue and green backends over time.

**Step 8:** Inspect the resources that make the routing happen.

```bash
kubectl get gateway -n gateway-demo -o wide
kubectl get httproute -n gateway-demo -o wide
kubectl get pods -n gateway-demo -o wide
kubectl get svc -n gateway-demo -o wide
```

## TLS and HTTPS

This optional example adds an HTTPS listener to the Gateway and attaches a self-signed certificate from a Kubernetes
Secret. The route stays simple so you can focus on the TLS wiring rather than the backend behavior.

**Step 1:** Generate a self-signed certificate that matches the HTTPS hostname.

```bash
mkdir -p /tmp/gateway-api-tls
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout /tmp/gateway-api-tls/tls.key \
  -out /tmp/gateway-api-tls/tls.crt \
  -subj "/CN=tls.demo.local" \
  -addext "subjectAltName=DNS:tls.demo.local"
```

**Step 2:** Create the TLS Secret in the same namespace as the Gateway.

```bash
kubectl create secret tls demo-tls -n gateway-demo \
  --cert=/tmp/gateway-api-tls/tls.crt \
  --key=/tmp/gateway-api-tls/tls.key
```

**Step 3:** Apply the HTTPS Gateway and route.

```bash
kubectl apply -f manifests/tls/gateway.yaml
kubectl apply -f manifests/tls/httproute.yaml
```

Check that the Gateway accepted the listener.

```bash
kubectl describe gateway tls-gateway -n gateway-demo
kubectl get httproute tls-route -n gateway-demo
```

**Step 4:** Open a second port-forward to the HTTPS listener.

```bash
export ENVOY_SERVICE=$(kubectl get svc -n envoy-gateway-system --selector=gateway.envoyproxy.io/owning-gateway-namespace=gateway-demo,gateway.envoyproxy.io/owning-gateway-name=tls-gateway -o jsonpath='{.items[0].metadata.name}')
kubectl -n envoy-gateway-system port-forward service/${ENVOY_SERVICE} 8443:443
```

**Step 5:** Call the endpoint over HTTPS and trust the self-signed certificate explicitly.

```bash
curl --cacert /tmp/gateway-api-tls/tls.crt \
  --resolve tls.demo.local:8443:127.0.0.1 \
  https://tls.demo.local:8443/
```

You should see the blue backend response over HTTPS.

## Advanced Traffic Controls

The basic exercise already demonstrates traffic shaping with weighted routing in `manifests/httproute.yaml`.
This optional extension adds three more Gateway capabilities:

* Local rate limiting
* Circuit breaking
* A dedicated traffic-shaping route for a second weighted split demo

Apply the extra resources:

```bash
kubectl apply -f manifests/advanced/slow-backend.yaml
kubectl apply -f manifests/advanced/httproutes.yaml
kubectl apply -f manifests/advanced/policies.yaml
kubectl rollout status deployment/slow-backend -n gateway-demo
```

Keep the existing port-forward from Step 6 open, then try the advanced routes.

**Rate limiting**

The `/limited` route allows the first three requests and then returns `429 Too Many Requests`.

```bash
for i in 1 2 3 4; do curl -i -H "Host: demo.local" http://localhost:8888/limited; echo; done
```

**Circuit breaking**

The `/slow` route points to a backend that sleeps before responding. The circuit breaker is configured to fail fast
when that backend is under concurrent load.

```bash
for i in 1 2 3 4 5; do
  curl -s -o /dev/null -w "request %{num_connects}: %{http_code}\n" -H "Host: demo.local" http://localhost:8888/slow &
done
wait
```

You should see at least one `200` and some `503` responses.

**Traffic shaping**

The `/shape` route splits requests between `blue` and `green`. Run the request multiple times to see both backends.

```bash
for i in $(seq 1 20); do curl -s -H "Host: demo.local" http://localhost:8888/shape; echo; done
```

If you want a fully automated version of these checks, run:

```bash
bash scripts/test-advanced.sh
```

## Official Sources

The exercise is based on these official references:

### Basic Exercise

* [Gateway API home](https://gateway-api.sigs.k8s.io/)
* [Gateway API versioning and support policy](https://gateway-api.sigs.k8s.io/docs/concepts/versioning/)
* [Envoy Gateway quickstart](https://gateway.envoyproxy.io/docs/tasks/quickstart/)
* [Envoy Gateway traffic tasks overview](https://gateway.envoyproxy.io/docs/tasks/traffic/)
* [Gateway API TLS configuration](https://gateway-api.sigs.k8s.io/guides/tls/)

### Advanced Exercise

* [Envoy Gateway local rate limit](https://gateway.envoyproxy.io/docs/tasks/traffic/local-rate-limit/)
* [Envoy Gateway rate limiting concept](https://gateway.envoyproxy.io/v1.5/concepts/rate-limiting/)
* [Envoy Gateway circuit breakers](https://gateway.envoyproxy.io/latest/tasks/traffic/circuit-breaker/)
* [Envoy Gateway BackendTrafficPolicy](https://gateway.envoyproxy.io/v1.3/concepts/introduction/gateway_api_extensions/backend-traffic-policy/)

## Automated Tests

The following script launches the verification checks used for this exercise:

```bash
bash scripts/test.sh
```

It checks that the GatewayClass exists, the Gateway is created, and the routing returns the expected blue and green
responses, including a weighted split sample.

### TLS Example Cleanup

To remove the HTTPS example only, run:

```bash
kubectl delete -f manifests/tls/httproute.yaml
kubectl delete -f manifests/tls/gateway.yaml
kubectl delete secret demo-tls -n gateway-demo --ignore-not-found=true
```

## Cleanup Script

To remove everything created by this lab, run:

```bash
bash scripts/cleanup.sh
```

If you also want to delete the Minikube cluster itself:

```bash
DELETE_MINIKUBE=true bash scripts/cleanup.sh
```

---

## Cleaning Up

Remove the demo app and the upstream quickstart resources.

```bash
kubectl delete -f manifests/httproute.yaml
kubectl delete -f manifests/gateway.yaml
kubectl delete -f manifests/services.yaml
kubectl delete -f manifests/deployments.yaml
kubectl delete -f manifests/configmaps.yaml
kubectl delete -f manifests/namespace.yaml
kubectl delete -f https://github.com/envoyproxy/gateway/releases/download/v1.8.1/quickstart.yaml --ignore-not-found=true
helm uninstall eg -n envoy-gateway-system
```
