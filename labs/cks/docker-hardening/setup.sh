#!/usr/bin/env bash
set -euo pipefail

# CKS Lab: Docker Daemon Hardening
# Installs Docker in an intentionally insecure configuration:
# - TCP socket exposed on 0.0.0.0:2375 (unauthenticated remote access)
# - Socket group set to "docker" (any docker-group user = root)
# The student must identify and fix both issues.

echo "=== CKS Lab: Docker Daemon Hardening ==="

echo "[1/4] Installing Docker..."
if command -v docker &>/dev/null; then
  echo "Docker already installed: $(docker --version)"
else
  apt-get update
  apt-get install -y docker.io
fi

echo "[2/4] Creating insecure Docker configuration..."

# Expose Docker daemon on TCP without TLS (intentionally insecure!)
mkdir -p /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/override.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H fd:// -H tcp://0.0.0.0:2375 --containerd=/run/containerd/containerd.sock
EOF

# Set socket group to "docker" (intentionally too permissive)
mkdir -p /etc/systemd/system/docker.socket.d
cat > /etc/systemd/system/docker.socket.d/override.conf <<'EOF'
[Socket]
SocketGroup=docker
SocketMode=0660
EOF

echo "[3/4] Ensuring docker group exists and restarting..."
groupadd -f docker
systemctl daemon-reload
systemctl restart docker.socket docker

echo "[4/4] Verifying insecure state..."
echo ""

echo "--- TCP Socket ---"
if ss -tlnp | grep -q ':2375'; then
  echo "INSECURE: Docker daemon is listening on TCP port 2375!"
  ss -tlnp | grep ':2375'
else
  echo "TCP socket check failed (may need a moment to start)"
fi
echo ""

echo "--- Unix Socket Permissions ---"
ls -la /var/run/docker.sock
echo ""

echo "--- Docker Info ---"
docker info 2>/dev/null | grep -E 'Server Version|Storage Driver|Docker Root Dir' || true

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Two security issues have been introduced:"
echo ""
echo "  1. CRITICAL: Docker daemon listens on TCP 0.0.0.0:2375 (no TLS!)"
echo "     Anyone on the network can control your containers:"
echo "     curl http://localhost:2375/version"
echo ""
echo "  2. HIGH: Socket owned by root:docker (group 'docker' = root access)"
echo "     ls -la /var/run/docker.sock"
echo "     Any user in the 'docker' group can mount the host filesystem:"
echo "     docker run -v /:/host alpine chroot /host"
echo ""
echo "Your task:"
echo "  1. Disable the TCP socket:"
echo "     - Find and remove the -H tcp://... flag"
echo "     - Hint: check systemd overrides in /etc/systemd/system/docker.service.d/"
echo ""
echo "  2. Fix the socket permissions:"
echo "     - Change the socket group from 'docker' to 'root'"
echo "     - Hint: check systemd overrides in /etc/systemd/system/docker.socket.d/"
echo "     - The relevant directives are SocketGroup and SocketMode"
echo ""
echo "  3. Reload and restart:"
echo "     systemctl daemon-reload"
echo "     systemctl restart docker.socket docker"
echo ""
echo "  4. Verify your fixes:"
echo "     ss -tlnp | grep 2375           (should show nothing)"
echo "     ls -la /var/run/docker.sock     (should show root:root)"
echo "     curl http://localhost:2375/version  (should fail: connection refused)"
