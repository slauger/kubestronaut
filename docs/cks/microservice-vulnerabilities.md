# Minimize Microservice Vulnerabilities (20%)

This domain covers securing workloads at the pod and container level. You need to understand Pod Security Standards and Pod Security Admission, policy engines like OPA/Gatekeeper, secure management of Kubernetes Secrets, container sandboxing technologies, and mTLS with service meshes. At 20% of the exam weight, this is one of the three highest-weighted domains.

## Key Concepts

### Pod Security Standards

Pod Security Standards define three security levels that cover the spectrum of security needs:

| Level | Description |
|---|---|
| **Privileged** | Unrestricted policy. Allows everything, including known privilege escalations. For system-level workloads only. |
| **Baseline** | Minimally restrictive policy. Prevents known privilege escalations while allowing the default pod configuration. |
| **Restricted** | Heavily restricted policy. Follows hardening best practices. Requires pods to have security contexts properly configured. |

#### Key Restrictions by Level

| Control | Baseline | Restricted |
|---|---|---|
| `hostNetwork` | Must be `false` | Must be `false` |
| `hostPID` / `hostIPC` | Must be `false` | Must be `false` |
| `privileged` | Must be `false` | Must be `false` |
| `capabilities` | Drops `ALL` except allowed | Must drop `ALL`, may add only `NET_BIND_SERVICE` |
| `runAsNonRoot` | Not required | Must be `true` |
| `allowPrivilegeEscalation` | Not required | Must be `false` |
| `seccompProfile` | Not required | Must be `RuntimeDefault` or `Localhost` |
| Volume types | Not restricted | Limited to core volume types |

### Pod Security Admission

Pod Security Admission (PSA) is a built-in admission controller that enforces Pod Security Standards at the namespace level. It replaced the deprecated PodSecurityPolicy (PSP).

#### Modes

| Mode | Behavior |
|---|---|
| `enforce` | Violations cause the pod to be rejected |
| `audit` | Violations are recorded in the audit log but the pod is allowed |
| `warn` | Violations trigger a user-facing warning but the pod is allowed |

#### Applying Pod Security Standards via Labels

```bash
# Apply restricted security standard in enforce mode
kubectl label namespace production \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest

# Apply baseline with audit and warn
kubectl label namespace staging \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted
```

```yaml
# Or via namespace manifest
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

#### A Pod That Passes the Restricted Standard

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: restricted-compliant
  namespace: production
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: app
      image: nginx:latest
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
        readOnlyRootFilesystem: true
      volumeMounts:
        - name: tmp
          mountPath: /tmp
  volumes:
    - name: tmp
      emptyDir: {}
```

!!! tip "Exam Tip"
    When a namespace has `enforce: restricted`, you must ensure every pod meets all restricted requirements. The most commonly missed fields are `seccompProfile`, `runAsNonRoot`, `allowPrivilegeEscalation: false`, and `capabilities.drop: ["ALL"]`. Always check all of these.

!!! warning "Common Pitfall"
    Pod Security Admission only checks pod specifications. It does not modify them. If a pod does not meet the standard, it is simply rejected (in enforce mode). Make sure the pod spec is fully compliant before creating it.

### OPA/Gatekeeper

Open Policy Agent (OPA) Gatekeeper is a customizable policy engine for Kubernetes. It extends Pod Security Standards with custom policies defined as constraints.

#### Gatekeeper Architecture

Gatekeeper uses two custom resources:

- **ConstraintTemplate**: Defines the policy logic in Rego
- **Constraint**: Instantiates a template with specific parameters

#### Example: Require Labels on All Pods

```yaml
# ConstraintTemplate
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
# Constraint
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: pods-must-have-owner
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
  parameters:
    labels:
      - "owner"
      - "app"
```

#### Example: Deny Privileged Containers

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8sdenyprivileged
spec:
  crd:
    spec:
      names:
        kind: K8sDenyPrivileged
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sdenyprivileged

        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          container.securityContext.privileged == true
          msg := sprintf("Privileged container not allowed: %v", [container.name])
        }
