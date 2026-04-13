# Cluster Hardening (15%)

This domain focuses on hardening the Kubernetes control plane and its components. You must understand how to implement fine-grained RBAC policies, manage ServiceAccounts securely, harden the API server through admission controllers and audit logging, and keep the cluster up to date through the kubeadm upgrade process.

## Key Concepts

### RBAC (Role-Based Access Control)

RBAC controls who can do what within a Kubernetes cluster. It uses four resource types: Role, ClusterRole, RoleBinding, and ClusterRoleBinding. The principle of **least privilege** is central to CKS exam questions.

#### Roles and ClusterRoles

A **Role** grants permissions within a specific namespace. A **ClusterRole** grants permissions cluster-wide or across all namespaces.

```yaml
# Role: allows reading pods in the "production" namespace only
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: production
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
```

```yaml
# ClusterRole: allows reading secrets across all namespaces
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: secret-reader
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list"]
```

#### RoleBindings and ClusterRoleBindings

```yaml
# RoleBinding: bind a Role to a user in a namespace
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods-binding
  namespace: production
subjects:
  - kind: User
    name: jane
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

```yaml
# ClusterRoleBinding: bind a ClusterRole to a group cluster-wide
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: read-secrets-global
subjects:
  - kind: Group
    name: auditors
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: secret-reader
  apiGroup: rbac.authorization.k8s.io
```

#### Investigating and Restricting RBAC

```bash
# Check what a user can do
kubectl auth can-i --list --as=jane
kubectl auth can-i create deployments --as=jane -n production

# Check what a ServiceAccount can do
kubectl auth can-i --list --as=system:serviceaccount:default:my-sa

# List all ClusterRoleBindings for cluster-admin
kubectl get clusterrolebindings -o json | \
  jq '.items[] | select(.roleRef.name=="cluster-admin") | .metadata.name'

# List all RoleBindings in a namespace
kubectl get rolebindings -n production -o wide
```

!!! warning "Common Pitfall"
    Be careful with ClusterRoleBindings that reference `cluster-admin`. The exam may present a scenario where a ServiceAccount or user has been granted excessive permissions. Always check both RoleBindings and ClusterRoleBindings.

!!! tip "Exam Tip"
    Use `kubectl auth can-i` extensively to verify permissions. The `--as` flag lets you impersonate any user or ServiceAccount to test RBAC rules without switching contexts.

### ServiceAccount Management

ServiceAccounts provide identities for pods. By default, every pod gets a ServiceAccount token mounted automatically, which can be a security risk if not managed properly.

#### Disable Automount of ServiceAccount Tokens

```yaml
# At the ServiceAccount level
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app-sa
  namespace: production
automountServiceAccountToken: false
```

```yaml
# At the Pod level (overrides ServiceAccount setting)
apiVersion: v1
kind: Pod
metadata:
  name: my-app
  namespace: production
spec:
  serviceAccountName: my-app-sa
  automountServiceAccountToken: false
  containers:
    - name: app
      image: my-app:latest
```

#### Create Dedicated ServiceAccounts with Minimal Permissions

```bash
# Create a ServiceAccount
kubectl create serviceaccount app-sa -n production

# Create a Role with minimal permissions
kubectl create role app-role -n production \
  --verb=get,list --resource=configmaps

# Bind the Role to the ServiceAccount
kubectl create rolebinding app-rb -n production \
  --role=app-role \
  --serviceaccount=production:app-sa
```

#### Restrict Token Audience and Expiry

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
spec:
  serviceAccountName: my-app-sa
  containers:
    - name: app
      image: my-app:latest
      volumeMounts:
        - name: token
          mountPath: /var/run/secrets/tokens
          readOnly: true
  volumes:
    - name: token
      projected:
        sources:
          - serviceAccountToken:
              path: token
              expirationSeconds: 3600
              audience: api-server
```

!!! tip "Exam Tip"
    The exam frequently asks you to disable automatic ServiceAccount token mounting. Remember you can set `automountServiceAccountToken: false` at either the ServiceAccount level or the Pod level. Setting it at the Pod level takes precedence.

### API Server Hardening

The API server is the central management point for the entire cluster. Hardening it is critical.

#### Admission Controllers

Admission controllers intercept requests to the API server before objects are persisted. They can validate, mutate, or reject requests.

```bash
# View currently enabled admission controllers
kubectl exec -n kube-system kube-apiserver-controlplane -- \
  kube-apiserver -h | grep enable-admission-plugins

# Or check the API server manifest
cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep admission
```

