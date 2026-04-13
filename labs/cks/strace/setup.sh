#!/usr/bin/env bash
set -euo pipefail

# CKS Lab: strace Syscall Analysis
# Deploys workloads and provides tools for syscall tracing.

NAMESPACE="strace-lab"

echo "=== CKS Lab: strace Syscall Analysis ==="

echo "[1/3] Ensuring strace is installed..."
if ! command -v strace &>/dev/null; then
  apt-get update && apt-get install -y strace
fi
echo "strace version: $(strace --version 2>&1 | head -1)"

echo "[2/3] Creating namespace and workloads..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: Pod
metadata:
  name: web-server
  namespace: strace-lab
  labels:
    app: web-server
spec:
  containers:
    - name: nginx
      image: nginx:alpine
      ports:
        - containerPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: crypto-miner-sim
  namespace: strace-lab
  labels:
    app: suspicious
spec:
  containers:
    - name: miner
      image: nginx:alpine
      command: ["/bin/sh", "-c"]
      args:
        - |
          while true; do
            dd if=/dev/urandom bs=1024 count=100 of=/dev/null 2>/dev/null
            sleep 5
          done
MANIFEST

echo "[3/3] Waiting for pods..."
kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod --all --timeout=120s

echo ""
echo "=== Setup Complete ==="
echo ""
kubectl -n "${NAMESPACE}" get pods -o wide
echo ""
echo "Your task:"
echo "  Use strace and crictl to analyze syscall behavior of containers."
echo ""
echo "  1. Find the container PID on the host:"
echo "     CONTAINER_ID=\$(crictl ps --name nginx -q | head -1)"
echo "     PID=\$(crictl inspect \$CONTAINER_ID | jq .info.pid)"
echo ""
echo "  2. Trace syscalls of the web-server container:"
echo "     strace -f -p \$PID -c -t 2>&1 | head -50"
echo "     (-c for summary, -f to follow forks, -t for timestamps)"
echo ""
echo "  3. Trace specific syscall categories:"
echo "     strace -f -p \$PID -e trace=network 2>&1 | head -20"
echo "     strace -f -p \$PID -e trace=file 2>&1 | head -20"
echo "     strace -f -p \$PID -e trace=process 2>&1 | head -20"
echo ""
echo "  4. Compare the crypto-miner-sim pod's syscalls with web-server:"
echo "     - Which pod makes more read() calls to /dev/urandom?"
echo "     - Which syscalls are unique to the suspicious pod?"
echo ""
echo "  5. Based on your analysis, which syscalls could you block with"
echo "     a seccomp profile to stop the suspicious behavior?"