```

### Managing Kubernetes Secrets

Secrets store sensitive data such as passwords, tokens, and certificates. By default, Secrets are stored unencrypted in etcd.

#### Creating Secrets

```bash
# Create from literal values
kubectl create secret generic db-credentials \
  --from-literal=username=admin \
  --from-literal=password='S3cur3P@ss!'

# Create from files
kubectl create secret generic tls-certs \
  --from-file=tls.crt=./server.crt \
  --from-file=tls.key=./server.key

# Create a TLS secret
kubectl create secret tls my-tls-secret \
  --cert=./server.crt --key=./server.key
```

#### Encryption at Rest

By default, Secrets are stored as base64-encoded plaintext in etcd. To encrypt them at rest, configure an EncryptionConfiguration:

```yaml
# /etc/kubernetes/enc/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: <base64-encoded-32-byte-key>
      - identity: {}
```

```bash
# Generate a 32-byte encryption key
head -c 32 /dev/urandom | base64

# Enable encryption in the API server manifest
# /etc/kubernetes/manifests/kube-apiserver.yaml
# Add:
#   --encryption-provider-config=/etc/kubernetes/enc/encryption-config.yaml
# And mount the config file as a volume
```

```yaml
# API server manifest additions
spec:
  containers:
    - command:
        - kube-apiserver
        - --encryption-provider-config=/etc/kubernetes/enc/encryption-config.yaml
      volumeMounts:
        - name: enc-config
          mountPath: /etc/kubernetes/enc
          readOnly: true
  volumes:
    - name: enc-config
      hostPath:
        path: /etc/kubernetes/enc
        type: DirectoryOrCreate
```

After enabling encryption, re-encrypt all existing Secrets:

```bash
# Re-encrypt all secrets
kubectl get secrets --all-namespaces -o json | kubectl replace -f -

# Verify encryption by reading directly from etcd
ETCDCTL_API=3 etcdctl get /registry/secrets/default/db-credentials \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  | hexdump -C
# The output should show encrypted data, not plaintext
```

!!! warning "Common Pitfall"
    The order of providers in the EncryptionConfiguration matters. The first provider is used for encryption. The `identity: {}` provider at the end allows reading unencrypted Secrets that existed before encryption was enabled. Without it, old Secrets become unreadable until re-encrypted.

!!! tip "Exam Tip"
    When asked to enable Secret encryption at rest, remember three steps: (1) create the EncryptionConfiguration file, (2) add the `--encryption-provider-config` flag to the API server manifest with proper volume mounts, (3) re-encrypt existing Secrets with `kubectl get secrets -A -o json | kubectl replace -f -`.

#### Using Secrets Securely in Pods

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-secrets
spec:
  containers:
    - name: app
      image: my-app:latest
      # Mount secrets as files (preferred over env vars)
      volumeMounts:
        - name: secret-volume
          mountPath: /etc/secrets
          readOnly: true
      # Env vars from secrets (less secure - visible in pod spec)
      env:
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: password
  volumes:
    - name: secret-volume
      secret:
        secretName: db-credentials
        defaultMode: 0400
```

### Container Sandboxing

Container sandboxing provides stronger isolation than standard Linux containers by adding an additional layer between the container and the host kernel.

#### gVisor (runsc)

gVisor intercepts application syscalls and implements them in a user-space kernel, preventing direct interaction with the host kernel.

```yaml
# RuntimeClass for gVisor
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
```

```yaml
# Pod using gVisor sandbox
apiVersion: v1
kind: Pod
metadata:
  name: sandboxed-pod
spec:
  runtimeClassName: gvisor
  containers:
    - name: app
      image: nginx:latest
```

#### Kata Containers

Kata Containers run each container in a lightweight virtual machine, providing hardware-level isolation.

```yaml
# RuntimeClass for Kata Containers
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: kata
handler: kata
```

```yaml
# Pod using Kata Containers
apiVersion: v1
kind: Pod
metadata:
  name: kata-pod
spec:
  runtimeClassName: kata
  containers:
    - name: app
      image: nginx:latest
```

#### RuntimeClass Configuration

