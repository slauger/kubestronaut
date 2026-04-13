#!/bin/bash
#
# CKS Lab Setup Script
#
# Single-node Kubernetes cluster with Cilium CNI and CKS-relevant tools.
# Designed for Ubuntu 24.04 on Hetzner Cloud. Can be used as cloud-init template.
#
# Usage:
#   sudo bash cks-lab-setup.sh [--public-ip <IP>] [--node-name <NAME>] [--san <SAN>]
#
# Defaults are configured for cks01.lnxlabs.de (178.104.160.240).

set -euo pipefail

###############################################################################
# Configuration
###############################################################################

KUBE_VERSION="${KUBE_VERSION:-1.35.0}"
CILIUM_CLI_VERSION="${CILIUM_CLI_VERSION:-v0.18.3}"
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"
PUBLIC_IP="${PUBLIC_IP:-178.104.160.240}"
NODE_NAME="${NODE_NAME:-cks01}"
CERT_SANS="${CERT_SANS:-cks01.lnxlabs.de}"
KUBESEC_VERSION="${KUBESEC_VERSION:-2.14.0}"
BOM_VERSION="${BOM_VERSION:-0.7.1}"

###############################################################################
# Parse CLI arguments (override defaults)
###############################################################################

while [[ $# -gt 0 ]]; do
  case $1 in
    --public-ip)   PUBLIC_IP="$2";  shift 2 ;;
    --node-name)   NODE_NAME="$2";  shift 2 ;;
    --san)         CERT_SANS="$2";  shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

###############################################################################
# Helper
###############################################################################

info() { echo -e "\n\033[1;34m>>> $*\033[0m"; }

###############################################################################
# 1. OS validation
###############################################################################

info "Validating OS"
source /etc/lsb-release
if [[ "${DISTRIB_RELEASE}" != "24.04" ]]; then
  echo "WARNING: This script targets Ubuntu 24.04. Detected: ${DISTRIB_DESCRIPTION}"
  echo "Press Ctrl+C to abort or any key to continue."
  read -r
fi

PLATFORM=$(uname -m)
case "${PLATFORM}" in
  aarch64) PLATFORM="arm64" ;;
  x86_64)  PLATFORM="amd64" ;;
  *) echo "Unsupported platform: ${PLATFORM}"; exit 1 ;;
esac

###############################################################################
# 2. Hostname
###############################################################################

info "Setting hostname to ${NODE_NAME}"
hostnamectl set-hostname "${NODE_NAME}"

###############################################################################
# 3. Terminal setup
###############################################################################

info "Configuring terminal environment"
cat > ~/.vimrc <<'EOF'
colorscheme ron
set tabstop=2
set shiftwidth=2
set expandtab
EOF

grep -q 'source <(kubectl completion bash)' ~/.bashrc 2>/dev/null || {
  cat >> ~/.bashrc <<'EOF'
force_color_prompt=yes
source <(kubectl completion bash)
alias k=kubectl
alias c=clear
complete -F __start_kubectl k
EOF
}

mkdir -p /etc/crictl.yaml.d
cat > /etc/crictl.yaml <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
EOF

###############################################################################
# 4. Swap
###############################################################################

info "Disabling swap"
swapoff -a
sed -i '/\sswap\s/ s/^\(.*\)$/#\1/g' /etc/fstab

###############################################################################
# 5. Kernel modules + sysctl
###############################################################################

info "Loading kernel modules and sysctl settings"
cat > /etc/modules-load.d/containerd.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat > /etc/sysctl.d/99-kubernetes-cri.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl --system

###############################################################################
# 6. Kubernetes apt repos (v1.35 + v1.34 for upgrade exercises)
###############################################################################

info "Adding Kubernetes apt repositories"
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg

mkdir -p /etc/apt/keyrings
rm -f /etc/apt/keyrings/kubernetes-1-35-apt-keyring.gpg
rm -f /etc/apt/keyrings/kubernetes-1-34-apt-keyring.gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-1-35-apt-keyring.gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-1-34-apt-keyring.gpg