Key admission controllers for security:

| Admission Controller | Purpose |
|---|---|
| `NodeRestriction` | Limits kubelet to only modify its own Node and Pod objects |
| `PodSecurity` | Enforces Pod Security Standards at the namespace level |
| `ImagePolicyWebhook` | Validates container images against an external policy server |
| `EventRateLimit` | Limits the rate of events to prevent API server overload |
| `AlwaysPullImages` | Forces image pull on every pod start, preventing cached image abuse |

To enable additional admission controllers, edit the API server manifest:

```yaml
# /etc/kubernetes/manifests/kube-apiserver.yaml
spec:
  containers:
    - command:
        - kube-apiserver
        - --enable-admission-plugins=NodeRestriction,PodSecurity,ImagePolicyWebhook
        # ... other flags
```

#### Admission Webhooks

Kubernetes supports dynamic admission control through webhooks. Unlike built-in admission controllers, webhooks call external services to validate or mutate requests.

- **ValidatingWebhookConfiguration**: Rejects requests that don't meet your criteria
- **MutatingWebhookConfiguration**: Modifies requests before they are persisted (e.g., injecting sidecars, adding default labels)

```yaml
# ValidatingWebhookConfiguration: deny pods without security context
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: validate-security-context
webhooks:
  - name: validate-security-context.example.com
    admissionReviewVersions: ["v1"]
    sideEffects: None
    clientConfig:
      service:
        name: security-webhook
        namespace: kube-system
        path: /validate
      caBundle: <CA_BUNDLE_BASE64>
    rules:
      - operations: ["CREATE", "UPDATE"]
        apiGroups: [""]
        apiVersions: ["v1"]
        resources: ["pods"]
    failurePolicy: Fail
    namespaceSelector:
      matchExpressions:
        - key: kubernetes.io/metadata.name
          operator: NotIn
          values: ["kube-system"]
```

```yaml
# MutatingWebhookConfiguration: inject sidecar containers
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata:
  name: inject-sidecar
webhooks:
  - name: inject-sidecar.example.com
    admissionReviewVersions: ["v1"]
    sideEffects: None
    clientConfig:
      service:
        name: sidecar-injector
        namespace: kube-system
        path: /mutate
      caBundle: <CA_BUNDLE_BASE64>
    rules:
      - operations: ["CREATE"]
        apiGroups: [""]
        apiVersions: ["v1"]
        resources: ["pods"]
    failurePolicy: Ignore
```

Key webhook configuration fields:

| Field | Description |
|---|---|
| `failurePolicy` | `Fail` (reject if webhook unreachable) or `Ignore` (allow if webhook unreachable) |
| `namespaceSelector` | Restrict which namespaces the webhook applies to |
| `objectSelector` | Filter objects by labels |
| `timeoutSeconds` | Webhook call timeout (default 10s, max 30s) |
| `caBundle` | CA certificate to verify the webhook server's TLS certificate |
| `sideEffects` | Must be `None` or `NoneOnDryRun` for v1 webhooks |

```bash
# List all webhook configurations
kubectl get validatingwebhookconfigurations
kubectl get mutatingwebhookconfigurations

# Inspect a specific webhook
kubectl get validatingwebhookconfiguration <name> -o yaml

# Temporarily disable a webhook (for emergency debugging)
kubectl delete validatingwebhookconfiguration <name>
```

!!! warning "Common Pitfall"
    Setting `failurePolicy: Fail` on a misconfigured webhook can lock you out of the cluster entirely. Always use `namespaceSelector` to exclude `kube-system` from webhook enforcement. If locked out, manually remove the webhook resource or restart the API server with `--disable-admission-plugins`.

!!! tip "Exam Tip"
    The exam may ask you to troubleshoot why pod creation is blocked. Check webhook configurations first with `kubectl get validatingwebhookconfigurations`. Common issues: expired `caBundle`, wrong `failurePolicy`, webhook service not running, or overly broad `rules` matching system namespaces.

#### ValidatingAdmissionPolicy (CEL)

ValidatingAdmissionPolicy provides in-process admission validation using Common Expression Language (CEL) expressions, without requiring an external webhook service.

!!! info "Availability"
    ValidatingAdmissionPolicy is GA since Kubernetes v1.30. On older versions, enable the `ValidatingAdmissionPolicy` feature gate and admission plugin.

