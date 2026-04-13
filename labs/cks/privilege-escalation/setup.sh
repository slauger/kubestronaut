#!/usr/bin/env bash
set -euo pipefail

# CKS Lab: Privilege Escalation Prevention
# Deploys pods with various insecure configurations that the student
# must identify and harden.

NAMESPACE="privesc-lab"

echo "=== CKS Lab: Privilege Escalation Prevention ==="

echo "[1/2] Creating namespace and insecure workloads..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<'MANIFEST'
# Pod 1: Runs as root with privilege escalation allowed
apiVersion: v1
kind: Pod
metadata:
  name: insecure-app
  namespace: privesc-lab
  labels:
    app: insecure-app
    status: vulnerable
spec:
  containers:
    - name: app
      image: nginx:alpine
      securityContext:
        runAsUser: 0
        allowPrivilegeEscalation: true
---
# Pod 2: Privileged container (full host access)
apiVersion: v1
kind: Pod
metadata:
  name: privileged-app
  namespace: privesc-lab
  labels:
    app: privileged-app
    status: vulnerable
spec:
  containers:
    - name: app
      image: nginx:alpine
      securityContext:
        privileged: true
---
# Pod 3: Host PID and network namespace
apiVersion: v1
kind: Pod
metadata:
  name: hostns-app
  namespace: privesc-lab
  labels:
    app: hostns-app
    status: vulnerable
spec:
  hostPID: true
  hostNetwork: true
  containers:
    - name: app
      image: nginx:alpine
---
# Pod 4: Already hardened (reference)
apiVersion: v1
kind: Pod
metadata:
  name: secure-app
  namespace: privesc-lab
  labels:
    app: secure-app
    status: hardened
spec:
  containers:
    - name: app
      image: nginx:alpine
      securityContext:
        runAsNonRoot: true
        runAsUser: 101
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
      volumeMounts:
        - name: cache
          mountPath: /var/cache/nginx
        - name: run
          mountPath: /var/run
        - name: tmp
          mountPath: /tmp
  volumes:
    - name: cache
      emptyDir: {}
    - name: run
      emptyDir: {}
    - name: tmp
      emptyDir: {}
MANIFEST

echo "[2/2] Waiting for pods..."
kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod --all --timeout=120s

echo ""
echo "=== Setup Complete ==="
echo ""
kubectl -n "${NAMESPACE}" get pods -o wide
echo ""
echo "Insecure pods deployed with various privilege escalation vectors:"
echo "  - insecure-app:   runs as root, allowPrivilegeEscalation=true"
echo "  - privileged-app: privileged=true (full host access)"
echo "  - hostns-app:     hostPID=true, hostNetwork=true"
echo "  - secure-app:     already hardened (use as reference)"
echo ""
echo "Demonstrate the risks:"
echo "  kubectl -n ${NAMESPACE} exec insecure-app -- id"
echo "  kubectl -n ${NAMESPACE} exec privileged-app -- mount | head"
echo "  kubectl -n ${NAMESPACE} exec hostns-app -- ps aux | head"
echo ""
echo "Your task:"
echo "  1. Identify all security issues in each pod"
echo "  2. Create hardened replacements for each insecure pod:"
echo "     - runAsNonRoot: true"
echo "     - allowPrivilegeEscalation: false"
echo "     - capabilities.drop: [ALL]"
echo "     - No privileged, no hostPID, no hostNetwork"
echo "     - readOnlyRootFilesystem: true (with emptyDir for writable paths)"
echo "  3. Verify the hardened pods cannot escalate privileges:"
echo "     kubectl -n ${NAMESPACE} exec <pod> -- id      (should NOT be uid=0)"
echo "     kubectl -n ${NAMESPACE} exec <pod> -- ps aux  (should NOT see host processes)"
echo "  4. Compare with secure-app as reference"
