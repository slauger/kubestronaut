# Services & Networking (20%)

This domain covers Kubernetes networking fundamentals, including how services expose applications, how ingress routes external traffic, how network policies enforce segmentation, and how DNS resolution works inside a cluster. Networking accounts for 20% of the CKA exam.

## Key Concepts

### Service Types

Services provide stable network endpoints for accessing pods. Kubernetes supports four service types.

#### ClusterIP (Default)

Exposes the service on an internal cluster IP. Only reachable from within the cluster.

=== "Imperative"

    ```bash
    # Expose a deployment as a ClusterIP service
    kubectl expose deployment nginx --port=80 --target-port=80 --name=nginx-svc

    # Or create directly
    kubectl create service clusterip nginx-svc --tcp=80:80
    ```

=== "Declarative"

    ```yaml
    apiVersion: v1
    kind: Service
    metadata:
      name: nginx-svc
    spec:
      type: ClusterIP
      selector:
        app: nginx
      ports:
      - port: 80
        targetPort: 80
        protocol: TCP
    ```

#### NodePort

Exposes the service on each node's IP at a static port (range 30000-32767).

=== "Imperative"

    ```bash
    kubectl expose deployment nginx --type=NodePort --port=80 --target-port=80 --name=nginx-nodeport
    ```

=== "Declarative"

    ```yaml
    apiVersion: v1
    kind: Service
    metadata:
      name: nginx-nodeport
    spec:
      type: NodePort
      selector:
        app: nginx
      ports:
      - port: 80
        targetPort: 80
        nodePort: 30080
    ```

#### LoadBalancer

Provisions an external load balancer (cloud provider integration). Extends NodePort.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-lb
spec:
  type: LoadBalancer
  selector:
    app: nginx
  ports:
  - port: 80
    targetPort: 80
```

#### ExternalName

Maps a service to an external DNS name. No proxying -- just a CNAME record.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: external-db
spec:
  type: ExternalName
  externalName: db.example.com
```

### Service Discovery and DNS

```bash
# Services are accessible via DNS within the cluster
# Format: <service-name>.<namespace>.svc.cluster.local

# From any pod in the same namespace
curl http://nginx-svc

# From a pod in a different namespace
curl http://nginx-svc.default.svc.cluster.local

# Headless service (clusterIP: None) - returns individual pod IPs
# Used with StatefulSets for stable DNS per pod
# Format: <pod-name>.<service-name>.<namespace>.svc.cluster.local
```

!!! tip "Exam Tip"
    Remember the DNS format: `<service>.<namespace>.svc.cluster.local`. Within the same namespace you can use just the service name. Across namespaces, you need at least `<service>.<namespace>`.

### Useful Service Debugging Commands

```bash
# List all services
kubectl get svc -A

# Get service details including endpoints
kubectl describe svc nginx-svc

# Check endpoints (are pods correctly selected?)
kubectl get endpoints nginx-svc

# Test service from within the cluster
kubectl run tmp-shell --rm -it --image=busybox -- wget -qO- http://nginx-svc

# Check service port mapping
kubectl get svc nginx-nodeport -o wide
```

### Ingress

Ingress manages external HTTP/HTTPS access to services. It requires an Ingress controller (e.g., NGINX Ingress Controller) to be installed in the cluster.

#### Simple Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: simple-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: webapp-svc
            port:
              number: 80
```

#### Ingress with Multiple Paths

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: multi-path-ingress
spec:
  ingressClassName: nginx
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-svc
            port:
              number: 8080
      - path: /web
        pathType: Prefix
        backend:
          service:
            name: web-svc
            port:
              number: 80
```

#### Ingress with TLS

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tls-ingress
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - app.example.com
    secretName: app-tls-secret
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: webapp-svc
            port:
              number: 80
```

```bash
# Create a TLS secret for ingress
kubectl create secret tls app-tls-secret \
  --cert=tls.crt \
  --key=tls.key

# Create a basic ingress imperatively
kubectl create ingress simple-ingress \
  --class=nginx \
  --rule="app.example.com/=webapp-svc:80"

# List ingress resources
kubectl get ingress

# Describe ingress for debugging
kubectl describe ingress simple-ingress
```

!!! tip "Exam Tip"
    Pay attention to `pathType`. `Prefix` matches URL paths with a prefix (e.g., `/api` matches `/api/v1`). `Exact` matches the exact path only. The `ingressClassName` field is required in newer Kubernetes versions.

### NetworkPolicies

NetworkPolicies control pod-to-pod traffic. By default, all pods can communicate with each other. NetworkPolicies restrict this based on labels, namespaces, and IP blocks.

#### Deny All Ingress Traffic

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
```

#### Allow Ingress from Specific Pods

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend
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

#### Allow Ingress from a Specific Namespace

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          purpose: monitoring
    ports:
    - protocol: TCP
      port: 9090
```

#### Egress Policy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: restrict-egress
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: database
    ports:
    - protocol: TCP
      port: 5432
  - to:
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

!!! tip "Exam Tip"
    When creating egress policies, always remember to allow DNS traffic (port 53 TCP/UDP). Without it, pods cannot resolve service names and will fail to connect even if the data port is allowed. Also remember that NetworkPolicies require a CNI plugin that supports them (e.g., Calico, Cilium). Flannel does not support NetworkPolicies.

### DNS in Kubernetes (CoreDNS)

CoreDNS is the default DNS server in Kubernetes. It resolves service names to cluster IPs.

```bash
# Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check CoreDNS ConfigMap
kubectl get configmap coredns -n kube-system -o yaml

# Test DNS resolution from a pod
kubectl run dns-test --rm -it --image=busybox:1.36 -- nslookup kubernetes.default

