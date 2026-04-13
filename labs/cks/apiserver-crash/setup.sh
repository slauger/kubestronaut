#!/usr/bin/env bash
set -euo pipefail

# CKS Lab: API Server Crash & Recovery
# Intentionally introduces a misconfiguration into the API server
# that the student must diagnose and fix.

echo "=== CKS Lab: API Server Crash & Recovery ==="
echo ""
echo "WARNING: This lab will intentionally break your API server!"
echo "You will need to fix it by editing the static pod manifest."
echo ""
read -p "Press Enter to continue or Ctrl+C to abort..."

MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
BACKUP="/etc/kubernetes/kube-apiserver.yaml.backup"

echo "[1/2] Creating backup of API server manifest..."
sudo cp "${MANIFEST}" "${BACKUP}"
echo "Backup saved to ${BACKUP}"

echo "[2/2] Introducing misconfiguration..."

# Pick a random misconfiguration scenario
SCENARIO=$((RANDOM % 3))

case ${SCENARIO} in
  0)
    # Scenario: Invalid admission plugin name
    sudo sed -i 's/--enable-admission-plugins=\(.*\)/--enable-admission-plugins=\1,InvalidPluginName/' "${MANIFEST}"
    HINT="Check the --enable-admission-plugins flag for invalid plugin names"
    ;;
  1)
    # Scenario: Wrong etcd endpoint
    sudo sed -i 's|--etcd-servers=https://127.0.0.1:2379|--etcd-servers=https://127.0.0.1:9999|' "${MANIFEST}"
    HINT="Check the --etcd-servers flag for the correct endpoint"
    ;;
  2)
    # Scenario: Reference to non-existent certificate file
    sudo sed -i 's|--tls-cert-file=\(.*\)|--tls-cert-file=/etc/kubernetes/pki/DOES-NOT-EXIST.crt|' "${MANIFEST}"
    HINT="Check TLS certificate paths for missing files"
    ;;
esac

echo ""
echo "=== Misconfiguration Applied ==="
echo ""
echo "The API server will fail to start. kubectl commands will stop working."
echo ""
echo "Your task:"
echo "  1. Diagnose WHY the API server crashed"
echo "     Useful commands (kubectl won't work!):"
echo "     - crictl ps -a | grep apiserver"
echo "     - crictl logs <container-id>"
echo "     - journalctl -u kubelet --since '5 minutes ago'"
echo "     - cat ${MANIFEST}"
echo ""
echo "  2. Fix the issue by editing: sudo vi ${MANIFEST}"
echo ""
echo "  3. Wait for the API server to recover:"
echo "     - Watch with: crictl ps | grep apiserver"
echo "     - Then verify: kubectl get nodes"
echo ""
echo "  Hint: ${HINT}"
echo ""
echo "  If you get stuck, restore the backup:"
echo "     sudo cp ${BACKUP} ${MANIFEST}"
