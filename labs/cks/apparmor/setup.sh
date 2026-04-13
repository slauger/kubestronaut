#!/usr/bin/env bash
set -euo pipefail

# CKS Lab: AppArmor
# Provides a pre-built AppArmor profile and deploys a test workload.

echo "=== CKS Lab: AppArmor ==="

echo "[1/3] Verifying AppArmor is available..."
if ! command -v apparmor_parser &>/dev/null; then
  echo "ERROR: apparmor_parser not found. Install with: apt install apparmor-utils"
  exit 1
fi
echo "AppArmor status: $(aa-enabled 2>/dev/null || echo 'unknown')"

echo "[2/3] Installing AppArmor profile..."
cat > /etc/apparmor.d/cks-lab-nginx <<'PROFILE'
#include <tunables/global>

profile cks-lab-nginx flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  #include <abstractions/nameservice>

  # Allow network access
  network,

  # Allow reading most files
  file,

  # Deny writes to sensitive directories
  deny /etc/** w,
  deny /usr/** w,
  deny /root/** rw,
  deny /home/** rw,

  # Deny execution of shells
  deny /bin/dash x,
  deny /bin/sh x,
  deny /bin/bash x,
  deny /usr/bin/bash x,

  # Deny raw network access
  deny network raw,
  deny network packet,
}
PROFILE

apparmor_parser -r /etc/apparmor.d/cks-lab-nginx
echo "Profile 'cks-lab-nginx' loaded."

echo "[3/3] Deploying test pod WITHOUT AppArmor..."
kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: Pod
metadata:
  name: nginx-no-apparmor
  labels:
    app: nginx
    security: none
spec:
  containers:
    - name: nginx
      image: nginx:alpine
MANIFEST

kubectl wait --for=condition=Ready pod/nginx-no-apparmor --timeout=60s

echo ""
echo "=== Setup Complete ==="
echo ""
echo "AppArmor profile loaded: cks-lab-nginx"
echo "  - Allows: network access, file reads"
echo "  - Denies: writes to /etc, /usr, /root, /home"
echo "  - Denies: shell execution (/bin/sh, /bin/bash, /bin/dash)"
echo "  - Denies: raw/packet network access"
echo ""
echo "Verify loaded profiles:"
echo "  aa-status | grep cks-lab"
echo ""
echo "Test pod deployed: nginx-no-apparmor (no restrictions)"
echo "  kubectl exec nginx-no-apparmor -- sh -c 'echo test > /etc/test.txt'"
echo "  (should SUCCEED - no AppArmor)"
echo ""
echo "Your task:"
echo "  1. Create a new pod 'nginx-apparmor' that uses the 'cks-lab-nginx' profile"
echo "     Hint: use spec.containers[].securityContext.appArmorProfile"
echo "  2. Verify writes to /etc/ are DENIED:"
echo "     kubectl exec nginx-apparmor -- sh -c 'echo test > /etc/test.txt'"
echo "  3. Verify shell execution is DENIED:"
echo "     kubectl exec nginx-apparmor -- bash"
echo "  4. Verify normal nginx operation still works:"
echo "     kubectl exec nginx-apparmor -- wget -qO- http://localhost"
