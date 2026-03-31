# Compliance and Security Frameworks (10%)

This domain covers the regulatory and industry frameworks that govern security in cloud native environments. Understanding how compliance standards apply to Kubernetes, and knowing the tools that automate compliance checks, is important for the KCSA exam. While this is the lowest-weighted domain, it is also the most straightforward to study.

## CIS Kubernetes Benchmarks

The **Center for Internet Security (CIS) Kubernetes Benchmark** is the most widely used hardening guide for Kubernetes clusters. It provides prescriptive, consensus-based configuration recommendations.

### Benchmark Structure

The CIS Kubernetes Benchmark covers:

| Section | Focus Area |
|---|---|
| 1 - Control Plane Components | API server, controller manager, scheduler, etcd |
| 2 - etcd | etcd configuration and security |
| 3 - Control Plane Configuration | Authentication, authorization, audit logging |
| 4 - Worker Nodes | Kubelet configuration, node security |
| 5 - Policies | RBAC, Pod Security, NetworkPolicies, Secrets management |

### Scoring Levels

| Level | Description |
|---|---|
| **Level 1** | Basic security settings that can be applied without significant impact on functionality. Suitable for all environments |
| **Level 2** | Advanced security settings that may reduce functionality or require additional configuration. Suitable for security-sensitive environments |

### Example CIS Recommendations

| ID | Recommendation | Level |
|---|---|---|
| 1.1.1 | Ensure API server `--anonymous-auth` is set to `false` | 1 |
| 1.2.1 | Ensure `--authorization-mode` includes `RBAC` | 1 |
| 1.2.6 | Ensure `--kubelet-certificate-authority` is set | 1 |
| 2.1 | Ensure etcd client cert authentication is configured | 1 |
| 4.2.1 | Ensure kubelet `--anonymous-auth` is set to `false` | 1 |
| 4.2.4 | Ensure kubelet `--read-only-port` is set to `0` | 1 |
| 5.1.1 | Ensure RBAC is used instead of ABAC | 1 |
| 5.2.1 | Ensure Pod Security Standards are applied | 1 |
| 5.3.2 | Ensure all namespaces have NetworkPolicies defined | 2 |

### kube-bench

**kube-bench** is the standard open-source tool for running CIS Kubernetes Benchmark checks against a cluster.

```bash
# Run kube-bench on a control plane node
kube-bench run --targets=master

# Run kube-bench on a worker node
kube-bench run --targets=node

# Run all checks
kube-bench run

# Output as JSON
kube-bench run --json
```

**Sample output:**

```
[PASS] 1.1.1 Ensure that the API server pod specification file permissions are set to 644 or more restrictive
[FAIL] 1.1.2 Ensure that the API server pod specification file ownership is set to root:root
[WARN] 1.1.3 Ensure that the proxy kubeconfig file permissions are set to 644 or more restrictive
```

Each check results in one of:

- **PASS** — Configuration meets the benchmark recommendation
- **FAIL** — Configuration does not meet the recommendation (requires remediation)
- **WARN** — Manual verification required
- **INFO** — Informational only

!!! tip "Exam Tip"
    Know what kube-bench is, what it checks (CIS Kubernetes Benchmark), and how it reports results. You do not need to memorize specific benchmark numbers, but understand the categories of checks and the concept of Level 1 vs. Level 2 recommendations.

## NIST Frameworks

The **National Institute of Standards and Technology (NIST)** publishes several security frameworks relevant to cloud native environments.

### NIST Cybersecurity Framework (CSF)

A risk-based framework organized around five core functions:

| Function | Description | Kubernetes Relevance |
|---|---|---|
| **Identify** | Understand assets, risks, and vulnerabilities | Asset inventory, SBOM, risk assessments |
| **Protect** | Implement safeguards | RBAC, NetworkPolicies, encryption, Pod Security Standards |
| **Detect** | Identify security events | Audit logging, runtime monitoring (Falco), alerting |
| **Respond** | Take action on detected events | Incident response plans, automated remediation |
| **Recover** | Restore capabilities after an incident | Backup/restore procedures, disaster recovery, etcd snapshots |

### NIST SP 800-190: Application Container Security Guide

Specifically addresses container security:

