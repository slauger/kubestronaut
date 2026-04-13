# Hands-On Labs

Practical, exam-realistic labs that run on a real Kubernetes cluster. Each lab includes a setup script that deploys the required resources, followed by tasks you solve yourself — just like in the actual exams.

## Lab Cluster Setup

All labs are designed for a single-node kubeadm cluster with Cilium CNI. Use the setup script to provision a fresh cluster on Ubuntu 24.04 (e.g. Hetzner Cloud CX22):

```bash
curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/scripts/cks-lab-setup.sh | sudo bash
```

This installs:

- **Kubernetes** (kubeadm, kubelet, kubectl)
- **Cilium** CNI (required for CiliumNetworkPolicy labs)
- **containerd** + **Docker** + **podman**
- **Security tools**: Falco, Trivy, kubesec, bom, AppArmor
- **Utilities**: etcdctl, jq, vim, crictl, strace

After setup, run any lab with:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/<lab-name>/setup.sh)
```

## Available Lab Environments

| Certification | Labs | Description |
|---|---|---|
| [CKS](cks.md) | 18 | Cluster security, runtime detection, supply chain, hardening |