```yaml
# ValidatingAdmissionPolicy: deny containers running as root
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: deny-run-as-root
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["pods"]
  validations:
    - expression: >-
        object.spec.containers.all(c,
          has(c.securityContext) &&
          has(c.securityContext.runAsNonRoot) &&
          c.securityContext.runAsNonRoot == true)
      message: "All containers must set runAsNonRoot to true"
```

```yaml
# ValidatingAdmissionPolicyBinding: apply to specific namespaces
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: deny-run-as-root-binding
spec:
  policyName: deny-run-as-root
  validationActions:
    - Deny
  matchResources:
    namespaceSelector:
      matchLabels:
        environment: production
```

Common CEL expressions for security:

| Policy | CEL Expression |
|---|---|
| Deny privileged | `object.spec.containers.all(c, !has(c.securityContext) \|\| !has(c.securityContext.privileged) \|\| c.securityContext.privileged != true)` |
| Deny hostNetwork | `!has(object.spec.hostNetwork) \|\| object.spec.hostNetwork == false` |
| Require image registry | `object.spec.containers.all(c, c.image.startsWith('registry.example.com/'))` |
| Require resource limits | `object.spec.containers.all(c, has(c.resources) && has(c.resources.limits))` |

!!! tip "Exam Tip"
    ValidatingAdmissionPolicy requires two resources: the **policy** (CEL expression) and the **binding** (applies it to namespaces/resources). The `validationActions` can be `Deny`, `Warn`, or `Audit`, similar to Pod Security Admission modes.

#### API Server Audit Logging

Audit logging records all requests to the API server, providing an audit trail for security investigations.

```yaml
# /etc/kubernetes/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # Log all requests to secrets at the Metadata level
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets"]

  # Log pod changes at the RequestResponse level
  - level: RequestResponse
    resources:
      - group: ""
        resources: ["pods"]
    verbs: ["create", "update", "patch", "delete"]

  # Log everything else at the Request level
  - level: Request
    resources:
      - group: ""
        resources: ["configmaps"]

  # Default: log at Metadata level
  - level: Metadata
    omitStages:
      - RequestReceived
```

Enable audit logging in the API server manifest:

```yaml
# /etc/kubernetes/manifests/kube-apiserver.yaml
spec:
  containers:
    - command:
        - kube-apiserver
        - --audit-policy-file=/etc/kubernetes/audit-policy.yaml
        - --audit-log-path=/var/log/kubernetes/audit/audit.log
        - --audit-log-maxage=30
        - --audit-log-maxbackup=10
        - --audit-log-maxsize=100
      volumeMounts:
        - name: audit-policy
          mountPath: /etc/kubernetes/audit-policy.yaml
          readOnly: true
        - name: audit-log
          mountPath: /var/log/kubernetes/audit
  volumes:
    - name: audit-policy
      hostPath:
        path: /etc/kubernetes/audit-policy.yaml
        type: File
    - name: audit-log
      hostPath:
        path: /var/log/kubernetes/audit
        type: DirectoryOrCreate
```

!!! warning "Common Pitfall"
    When modifying the API server manifest (`/etc/kubernetes/manifests/kube-apiserver.yaml`), the API server pod will restart automatically. Always verify the pod comes back up with `kubectl get pods -n kube-system`. If it does not, check the logs with `crictl logs` or `journalctl -u kubelet`. Missing volume mounts for audit policy files are a common cause of failure.

#### Audit Log Levels

| Level | What is Logged |
|---|---|
| `None` | Nothing |
| `Metadata` | Request metadata (user, timestamp, resource, verb) but not request/response body |
| `Request` | Metadata + request body |
| `RequestResponse` | Metadata + request body + response body |

### API Server TLS Configuration

The API server supports configuring TLS minimum version and cipher suites to enforce strong encryption.

```bash
# Set TLS minimum version to 1.3 in the API server manifest
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml
```

```yaml
# /etc/kubernetes/manifests/kube-apiserver.yaml
spec:
  containers:
    - command:
        - kube-apiserver
        - --tls-min-version=VersionTLS13
        # Or for TLS 1.2 minimum:
        # - --tls-min-version=VersionTLS12
        # Optionally restrict cipher suites (TLS 1.2 only, TLS 1.3 has fixed ciphers):
        # - --tls-cipher-suites=TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
```

```bash
# Verify TLS settings after API server restart
# Test that TLS 1.2 is rejected when min version is 1.3
curl --tls-max 1.2 --tlsv1.2 -k https://localhost:6443/healthz
# Expected: SSL error / connection refused

# Test that TLS 1.3 works
curl --tlsv1.3 -k https://localhost:6443/healthz
# Expected: ok
```