RuntimeClass supports scheduling constraints and resource overhead accounting:

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
overhead:
  podFixed:
    memory: "120Mi"
    cpu: "250m"
scheduling:
  nodeSelector:
    sandbox-runtime: "gvisor"
  tolerations:
    - key: "sandbox"
      operator: "Equal"
      value: "true"
      effect: "NoSchedule"
```

| Field | Purpose |
|---|---|
| `handler` | Name of the CRI handler (must match container runtime configuration) |
| `overhead.podFixed` | Additional resource overhead accounted for when scheduling sandboxed pods |
| `scheduling.nodeSelector` | Ensures pods only run on nodes with the runtime installed |
| `scheduling.tolerations` | Tolerations automatically applied to pods using this RuntimeClass |

#### Container Runtime Comparison

| Feature | runc (default) | gVisor (runsc) | Kata Containers |
|---|---|---|---|
| Isolation | Linux namespaces/cgroups | User-space kernel | Lightweight VM |
| Syscall handling | Direct to host kernel | Intercepted by Sentry | Full guest kernel |
| Performance overhead | None | ~5-10% | ~10-20% |
| Security boundary | Kernel | User-space + seccomp | Hardware (VMM) |
| Resource overhead | Minimal | ~50-100 MB per sandbox | ~100-300 MB per VM |

```bash
# Verify which runtime a pod is using
kubectl get pod <pod-name> -o jsonpath='{.spec.runtimeClassName}'

# Verify gVisor is active inside the container
kubectl exec <pod-name> -- dmesg 2>&1 | head
# gVisor shows its own kernel messages instead of Linux kernel
```

!!! tip "Exam Tip"
    To use a different container runtime, first create a `RuntimeClass` resource with the appropriate `handler`, then reference it in the pod spec with `runtimeClassName`. The exam may ask you to configure a pod to run in a gVisor sandbox. Use `scheduling.nodeSelector` to ensure pods land on nodes with the runtime installed.

### Pod-to-Pod Encryption with Cilium

Cilium provides transparent encryption of traffic between pods using either IPsec or WireGuard. Additionally, Cilium supports **Mutual Authentication** at the network policy level, ensuring that only authenticated workloads can communicate.

!!! warning "2024 Curriculum Addition"
    Cilium pod-to-pod encryption and mutual authentication were added to the CKS curriculum in October 2024.

#### Cilium Mutual Authentication

Mutual Authentication in Cilium verifies the identity of both the source and destination of a connection at the network layer, without requiring application changes.

```yaml
# Enable mutual authentication for traffic between services
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: require-mutual-auth
  namespace: app
spec:
  endpointSelector:
    matchLabels:
      type: database
  egress:
    - toEndpoints:
        - matchLabels:
            type: messenger
      authentication:
        mode: required
```

#### Verifying Cilium Encryption

```bash
# Check if encryption is enabled
cilium status | grep Encryption

# Verify encrypted traffic between pods
cilium encrypt status

# Check if WireGuard is active
cilium status --verbose | grep -i wireguard
```

!!! tip "Exam Tip"
    To enable mutual authentication in a CiliumNetworkPolicy, add the `authentication.mode: required` field to the egress or ingress rule. This ensures both ends of the connection are cryptographically verified using Cilium's identity system.

### mTLS with Service Meshes

Mutual TLS (mTLS) ensures that both the client and server authenticate each other, encrypting all inter-service communication.

#### Istio mTLS Configuration

```yaml
# Enable strict mTLS for all services in a namespace
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: STRICT
```

#### How mTLS Works

In a service mesh, each pod gets a sidecar proxy (e.g., Envoy) that handles TLS:

1. **Certificate issuance**: The mesh control plane (e.g., Istiod) issues short-lived certificates to each workload
2. **Handshake**: When Pod A calls Pod B, the sidecar proxies perform a mutual TLS handshake — both sides present and verify certificates
3. **Certificate rotation**: Certificates are automatically rotated (typically every 24 hours) without application restarts
4. **Identity verification**: The certificate's SPIFFE identity (e.g., `spiffe://cluster.local/ns/production/sa/frontend`) identifies the workload

#### mTLS Modes

