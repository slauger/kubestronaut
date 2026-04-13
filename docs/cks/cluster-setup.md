# Cluster Setup (15%)

This domain covers the foundational security measures applied when setting up and configuring a Kubernetes cluster. You need to know how to restrict network traffic with NetworkPolicies, run CIS Benchmark checks, secure Ingress resources with TLS, protect node metadata from pods, lock down dashboard access, and verify the integrity of Kubernetes platform binaries.

## Key Concepts

### NetworkPolicies

NetworkPolicies are Kubernetes resources that control traffic flow between pods and between pods and external endpoints. By default, all pods can communicate with each other. NetworkPolicies allow you to implement a zero-trust network model.

!!! warning "CNI Requirement"
    NetworkPolicies require a CNI plugin that supports them (e.g., Calico, Cilium, Weave Net). If your cluster uses Flannel without additional plugins, NetworkPolicies will have no effect.

#### Default Deny All Ingress Traffic

The first step in securing a namespace is applying a default deny policy:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Ingress
```

#### Default Deny All Egress Traffic

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Egress
```

#### Default Deny All Traffic (Ingress and Egress)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

#### Allow Specific Traffic

After applying a deny-all policy, selectively allow required traffic:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - protocol: TCP
          port: 8080
```

#### Allow DNS Egress

When using egress deny-all, pods cannot resolve DNS. You must explicitly allow DNS traffic:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to: []
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

!!! tip "Exam Tip"
    In the exam, always apply a default deny policy first, then create allow rules for the specific traffic patterns described in the task. Remember to allow DNS egress if pods need name resolution.

### CiliumNetworkPolicy

Cilium is a CNI plugin that provides advanced networking, security, and observability for Kubernetes. CiliumNetworkPolicies extend standard Kubernetes NetworkPolicies with Layer 3/4/7 filtering, CIDR-based rules, identity-aware policies, and DNS-aware egress controls.

!!! warning "2024 Curriculum Addition"
    CiliumNetworkPolicy was added to the CKS curriculum in October 2024. It is a key topic for securing pod-to-pod communication and protecting metadata endpoints.

#### CiliumNetworkPolicy vs Kubernetes NetworkPolicy

| Feature | Kubernetes NetworkPolicy | CiliumNetworkPolicy |
|---|---|---|
| Layer 3 (IP) | Yes | Yes |
| Layer 4 (Port/Protocol) | Yes | Yes |
| Layer 7 (HTTP, DNS) | No | Yes |
| CIDR-based deny | Via `except` only | Native deny rules |
| DNS-aware egress | No | Yes |
| Identity-based | Label selectors only | Cilium identity + labels |
| Mutual Authentication | No | Yes |

#### Default Deny with CiliumNetworkPolicy

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  endpointSelector: {}
  ingressDeny:
    - fromEntities:
        - world
  egressDeny:
    - toEntities:
        - world
```

#### Allow Specific Egress with CIDR Deny

A common exam pattern is allowing general egress while blocking access to a metadata service endpoint:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: block-metadata
  namespace: app
spec:
  endpointSelector: {}
  egress:
    # Allow all egress traffic
    - toCIDR:
        - 0.0.0.0/0
    # Allow egress to endpoints in same namespace
    - toEndpoints:
        - matchLabels: {}
    # Allow egress to kube-system namespace
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
  egressDeny:
    # Deny access to metadata service
    - toCIDR:
        - 192.168.100.21/32
      toPorts:
        - ports:
            - port: "9055"
              protocol: TCP
```

#### Layer 4 Rules (Port and Protocol Filtering)

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: deny-icmp-to-database
  namespace: app
spec:
  endpointSelector:
    matchLabels:
      app: transmitter
  egressDeny:
    - toEndpoints:
        - matchLabels:
            app: database
      icmps:
        - fields:
            - type: 8
              family: IPv4
```

#### Cross-Namespace Policies

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-monitoring
  namespace: app
spec:
  endpointSelector:
    matchLabels:
      app: backend
  ingress:
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: monitoring
            app: prometheus
      toPorts:
        - ports:
            - port: "9090"
              protocol: TCP