# Check a pod's DNS configuration
kubectl exec <pod-name> -- cat /etc/resolv.conf
```

DNS record formats:

| Resource | DNS Record |
|---|---|
| Service | `<svc>.<ns>.svc.cluster.local` |
| Pod (by IP) | `<ip-with-dashes>.<ns>.pod.cluster.local` |
| StatefulSet Pod | `<pod>.<svc>.<ns>.svc.cluster.local` |

### CNI Plugins Overview

The Container Network Interface (CNI) provides networking for pods:

| Plugin | Key Features |
|---|---|
| **Flannel** | Simple overlay network, no NetworkPolicy support |
| **Calico** | NetworkPolicy support, BGP routing, popular choice |
| **Cilium** | eBPF-based, advanced NetworkPolicy, observability |
| **Weave Net** | Mesh networking, encrypted traffic, NetworkPolicy support |

```bash
# Check which CNI plugin is installed
ls /etc/cni/net.d/
cat /etc/cni/net.d/*.conflist

# Check CNI binaries
ls /opt/cni/bin/
```

## Practice Exercises

??? question "Exercise 1: Create and Expose a Service"
    Create a deployment named `httpd` with image `httpd:2.4` and 3 replicas. Expose it as a NodePort service on port 80 with NodePort 30080.

    ??? success "Solution"
        ```bash
        # Create the deployment
        kubectl create deployment httpd --image=httpd:2.4 --replicas=3

        # Expose as NodePort
        kubectl expose deployment httpd --type=NodePort --port=80 --target-port=80 --name=httpd-svc \
          --dry-run=client -o yaml > httpd-svc.yaml
        ```

        Edit `httpd-svc.yaml` to set the nodePort:

        ```yaml
        apiVersion: v1
        kind: Service
        metadata:
          name: httpd-svc
        spec:
          type: NodePort
          selector:
            app: httpd
          ports:
          - port: 80
            targetPort: 80
            nodePort: 30080
        ```

        ```bash
        kubectl apply -f httpd-svc.yaml

        # Verify
        kubectl get svc httpd-svc
        kubectl get endpoints httpd-svc
        ```

??? question "Exercise 2: Create an Ingress Resource"
    Create an ingress named `app-ingress` that routes traffic for host `myapp.example.com` with path `/` to service `webapp-svc` on port 80 and path `/api` to service `api-svc` on port 8080. Use ingress class `nginx`.

    ??? success "Solution"
        ```bash
        kubectl create ingress app-ingress \
          --class=nginx \
          --rule="myapp.example.com/=webapp-svc:80" \
          --rule="myapp.example.com/api=api-svc:8080" \
          --dry-run=client -o yaml > ingress.yaml
        ```

        Verify and adjust `pathType` if needed:

        ```yaml
        apiVersion: networking.k8s.io/v1
        kind: Ingress
        metadata:
          name: app-ingress
        spec:
          ingressClassName: nginx
          rules:
          - host: myapp.example.com
            http:
              paths:
              - path: /
                pathType: Prefix
                backend:
                  service:
                    name: webapp-svc
                    port:
                      number: 80
              - path: /api
                pathType: Prefix
                backend:
                  service:
                    name: api-svc
                    port:
                      number: 8080
        ```

        ```bash
        kubectl apply -f ingress.yaml
        kubectl describe ingress app-ingress
        ```

??? question "Exercise 3: Create a NetworkPolicy"
    In the `secure` namespace, create a NetworkPolicy named `db-policy` that only allows ingress traffic to pods labeled `role=db` from pods labeled `role=api` on TCP port 3306. Deny all other ingress traffic to the database pods.

    ??? success "Solution"
        ```bash
        kubectl create namespace secure
        ```

        ```yaml
        apiVersion: networking.k8s.io/v1
        kind: NetworkPolicy
        metadata:
          name: db-policy
          namespace: secure
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
                  role: api
            ports:
            - protocol: TCP
              port: 3306
        ```

        ```bash
        kubectl apply -f db-policy.yaml

        # Verify
        kubectl describe networkpolicy db-policy -n secure
        ```

??? question "Exercise 4: Debug DNS Resolution"
    A pod cannot resolve the service `backend-svc` in namespace `app`. Troubleshoot the DNS issue.

    ??? success "Solution"
        ```bash
        # Check if CoreDNS is running
        kubectl get pods -n kube-system -l k8s-app=kube-dns

        # Check CoreDNS logs
        kubectl logs -n kube-system -l k8s-app=kube-dns

        # Test DNS from a debug pod
        kubectl run dns-debug --rm -it --image=busybox:1.36 -n app -- nslookup backend-svc.app.svc.cluster.local

        # Check if the service exists and has endpoints
        kubectl get svc backend-svc -n app
        kubectl get endpoints backend-svc -n app

        # Check the pod's resolv.conf
        kubectl exec <pod-name> -n app -- cat /etc/resolv.conf

        # Verify CoreDNS ConfigMap
        kubectl get configmap coredns -n kube-system -o yaml
        ```

??? question "Exercise 5: Identify the CNI Plugin"
    Determine which CNI plugin is installed on the cluster and where its configuration is located.

    ??? success "Solution"
        ```bash
        # Check CNI configuration directory
        ls /etc/cni/net.d/

        # View the CNI configuration
        cat /etc/cni/net.d/*.conflist

        # Check CNI binaries
        ls /opt/cni/bin/

        # Look for CNI-related pods
        kubectl get pods -n kube-system | grep -E 'calico|flannel|cilium|weave'

        # Check the kubelet's CNI configuration
        ps aux | grep kubelet | grep cni
        ```

## Relevant Documentation

- [Service](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Ingress Controllers](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/)
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [Cluster Networking](https://kubernetes.io/docs/concepts/cluster-administration/networking/)