| Mode | Description |
|---|---|
| `STRICT` | Only mTLS traffic is accepted |
| `PERMISSIVE` | Both plaintext and mTLS traffic are accepted (useful during migration) |
| `DISABLE` | mTLS is disabled |

```bash
# Verify mTLS status between services (Istio)
istioctl x describe pod <pod-name>

# Check proxy certificates
istioctl proxy-config secret <pod-name> -n <namespace>
```

#### Choosing Between Cilium Encryption and Service Mesh mTLS

| Aspect | Cilium Encryption | Service Mesh (Istio) |
|---|---|---|
| Layer | L3/L4 (network) | L7 (application) |
| Identity | Cilium endpoint identity | SPIFFE/x.509 certificate |
| Encryption | WireGuard or IPsec | TLS 1.2/1.3 |
| L7 policy support | Limited | Full (path, header, method) |
| Performance impact | Low (~2-5%) | Medium (~5-15%) |
| Setup complexity | Low (Cilium config) | High (control plane, sidecars) |

!!! tip "Exam Tip"
    Cilium encryption works at the network layer and requires no application changes. Service mesh mTLS provides L7 visibility and policy but adds sidecar overhead. The exam may ask about either approach — know the trade-offs.

## Practice Exercises

??? question "Exercise 1: Enforce Pod Security Standards"
    Configure the `production` namespace to:

    1. Enforce the `restricted` Pod Security Standard
    2. Audit violations against `restricted`
    3. Warn on violations against `restricted`
    4. Deploy a compliant pod

    ??? success "Solution"
        ```bash
        # Label the namespace
        kubectl label namespace production \
          pod-security.kubernetes.io/enforce=restricted \
          pod-security.kubernetes.io/enforce-version=latest \
          pod-security.kubernetes.io/audit=restricted \
          pod-security.kubernetes.io/warn=restricted

        # Verify labels
        kubectl get namespace production --show-labels
        ```

        Deploy a compliant pod:

        ```yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: compliant-app
          namespace: production
        spec:
          securityContext:
            runAsNonRoot: true
            runAsUser: 65534
            seccompProfile:
              type: RuntimeDefault
          containers:
            - name: app
              image: nginx:latest
              securityContext:
                allowPrivilegeEscalation: false
                capabilities:
                  drop:
                    - ALL
                readOnlyRootFilesystem: true
              volumeMounts:
                - name: tmp
                  mountPath: /tmp
                - name: cache
                  mountPath: /var/cache/nginx
                - name: run
                  mountPath: /var/run
          volumes:
            - name: tmp
              emptyDir: {}
            - name: cache
              emptyDir: {}
            - name: run
              emptyDir: {}
        ```

        ```bash
        kubectl apply -f compliant-app.yaml

        # Test: a non-compliant pod should be rejected
        kubectl run test --image=nginx -n production
        # Expected: Error - violates PodSecurity "restricted"
        ```

??? question "Exercise 2: Enable Secret Encryption at Rest"
    Configure the cluster to encrypt Secrets at rest using AES-CBC encryption and verify that encryption is working.

    ??? success "Solution"
        ```bash
        # Generate a 32-byte encryption key
        ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

        # Create the encryption config directory
        sudo mkdir -p /etc/kubernetes/enc
        ```

        ```yaml
        # /etc/kubernetes/enc/encryption-config.yaml
        apiVersion: apiserver.config.k8s.io/v1
        kind: EncryptionConfiguration
        resources:
          - resources:
              - secrets
            providers:
              - aescbc:
                  keys:
                    - name: key1
                      secret: <ENCRYPTION_KEY_FROM_ABOVE>
              - identity: {}
        ```

        ```bash
        # Edit the API server manifest
        sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml

        # Add the flag:
        # --encryption-provider-config=/etc/kubernetes/enc/encryption-config.yaml

        # Add volumeMount:
        # - name: enc-config
        #   mountPath: /etc/kubernetes/enc
        #   readOnly: true

        # Add volume:
        # - name: enc-config
        #   hostPath:
        #     path: /etc/kubernetes/enc
        #     type: DirectoryOrCreate

        # Wait for API server to restart
        kubectl get pods -n kube-system -w

        # Create a new secret
        kubectl create secret generic test-encryption --from-literal=key=supersecret

        # Verify it is encrypted in etcd
        ETCDCTL_API=3 etcdctl get /registry/secrets/default/test-encryption \
          --endpoints=https://127.0.0.1:2379 \
          --cacert=/etc/kubernetes/pki/etcd/ca.crt \
          --cert=/etc/kubernetes/pki/etcd/server.crt \
          --key=/etc/kubernetes/pki/etcd/server.key \
          | hexdump -C | head
        # Should NOT show "supersecret" in plaintext

        # Re-encrypt all existing secrets
        kubectl get secrets --all-namespaces -o json | kubectl replace -f -
        ```