cat > /etc/apt/sources.list.d/kubernetes.list <<EOF
deb [signed-by=/etc/apt/keyrings/kubernetes-1-35-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /
deb [signed-by=/etc/apt/keyrings/kubernetes-1-34-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /
EOF

###############################################################################
# 7. Install containerd + Kubernetes packages
###############################################################################

info "Installing containerd, kubelet, kubeadm, kubectl"
apt-get update
apt-get install -y containerd kubelet="${KUBE_VERSION}-1.1" kubeadm="${KUBE_VERSION}-1.1" kubectl="${KUBE_VERSION}-1.1" kubernetes-cni
apt-mark hold kubelet kubeadm kubectl

###############################################################################
# 8. Configure containerd
###############################################################################

info "Configuring containerd"
mkdir -p /etc/containerd

# Registry mirror configuration
mkdir -p /etc/containerd/certs.d/docker.io
cat > /etc/containerd/certs.d/docker.io/hosts.toml <<'EOF'
server = "https://docker.io"

[host."https://mirror.gcr.io"]
  capabilities = ["pull", "resolve"]

[host."https://registry-1.docker.io"]
  capabilities = ["pull", "resolve"]
EOF

# Generate default config and enable SystemdCgroup
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
# Set registry config path for mirrors
sed -i 's|config_path = ""|config_path = "/etc/containerd/certs.d"|' /etc/containerd/config.toml

systemctl daemon-reload
systemctl enable containerd
systemctl restart containerd

###############################################################################
# 9. Install Docker + podman
###############################################################################

info "Installing Docker"
apt-get install -y docker.io

info "Installing podman"
apt-get install -y podman

mkdir -p /etc/containers
cat > /etc/containers/registries.conf <<'EOF'
unqualified-search-registries = ["docker.io"]

[[registry]]
prefix = "docker.io"
location = "docker.io"

[[registry.mirror]]
prefix = "docker.io"
location = "mirror.gcr.io"

[[registry.mirror]]
prefix = "docker.io"
location = "registry-1.docker.io"
EOF

###############################################################################
# 10. Start kubelet
###############################################################################

info "Enabling kubelet"
systemctl enable kubelet
systemctl start kubelet || true  # will crashloop until kubeadm init, that's OK

###############################################################################
# 11. kubeadm init
###############################################################################

info "Running kubeadm init (Kubernetes ${KUBE_VERSION})"
kubeadm init \
  --kubernetes-version="${KUBE_VERSION}" \
  --pod-network-cidr="${POD_CIDR}" \
  --apiserver-advertise-address="${PUBLIC_IP}" \
  --apiserver-cert-extra-sans="${CERT_SANS}" \
  --node-name="${NODE_NAME}" \
  --ignore-preflight-errors=NumCPU \
  --skip-token-print

###############################################################################
# 12. kubeconfig
###############################################################################

info "Setting up kubeconfig"
mkdir -p /root/.kube
cp -f /etc/kubernetes/admin.conf /root/.kube/config
chmod 600 /root/.kube/config

export KUBECONFIG=/root/.kube/config

###############################################################################
# 13. Untaint control plane (single-node)
###############################################################################

info "Removing control-plane taint for single-node operation"
kubectl taint nodes "${NODE_NAME}" node-role.kubernetes.io/control-plane:NoSchedule- || true

###############################################################################
# 14. Install Cilium CLI + CNI
###############################################################################

info "Installing Cilium CLI ${CILIUM_CLI_VERSION}"
curl -fsSL "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${PLATFORM}.tar.gz" \
  | tar xz -C /usr/local/bin cilium
chmod +x /usr/local/bin cilium || true

info "Installing Cilium CNI"
cilium install --set ipam.operator.clusterPoolIPv4PodCIDRList="${POD_CIDR}"

echo "Waiting for Cilium to be ready..."
cilium status --wait --wait-duration 300s

# Wait for node to be Ready
echo "Waiting for node to be Ready..."
kubectl wait --for=condition=Ready node/"${NODE_NAME}" --timeout=300s

###############################################################################
# 15. CKS Tools
###############################################################################

# --- AppArmor (keep installed, CKS-relevant!) ---
info "Ensuring AppArmor utils are installed"
apt-get install -y apparmor-utils

# --- etcd-client ---
info "Installing etcd-client"
apt-get install -y etcd-client

# --- jq, vim, bash-completion, binutils ---
info "Installing utilities"
apt-get install -y jq vim bash-completion binutils

# --- Falco (modern-bpf) ---
info "Installing Falco"
curl -fsSL https://falco.org/repo/falcosecurity-packages.asc | gpg --dearmor -o /etc/apt/keyrings/falco-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/falco-archive-keyring.gpg] https://download.falco.org/packages/deb stable main" \
  > /etc/apt/sources.list.d/falcosecurity.list
apt-get update
FALCO_FRONTEND=noninteractive DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends falco
# Configure Falco to use modern_ebpf driver
mkdir -p /etc/falco
if [[ -f /etc/falco/falco.yaml ]]; then
  sed -i 's/^driver:$/driver:/' /etc/falco/falco.yaml
fi

# --- Trivy ---
info "Installing Trivy"
curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor -o /etc/apt/keyrings/trivy-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/trivy-archive-keyring.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
  > /etc/apt/sources.list.d/trivy.list
apt-get update
apt-get install -y trivy

# --- kubesec ---
info "Installing kubesec ${KUBESEC_VERSION}"
curl -fsSL "https://github.com/controlplaneio/kubesec/releases/download/v${KUBESEC_VERSION}/kubesec_linux_${PLATFORM}.tar.gz" \
  | tar xz -C /usr/local/bin kubesec
chmod +x /usr/local/bin/kubesec

# --- bom (SBOM generator) ---
info "Installing bom ${BOM_VERSION}"
curl -fsSL "https://github.com/kubernetes-sigs/bom/releases/download/v${BOM_VERSION}/bom-${PLATFORM}-linux" \
  -o /usr/local/bin/bom
chmod +x /usr/local/bin/bom

###############################################################################
# 16. Verification
###############################################################################

info "Verifying installation"
echo ""
echo "--- Node status ---"
kubectl get nodes -o wide
echo ""
echo "--- All pods ---"
kubectl get pods -A
echo ""
echo "--- CKS tool versions ---"
echo -n "falco:   "; falco --version 2>/dev/null | head -1 || echo "not found"
echo -n "trivy:   "; trivy --version 2>/dev/null | head -1 || echo "not found"
echo -n "kubesec: "; kubesec version 2>/dev/null || echo "not found"
echo -n "bom:     "; bom version 2>/dev/null | head -1 || echo "not found"
echo -n "cilium:  "; cilium version --client 2>/dev/null | head -1 || echo "not found"
echo ""

info "CKS lab setup complete!"
echo "  Node:       ${NODE_NAME}"
echo "  Public IP:  ${PUBLIC_IP}"
echo "  K8s:        ${KUBE_VERSION}"
echo "  CNI:        Cilium (CLI ${CILIUM_CLI_VERSION})"
echo "  Pod CIDR:   ${POD_CIDR}"
echo ""
echo "Useful commands:"
echo "  kubectl get nodes"
echo "  kubectl get pods -A"
echo "  cilium status"
echo "  cilium connectivity test"
echo "  crictl ps"
echo "  falco --modern-bpf"