| TLS Flag Value | Version |
|---|---|
| `VersionTLS10` | TLS 1.0 |
| `VersionTLS11` | TLS 1.1 |
| `VersionTLS12` | TLS 1.2 |
| `VersionTLS13` | TLS 1.3 |

!!! tip "Exam Tip"
    The exam may ask you to set the TLS minimum version and then verify it with `curl`. Remember that `--tls-min-version` uses Go-style version names (`VersionTLS13`), not numeric versions. The kubelet and etcd also support similar flags: `--tls-min-version`.

### CertificateSigningRequests

Kubernetes provides a built-in API for managing TLS certificates through CertificateSigningRequests (CSRs). This allows you to issue, approve, and deny certificates within the cluster.

#### Creating and Approving a CSR

```bash
# Generate a private key and CSR
openssl genrsa -out myuser.key 2048
openssl req -new -key myuser.key -out myuser.csr -subj "/CN=myuser/O=developers"

# Encode the CSR for the Kubernetes API
CSR_CONTENT=$(cat myuser.csr | base64 | tr -d '\n')
```

```yaml
# csr.yaml
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: myuser
spec:
  request: <BASE64_ENCODED_CSR>
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400  # 24 hours
  usages:
    - client auth
```

```bash
# Create the CSR
kubectl apply -f csr.yaml

# View pending CSRs
kubectl get csr

# Approve the CSR
kubectl certificate approve myuser

# Deny a CSR
kubectl certificate deny myuser

# Download the signed certificate
kubectl get csr myuser -o jsonpath='{.status.certificate}' | base64 -d > myuser.crt

# View the certificate details
openssl x509 -in myuser.crt -text -noout
```

#### Common Signer Names

| Signer | Purpose |
|---|---|
| `kubernetes.io/kube-apiserver-client` | Client certificates for authenticating to the API server |
| `kubernetes.io/kube-apiserver-client-kubelet` | Client certificates for kubelets |
| `kubernetes.io/kubelet-serving` | Serving certificates for kubelets |

!!! tip "Exam Tip"
    When creating a CSR, the `signerName` must match the intended use. For user authentication, use `kubernetes.io/kube-apiserver-client`. The `usages` field must include `client auth` for client certificates or `server auth` for server certificates. To extract the CN (Common Name) from an existing CSR file: `openssl req -in file.csr -noout -subject`.

### API Server Authorization Modes

The API server supports multiple authorization modes configured via `--authorization-mode`. Modes are evaluated in order — if one authorizer has no opinion, the request passes to the next.

```yaml
# /etc/kubernetes/manifests/kube-apiserver.yaml
spec:
  containers:
    - command:
        - kube-apiserver
        - --authorization-mode=Node,RBAC
```

| Mode | Description |
|---|---|
| `Node` | Authorizes kubelet API requests based on pods scheduled to the node |
| `RBAC` | Role-based access control using Roles, ClusterRoles, and Bindings |
| `Webhook` | Delegates authorization to an external HTTP service |
| `ABAC` | Attribute-based access control using static policy files (legacy) |
| `AlwaysAllow` | Allows all requests (insecure, only for testing) |
| `AlwaysDeny` | Denies all requests (only for testing) |

#### Node Authorization

The Node authorizer restricts kubelets to only access resources related to pods scheduled on their node. It works together with the `NodeRestriction` admission controller.

What Node authorization restricts:

- Kubelets can only read Secrets, ConfigMaps, PVs, and PVCs referenced by pods bound to their node
- Kubelets can only modify their own Node object and Pod status for pods on their node
- Kubelets cannot access resources for pods on other nodes

```bash
# Verify current authorization modes
cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep authorization-mode
# Expected: --authorization-mode=Node,RBAC
```

!!! warning "Common Pitfall"
    Removing `Node` from `--authorization-mode` weakens kubelet isolation. A compromised kubelet could then access Secrets for pods on other nodes. Always keep `Node` authorization enabled.

#### Webhook Authorization

Webhook authorization delegates authorization decisions to an external service via HTTP callbacks.

```yaml
# /etc/kubernetes/webhook-authz-config.yaml
apiVersion: v1
kind: Config
clusters:
  - name: authz-webhook
    cluster:
      server: https://authz.example.com/authorize
      certificate-authority: /etc/kubernetes/pki/authz-ca.crt
users:
  - name: api-server
    user:
      client-certificate: /etc/kubernetes/pki/authz-client.crt
      client-key: /etc/kubernetes/pki/authz-client.key
current-context: webhook
contexts:
  - context:
      cluster: authz-webhook
      user: api-server
    name: webhook
```