??? question "Exercise 3: Configure a Pod with gVisor Sandbox"
    Create a RuntimeClass for gVisor and deploy a pod that uses it.

    ??? success "Solution"
        ```yaml
        # gvisor-runtimeclass.yaml
        apiVersion: node.k8s.io/v1
        kind: RuntimeClass
        metadata:
          name: gvisor
        handler: runsc
        ```

        ```yaml
        # sandboxed-nginx.yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: sandboxed-nginx
        spec:
          runtimeClassName: gvisor
          containers:
            - name: nginx
              image: nginx:latest
        ```

        ```bash
        kubectl apply -f gvisor-runtimeclass.yaml
        kubectl apply -f sandboxed-nginx.yaml

        # Verify the pod is using gVisor
        kubectl get pod sandboxed-nginx -o jsonpath='{.spec.runtimeClassName}'
        # Expected: gvisor

        # Verify inside the container (gVisor implements its own kernel)
        kubectl exec sandboxed-nginx -- dmesg | head
        # Should show gVisor kernel messages instead of Linux kernel
        ```

??? question "Exercise 4: Create an OPA Gatekeeper Constraint"
    Using OPA Gatekeeper, create a policy that prevents pods from running as root (UID 0) in the `secure` namespace.

    ??? success "Solution"
        ```yaml
        # ConstraintTemplate
        apiVersion: templates.gatekeeper.sh/v1
        kind: ConstraintTemplate
        metadata:
          name: k8sdenyroot
        spec:
          crd:
            spec:
              names:
                kind: K8sDenyRoot
          targets:
            - target: admission.k8s.gatekeeper.sh
              rego: |
                package k8sdenyroot

                violation[{"msg": msg}] {
                  container := input.review.object.spec.containers[_]
                  not container.securityContext.runAsNonRoot
                  msg := sprintf("Container %v must set runAsNonRoot to true", [container.name])
                }

                violation[{"msg": msg}] {
                  container := input.review.object.spec.containers[_]
                  container.securityContext.runAsUser == 0
                  msg := sprintf("Container %v must not run as root (UID 0)", [container.name])
                }
        ```

        ```yaml
        # Constraint
        apiVersion: constraints.gatekeeper.sh/v1beta1
        kind: K8sDenyRoot
        metadata:
          name: deny-root-in-secure
        spec:
          match:
            kinds:
              - apiGroups: [""]
                kinds: ["Pod"]
            namespaces: ["secure"]
        ```

        ```bash
        kubectl apply -f constraint-template.yaml
        kubectl apply -f constraint.yaml

        # Test: this should be denied
        kubectl run test --image=nginx -n secure
        # Expected: denied by deny-root-in-secure

        # Test: this should be allowed
        kubectl run test --image=nginx -n secure \
          --overrides='{"spec":{"containers":[{"name":"test","image":"nginx","securityContext":{"runAsNonRoot":true,"runAsUser":1000}}]}}'
        ```