```

!!! tip "Exam Tip"
    CiliumNetworkPolicy uses `endpointSelector` instead of `podSelector`. When referencing pods in other namespaces, use the label `io.kubernetes.pod.namespace: <namespace>` in the endpoint selector. Remember that `egress` rules allow traffic while `egressDeny` rules explicitly block it — deny rules take precedence over allow rules.

#### Useful Cilium Debugging Commands

```bash
# Check Cilium status
cilium status

# List Cilium endpoints
cilium endpoint list

# Check policy enforcement for a specific endpoint
cilium endpoint get <endpoint-id>

# Monitor traffic in real time
cilium monitor --type policy-verdict
```

### CIS Benchmarks with kube-bench

The CIS (Center for Internet Security) Kubernetes Benchmark provides prescriptive guidance for hardening Kubernetes clusters. **kube-bench** is a tool that checks whether your cluster meets these benchmarks.

#### Running kube-bench

```bash
# Run kube-bench as a job on the cluster
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml

# View results
kubectl logs job/kube-bench

# Run kube-bench directly on a node (if installed)
kube-bench run --targets master
kube-bench run --targets node

# Run specific checks
kube-bench run --targets master --check 1.2.1,1.2.2

# Run kube-bench as a container
docker run --pid=host -v /etc:/etc:ro -v /var:/var:ro \
  -t aquasec/kube-bench:latest run --targets master
```

#### Remediating kube-bench Findings

Common remediations involve modifying API server, kubelet, or etcd configuration:

```bash
# Example: Ensure audit logging is enabled (CIS 1.2.22)
# Edit the API server manifest
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml

# Add or modify these flags:
# --audit-log-path=/var/log/kubernetes/audit.log
# --audit-log-maxage=30
# --audit-log-maxbackup=10
# --audit-log-maxsize=100
```

### Ingress with TLS

Securing Ingress resources with TLS ensures encrypted communication to your services.

#### Creating a TLS Secret

```bash
# Generate a self-signed certificate (for testing)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=myapp.example.com/O=myorg"

# Create a TLS secret
kubectl create secret tls myapp-tls \
  --cert=tls.crt \
  --key=tls.key \
  -n production
```

#### Configuring Ingress with TLS

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  tls:
    - hosts:
        - myapp.example.com
      secretName: myapp-tls
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp-service
                port:
                  number: 443
```

### Node Metadata Protection

Cloud providers expose instance metadata APIs (e.g., `169.254.169.254`) that can leak sensitive information such as IAM credentials. Pods should be prevented from accessing these endpoints.

#### Block Metadata Access with NetworkPolicy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-metadata-access
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 169.254.169.254/32
```

!!! tip "Exam Tip"
    The metadata endpoint `169.254.169.254` is the standard cloud metadata IP across AWS, GCP, and Azure. Blocking it via NetworkPolicy is the most common exam approach.

### Securing etcd

etcd stores all Kubernetes cluster state including Secrets, ConfigMaps, and RBAC policies. Access to etcd means full control of the cluster.

#### etcd TLS Configuration

etcd should use TLS for both client-to-server and peer-to-peer communication. In kubeadm clusters, this is configured by default.

```yaml
# /etc/kubernetes/manifests/etcd.yaml (typical kubeadm configuration)
spec:
  containers:
    - command:
        - etcd
        - --cert-file=/etc/kubernetes/pki/etcd/server.crt
        - --key-file=/etc/kubernetes/pki/etcd/server.key
        - --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
        - --client-cert-auth=true
        - --peer-cert-file=/etc/kubernetes/pki/etcd/peer.crt
        - --peer-key-file=/etc/kubernetes/pki/etcd/peer.key
        - --peer-trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
        - --peer-client-cert-auth=true
        - --listen-client-urls=https://127.0.0.1:2379,https://<node-ip>:2379
```

Key etcd TLS flags:

| Flag | Purpose |
|---|---|
| `--cert-file` / `--key-file` | Server TLS certificate and key |
| `--trusted-ca-file` | CA certificate for verifying client certificates |
| `--client-cert-auth=true` | Require client certificate authentication |
| `--peer-cert-file` / `--peer-key-file` | Peer TLS certificate and key (cluster communication) |
| `--peer-trusted-ca-file` | CA certificate for verifying peer certificates |
| `--peer-client-cert-auth=true` | Require peer client certificate authentication |

#### Restricting etcd Network Access

```bash
# Verify etcd is only listening on expected interfaces
ss -tlnp | grep 2379