- Image security (vulnerabilities, configuration, signing)
- Registry security (access controls, scanning)
- Orchestrator security (Kubernetes hardening)
- Container runtime security (isolation, resource limits)
- Host OS security (minimal OS, hardening)

### NIST SP 800-207: Zero Trust Architecture

Defines zero trust principles for enterprise networks:

- No implicit trust based on network location
- All communication is authenticated and authorized
- Access is granted on a per-session basis
- Policies are dynamic and based on multiple data sources

## SOC 2

**SOC 2 (Service Organization Control 2)** is an auditing standard that evaluates how organizations manage customer data, based on five Trust Services Criteria.

| Criteria | Description | Kubernetes Controls |
|---|---|---|
| **Security** | Protection against unauthorized access | RBAC, NetworkPolicies, encryption, Pod Security Standards |
| **Availability** | System uptime and accessibility | PodDisruptionBudgets, resource quotas, HA control plane |
| **Processing Integrity** | Accurate and complete data processing | Admission controllers, input validation |
| **Confidentiality** | Protection of sensitive data | Secrets encryption, TLS, access controls |
| **Privacy** | Protection of personal information | Data classification, access logs, retention policies |

### SOC 2 in Kubernetes Context

Key controls for SOC 2 compliance in Kubernetes:

- **Access control** — RBAC with least privilege, MFA for cluster access
- **Audit logging** — Enable Kubernetes audit logs with appropriate retention
- **Encryption** — TLS in transit, encryption at rest for etcd
- **Change management** — GitOps workflows with approval processes
- **Monitoring** — Continuous monitoring with alerting for security events
- **Incident response** — Documented procedures for security incidents

## PCI-DSS in Cloud Native Context

**PCI-DSS (Payment Card Industry Data Security Standard)** applies to organizations that handle credit card data. Several requirements map directly to Kubernetes security controls.

| PCI-DSS Requirement | Kubernetes Control |
|---|---|
| Req 1: Network segmentation | NetworkPolicies, namespace isolation |
| Req 2: Secure defaults | Remove default credentials, harden components |
| Req 3: Protect stored data | Secrets encryption at rest, external KMS |
| Req 4: Encrypt data in transit | TLS everywhere, mTLS via service mesh |
| Req 6: Secure development | Image scanning, vulnerability management |
| Req 7: Restrict access | RBAC with least privilege |
| Req 8: Authentication | Strong authentication, short-lived tokens, OIDC |
| Req 10: Logging and monitoring | Audit logging, centralized log management |
| Req 11: Security testing | Penetration testing, CIS benchmark scans |
| Req 12: Security policies | Documented policies, incident response plans |

!!! info "Scope Reduction"
    In Kubernetes, PCI-DSS scope can be reduced by isolating cardholder data environments (CDE) in dedicated namespaces with strict NetworkPolicies, separate ServiceAccounts, and dedicated node pools. This minimizes the number of components subject to PCI audit.

## Compliance Automation Tools

### OPA / Gatekeeper

**Open Policy Agent (OPA)** is a general-purpose policy engine. **Gatekeeper** is the Kubernetes-native integration that uses OPA to enforce policies via admission webhooks.

```yaml
# ConstraintTemplate: Define the policy logic
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels
      validation:
        openAPIV3Schema:
          type: object
          properties:
            labels:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequiredlabels
        violation[{"msg": msg}] {
          provided := {label | input.review.object.metadata.labels[label]}
          required := {label | label := input.parameters.labels[_]}
          missing := required - provided
          count(missing) > 0
          msg := sprintf("Missing required labels: %v", [missing])
        }
```

```yaml
# Constraint: Apply the policy
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-team-label
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Namespace"]
  parameters:
    labels:
      - "team"
```

### Kyverno

**Kyverno** is a Kubernetes-native policy engine that uses YAML-based policies (no Rego language required).

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-latest-tag
spec:
  validationFailureAction: Enforce
  rules:
    - name: require-image-tag
      match:
        any:
          - resources:
              kinds:
                - Pod
      validate:
        message: "Using 'latest' tag is not allowed."
        pattern:
          spec:
            containers:
              - image: "!*:latest"