??? question "Exercise 5: Mount Secrets Securely"
    Create a pod that mounts a Secret as a volume with restricted file permissions (0400) and does NOT expose secrets as environment variables. The Secret should contain a database password.

    ??? success "Solution"
        ```bash
        # Create the secret
        kubectl create secret generic db-secret \
          --from-literal=password='MyS3cur3P@ssw0rd'
        ```

        ```yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: secure-db-app
        spec:
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            seccompProfile:
              type: RuntimeDefault
          containers:
            - name: app
              image: busybox:latest
              command: ["sh", "-c", "cat /etc/db-secrets/password && sleep 3600"]
              securityContext:
                allowPrivilegeEscalation: false
                capabilities:
                  drop:
                    - ALL
                readOnlyRootFilesystem: true
              volumeMounts:
                - name: db-secret-vol
                  mountPath: /etc/db-secrets
                  readOnly: true
          volumes:
            - name: db-secret-vol
              secret:
                secretName: db-secret
                defaultMode: 0400
        ```

        ```bash
        kubectl apply -f secure-db-app.yaml

        # Verify the secret is mounted with correct permissions
        kubectl exec secure-db-app -- ls -la /etc/db-secrets/
        # Expected: -r-------- (0400 permissions)

        # Verify secret content is readable
        kubectl exec secure-db-app -- cat /etc/db-secrets/password
        # Expected: MyS3cur3P@ssw0rd
        ```

??? question "Exercise 6: Encrypt Secrets at Rest in etcd (Hands-On Lab)"
    Secrets in your cluster are currently stored unencrypted in etcd. Configure encryption at rest and verify it works.

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/etcd-encryption/setup.sh)
    ```

    **Task:**

    1. Confirm secrets are stored **unencrypted** in etcd using `etcdctl` and `hexdump`
    2. Generate a 32-byte encryption key and create an `EncryptionConfiguration` with `aescbc` provider
    3. Configure the API server to use `--encryption-provider-config`
    4. Re-encrypt all existing secrets so they are encrypted retroactively
    5. Verify secrets are now **encrypted** in etcd (hexdump should show `k8s:enc:aescbc` prefix)

    ??? success "Solution"
        Verify secrets are unencrypted:

        ```bash
        ETCDCTL_API=3 etcdctl get /registry/secrets/encryption-test/db-credentials \
          --endpoints=https://127.0.0.1:2379 \
          --cacert=/etc/kubernetes/pki/etcd/ca.crt \
          --cert=/etc/kubernetes/pki/etcd/server.crt \
          --key=/etc/kubernetes/pki/etcd/server.key | hexdump -C | head -20
        # You should see "S3cretP@ssw0rd-12345" in plaintext
        ```

        Generate encryption key and create config:

        ```bash
        ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)
        sudo mkdir -p /etc/kubernetes/enc
        ```

        ```yaml
        # /etc/kubernetes/enc/encryption-config.yaml
        apiVersion: apiserver.config.k8s.io/v1
        kind: EncryptionConfiguration
        resources:
          - resources:
              - secrets
            providers:
              - aescbc:
                  keys:
                    - name: key1
                      secret: <ENCRYPTION_KEY from above>
              - identity: {}
        ```

        Update API server manifest:

        ```bash
        sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml
        ```

        ```yaml
        spec:
          containers:
            - command:
                - kube-apiserver
                - --encryption-provider-config=/etc/kubernetes/enc/encryption-config.yaml
              volumeMounts:
                - name: enc-config
                  mountPath: /etc/kubernetes/enc
                  readOnly: true
          volumes:
            - name: enc-config
              hostPath:
                path: /etc/kubernetes/enc
                type: DirectoryOrCreate
        ```

        ```bash
        # Wait for API server to restart
        kubectl get pods -n kube-system -w

        # Re-encrypt all existing secrets
        kubectl get secrets --all-namespaces -o json | kubectl replace -f -

        # Verify encryption in etcd
        ETCDCTL_API=3 etcdctl get /registry/secrets/encryption-test/db-credentials \
          --endpoints=https://127.0.0.1:2379 \
          --cacert=/etc/kubernetes/pki/etcd/ca.crt \
          --cert=/etc/kubernetes/pki/etcd/server.crt \
          --key=/etc/kubernetes/pki/etcd/server.key | hexdump -C | head -5
        # Should show "k8s:enc:aescbc" prefix instead of plaintext
        ```

??? question "Exercise 7: Deploy a Pod with gVisor Sandbox (Hands-On Lab)"
    Use gVisor to run a container in a sandboxed runtime, isolating it from the host kernel.

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/gvisor-runtime/setup.sh)
    ```

    **Task:**

    1. Create a pod `sandboxed-nginx` that uses `runtimeClassName: gvisor`
    2. Compare kernel messages between the default and sandboxed pod using `dmesg`
    3. Compare kernel versions using `uname -r`
    4. Explain why gVisor improves security over the default runtime

    ??? success "Solution"
        ```yaml
        # sandboxed-nginx.yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: sandboxed-nginx
        spec:
          runtimeClassName: gvisor
          containers:
            - name: nginx
              image: nginx:alpine
        ```

        ```bash
        kubectl apply -f sandboxed-nginx.yaml
        kubectl wait --for=condition=Ready pod/sandboxed-nginx --timeout=60s

        # Compare kernel messages
        kubectl exec default-runtime -- dmesg | head -5
        # Shows Linux kernel boot messages

        kubectl exec sandboxed-nginx -- dmesg | head -5
        # Shows "Starting gVisor" - running in user-space kernel

        # Compare kernel versions
        kubectl exec default-runtime -- uname -r
        # Shows host Linux kernel (e.g., 6.8.0-xxx)

        kubectl exec sandboxed-nginx -- uname -r
        # Shows gVisor kernel version (e.g., 4.4.0)
        ```

        gVisor improves security by intercepting all system calls in a user-space kernel (`Sentry`), preventing the container from directly interacting with the host kernel. Even if a container escape vulnerability exists, the attacker only reaches the gVisor sandbox, not the host.

