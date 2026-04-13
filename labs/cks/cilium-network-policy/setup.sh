#!/usr/bin/env bash
set -euo pipefail

# CKS Lab: CiliumNetworkPolicy
# Deploys a multi-tier application in the microservices namespace
# for practicing network policy exercises

NAMESPACE="microservices"

echo "=== CKS Lab: CiliumNetworkPolicy Setup ==="

echo "[1/3] Creating namespace ${NAMESPACE}..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "[2/3] Deploying multi-tier application..."
kubectl apply -f - <<'MANIFEST'
# --- Frontend (nginx) ---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: microservices
  labels:
    app: frontend
    tier: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
        tier: frontend
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
  name: frontend
  namespace: microservices
spec:
  selector:
    app: frontend
  ports:
    - port: 80
      targetPort: 80
---
# --- Backend (httpd) ---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: microservices
  labels:
    app: backend
    tier: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
        tier: backend
    spec:
      containers:
        - name: httpd
          image: httpd:alpine
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: microservices
spec:
  selector:
    app: backend
  ports:
    - port: 80
      targetPort: 80
---
# --- Database (nginx as placeholder) ---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: database
  namespace: microservices
  labels:
    app: database
    tier: database
spec:
  replicas: 1
  selector:
    matchLabels:
      app: database
  template:
    metadata:
      labels:
        app: database
        tier: database
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
  name: database
  namespace: microservices
spec:
  selector:
    app: database
  ports:
    - port: 80
      targetPort: 80
MANIFEST

echo "[3/3] Deploying external test pod in default namespace..."
kubectl run external --image=nginx:alpine --labels="app=external" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Waiting for all pods to be ready..."
kubectl -n "${NAMESPACE}" rollout status deployment/frontend --timeout=120s
kubectl -n "${NAMESPACE}" rollout status deployment/backend --timeout=120s
kubectl -n "${NAMESPACE}" rollout status deployment/database --timeout=120s
kubectl wait --for=condition=Ready pod/external --timeout=120s

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Namespace: ${NAMESPACE}"
echo ""
echo "Pods:"
kubectl -n "${NAMESPACE}" get pods -o wide
echo ""
kubectl get pod external -o wide
echo ""
echo "Services:"
kubectl -n "${NAMESPACE}" get svc
echo ""
echo "Verify connectivity (before policies):"
echo "  kubectl -n ${NAMESPACE} exec deploy/frontend -- wget -qO- --timeout=3 http://backend"
echo "  kubectl -n ${NAMESPACE} exec deploy/frontend -- wget -qO- --timeout=3 http://database"
echo "  kubectl -n ${NAMESPACE} exec deploy/backend -- wget -qO- --timeout=3 http://database"
echo "  kubectl exec external -- wget -qO- --timeout=3 http://frontend.${NAMESPACE}"
echo ""
echo "Your task:"
echo "  1. Apply a default deny all ingress+egress CiliumNetworkPolicy in ${NAMESPACE}"
echo "  2. Allow frontend -> backend on port 80"
echo "  3. Allow backend -> database on port 80"
echo "  4. Allow DNS egress for all pods (kube-dns in kube-system)"
echo "  5. Verify: frontend can reach backend but NOT database"
echo "  6. Verify: external pod in default ns cannot reach any microservice"
