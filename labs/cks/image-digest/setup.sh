#!/usr/bin/env bash
set -euo pipefail

# CKS Lab: Image Digest Enforcement
# Deploys pods using mutable tags and provides tools to switch to immutable digests.

NAMESPACE="digest-lab"

echo "=== CKS Lab: Image Digest Enforcement ==="

echo "[1/2] Creating namespace and workloads with mutable tags..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-latest
  namespace: digest-lab
  labels:
    app: web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: nginx
          image: nginx:latest
          ports:
            - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-tagged
  namespace: digest-lab
  labels:
    app: api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
        - name: httpd
          image: httpd:2.4
          ports:
            - containerPort: 80
MANIFEST

echo "[2/2] Waiting for deployments..."
kubectl -n "${NAMESPACE}" rollout status deployment/web-latest --timeout=120s
kubectl -n "${NAMESPACE}" rollout status deployment/api-tagged --timeout=120s

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Deployments using mutable image tags:"
kubectl -n "${NAMESPACE}" get pods -o custom-columns='NAME:.metadata.name,IMAGE:.spec.containers[*].image'
echo ""
echo "The problem: tags like 'latest' and '2.4' are MUTABLE."
echo "Someone could push a different image to the same tag."
echo ""
echo "Your task:"
echo "  1. Find the immutable digest (sha256) for each image:"
echo "     crictl inspecti nginx:latest | grep -i digest"
echo "     # or: kubectl -n ${NAMESPACE} get pod <pod> -o jsonpath='{.status.containerStatuses[0].imageID}'"
echo ""
echo "  2. Update both Deployments to use image digests instead of tags:"
echo "     e.g., nginx@sha256:abc123... instead of nginx:latest"
echo ""
echo "  3. Verify pods are running with pinned digests:"
echo "     kubectl -n ${NAMESPACE} get pods -o jsonpath='{range .items[*]}{.spec.containers[*].image}{\"\\n\"}{end}'"
echo ""
echo "  4. (Bonus) Create an OPA Gatekeeper ConstraintTemplate that denies"
echo "     pods using ':latest' tag or images without a '@sha256:' digest"
