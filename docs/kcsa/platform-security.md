# Platform Security (16%)

This domain covers the security of the broader platform surrounding Kubernetes, including container image security, software supply chain integrity, runtime threat detection, node hardening, and using observability for security monitoring.

## Image Security

Container images are the foundation of every workload. A compromised or vulnerable image introduces risk before a single container starts running.

### Image Scanning

Image scanning analyzes container images for known vulnerabilities (CVEs), misconfigurations, and embedded secrets.

**When to scan:**

- At build time in the CI/CD pipeline (shift left)
- Before pushing to the registry
- Continuously in the registry (new CVEs are published daily)
- At deploy time via admission controllers

**Popular scanning tools:**

| Tool | Description |
|---|---|
| [Trivy](https://github.com/aquasecurity/trivy) | Open-source scanner for images, filesystems, git repos, and IaC |
| [Grype](https://github.com/anchore/grype) | Open-source vulnerability scanner by Anchore |
| [Snyk Container](https://snyk.io/) | Commercial scanner with CI/CD integrations |
| [Clair](https://github.com/quay/clair) | Open-source static analysis for container images |
| [Docker Scout](https://docs.docker.com/scout/) | Docker's built-in image analysis |

### Image Best Practices

- **Use minimal base images** — `distroless`, `scratch`, or Alpine-based images reduce the attack surface
- **Pin image versions** — Use image digests (`image@sha256:...`) instead of mutable tags (`:latest`)
- **Multi-stage builds** — Use build stages to exclude build tools, compilers, and source code from the final image
- **No secrets in images** — Never bake credentials, API keys, or certificates into image layers
- **Run as non-root** — Set `USER` directive in Dockerfile to a non-root user
- **Use `.dockerignore`** — Prevent sensitive files from being included in the build context

```dockerfile
# Example: Minimal, secure Dockerfile
FROM golang:1.22 AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /app/server

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /app/server /server
USER nonroot:nonroot
ENTRYPOINT ["/server"]
```

### Image Signing and Verification

Image signing provides cryptographic proof that an image was built by a trusted entity and has not been tampered with.

- **cosign** (part of Sigstore) — Signs and verifies container images using keyless or key-based signing
- **Notary / Docker Content Trust** — Signs images pushed to a registry
- **Admission enforcement** — Use Kyverno or OPA/Gatekeeper to reject unsigned images at deploy time

```bash
# Sign an image with cosign
cosign sign --key cosign.key registry.example.com/my-app:v1.0

# Verify an image signature
cosign verify --key cosign.pub registry.example.com/my-app:v1.0
```

### Trusted Registries

- Use **private registries** for production images (Harbor, ECR, GCR, ACR)
- Restrict image sources via **admission policies** (only allow images from approved registries)
- Enable **vulnerability scanning** in the registry
- Implement **image retention policies** to remove old, unpatched images
- Use **registry authentication** to prevent unauthorized pulls

!!! tip "Exam Tip"
    Know the difference between image scanning (finding vulnerabilities), image signing (proving provenance), and trusted registries (controlling where images come from). The exam tests all three concepts and how they work together.

## Supply Chain Security

Supply chain security ensures the integrity and trustworthiness of every component from source code to deployed container.

### Software Bill of Materials (SBOM)

An **SBOM** is a comprehensive inventory of all components, libraries, and dependencies in a software artifact. It enables:

- Rapid response to newly discovered vulnerabilities (search SBOM for affected libraries)
- License compliance verification
- Transparency in the software supply chain

**SBOM formats:**

| Format | Description |
|---|---|
| **SPDX** | Linux Foundation standard, ISO/IEC 5962:2021 |
| **CycloneDX** | OWASP standard, focused on security use cases |
| **SWID** | ISO/IEC 19770-2, used for software identification |

**Generating SBOMs:**

```bash
# Generate SBOM with Syft
syft registry.example.com/my-app:v1.0 -o spdx-json > sbom.json

# Scan SBOM for vulnerabilities with Grype
grype sbom:sbom.json
```

### Sigstore

**Sigstore** is an open-source project that provides free, transparent, and auditable code signing and verification.

Components:

| Component | Purpose |
|---|---|
| **cosign** | Sign and verify container images and other artifacts |
| **Rekor** | Transparency log for recording signing events (immutable, append-only) |
| **Fulcio** | Certificate authority for keyless signing (uses OIDC identity) |

**Keyless signing** allows developers to sign images using their OIDC identity (e.g., GitHub Actions, Google) without managing private keys:

```bash
# Keyless signing with cosign (uses OIDC)
cosign sign registry.example.com/my-app:v1.0

# Verify with identity and issuer
cosign verify \
  --certificate-identity user@example.com \
  --certificate-oidc-issuer https://accounts.google.com \
  registry.example.com/my-app:v1.0
```

### SLSA Framework

**SLSA (Supply chain Levels for Software Artifacts)** is a framework for ensuring the integrity of software artifacts throughout the supply chain.

| Level | Requirements |
|---|---|
| SLSA 1 | Build process is documented and produces provenance |
| SLSA 2 | Build service generates authenticated provenance |
| SLSA 3 | Hardened build platform with tamper-resistant provenance |
| SLSA 4 | Two-party review and hermetic, reproducible builds |

!!! info "Exam Focus"
    The KCSA exam emphasizes understanding supply chain concepts (SBOM, signing, provenance) and the tools that implement them (cosign, Sigstore, Trivy). You do not need deep expertise in running these tools, but you should understand what each does and why it matters.

## Runtime Security

Runtime security monitors running containers for suspicious behavior and policy violations in real time.

### Falco

**Falco** (CNCF Incubating project) is the leading open-source runtime security tool for Kubernetes. It monitors system calls using eBPF or a kernel module to detect unexpected behavior.

Detection examples:

- Shell spawned inside a container
- Unexpected network connections
- File access in sensitive directories (`/etc/shadow`, `/etc/passwd`)
- Privilege escalation attempts
- Binary executed that was not part of the original image

```yaml
# Example Falco rule
- rule: Shell Spawned in Container
  desc: Detect shell spawned in a container
  condition: >
    spawned_process and container and
    proc.name in (bash, sh, zsh, dash)
  output: >
    Shell spawned in container
    (user=%user.name container=%container.name
     shell=%proc.name parent=%proc.pname)
  priority: WARNING
```

### Other Runtime Security Tools

| Tool | Description |
|---|---|
| [Tetragon](https://github.com/cilium/tetragon) | eBPF-based security observability and enforcement (Cilium) |
| [KubeArmor](https://github.com/kubearmor/KubeArmor) | Runtime security enforcement using LSMs (AppArmor, BPF-LSM) |
| [Sysdig Secure](https://sysdig.com/) | Commercial runtime security based on Falco |

### Linux Security Mechanisms

| Mechanism | Description |
|---|---|
| **seccomp** | Restricts which system calls a process can make. `RuntimeDefault` profile blocks dangerous syscalls |
| **AppArmor** | Mandatory access control that restricts file access, network access, and capabilities per-process |
| **SELinux** | Label-based mandatory access control for fine-grained process and file access control |
| **Capabilities** | Divide root privileges into distinct units. Drop all and add only what is needed |

## Node Security

Worker nodes run the kubelet, container runtime, and workloads. Compromising a node compromises all pods on that node.

### Node Hardening Best Practices

- **Minimal OS** — Use container-optimized operating systems (e.g., Bottlerocket, Flatcar, Talos)
- **Automatic patching** — Keep the OS, kernel, and container runtime up to date
- **Disable SSH** — Or restrict SSH access to a bastion host with key-based authentication
- **CIS Benchmarks** — Apply CIS benchmarks for the OS and Kubernetes node configuration
- **File integrity monitoring** — Detect unauthorized changes to critical system files
- **Restrict kubelet access** — Disable anonymous auth and the read-only port
- **Limit node access** — Use network-level controls to restrict which systems can reach node ports
- **Immutable infrastructure** — Replace nodes instead of patching them in place (cattle, not pets)

### Container Runtime Security

- Use a modern, minimal runtime — **containerd** or **CRI-O** (Docker is deprecated as a Kubernetes runtime)
- Enable **seccomp default profiles** for all containers
- Configure the runtime to enforce **read-only root filesystems** by default
- Set **pid limits** to prevent fork bombs
- Ensure the runtime socket is not exposed to containers

## Network Security

### Network-Level Controls

| Control | Description |
|---|---|
| **NetworkPolicies** | Restrict pod-to-pod and pod-to-external traffic |
| **Service Mesh (mTLS)** | Encrypt and authenticate all service-to-service communication |
| **Ingress/Egress controls** | Control traffic entering and leaving the cluster |
| **DNS policies** | Restrict which DNS names pods can resolve |
| **Encryption in transit** | TLS for all internal and external communication |
| **Network segmentation** | Separate control plane, worker nodes, and management networks |

### Service Mesh Security

A service mesh (Istio, Linkerd, Cilium) adds a sidecar proxy to each pod that handles:

- **Mutual TLS (mTLS)** — Automatic encryption and identity verification between services
- **Authorization policies** — Fine-grained access control between services
- **Traffic observability** — Visibility into all service-to-service communication
- **Rate limiting** — Protect services from excessive traffic

## Observability for Security

Observability provides the visibility needed to detect, investigate, and respond to security incidents.

### Audit Logging

Kubernetes audit logs record all requests to the API server, providing a chronological record of cluster activity.

```yaml
# Example audit policy
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets", "configmaps"]
  - level: RequestResponse
    resources:
      - group: ""
        resources: ["pods"]
    verbs: ["create", "delete"]
  - level: None
    resources:
      - group: ""
        resources: ["events"]
```

**Audit levels:**

| Level | What is Logged |
|---|---|
| `None` | Nothing |
| `Metadata` | Request metadata (user, timestamp, resource, verb) |
| `Request` | Metadata + request body |
| `RequestResponse` | Metadata + request body + response body |

### Security-Relevant Metrics

- Failed authentication and authorization attempts
- Admission controller rejections
- Pod security violations (audit/warn events)
- Abnormal resource usage patterns
- Network connection anomalies
- Container restart counts and OOM kills

### Centralized Logging

- Ship logs to an external, immutable log store (Elasticsearch, Loki, Splunk, SIEM)
- Ensure logs cannot be deleted by cluster users
- Set retention policies that meet compliance requirements
- Correlate Kubernetes audit logs with application and node-level logs

!!! tip "Exam Tip"
    Understand the audit logging levels (None, Metadata, Request, RequestResponse) and when to use each. The exam may ask which level is appropriate for specific use cases. Use `Metadata` for most resources, `RequestResponse` for sensitive operations like Secret creation, and `None` for high-volume, low-risk events like health checks.

## Important Links

- [Trivy Documentation](https://aquasecurity.github.io/trivy/)
- [Sigstore / cosign](https://docs.sigstore.dev/)
- [Falco Documentation](https://falco.org/docs/)
- [Kubernetes Audit Logging](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [SLSA Framework](https://slsa.dev/)
- [SBOM Overview (NTIA)](https://www.ntia.gov/SBOM)
- [Bottlerocket OS](https://bottlerocket.dev/)

## Practice Questions

??? question "What is the difference between image scanning, image signing, and using trusted registries?"
    Explain how each addresses a different aspect of image security.

    ??? success "Answer"
        These three controls address different aspects of image security:

        **Image scanning** identifies known vulnerabilities (CVEs) and misconfigurations in container image layers and dependencies. It answers: "Does this image contain known security issues?" Tools: Trivy, Grype, Clair.

        **Image signing** provides cryptographic proof of image provenance and integrity. It answers: "Was this image built by a trusted party, and has it been tampered with since?" Tools: cosign (Sigstore), Notary.

        **Trusted registries** control where images can be pulled from. They answer: "Is this image from an approved source?" Implemented via admission controllers (Kyverno, OPA/Gatekeeper) that reject images from unapproved registries.

        Together, they form a defense-in-depth approach: the registry controls the source, scanning identifies vulnerabilities, and signing verifies integrity and authorship.

??? question "A security team discovers a new CVE affecting the log4j library. How can SBOMs help respond to this?"
    Describe the role of SBOMs in vulnerability response.

    ??? success "Answer"
        SBOMs (Software Bill of Materials) contain a comprehensive inventory of all components and dependencies in each software artifact. When a new CVE like Log4Shell is announced:

        1. **Rapid identification** — Search all SBOMs across the organization to instantly identify which container images contain the affected log4j library and which specific versions are in use
        2. **Scope assessment** — Determine how many services and environments are affected without needing to scan every image from scratch
        3. **Prioritized remediation** — Focus patching efforts on the most critical/exposed services first
        4. **Compliance evidence** — Provide auditable proof that the organization identified and addressed the vulnerability

        Without SBOMs, the team would need to scan every image in every registry, which is significantly slower. SBOMs shift vulnerability identification from a scan-time activity to a query-time activity.

??? question "What is Falco, and how does it detect threats at runtime?"
    Describe Falco's architecture and detection approach.

    ??? success "Answer"
        **Falco** is a CNCF Incubating project for runtime security monitoring. It detects unexpected application behavior and alerts on threats in real time.

        **Architecture:**

        - Falco uses **eBPF** (or a kernel module) to intercept system calls at the kernel level
        - System call data is processed by the Falco engine against a set of rules
        - Rules define conditions that indicate suspicious behavior
        - When a rule is triggered, Falco generates an alert that can be sent to stdout, files, Slack, a SIEM, or other outputs

        **What it detects:**

        - Shell spawned inside a container
        - Read/write to sensitive files (`/etc/shadow`, `/etc/passwd`)
        - Unexpected outbound network connections
        - Privilege escalation attempts
        - Binary execution not part of the original image
        - Container namespace changes

        Falco operates at the **detection** layer, not the **prevention** layer. It alerts operators to suspicious activity but does not block it (though it can be combined with response tools for automated remediation).

??? question "Why should organizations use container-optimized operating systems like Bottlerocket or Talos for Kubernetes nodes?"
    Compare container-optimized OSes with general-purpose distributions.

    ??? success "Answer"
        Container-optimized operating systems are purpose-built for running containers and offer significant security advantages:

        1. **Minimal attack surface** — Only essential packages are included. No package manager, no shell (or limited shell), no unnecessary services
        2. **Immutable filesystem** — The root filesystem is read-only, preventing runtime modifications and persistent malware
        3. **Automated updates** — Atomic, transactional updates that can be rolled back if they fail
        4. **Security hardening** — Pre-configured with security best practices (SELinux/AppArmor enabled, hardened kernel settings)
        5. **API-driven management** — Configuration changes are made through APIs, not SSH, reducing the risk of configuration drift

        Compared to general-purpose distributions (Ubuntu, CentOS), container-optimized OSes eliminate hundreds of unnecessary packages and services that could contain vulnerabilities or be exploited by attackers. The tradeoff is reduced flexibility for debugging and troubleshooting on the node itself.

??? question "What audit log level should be used for Kubernetes Secrets, and why?"
    Consider the trade-off between security visibility and data sensitivity.

    ??? success "Answer"
        For Kubernetes Secrets, the recommended audit log level is **Metadata**.

        **Why not higher levels:**

        - **Request** level would log the Secret data in the request body (the actual secret values), creating a security risk — the audit log itself becomes a target for attackers
        - **RequestResponse** would log both the request and response bodies, further exposing sensitive data

        **Why not None:**

        - Disabling audit logging for Secrets would create a blind spot. You need to know who accessed, created, modified, or deleted Secrets for security monitoring and compliance

        **Metadata** level logs *who* accessed *which* Secret and *when*, without exposing the Secret's actual content. This provides the necessary visibility for detecting unauthorized access while protecting the sensitive data itself.

        For monitoring Secret creation and deletion events specifically, some organizations use `Request` level only for `create` and `delete` verbs (not `get` or `list`) to detect unauthorized modifications while minimizing exposure.