# Verify the API server connects to etcd via TLS
cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep etcd
# Should show:
#   --etcd-servers=https://127.0.0.1:2379
#   --etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt
#   --etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt
#   --etcd-keyfile=/etc/kubernetes/pki/apiserver-etcd-client.key

# Test etcd connectivity (requires client certificates)
ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

!!! warning "Common Pitfall"
    etcd should never be exposed to the public network. Verify that `--listen-client-urls` only includes `127.0.0.1` and the node's internal IP. If etcd is accessible without client certificates, an attacker can read all cluster Secrets directly.

!!! tip "Exam Tip"
    The exam may ask you to verify or fix etcd security settings. Check the etcd static pod manifest at `/etc/kubernetes/manifests/etcd.yaml`. Ensure `--client-cert-auth=true` is set and that the API server uses TLS to connect. Use `etcdctl endpoint health` with the correct certificates to verify connectivity.

### GUI Element Security (Kubernetes Dashboard)

The Kubernetes Dashboard is a web-based UI that, if misconfigured, can provide full cluster access to attackers.

#### Securing the Dashboard

Key security measures:

```bash
# Deploy dashboard with restricted access
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# Verify the dashboard is only accessible via kubectl proxy or port-forward
kubectl -n kubernetes-dashboard get svc

# Create a read-only ServiceAccount for dashboard access
kubectl create serviceaccount dashboard-viewer -n kubernetes-dashboard
kubectl create clusterrolebinding dashboard-viewer-binding \
  --clusterrole=view \
  --serviceaccount=kubernetes-dashboard:dashboard-viewer
```

!!! warning "Common Pitfall"
    Never deploy the dashboard with `--enable-skip-login` or bind it to `cluster-admin`. In exam scenarios, you may be asked to identify or fix insecure dashboard configurations.

### Verifying Platform Binaries

You should verify Kubernetes binaries against their published checksums to ensure they have not been tampered with.

```bash
# Download the binary and its checksum
VERSION="v1.31.0"
curl -LO "https://dl.k8s.io/${VERSION}/bin/linux/amd64/kubectl"
curl -LO "https://dl.k8s.io/${VERSION}/bin/linux/amd64/kubectl.sha256"

# Verify the checksum
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
# Expected output: kubectl: OK

# For sha512 verification
curl -LO "https://dl.k8s.io/${VERSION}/bin/linux/amd64/kubectl.sha512"
echo "$(cat kubectl.sha512)  kubectl" | sha512sum --check

# Compare the running version with the expected hash
sha512sum /usr/bin/kubelet
# Compare the output against the published hash from the Kubernetes release page
```

!!! tip "Exam Tip"
    The exam may ask you to verify that a binary on a node matches the expected version. Use `sha512sum` to compute the hash and compare it against the official release checksum from the Kubernetes GitHub releases page or changelog.

## Practice Exercises

??? question "Exercise 1: Implement Network Isolation"
    Create a namespace called `secure-ns`. Deploy two pods: `web` (with label `role: web`) and `db` (with label `role: db`). Implement NetworkPolicies so that:

    1. All ingress traffic is denied by default
    2. The `web` pod can receive traffic on port 80 from any pod in the namespace
    3. The `db` pod can only receive traffic on port 5432 from the `web` pod

    ??? success "Solution"
        ```bash
        # Create namespace and pods
        kubectl create namespace secure-ns
        kubectl run web --image=nginx --labels="role=web" -n secure-ns
        kubectl run db --image=postgres --labels="role=db" -n secure-ns --env="POSTGRES_PASSWORD=secret"
        ```

        ```yaml
        # default-deny-ingress.yaml
        apiVersion: networking.k8s.io/v1
        kind: NetworkPolicy
        metadata:
          name: default-deny-ingress
          namespace: secure-ns
        spec:
          podSelector: {}
          policyTypes:
            - Ingress
        ---
        # allow-web-ingress.yaml
        apiVersion: networking.k8s.io/v1
        kind: NetworkPolicy
        metadata:
          name: allow-web-ingress
          namespace: secure-ns
        spec:
          podSelector:
            matchLabels:
              role: web
          policyTypes:
            - Ingress
          ingress:
            - from:
                - podSelector: {}
              ports:
                - protocol: TCP
                  port: 80
        ---
        # allow-db-from-web.yaml
        apiVersion: networking.k8s.io/v1
        kind: NetworkPolicy
        metadata:
          name: allow-db-from-web
          namespace: secure-ns
        spec:
          podSelector:
            matchLabels:
              role: db
          policyTypes:
            - Ingress
          ingress:
            - from:
                - podSelector:
                    matchLabels:
                      role: web
              ports:
                - protocol: TCP
                  port: 5432
        ```

        ```bash
        kubectl apply -f default-deny-ingress.yaml
        kubectl apply -f allow-web-ingress.yaml
        kubectl apply -f allow-db-from-web.yaml
        ```