??? question "Exercise 8: Prevent Privilege Escalation (Hands-On Lab)"
    Identify and fix insecure pod configurations that allow privilege escalation.

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/privilege-escalation/setup.sh)
    ```

    **Task:**

    1. Identify all security issues in the three insecure pods in `privesc-lab`
    2. Demonstrate the risks (run `id`, `ps aux`, `mount` inside each pod)
    3. Create hardened replacements with: `runAsNonRoot`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `readOnlyRootFilesystem: true`
    4. Compare behavior with the reference pod `secure-app`

    ??? success "Solution"
        Identify vulnerabilities:

        ```bash
        # insecure-app: runs as root, privilege escalation allowed
        kubectl -n privesc-lab exec insecure-app -- id
        # uid=0(root)

        # privileged-app: full host device access
        kubectl -n privesc-lab exec privileged-app -- mount | wc -l
        # Shows many host mounts

        # hostns-app: sees host processes and network
        kubectl -n privesc-lab exec hostns-app -- ps aux | head
        # Shows ALL host processes (systemd, kubelet, etc.)
        ```

        Create hardened replacements (example for insecure-app):

        ```yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: insecure-app-fixed
          namespace: privesc-lab
        spec:
          containers:
            - name: app
              image: nginx:alpine
              securityContext:
                runAsNonRoot: true
                runAsUser: 101
                allowPrivilegeEscalation: false
                readOnlyRootFilesystem: true
                capabilities:
                  drop: ["ALL"]
              volumeMounts:
                - name: cache
                  mountPath: /var/cache/nginx
                - name: run
                  mountPath: /var/run
                - name: tmp
                  mountPath: /tmp
          volumes:
            - name: cache
              emptyDir: {}
            - name: run
              emptyDir: {}
            - name: tmp
              emptyDir: {}
        ```

        ```bash
        kubectl apply -f insecure-app-fixed.yaml

        # Verify: no longer root
        kubectl -n privesc-lab exec insecure-app-fixed -- id
        # uid=101(nginx)

        # Verify: cannot escalate
        kubectl -n privesc-lab exec insecure-app-fixed -- cat /etc/shadow
        # Permission denied
        ```

## Further Reading

- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/)
- [OPA Gatekeeper](https://open-policy-agent.github.io/gatekeeper/website/docs/)
- [Encrypting Confidential Data at Rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)
- [RuntimeClass Documentation](https://kubernetes.io/docs/concepts/containers/runtime-class/)
- [gVisor Documentation](https://gvisor.dev/docs/)