```yaml
# Enable in API server manifest
spec:
  containers:
    - command:
        - kube-apiserver
        - --authorization-mode=Node,Webhook,RBAC
        - --authorization-webhook-config-file=/etc/kubernetes/webhook-authz-config.yaml
```

!!! tip "Exam Tip"
    The default authorization mode for kubeadm clusters is `Node,RBAC`. Modes are evaluated in order — `Node` should always come before `RBAC` to ensure kubelet requests are properly scoped. Use `kubectl auth can-i` to test authorization for any user or ServiceAccount.

### Upgrading Kubernetes with kubeadm

Keeping Kubernetes up to date is critical for security. The upgrade process follows a specific order: control plane first, then worker nodes.

#### Upgrade Process (Control Plane)

```bash
# 1. Check available versions
sudo apt update
sudo apt-cache madison kubeadm

# 2. Upgrade kubeadm
sudo apt-mark unhold kubeadm
sudo apt-get update && sudo apt-get install -y kubeadm=1.31.0-1.1
sudo apt-mark hold kubeadm

# 3. Verify the upgrade plan
sudo kubeadm upgrade plan

# 4. Apply the upgrade
sudo kubeadm upgrade apply v1.31.0

# 5. Drain the control plane node
kubectl drain <control-plane-node> --ignore-daemonsets --delete-emptydir-data

# 6. Upgrade kubelet and kubectl
sudo apt-mark unhold kubelet kubectl
sudo apt-get update && sudo apt-get install -y kubelet=1.31.0-1.1 kubectl=1.31.0-1.1
sudo apt-mark hold kubelet kubectl

# 7. Restart kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# 8. Uncordon the node
kubectl uncordon <control-plane-node>
```

#### Upgrade Process (Worker Nodes)

```bash
# 1. Upgrade kubeadm on the worker node
sudo apt-mark unhold kubeadm
sudo apt-get update && sudo apt-get install -y kubeadm=1.31.0-1.1
sudo apt-mark hold kubeadm

# 2. Upgrade the node configuration
sudo kubeadm upgrade node

# 3. Drain the worker node (run from control plane)
kubectl drain <worker-node> --ignore-daemonsets --delete-emptydir-data

# 4. Upgrade kubelet and kubectl
sudo apt-mark unhold kubelet kubectl
sudo apt-get update && sudo apt-get install -y kubelet=1.31.0-1.1 kubectl=1.31.0-1.1
sudo apt-mark hold kubelet kubectl

# 5. Restart kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# 6. Uncordon the worker node (run from control plane)
kubectl uncordon <worker-node>
```

!!! tip "Exam Tip"
    The upgrade sequence matters: always upgrade the control plane before worker nodes. You can only skip one minor version at a time (e.g., 1.29 to 1.30, not 1.29 to 1.31). Practice the full upgrade workflow, including draining and uncordoning nodes.

## Practice Exercises

??? question "Exercise 1: Restrict RBAC Permissions"
    A ServiceAccount named `deploy-sa` in the `staging` namespace currently has a ClusterRoleBinding to `cluster-admin`. Fix this by:

    1. Removing the ClusterRoleBinding
    2. Creating a Role that only allows `get`, `list`, `create`, and `update` on Deployments in the `staging` namespace
    3. Binding the Role to the ServiceAccount

    ??? success "Solution"
        ```bash
        # Find and delete the overprivileged ClusterRoleBinding
        kubectl get clusterrolebindings -o json | \
          jq -r '.items[] | select(.subjects[]?.name=="deploy-sa" and .subjects[]?.namespace=="staging") | .metadata.name'

        kubectl delete clusterrolebinding <binding-name>

        # Create a restrictive Role
        kubectl create role deploy-manager -n staging \
          --verb=get,list,create,update \
          --resource=deployments

        # Bind the Role to the ServiceAccount
        kubectl create rolebinding deploy-manager-binding -n staging \
          --role=deploy-manager \
          --serviceaccount=staging:deploy-sa

        # Verify
        kubectl auth can-i create deployments --as=system:serviceaccount:staging:deploy-sa -n staging
        # yes

        kubectl auth can-i delete deployments --as=system:serviceaccount:staging:deploy-sa -n staging
        # no

        kubectl auth can-i create deployments --as=system:serviceaccount:staging:deploy-sa -n default
        # no
        ```