??? question "Exercise 2: Run CIS Benchmark with kube-bench"
    Run kube-bench against the master node and identify any FAIL results related to the API server. Remediate one failing check.

    ??? success "Solution"
        ```bash
        # Run kube-bench targeting master components
        kube-bench run --targets master | grep -A 3 "FAIL"

        # Example: If check 1.2.18 fails (--audit-log-path not set)
        # Edit the API server manifest
        sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml

        # Add the flag to the command section:
        # - --audit-log-path=/var/log/kubernetes/audit/audit.log

        # Create the log directory
        sudo mkdir -p /var/log/kubernetes/audit

        # The API server will restart automatically (static pod)
        # Verify the fix
        kube-bench run --targets master --check 1.2.18
        ```

??? question "Exercise 3: Secure Ingress with TLS"
    Create a TLS-secured Ingress resource for a service called `webapp` running on port 8080 in the `default` namespace. The Ingress should be accessible at `webapp.example.com`.

    ??? success "Solution"
        ```bash
        # Generate a TLS certificate
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
          -keyout webapp-tls.key -out webapp-tls.crt \
          -subj "/CN=webapp.example.com"

        # Create the TLS secret
        kubectl create secret tls webapp-tls \
          --cert=webapp-tls.crt --key=webapp-tls.key
        ```

        ```yaml
        # webapp-ingress.yaml
        apiVersion: networking.k8s.io/v1
        kind: Ingress
        metadata:
          name: webapp-ingress
          annotations:
            nginx.ingress.kubernetes.io/ssl-redirect: "true"
        spec:
          tls:
            - hosts:
                - webapp.example.com
              secretName: webapp-tls
          rules:
            - host: webapp.example.com
              http:
                paths:
                  - path: /
                    pathType: Prefix
                    backend:
                      service:
                        name: webapp
                        port:
                          number: 8080
        ```

        ```bash
        kubectl apply -f webapp-ingress.yaml
        ```

??? question "Exercise 4: Block Cloud Metadata Access"
    Create a NetworkPolicy that prevents all pods in the `app` namespace from accessing the cloud provider metadata endpoint at `169.254.169.254`, while still allowing all other egress traffic including DNS.

    ??? success "Solution"
        ```yaml
        apiVersion: networking.k8s.io/v1
        kind: NetworkPolicy
        metadata:
          name: block-metadata
          namespace: app
        spec:
          podSelector: {}
          policyTypes:
            - Egress
          egress:
            - to:
                - ipBlock:
                    cidr: 0.0.0.0/0
                    except:
                      - 169.254.169.254/32
        ```

        ```bash
        kubectl apply -f block-metadata.yaml

        # Verify: this should time out
        kubectl run test --rm -it --image=busybox -n app -- wget -qO- --timeout=3 http://169.254.169.254/
        ```

??? question "Exercise 5: Verify Kubernetes Binary Integrity"
    Verify that the `kubelet` binary on a node has not been tampered with by comparing its checksum to the official release.

    ??? success "Solution"
        ```bash
        # Check the running kubelet version
        kubelet --version
        # Example output: Kubernetes v1.31.0

        # Compute the sha512 hash of the installed binary
        sha512sum $(which kubelet)

        # Download the official checksum
        VERSION="v1.31.0"
        curl -LO "https://dl.k8s.io/${VERSION}/bin/linux/amd64/kubelet.sha512"

        # Download the official binary for comparison
        curl -LO "https://dl.k8s.io/${VERSION}/bin/linux/amd64/kubelet"

        # Verify
        echo "$(cat kubelet.sha512)  kubelet" | sha512sum --check
        # Expected: kubelet: OK

        # Or directly compare hashes
        sha512sum kubelet
        sha512sum /usr/bin/kubelet
        # Both outputs should match
        ```

