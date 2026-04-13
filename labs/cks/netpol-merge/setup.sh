#!/usr/bin/env bash
set -euo pipefail

# CKS Lab: NetworkPolicy Merge Behavior
# Deploys pods with overlapping labels to practice how multiple
# NetworkPolicies combine on the same target.

NAMESPACE="netpol-merge"

echo "=== CKS Lab: NetworkPolicy Merge Behavior ==="

echo "[1/2] Creating namespace and pods..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<'MANIFEST'
# Pod with multiple labels (selected by multiple policies)
apiVersion: v1
kind: Pod
metadata:
  name: web
  namespace: netpol-merge
  labels:
    app: web
    tier: frontend
    version: v1
spec:
  containers:
    - name: nginx
      image: nginx:alpine
---
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: netpol-merge
spec:
  selector:
    app: web
  ports:
    - port: 80
---
# Client pods in different roles
apiVersion: v1
kind: Pod
metadata:
  name: client-internal
  namespace: netpol-merge
  labels:
    app: client
    team: internal
spec:
  containers:
    - name: tools
      image: nginx:alpine
      command: ["sleep", "infinity"]
---
apiVersion: v1
kind: Pod
metadata:
  name: client-external
  namespace: netpol-merge
  labels:
    app: client
    team: external
spec:
  containers:
    - name: tools
      image: nginx:alpine
      command: ["sleep", "infinity"]
---
apiVersion: v1
kind: Pod
metadata:
  name: monitoring
  namespace: netpol-merge
  labels:
    app: monitoring
    team: ops
spec:
  containers:
    - name: tools
      image: nginx:alpine
      command: ["sleep", "infinity"]
MANIFEST

echo "[2/2] Waiting for pods to be ready..."
kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod --all --timeout=120s

echo ""
echo "=== Setup Complete ==="
echo ""
kubectl -n "${NAMESPACE}" get pods --show-labels
echo ""
echo "All pods can currently reach each other (no policies yet)."
echo ""
echo "Your task:"
echo "  Understand how multiple NetworkPolicies MERGE (they are additive/union)."
echo ""
echo "  1. Create a default deny ingress policy for all pods in ${NAMESPACE}"
echo ""
echo "  2. Create Policy A: allow ingress to 'web' from pods with label team=internal on port 80"
echo ""
echo "  3. Create Policy B: allow ingress to 'web' from pods with label app=monitoring on port 80"
echo ""
echo "  4. Predict and verify:"
echo "     - client-internal -> web:80    (allowed by Policy A)"
echo "     - monitoring -> web:80         (allowed by Policy B)"
echo "     - client-external -> web:80    (denied by both)"
echo ""
echo "  5. Key insight: Policies targeting the same pod are UNIONED."
echo "     client-internal is allowed by A, monitoring is allowed by B."
echo "     Neither policy alone allows client-external."
echo ""
echo "  Verify commands:"
echo "    kubectl -n ${NAMESPACE} exec client-internal -- wget -qO- --timeout=3 http://web"
echo "    kubectl -n ${NAMESPACE} exec monitoring -- wget -qO- --timeout=3 http://web"
echo "    kubectl -n ${NAMESPACE} exec client-external -- wget -qO- --timeout=3 http://web"