??? question "Exercise 2: Disable ServiceAccount Token Automount"
    In the `secure` namespace, there are multiple pods using the `default` ServiceAccount. Ensure that:

    1. The `default` ServiceAccount does not automount tokens
    2. An existing pod named `web-app` explicitly disables token mounting

    ??? success "Solution"
        ```bash
        # Patch the default ServiceAccount
        kubectl patch serviceaccount default -n secure \
          -p '{"automountServiceAccountToken": false}'

        # Edit the existing pod (you need to recreate it)
        kubectl get pod web-app -n secure -o yaml > web-app.yaml
        ```

        Edit `web-app.yaml` to add `automountServiceAccountToken: false`:

        ```yaml
        spec:
          automountServiceAccountToken: false
          containers:
            - name: web-app
              # ... existing config
        ```

        ```bash
        kubectl delete pod web-app -n secure
        kubectl apply -f web-app.yaml

        # Verify no token is mounted
        kubectl exec web-app -n secure -- ls /var/run/secrets/kubernetes.io/serviceaccount/
        # Should fail or show no token
        ```

??? question "Exercise 3: Configure API Server Audit Logging"
    Configure the API server to audit log with the following policy:

    1. Log all Secret access at the `Metadata` level
    2. Log all changes to pods at the `RequestResponse` level
    3. Do not log read-only requests to ConfigMaps
    4. Log everything else at the `Request` level

    ??? success "Solution"
        Create the audit policy file:

        ```yaml
        # /etc/kubernetes/audit-policy.yaml
        apiVersion: audit.k8s.io/v1
        kind: Policy
        rules:
          - level: Metadata
            resources:
              - group: ""
                resources: ["secrets"]

          - level: RequestResponse
            resources:
              - group: ""
                resources: ["pods"]
            verbs: ["create", "update", "patch", "delete"]

          - level: None
            resources:
              - group: ""
                resources: ["configmaps"]
            verbs: ["get", "list", "watch"]

          - level: Request
        ```

        Update the API server manifest:

        ```bash
        sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml
        ```

        Add these flags and volume mounts:

        ```yaml
        spec:
          containers:
            - command:
                - kube-apiserver
                - --audit-policy-file=/etc/kubernetes/audit-policy.yaml
                - --audit-log-path=/var/log/kubernetes/audit/audit.log
                - --audit-log-maxage=30
                - --audit-log-maxbackup=3
                - --audit-log-maxsize=100
              volumeMounts:
                - name: audit-policy
                  mountPath: /etc/kubernetes/audit-policy.yaml
                  readOnly: true
                - name: audit-log
                  mountPath: /var/log/kubernetes/audit
          volumes:
            - name: audit-policy
              hostPath:
                path: /etc/kubernetes/audit-policy.yaml
                type: File
            - name: audit-log
              hostPath:
                path: /var/log/kubernetes/audit
                type: DirectoryOrCreate
        ```

        ```bash
        # Wait for API server to restart
        kubectl get pods -n kube-system -w

        # Verify audit logs are being generated
        sudo tail -f /var/log/kubernetes/audit/audit.log | jq .
        ```

??? question "Exercise 4: Upgrade Kubernetes Cluster"
    Upgrade a cluster from v1.30.0 to v1.31.0. The cluster has one control plane node (`controlplane`) and one worker node (`node01`).

    ??? success "Solution"
        ```bash
        # === Control Plane ===
        # Upgrade kubeadm
        sudo apt-mark unhold kubeadm
        sudo apt-get update && sudo apt-get install -y kubeadm=1.31.0-1.1
        sudo apt-mark hold kubeadm

        # Check upgrade plan
        sudo kubeadm upgrade plan

        # Apply upgrade
        sudo kubeadm upgrade apply v1.31.0

        # Drain control plane
        kubectl drain controlplane --ignore-daemonsets --delete-emptydir-data

        # Upgrade kubelet and kubectl
        sudo apt-mark unhold kubelet kubectl
        sudo apt-get install -y kubelet=1.31.0-1.1 kubectl=1.31.0-1.1
        sudo apt-mark hold kubelet kubectl
        sudo systemctl daemon-reload
        sudo systemctl restart kubelet

        # Uncordon
        kubectl uncordon controlplane

        # === Worker Node (SSH into node01) ===
        ssh node01

        sudo apt-mark unhold kubeadm
        sudo apt-get update && sudo apt-get install -y kubeadm=1.31.0-1.1
        sudo apt-mark hold kubeadm
        sudo kubeadm upgrade node

        # Back on control plane: drain worker
        # (exit ssh first)
        kubectl drain node01 --ignore-daemonsets --delete-emptydir-data

        # SSH back to worker
        ssh node01
        sudo apt-mark unhold kubelet kubectl
        sudo apt-get install -y kubelet=1.31.0-1.1 kubectl=1.31.0-1.1
        sudo apt-mark hold kubelet kubectl
        sudo systemctl daemon-reload
        sudo systemctl restart kubelet
        exit

        # Uncordon worker
        kubectl uncordon node01

        # Verify
        kubectl get nodes
        ```

