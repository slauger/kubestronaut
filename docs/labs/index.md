# Hands-On Labs

Practical, exam-realistic labs that run on a real Kubernetes cluster. Each lab includes a setup script that deploys the required resources, followed by tasks you solve yourself — just like in the actual CKS exam.

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
- **Utilities**: etcdctl, jq, vim, crictl

After setup, run any lab with:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/<lab-name>/setup.sh)
```

## CKS Labs

### Cluster Setup (15%)

| Lab | Setup Script | Description |
|---|---|---|
| [CiliumNetworkPolicy](../cks/cluster-setup.md#exercise-6) | `cilium-network-policy` | Restrict traffic in a multi-tier app with CiliumNetworkPolicy |
| [NetworkPolicy Merge](../cks/cluster-setup.md#exercise-7) | `netpol-merge` | Understand how multiple NetworkPolicies combine (union behavior) |

### Cluster Hardening (15%)

| Lab | Setup Script | Description |
|---|---|---|
| [ValidatingWebhook](../cks/cluster-hardening.md#exercise-5) | `validating-webhook` | Create a ValidatingWebhookConfiguration for pod security |
| [API Server Crash](../cks/cluster-hardening.md#exercise-6) | `apiserver-crash` | Diagnose and fix a broken API server (no kubectl available) |
| [CertificateSigningRequests](../cks/cluster-hardening.md#exercise-7) | `csr` | Inspect, approve/deny CSRs and configure user access |

### System Hardening (10%)

| Lab | Setup Script | Description |
|---|---|---|
| [AppArmor](../cks/system-hardening.md#exercise-6) | `apparmor` | Apply an AppArmor profile to restrict filesystem writes and shell execution |
| [Seccomp](../cks/system-hardening.md#exercise-7) | `seccomp` | Create and apply custom seccomp profiles to limit syscalls |
| [strace Analysis](../cks/system-hardening.md#exercise-8) | `strace` | Trace container syscalls with strace and crictl |
| [Docker Hardening](../cks/system-hardening.md#exercise-9) | `docker-hardening` | Disable Docker TCP socket and fix socket permissions |

### Minimize Microservice Vulnerabilities (20%)

| Lab | Setup Script | Description |
|---|---|---|
| [etcd Encryption](../cks/microservice-vulnerabilities.md#exercise-6) | `etcd-encryption` | Encrypt Secrets at rest and verify with etcdctl |
| [gVisor RuntimeClass](../cks/microservice-vulnerabilities.md#exercise-7) | `gvisor-runtime` | Run containers in a gVisor sandbox |
| [Privilege Escalation](../cks/microservice-vulnerabilities.md#exercise-8) | `privilege-escalation` | Identify and fix insecure pod security contexts |

### Supply Chain Security (20%)

| Lab | Setup Script | Description |
|---|---|---|
| [ImagePolicyWebhook](../cks/supply-chain-security.md#exercise-3) | `image-policy-webhook` | Configure the ImagePolicyWebhook admission controller |
| [Conftest Dockerfiles](../cks/supply-chain-security.md#exercise-6) | `conftest-docker` | Write OPA/Rego policies to lint Dockerfiles |
| [Image Digests](../cks/supply-chain-security.md#exercise-7) | `image-digest` | Replace mutable tags with immutable sha256 digests |

### Monitoring, Logging & Runtime Security (20%)

| Lab | Setup Script | Description |
|---|---|---|
| [Falco Custom Rules](../cks/monitoring-logging-runtime.md#exercise-6) | `falco-rules` | Write custom Falco rules for runtime threat detection |
| [Falco Log Analysis](../cks/monitoring-logging-runtime.md#exercise-8) | `falco-analysis` | Analyze Falco alerts to investigate a security incident |
| [Container Immutability](../cks/monitoring-logging-runtime.md#exercise-7) | `immutability` | Enforce read-only filesystems and prevent runtime modifications |

## Quick Reference

Run any lab:

```bash
# On your lab cluster
bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/<lab-name>/setup.sh)
```

Available lab names:

```
apparmor              conftest-docker       falco-analysis        image-policy-webhook
apiserver-crash       csr                   falco-rules           immutability
cilium-network-policy docker-hardening      gvisor-runtime        netpol-merge
                      etcd-encryption       image-digest          privilege-escalation
                                                                  seccomp
                                                                  strace
                                                                  validating-webhook
```
