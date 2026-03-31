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

## Further Reading

- [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [kube-bench GitHub Repository](https://github.com/aquasecurity/kube-bench)
- [Ingress TLS Configuration](https://kubernetes.io/docs/concepts/services-networking/ingress/#tls)
- [Restricting Cloud Metadata Access](https://kubernetes.io/docs/tasks/administer-cluster/securing-a-cluster/#restricting-cloud-metadata-api-access)