??? question "Exercise 5: Create a ValidatingWebhookConfiguration (Hands-On Lab)"
    A webhook server is running in namespace `webhook` that rejects pods without `runAsNonRoot: true` in their security context.

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/validating-webhook/setup.sh)
    ```

    **Task:**

    1. Get the CA bundle from the webhook-server TLS secret in namespace `webhook`
    2. Create a `ValidatingWebhookConfiguration` that:
        - Points to service `webhook-server` in namespace `webhook`, path `/validate`
        - Uses the CA bundle from step 1
        - Only applies to pods in namespace `webhook-test` (use `namespaceSelector`)
        - Uses `failurePolicy: Fail`
    3. Test: Create a pod in `webhook-test` **without** `runAsNonRoot` — should be **denied**
    4. Test: Create a pod in `webhook-test` **with** `runAsNonRoot: true` — should be **allowed**

    ??? success "Solution"
        Get the CA bundle:

        ```bash
        CA_BUNDLE=$(kubectl -n webhook get secret webhook-server-tls \
          -o jsonpath='{.data.tls\.crt}')
        echo "${CA_BUNDLE}"
        ```

        Create the `ValidatingWebhookConfiguration`:

        ```yaml
        # validating-webhook.yaml
        apiVersion: admissionregistration.k8s.io/v1
        kind: ValidatingWebhookConfiguration
        metadata:
          name: enforce-run-as-non-root
        webhooks:
          - name: enforce-run-as-non-root.webhook.svc
            admissionReviewVersions: ["v1"]
            sideEffects: None
            failurePolicy: Fail
            clientConfig:
              service:
                name: webhook-server
                namespace: webhook
                path: /validate
              caBundle: <CA_BUNDLE from above>
            rules:
              - operations: ["CREATE"]
                apiGroups: [""]
                apiVersions: ["v1"]
                resources: ["pods"]
            namespaceSelector:
              matchLabels:
                kubernetes.io/metadata.name: webhook-test
        ```

        ```bash
        # Apply (replace <CA_BUNDLE> with the actual value)
        kubectl apply -f validating-webhook.yaml

        # Test: pod WITHOUT runAsNonRoot (should be DENIED)
        kubectl -n webhook-test run test-denied --image=nginx
        # Expected: Error - container 'test-denied' must set
        #           securityContext.runAsNonRoot to true

        # Test: pod WITH runAsNonRoot (should be ALLOWED)
        kubectl -n webhook-test run test-allowed --image=nginx \
          --overrides='{"spec":{"securityContext":{"runAsNonRoot":true}}}'
        # Expected: pod/test-allowed created
        ```

??? question "Exercise 6: Troubleshoot a Crashed API Server (Hands-On Lab)"
    The API server has been misconfigured and is no longer starting. Diagnose and fix the issue without using `kubectl` (which won't work while the API server is down).

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/apiserver-crash/setup.sh)
    ```

    !!! warning
        This lab intentionally breaks the API server. A backup of the manifest is saved automatically.

    **Task:**

    1. Diagnose why the API server is not starting (without `kubectl`)
    2. Fix the misconfiguration in `/etc/kubernetes/manifests/kube-apiserver.yaml`
    3. Verify the API server recovers

    ??? success "Solution"
        When `kubectl` is not available, use these tools to diagnose:

        ```bash
        # Check if the API server container is crash-looping
        crictl ps -a | grep apiserver

        # Read the container logs
        CONTAINER_ID=$(crictl ps -a --name kube-apiserver -q | head -1)
        crictl logs ${CONTAINER_ID}
        # The error message will point to the misconfiguration

        # Check kubelet logs for static pod errors
        journalctl -u kubelet --since '5 minutes ago' | grep -i error | tail -20

        # Inspect the manifest directly
        cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep -E 'admission|etcd-servers|tls-cert'
        ```

        Common misconfigurations and fixes:

        - **Invalid admission plugin**: Remove the unknown plugin name from `--enable-admission-plugins`
        - **Wrong etcd endpoint**: Fix `--etcd-servers` to `https://127.0.0.1:2379`
        - **Missing certificate**: Fix `--tls-cert-file` to the correct path (e.g., `/etc/kubernetes/pki/apiserver.crt`)

        ```bash
        # Fix the manifest
        sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml

        # Wait for recovery (kubelet watches the manifest directory)
        crictl ps | grep apiserver
        # Once the container is running:
        kubectl get nodes
        ```

        If stuck, restore the backup:

        ```bash
        sudo cp /etc/kubernetes/kube-apiserver.yaml.backup \
          /etc/kubernetes/manifests/kube-apiserver.yaml
        ```

