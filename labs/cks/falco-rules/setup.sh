#!/usr/bin/env bash
set -euo pipefail

# CKS Lab: Falco Custom Rules
# Deploys workloads that exhibit suspicious behavior for Falco detection.

NAMESPACE="falco-lab"

echo "=== CKS Lab: Falco Custom Rules ==="

echo "[1/3] Creating namespace ${NAMESPACE}..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "[2/3] Deploying suspicious workloads..."
kubectl apply -f - <<'MANIFEST'
# A pod that simulates a compromised web application
apiVersion: v1
kind: Pod
metadata:
  name: web-app
  namespace: falco-lab
  labels:
    app: web-app
    scenario: suspicious
spec:
  containers:
    - name: web
      image: nginx:alpine
      command: ["/bin/sh", "-c"]
      args:
        - |
          nginx
          # Keep the container running
          sleep infinity
---
# A pod that will be used to simulate lateral movement
apiVersion: v1
kind: Pod
metadata:
  name: attacker-sim
  namespace: falco-lab
  labels:
    app: attacker-sim
    scenario: suspicious
spec:
  containers:
    - name: tools
      image: nginx:alpine
      command: ["sleep", "infinity"]
MANIFEST

echo "[3/3] Waiting for pods to be ready..."
kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod --all --timeout=120s

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Pods deployed in namespace '${NAMESPACE}':"
kubectl -n "${NAMESPACE}" get pods
echo ""
echo "Verify Falco is running:"
echo "  systemctl status falco"
echo ""
echo "Your task:"
echo "  1. Create a custom Falco rule in /etc/falco/falco_rules.local.yaml that:"
echo "     - Detects when a shell (bash/sh) is spawned inside a container"
echo "     - Has priority WARNING"
echo "     - Outputs: container name, image, user, and command"
echo ""
echo "  2. Create a second rule that:"
echo "     - Detects when /etc/shadow is read inside a container"
echo "     - Has priority ERROR"
echo ""
echo "  3. Restart Falco and trigger the rules:"
echo "     kubectl -n ${NAMESPACE} exec web-app -- sh -c 'cat /etc/shadow'"
echo ""
echo "  4. Check Falco logs for the alerts:"
echo "     journalctl -u falco --since '5 minutes ago' | grep -E 'Warning|Error'"