??? question "Exercise 6: Restrict Traffic with CiliumNetworkPolicy (Hands-On Lab)"
    A multi-tier application (frontend, backend, database) is running in namespace `microservices`. An external test pod runs in the `default` namespace.

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/cilium-network-policy/setup.sh)
    ```

    **Task:**

    1. Apply a default deny all ingress and egress `CiliumNetworkPolicy` in `microservices`
    2. Allow `frontend` to reach `backend` on port 80
    3. Allow `backend` to reach `database` on port 80
    4. Allow DNS egress for all pods (to `kube-system` for kube-dns)
    5. Verify: `frontend` can reach `backend` but **not** `database` directly
    6. Verify: `external` pod in `default` namespace cannot reach any microservice

    ??? success "Solution"
        Default deny all traffic:

        ```yaml
        # default-deny.yaml
        apiVersion: cilium.io/v2
        kind: CiliumNetworkPolicy
        metadata:
          name: default-deny
          namespace: microservices
        spec:
          endpointSelector: {}
          ingress:
            - {}
          egress:
            - {}
        ```

        !!! note
            An empty `ingress: [{}]` / `egress: [{}]` with `endpointSelector: {}` means "select all pods, allow nothing" — Cilium treats the presence of an ingress/egress section as "only allow what's listed". An empty list means nothing is allowed.

        Actually, for a true default deny, use this pattern:

        ```yaml
        # default-deny.yaml
        apiVersion: cilium.io/v2
        kind: CiliumNetworkPolicy
        metadata:
          name: default-deny
          namespace: microservices
        spec:
          endpointSelector: {}
          ingressDeny:
            - fromEntities:
                - world
                - cluster
          egressDeny:
            - toEntities:
                - world
                - cluster
        ```

        Or use the simpler approach with empty ingress/egress rules that implicitly denies:

        ```yaml
        # default-deny.yaml
        apiVersion: cilium.io/v2
        kind: CiliumNetworkPolicy
        metadata:
          name: default-deny
          namespace: microservices
        spec:
          endpointSelector: {}
          ingress: []
          egress: []
        ```

        Allow DNS egress for all pods:

        ```yaml
        # allow-dns.yaml
        apiVersion: cilium.io/v2
        kind: CiliumNetworkPolicy
        metadata:
          name: allow-dns
          namespace: microservices
        spec:
          endpointSelector: {}
          egress:
            - toEndpoints:
                - matchLabels:
                    io.kubernetes.pod.namespace: kube-system
                    k8s-app: kube-dns
              toPorts:
                - ports:
                    - port: "53"
                      protocol: UDP
        ```

        Allow frontend to backend:

        ```yaml
        # allow-frontend-to-backend.yaml
        apiVersion: cilium.io/v2
        kind: CiliumNetworkPolicy
        metadata:
          name: allow-frontend-to-backend
          namespace: microservices
        spec:
          endpointSelector:
            matchLabels:
              app: frontend
          egress:
            - toEndpoints:
                - matchLabels:
                    app: backend
              toPorts:
                - ports:
                    - port: "80"
                      protocol: TCP
        ---
        apiVersion: cilium.io/v2
        kind: CiliumNetworkPolicy
        metadata:
          name: backend-allow-from-frontend
          namespace: microservices
        spec:
          endpointSelector:
            matchLabels:
              app: backend
          ingress:
            - fromEndpoints:
                - matchLabels:
                    app: frontend
              toPorts:
                - ports:
                    - port: "80"
                      protocol: TCP
        ```

        Allow backend to database:

        ```yaml
        # allow-backend-to-database.yaml
        apiVersion: cilium.io/v2
        kind: CiliumNetworkPolicy
        metadata:
          name: allow-backend-to-database
          namespace: microservices
        spec:
          endpointSelector:
            matchLabels:
              app: backend
          egress:
            - toEndpoints:
                - matchLabels:
                    app: database
              toPorts:
                - ports:
                    - port: "80"
                      protocol: TCP
        ---
        apiVersion: cilium.io/v2
        kind: CiliumNetworkPolicy
        metadata:
          name: database-allow-from-backend
          namespace: microservices
        spec:
          endpointSelector:
            matchLabels:
              app: database
          ingress:
            - fromEndpoints:
                - matchLabels:
                    app: backend
              toPorts:
                - ports:
                    - port: "80"
                      protocol: TCP
        ```

        ```bash
        kubectl apply -f default-deny.yaml
        kubectl apply -f allow-dns.yaml
        kubectl apply -f allow-frontend-to-backend.yaml
        kubectl apply -f allow-backend-to-database.yaml

        # Verify: frontend -> backend (should WORK)
        kubectl -n microservices exec deploy/frontend -- wget -qO- --timeout=3 http://backend
        # Expected: HTML output from httpd

        # Verify: frontend -> database (should FAIL)
        kubectl -n microservices exec deploy/frontend -- wget -qO- --timeout=3 http://database
        # Expected: timeout

        # Verify: external -> frontend (should FAIL)
        kubectl exec external -- wget -qO- --timeout=3 http://frontend.microservices
        # Expected: timeout
        ```

??? question "Exercise 7: Understand NetworkPolicy Merge Behavior (Hands-On Lab)"
    Multiple NetworkPolicies can target the same pod. Understanding how they combine is critical for the exam.

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/netpol-merge/setup.sh)
    ```

    **Task:**

    1. Create a default deny ingress policy for all pods in `netpol-merge`
    2. Create Policy A: allow ingress to `web` from pods with label `team=internal` on port 80
    3. Create Policy B: allow ingress to `web` from pods with label `app=monitoring` on port 80
    4. Predict and verify which clients can reach `web`

    ??? success "Solution"
        ```yaml
        # default-deny.yaml
        apiVersion: networking.k8s.io/v1
        kind: NetworkPolicy
        metadata:
          name: default-deny-ingress
          namespace: netpol-merge
        spec:
          podSelector: {}
          policyTypes:
            - Ingress
        ---
        # policy-a.yaml - allow from team=internal
        apiVersion: networking.k8s.io/v1
        kind: NetworkPolicy
        metadata:
          name: allow-internal-to-web
          namespace: netpol-merge
        spec:
          podSelector:
            matchLabels:
              app: web
          policyTypes:
            - Ingress
          ingress:
            - from:
                - podSelector:
                    matchLabels:
                      team: internal
              ports:
                - protocol: TCP
                  port: 80
        ---
        # policy-b.yaml - allow from app=monitoring
        apiVersion: networking.k8s.io/v1
        kind: NetworkPolicy
        metadata:
          name: allow-monitoring-to-web
          namespace: netpol-merge
        spec:
          podSelector:
            matchLabels:
              app: web
          policyTypes:
            - Ingress
          ingress:
            - from:
                - podSelector:
                    matchLabels:
                      app: monitoring
              ports:
                - protocol: TCP
                  port: 80
        ```

        ```bash
        kubectl apply -f default-deny.yaml
        kubectl apply -f policy-a.yaml
        kubectl apply -f policy-b.yaml

        # client-internal (team=internal) -> web: ALLOWED by Policy A
        kubectl -n netpol-merge exec client-internal -- wget -qO- --timeout=3 http://web
        # Expected: nginx HTML

        # monitoring (app=monitoring) -> web: ALLOWED by Policy B
        kubectl -n netpol-merge exec monitoring -- wget -qO- --timeout=3 http://web
        # Expected: nginx HTML

        # client-external (team=external) -> web: DENIED by both
        kubectl -n netpol-merge exec client-external -- wget -qO- --timeout=3 http://web
        # Expected: timeout
        ```

        **Key insight**: Multiple NetworkPolicies targeting the same pod are **unioned** (OR logic). If _any_ policy allows the traffic, it is permitted. Policies never conflict — they only add more allowed paths.

## Further Reading

- [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [kube-bench GitHub Repository](https://github.com/aquasecurity/kube-bench)
- [Ingress TLS Configuration](https://kubernetes.io/docs/concepts/services-networking/ingress/#tls)
- [Restricting Cloud Metadata Access](https://kubernetes.io/docs/tasks/administer-cluster/securing-a-cluster/#restricting-cloud-metadata-api-access)
- [etcd Security Model](https://etcd.io/docs/v3.5/op-guide/security/)
- [Operating etcd for Kubernetes](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/)