??? question "Exercise 7: Handle CertificateSigningRequests (Hands-On Lab)"
    Two CSRs have been submitted to the cluster. One is a legitimate developer request, the other is a suspicious attempt to gain cluster-admin access. Inspect, approve/deny, and configure access.

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/csr/setup.sh)
    ```

    **Task:**

    1. Inspect both pending CSRs — decode the request to see the subject (CN and O)
    2. Identify the suspicious CSR (`O=system:masters` = cluster-admin!) and **deny** it
    3. **Approve** the legitimate developer CSR
    4. Extract the signed certificate
    5. Create a kubeconfig entry for the developer and verify RBAC works (access to `development` namespace only)

    ??? success "Solution"
        Inspect the CSRs:

        ```bash
        kubectl get csr
        # NAME              AGE   SIGNERNAME                            REQUESTOR          CONDITION
        # admin-backdoor    ...   kubernetes.io/kube-apiserver-client   kubernetes-admin   Pending
        # developer-jane    ...   kubernetes.io/kube-apiserver-client   kubernetes-admin   Pending

        # Decode the subject of each CSR
        kubectl get csr developer-jane -o jsonpath='{.spec.request}' \
          | base64 -d | openssl req -noout -subject
        # subject=CN=developer-jane, O=development

        kubectl get csr admin-backdoor -o jsonpath='{.spec.request}' \
          | base64 -d | openssl req -noout -subject
        # subject=CN=admin-backdoor, O=system:masters
        # DANGER: O=system:masters grants cluster-admin!
        ```

        Deny the suspicious CSR, approve the legitimate one:

        ```bash
        kubectl certificate deny admin-backdoor
        kubectl certificate approve developer-jane

        kubectl get csr
        # admin-backdoor: Denied
        # developer-jane: Approved,Issued
        ```

        Extract the signed certificate:

        ```bash
        kubectl get csr developer-jane -o jsonpath='{.status.certificate}' \
          | base64 -d > /root/csr-lab/developer.crt

        # Verify the certificate
        openssl x509 -in /root/csr-lab/developer.crt -noout -subject -issuer
        # subject=CN=developer-jane, O=development
        # issuer=CN=kubernetes (signed by cluster CA)
        ```

        Configure kubeconfig and verify access:

        ```bash
        # Add credentials
        kubectl config set-credentials developer-jane \
          --client-certificate=/root/csr-lab/developer.crt \
          --client-key=/root/csr-lab/developer.key

        # Add context
        kubectl config set-context developer \
          --cluster=kubernetes \
          --user=developer-jane \
          --namespace=development

        # Test: should work (Role grants access to development namespace)
        kubectl --context=developer get pods -n development
        # No resources found in development namespace.

        # Test: should be denied (no access outside development)
        kubectl --context=developer get pods -n kube-system
        # Error from server (Forbidden)

        kubectl --context=developer get nodes
        # Error from server (Forbidden)

        # Verify with can-i
        kubectl auth can-i create deployments \
          --as=developer-jane -n development
        # yes

        kubectl auth can-i create deployments \
          --as=developer-jane -n default
        # no
        ```

## Further Reading

- [Kubernetes RBAC Documentation](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [ServiceAccount Documentation](https://kubernetes.io/docs/concepts/security/service-accounts/)
- [CertificateSigningRequest Documentation](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/)
- [Admission Controllers Reference](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/)
- [Dynamic Admission Control (Webhooks)](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/)
- [ValidatingAdmissionPolicy](https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/)
- [Authorization Overview](https://kubernetes.io/docs/reference/access-authn-authz/authorization/)
- [Node Authorization](https://kubernetes.io/docs/reference/access-authn-authz/node/)
- [Kubernetes Auditing](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/)
- [Kubeadm Upgrade Guide](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)
