#!/usr/bin/env bash
set -euo pipefail

# CKS Lab: Falco Log Analysis
# Deploys workloads that trigger Falco rules, then the student must
# analyze the Falco output to answer specific questions.

NAMESPACE="falco-analysis"

echo "=== CKS Lab: Falco Log Analysis ==="

echo "[1/5] Verifying Falco is running..."
if ! systemctl is-active --quiet falco; then
  echo "Starting Falco..."
  systemctl start falco
fi
echo "Falco status: $(systemctl is-active falco)"

echo "[2/5] Creating namespace..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "[3/5] Deploying workloads..."
kubectl apply -f - <<'MANIFEST'
# Pod 1: web application that will exhibit suspicious behavior
apiVersion: v1
kind: Pod
metadata:
  name: webapp
  namespace: falco-analysis
  labels:
    app: webapp
spec:
  containers:
    - name: web
      image: nginx:alpine
      ports:
        - containerPort: 80
---
# Pod 2: data processor that accesses /dev/shm
apiVersion: v1
kind: Pod
metadata:
  name: data-processor
  namespace: falco-analysis
  labels:
    app: data-processor
spec:
  containers:
    - name: processor
      image: nginx:alpine
      command: ["/bin/sh", "-c"]
      args:
        - |
          sleep infinity
---
# Pod 3: a "compromised" pod that does many suspicious things
apiVersion: v1
kind: Pod
metadata:
  name: compromised
  namespace: falco-analysis
  labels:
    app: compromised
spec:
  containers:
    - name: attacker
      image: nginx:alpine
      command: ["/bin/sh", "-c"]
      args:
        - |
          sleep infinity
MANIFEST

echo "[4/5] Waiting for pods..."
kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod --all --timeout=120s

echo "[5/5] Triggering suspicious activities..."
echo ""
echo "Generating Falco alerts (this takes a few seconds)..."

# Trigger 1: Write to /dev/shm (shared memory - often used by crypto miners)
kubectl -n "${NAMESPACE}" exec data-processor -- sh -c 'echo "malicious_payload" > /dev/shm/hidden_data' 2>/dev/null || true

# Trigger 2: Read sensitive files
kubectl -n "${NAMESPACE}" exec compromised -- sh -c 'cat /etc/shadow' 2>/dev/null || true

# Trigger 3: Spawn a shell and run suspicious commands
kubectl -n "${NAMESPACE}" exec compromised -- sh -c 'whoami && id && cat /proc/1/environ' 2>/dev/null || true

# Trigger 4: Write to /bin (binary directory modification)
kubectl -n "${NAMESPACE}" exec compromised -- sh -c 'cp /bin/ls /bin/backdoor' 2>/dev/null || true

# Trigger 5: Read the Kubernetes ServiceAccount token
kubectl -n "${NAMESPACE}" exec compromised -- sh -c 'cat /var/run/secrets/kubernetes.io/serviceaccount/token' 2>/dev/null || true

# Trigger 6: Network tool usage (simulated recon)
kubectl -n "${NAMESPACE}" exec webapp -- sh -c 'wget -qO- --timeout=2 http://10.96.0.1:443 2>/dev/null' || true

# Give Falco a moment to process
sleep 3

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Multiple suspicious activities have been triggered across 3 pods"
echo "in namespace '${NAMESPACE}'."
echo ""
echo "Falco should have generated alerts. Check them with:"
echo "  journalctl -u falco --since '5 minutes ago' --no-pager"
echo ""
echo "Your task — answer these questions by analyzing the Falco logs:"
echo ""
echo "  Q1: Which pod wrote to /dev/shm? What was the filename?"
echo ""
echo "  Q2: Which container read /etc/shadow?"
echo ""
echo "  Q3: Which pod attempted to modify files in /bin/?"
echo "      What was the exact command?"
echo ""
echo "  Q4: Which pod read the Kubernetes ServiceAccount token?"
echo ""
echo "  Q5: List ALL distinct Falco rules that were triggered."
echo "      Hint: look for the rule name in the alert output"
echo ""
echo "Useful commands:"
echo "  journalctl -u falco --since '5 minutes ago' --no-pager"
echo "  journalctl -u falco --since '5 minutes ago' | grep 'Warning\|Error\|Critical'"
echo "  journalctl -u falco --since '5 minutes ago' | grep 'shm'"
echo "  journalctl -u falco --since '5 minutes ago' | grep 'shadow'"