```

### OPA/Gatekeeper vs. Kyverno

| Feature | OPA / Gatekeeper | Kyverno |
|---|---|---|
| Policy language | Rego (dedicated policy language) | YAML (Kubernetes-native) |
| Learning curve | Steeper (Rego syntax) | Lower (familiar YAML) |
| Mutation support | Yes | Yes |
| Generation (create resources) | No | Yes |
| Audit existing resources | Yes | Yes |
| CNCF status | Graduated (OPA) | Incubating (Kyverno) |

### kube-bench

As discussed in the CIS section above, kube-bench automates CIS Kubernetes Benchmark checks. It is the primary tool for CIS compliance validation.

### Additional Compliance Tools

| Tool | Purpose |
|---|---|
| [kube-bench](https://github.com/aquasecurity/kube-bench) | CIS Kubernetes Benchmark compliance checks |
| [kube-hunter](https://github.com/aquasecurity/kube-hunter) | Kubernetes penetration testing tool |
| [kubescape](https://github.com/kubescape/kubescape) | Multi-framework compliance scanning (NSA, MITRE, CIS) |
| [Polaris](https://github.com/FairwindsOps/polaris) | Best practices validation for Kubernetes resources |
| [Checkov](https://github.com/bridgecrewio/checkov) | Infrastructure-as-code security scanning |

## Audit Logging for Compliance

Audit logging is a common requirement across all compliance frameworks. In Kubernetes:

- **Enable API server audit logging** with an appropriate policy
- **Ship logs externally** — Logs must be stored outside the cluster in an immutable, append-only system
- **Define retention periods** — PCI-DSS requires at least 1 year; SOC 2 and NIST have similar requirements
- **Protect log integrity** — Ensure logs cannot be tampered with
- **Monitor and alert** — Set up automated alerts for suspicious activity patterns

### Compliance Logging Checklist

- [ ] API server audit logging enabled
- [ ] Audit policy defines appropriate levels per resource
- [ ] Logs shipped to external SIEM or log aggregation
- [ ] Retention period meets regulatory requirements
- [ ] Access to audit logs is restricted and logged
- [ ] Automated alerting on critical events
- [ ] Regular review of audit logs

## Important Links

- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [kube-bench GitHub](https://github.com/aquasecurity/kube-bench)
- [OPA Gatekeeper](https://open-policy-agent.github.io/gatekeeper/)
- [Kyverno Documentation](https://kyverno.io/docs/)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [NIST SP 800-190: Container Security Guide](https://csrc.nist.gov/publications/detail/sp/800-190/final)
- [PCI Security Standards](https://www.pcisecuritystandards.org/)
- [kubescape](https://github.com/kubescape/kubescape)

## Practice Questions

??? question "What is the CIS Kubernetes Benchmark, and what tool is commonly used to automate its checks?"
    Describe the benchmark and the tool.

    ??? success "Answer"
        The **CIS Kubernetes Benchmark** is a set of prescriptive, consensus-based security configuration recommendations published by the Center for Internet Security. It covers control plane components (API server, etcd, scheduler, controller manager), worker node configuration (kubelet), and policies (RBAC, Pod Security, NetworkPolicies, Secrets).

        The benchmark has two scoring levels:

        - **Level 1** — Basic hardening that can be applied without impacting functionality
        - **Level 2** — Advanced hardening that may affect functionality but provides stronger security

        **kube-bench** (by Aqua Security) is the standard open-source tool for automating CIS Benchmark checks. It runs on cluster nodes and reports PASS/FAIL/WARN results for each recommendation. It can output results as text, JSON, or JUnit for CI/CD integration.

??? question "How do the five functions of the NIST Cybersecurity Framework map to Kubernetes security controls?"
    Provide at least one Kubernetes control for each function.

    ??? success "Answer"
        The five NIST CSF functions and their Kubernetes mappings:

        1. **Identify** — Know your assets and risks. *Kubernetes controls:* SBOM generation for all images, namespace inventory, RBAC audit (`kubectl auth can-i --list`), risk assessments of workloads.

        2. **Protect** — Implement safeguards. *Kubernetes controls:* RBAC with least privilege, Pod Security Standards (restricted level), NetworkPolicies (default deny), encryption at rest for Secrets, TLS for all communication.

        3. **Detect** — Identify security events. *Kubernetes controls:* Kubernetes audit logging, Falco for runtime anomaly detection, monitoring failed authentication attempts, alerting on policy violations.

        4. **Respond** — Take action on incidents. *Kubernetes controls:* Incident response playbooks, automated pod quarantine (cordon/drain node), revoke compromised ServiceAccount tokens, NetworkPolicy isolation of compromised pods.

        5. **Recover** — Restore after incidents. *Kubernetes controls:* etcd backup and restore, GitOps-based cluster reconstruction, disaster recovery procedures, post-incident reviews.

??? question "What is the difference between OPA/Gatekeeper and Kyverno? When would you choose one over the other?"
    Compare the two policy engines.

    ??? success "Answer"
        Both are Kubernetes policy engines that enforce custom policies via admission webhooks, but they differ in key ways:

        **OPA/Gatekeeper:**

        - Uses **Rego**, a dedicated policy language, for writing policies
        - OPA is a **CNCF Graduated** project (mature, widely adopted)
        - Steeper learning curve due to Rego syntax
        - Supports validation and mutation
        - Better suited for organizations that need policies across multiple platforms (not just Kubernetes), as OPA is a general-purpose policy engine

        **Kyverno:**

        - Uses **YAML** for policy definitions (Kubernetes-native, no new language to learn)
        - **CNCF Incubating** project
        - Lower barrier to entry for Kubernetes teams
        - Supports validation, mutation, and **resource generation** (can create resources automatically)
        - Better suited for teams that want to stay within the Kubernetes YAML ecosystem

        **When to choose:**

        - Choose **Gatekeeper** if you already use OPA elsewhere, need cross-platform policies, or have team expertise in Rego
        - Choose **Kyverno** if you prefer YAML-based policies, need resource generation capabilities, or want a lower learning curve for Kubernetes-focused teams

??? question "How can Kubernetes help achieve PCI-DSS compliance for cardholder data environments?"
    Describe specific Kubernetes features that map to PCI-DSS requirements.

    ??? success "Answer"
        Kubernetes provides several features that directly support PCI-DSS compliance:

        - **Network segmentation (Req 1)** — Use dedicated namespaces for the cardholder data environment (CDE) with strict NetworkPolicies that block all traffic except explicitly allowed flows
        - **Secure defaults (Req 2)** — Apply `restricted` Pod Security Standard, remove default ServiceAccount permissions, disable unnecessary API server features
        - **Data protection (Req 3 & 4)** — Enable encryption at rest for Secrets in etcd (using KMS), enforce TLS for all communication, use mTLS via service mesh
        - **Access control (Req 7 & 8)** — Implement RBAC with least privilege, use OIDC with MFA for human access, create dedicated ServiceAccounts per workload
        - **Logging and monitoring (Req 10)** — Enable API server audit logging, ship logs to external SIEM with retention meeting PCI requirements (1 year minimum), monitor for unauthorized access
        - **Vulnerability management (Req 6 & 11)** — Image scanning in CI/CD, run kube-bench for CIS compliance, periodic penetration testing

        **Scope reduction** is achieved by isolating the CDE in dedicated namespaces (or dedicated clusters) with network policies, reducing the number of components subject to PCI audit.

??? question "A compliance auditor asks for evidence that the Kubernetes cluster meets CIS Benchmark recommendations. What steps would you take?"
    Describe the process of generating and presenting compliance evidence.

    ??? success "Answer"
        Steps to provide CIS Benchmark compliance evidence:

        1. **Run kube-bench** on all control plane and worker nodes to generate a report of all CIS checks with PASS/FAIL/WARN results. Use `--json` output for structured data:
           ```
           kube-bench run --json > cis-report.json
           ```

        2. **Review failures** — Document each FAIL result with either a remediation plan or an accepted risk justification (compensating control or business reason for deviation)

        3. **Automate continuous compliance** — Run kube-bench on a schedule (e.g., via a CronJob) and ship results to a compliance dashboard or SIEM

        4. **Supplement with policy enforcement** — Show that OPA/Gatekeeper or Kyverno policies enforce key CIS recommendations at admission time (preventing non-compliant configurations from being deployed)

        5. **Provide supporting evidence:**
            - RBAC configuration (Roles, ClusterRoles, Bindings)
            - Audit logging configuration and sample logs
            - Encryption at rest configuration
            - NetworkPolicy definitions
            - Pod Security Standard enforcement labels on namespaces

        6. **Document exceptions** — For any Level 2 recommendations not implemented, provide documented risk acceptance with compensating controls
