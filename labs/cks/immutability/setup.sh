#!/usr/bin/env bash
set -euo pipefail

# CKS Lab: Container Immutability
# Deploys mutable workloads that the student must harden.

NAMESPACE="immutability-lab"

echo "=== CKS Lab: Container Immutability ==="

echo "[1/2] Creating namespace ${NAMESPACE}..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "[2/2] Deploying mutable workloads..."
kubectl apply -f - <<'MANIFEST'
# A web server with a fully writable filesystem (insecure)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mutable-web
  namespace: immutability-lab
  labels:
    app: mutable-web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mutable-web
  template:
    metadata:
      labels:
        app: mutable-web
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: mutable-web
  namespace: immutability-lab
spec:
  selector:
    app: mutable-web
  ports:
    - port: 80
      targetPort: 80
MANIFEST

kubectl -n "${NAMESPACE}" rollout status deployment/mutable-web --timeout=120s

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Mutable deployment in namespace '${NAMESPACE}':"
kubectl -n "${NAMESPACE}" get pods
echo ""
echo "Demonstrate the problem - an attacker can modify the filesystem:"
echo "  kubectl -n ${NAMESPACE} exec deploy/mutable-web -- sh -c 'echo HACKED > /usr/share/nginx/html/index.html'"
echo "  kubectl -n ${NAMESPACE} exec deploy/mutable-web -- wget -qO- http://localhost"
echo "  (shows 'HACKED')"
echo ""
echo "  kubectl -n ${NAMESPACE} exec deploy/mutable-web -- sh -c 'apt update && apt install -y nmap'"
echo "  (attacker can install tools!)"
echo ""
echo "Your task:"
echo "  1. Create a new Deployment 'immutable-web' in namespace ${NAMESPACE} that:"
echo "     - Uses readOnlyRootFilesystem: true"
echo "     - Uses emptyDir volumes for directories nginx needs to write to:"
echo "       /var/cache/nginx, /var/run, /tmp"
echo "     - Runs as non-root (runAsNonRoot: true, runAsUser: 101)"
echo ""
echo "  2. Verify the filesystem is read-only:"
echo "     kubectl -n ${NAMESPACE} exec deploy/immutable-web -- sh -c 'echo test > /usr/share/nginx/html/test.txt'"
echo "     (should FAIL with read-only filesystem error)"
echo ""
echo "  3. Verify nginx still works:"
echo "     kubectl -n ${NAMESPACE} exec deploy/immutable-web -- wget -qO- http://localhost"
echo "     (should show default nginx page)"
echo ""
echo "  4. Verify package installation is blocked:"
echo "     kubectl -n ${NAMESPACE} exec deploy/immutable-web -- sh -c 'apk add nmap'"
echo "     (should FAIL)"
