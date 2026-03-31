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

!!! tip "Exam Tip"
    To use a different container runtime, first create a `RuntimeClass` resource with the appropriate `handler`, then reference it in the pod spec with `runtimeClassName`. The exam may ask you to configure a pod to run in a gVisor sandbox.

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

#### mTLS Modes

| Mode | Description |
|---|---|
| `STRICT` | Only mTLS traffic is accepted |
| `PERMISSIVE` | Both plaintext and mTLS traffic are accepted (useful during migration) |
| `DISABLE` | mTLS is disabled |

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

## Further Reading

- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/)
- [OPA Gatekeeper](https://open-policy-agent.github.io/gatekeeper/website/docs/)
- [Encrypting Confidential Data at Rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)
- [RuntimeClass Documentation](https://kubernetes.io/docs/concepts/containers/runtime-class/)
- [gVisor Documentation](https://gvisor.dev/docs/)
