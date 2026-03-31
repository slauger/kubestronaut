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

## Further Reading

- [Kubernetes RBAC Documentation](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [ServiceAccount Documentation](https://kubernetes.io/docs/concepts/security/service-accounts/)
- [Admission Controllers Reference](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/)
- [Kubernetes Auditing](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/)
- [Kubeadm Upgrade Guide](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)
