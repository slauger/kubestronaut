#!/usr/bin/env bash
set -euo pipefail

# CKS Lab: gVisor / RuntimeClass
# Installs gVisor (runsc) and configures containerd to use it.

PLATFORM=$(uname -m)
case "${PLATFORM}" in
  aarch64) PLATFORM="arm64" ;;
  x86_64)  PLATFORM="amd64" ;;
  *) echo "Unsupported platform: ${PLATFORM}"; exit 1 ;;
esac

echo "=== CKS Lab: gVisor / RuntimeClass ==="

echo "[1/4] Installing gVisor (runsc)..."
if command -v runsc &>/dev/null; then
  echo "gVisor already installed: $(runsc --version 2>&1 | head -1)"
else
  curl -fsSL https://gvisor.dev/archive.key | gpg --dearmor -o /usr/share/keyrings/gvisor-archive-keyring.gpg
  echo "deb [arch=${PLATFORM} signed-by=/usr/share/keyrings/gvisor-archive-keyring.gpg] https://storage.googleapis.com/gvisor/releases release main" \
    > /etc/apt/sources.list.d/gvisor.list
  apt-get update
  apt-get install -y runsc
  echo "Installed: $(runsc --version 2>&1 | head -1)"
fi

echo "[2/4] Configuring containerd for gVisor..."
# Check if runsc handler already exists
if grep -q 'runtime_type.*runsc' /etc/containerd/config.toml 2>/dev/null; then
  echo "containerd already configured for runsc."
else
  # Add runsc runtime to containerd config
  cat >> /etc/containerd/config.toml <<'EOF'

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]
  runtime_type = "io.containerd.runsc.v1"
EOF
  echo "Restarting containerd..."
  systemctl restart containerd
fi

echo "[3/4] Creating RuntimeClass..."
kubectl apply -f - <<'MANIFEST'
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
MANIFEST

echo "[4/4] Deploying reference pod with default runtime..."
kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: Pod
metadata:
  name: default-runtime
  labels:
    app: runtime-test
    runtime: default
spec:
  containers:
    - name: nginx
      image: nginx:alpine
MANIFEST

kubectl wait --for=condition=Ready pod/default-runtime --timeout=60s

echo ""
echo "=== Setup Complete ==="
echo ""
echo "gVisor (runsc) installed and configured."
echo "RuntimeClass 'gvisor' created."
echo ""
echo "Reference pod: default-runtime (uses default runc)"
echo "  kubectl exec default-runtime -- dmesg | head -5"
echo "  (shows Linux kernel messages)"
echo ""
echo "Your task:"
echo "  1. Create a pod 'sandboxed-nginx' that uses runtimeClassName: gvisor"
echo "  2. Compare kernel messages:"
echo "     kubectl exec sandboxed-nginx -- dmesg | head -5"
echo "     (should show 'Starting gVisor' instead of Linux kernel)"
echo ""
echo "  3. Compare system calls available:"
echo "     kubectl exec default-runtime -- uname -r"
echo "     kubectl exec sandboxed-nginx -- uname -r"
echo "     (gVisor reports its own kernel version)"
echo ""
echo "  4. Try running a workload that gVisor restricts:"
echo "     kubectl exec sandboxed-nginx -- mount -t tmpfs tmpfs /tmp"
echo "     (may fail depending on gVisor configuration)"
