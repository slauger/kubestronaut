# Services and Networking (20%)

This domain covers how applications communicate within and outside the Kubernetes cluster. You need to understand Service types, Ingress resources for HTTP routing, NetworkPolicies for traffic control, and how DNS works for service discovery.

## Key Concepts

### Service Types

Services provide a stable network endpoint for a set of pods. Kubernetes offers several Service types depending on how the application needs to be accessed.

#### ClusterIP (Default)

Exposes the Service on a cluster-internal IP. Only reachable from within the cluster.

=== "Imperative"

    ```bash
    # Expose an existing Deployment as a ClusterIP Service
    kubectl expose deployment webapp --port=80 --target-port=8080

    # Create a ClusterIP Service directly
    kubectl create service clusterip my-svc --tcp=80:8080
    ```

=== "Declarative"

    ```yaml
    apiVersion: v1
    kind: Service
    metadata:
      name: webapp-svc
    spec:
      type: ClusterIP
      selector:
        app: webapp
      ports:
        - port: 80
          targetPort: 8080
          protocol: TCP
    ```

#### NodePort

Exposes the Service on each node's IP at a static port (30000-32767). Accessible from outside the cluster via `<NodeIP>:<NodePort>`.

=== "Imperative"

    ```bash
    # Expose as NodePort
    kubectl expose deployment webapp --type=NodePort --port=80 --target-port=8080

    # Create NodePort with specific port
    kubectl create service nodeport my-svc --tcp=80:8080 --node-port=30080
    ```

=== "Declarative"

    ```yaml
    apiVersion: v1
    kind: Service
    metadata:
      name: webapp-nodeport
    spec:
      type: NodePort
      selector:
        app: webapp
      ports:
        - port: 80
          targetPort: 8080
          nodePort: 30080
          protocol: TCP
    ```

#### LoadBalancer

Exposes the Service externally using a cloud provider's load balancer. Automatically creates a NodePort and ClusterIP.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: webapp-lb
spec:
  type: LoadBalancer
  selector:
    app: webapp
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
```

```bash
# View the external IP (may show <pending> in non-cloud environments)
kubectl get svc webapp-lb
```

#### Service Overview

| Type | Scope | Use Case |
|---|---|---|
| `ClusterIP` | Internal only | Inter-service communication |
| `NodePort` | External via node IP | Development, testing |
| `LoadBalancer` | External via LB | Production with cloud provider |
| `ExternalName` | DNS alias | Map to external DNS name |

!!! tip "Exam Tip"
    The fastest way to create a Service is with `kubectl expose`. Remember that `--port` is the Service port and `--target-port` is the container port. If they are the same, you can omit `--target-port`. Always verify your Service is routing to the correct pods with `kubectl get endpoints <service-name>`.

### Ingress

Ingress provides HTTP and HTTPS routing to Services based on hostnames and URL paths. An Ingress controller (e.g., nginx-ingress) must be running in the cluster for Ingress resources to work.

#### Simple Ingress (Single Service)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: simple-ingress
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
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
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

#### Ingress with Multiple Hosts

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: multi-host-ingress
spec:
  ingressClassName: nginx
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api-svc
                port:
                  number: 8080
    - host: web.example.com
      http:
        paths:
          - path: /
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
      secretName: tls-secret
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
# Create a TLS Secret for Ingress
kubectl create secret tls tls-secret --cert=tls.crt --key=tls.key

# View Ingress resources
kubectl get ingress
kubectl describe ingress multi-path-ingress
```

Path types:

- `Prefix`: Matches based on a URL path prefix split by `/`
- `Exact`: Matches the URL path exactly
- `ImplementationSpecific`: Matching depends on the Ingress controller

!!! tip "Exam Tip"
    Always set `ingressClassName` in your Ingress spec (or use the `kubernetes.io/ingress.class` annotation for older clusters). Check which Ingress controller is running with `kubectl get ingressclass`. The `pathType` field is required -- use `Prefix` for most cases.

### NetworkPolicies

NetworkPolicies control traffic flow between pods and external endpoints. By default, all pods can communicate with each other. NetworkPolicies restrict this by defining explicit allow rules.

#### Default Deny All Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: production
spec:
  podSelector: {}    # Applies to all pods in the namespace
  policyTypes:
    - Ingress
  # No ingress rules = deny all incoming traffic
```

#### Default Deny All Egress

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-egress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Egress
  # No egress rules = deny all outgoing traffic
```

#### Allow Specific Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: backend           # Apply to backend pods
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend   # Allow from frontend pods
        - namespaceSelector:
            matchLabels:
              env: staging    # Also allow from staging namespace
      ports:
        - protocol: TCP
          port: 8080
```

#### Allow Specific Egress

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-egress
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
    - to:                     # Allow DNS resolution
        - namespaceSelector: {}
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

!!! tip "Exam Tip"
    NetworkPolicies are additive -- if multiple policies select the same pod, the union of their rules applies. A common mistake is forgetting to allow DNS egress (port 53) when restricting egress traffic, which breaks service discovery. Multiple items in the `from` array are OR-ed; multiple selectors within a single `from` item are AND-ed.

#### AND vs OR Logic

```yaml
# OR logic: Allow from frontend pods OR from staging namespace
ingress:
  - from:
      - podSelector:
          matchLabels:
            app: frontend
      - namespaceSelector:
          matchLabels:
            env: staging

# AND logic: Allow from frontend pods IN staging namespace
ingress:
  - from:
      - podSelector:
          matchLabels:
            app: frontend
        namespaceSelector:
          matchLabels:
            env: staging
```

```bash
# View NetworkPolicies
kubectl get networkpolicies -n production
kubectl describe networkpolicy allow-frontend-to-backend -n production
```

### DNS for Services and Pods

Kubernetes DNS automatically creates DNS records for Services and Pods.

**Service DNS format:**

```
<service-name>.<namespace>.svc.cluster.local
```

**Examples:**

```bash
# From within a pod, all of these resolve to the same Service:
curl webapp-svc                                    # Same namespace
curl webapp-svc.default                            # Explicit namespace
curl webapp-svc.default.svc                        # With svc
curl webapp-svc.default.svc.cluster.local          # Fully qualified

# Access a Service in a different namespace
curl webapp-svc.other-namespace.svc.cluster.local
```

**Pod DNS (if enabled):**

```
<pod-ip-dashed>.<namespace>.pod.cluster.local
# Example: 10-244-1-5.default.pod.cluster.local
```

**Headless Service (ClusterIP: None):**

Returns the IP addresses of individual pods instead of a single virtual IP. Useful for StatefulSets.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: headless-svc
spec:
  clusterIP: None
  selector:
    app: webapp
  ports:
    - port: 80
```

```bash
# Test DNS resolution from a temporary pod
kubectl run dns-test --image=busybox:1.36 --rm -it --restart=Never -- nslookup webapp-svc.default.svc.cluster.local
```

!!! tip "Exam Tip"
    You do not need to memorize the full DNS format. Remember the pattern: `<service>.<namespace>.svc.cluster.local`. For accessing services in the same namespace, just use the service name. For cross-namespace access, use `<service>.<namespace>`. Use `nslookup` or `wget` from a busybox pod to test DNS.

## Practice Exercises

??? question "Exercise 1: Create Services for a Deployment"
    Create a Deployment named `web` with 3 replicas using `nginx:1.27`. Expose it as a ClusterIP Service named `web-svc` on port 80. Then create a NodePort Service named `web-external` on port 30080 for the same Deployment.

    ??? success "Solution"
        ```bash
        # Create Deployment
        kubectl create deployment web --image=nginx:1.27 --replicas=3

        # Create ClusterIP Service
        kubectl expose deployment web --name=web-svc --port=80 --target-port=80

        # Create NodePort Service
        kubectl expose deployment web --name=web-external --port=80 --target-port=80 --type=NodePort

        # Or with a specific NodePort:
        kubectl create service nodeport web-external --tcp=80:80 --node-port=30080 --dry-run=client -o yaml > svc.yaml
        # Edit selector to match deployment labels, then apply

        # Verify
        kubectl get svc web-svc web-external
        kubectl get endpoints web-svc
        ```

??? question "Exercise 2: Create an Ingress with Multiple Paths"
    Create an Ingress named `app-ingress` that routes traffic for `app.example.com`. Path `/api` should route to the `api-svc` Service on port 8080, and path `/web` should route to the `web-svc` Service on port 80. Use `Prefix` path type and the `nginx` Ingress class.

    ??? success "Solution"
        ```yaml
        apiVersion: networking.k8s.io/v1
        kind: Ingress
        metadata:
          name: app-ingress
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

        ```bash
        kubectl apply -f ingress.yaml
        kubectl get ingress app-ingress
        kubectl describe ingress app-ingress
        ```

??? question "Exercise 3: Default Deny with Specific Allow NetworkPolicy"
    In the `secure` namespace, create a default-deny-all-ingress NetworkPolicy. Then create a second NetworkPolicy that allows pods with label `app: frontend` to send traffic to pods with label `app: backend` on port 8080.

    ??? success "Solution"
        ```bash
        kubectl create namespace secure
        ```

        ```yaml
        # Default deny all ingress
        apiVersion: networking.k8s.io/v1
        kind: NetworkPolicy
        metadata:
          name: deny-all-ingress
          namespace: secure
        spec:
          podSelector: {}
          policyTypes:
            - Ingress
        ---
        # Allow frontend to backend
        apiVersion: networking.k8s.io/v1
        kind: NetworkPolicy
        metadata:
          name: allow-frontend-to-backend
          namespace: secure
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

        ```bash
        kubectl apply -f netpol.yaml
        kubectl get networkpolicies -n secure
        ```

??? question "Exercise 4: Cross-Namespace DNS Resolution"
    Create a namespace `backend-ns`. Deploy an nginx pod named `api-server` and expose it as a ClusterIP Service named `api-svc` in that namespace. From a temporary pod in the `default` namespace, verify you can reach the service using its fully qualified DNS name.

    ??? success "Solution"
        ```bash
        # Create namespace and deploy
        kubectl create namespace backend-ns
        kubectl run api-server --image=nginx:1.27 -n backend-ns
        kubectl expose pod api-server --name=api-svc --port=80 -n backend-ns

        # Test DNS from default namespace
        kubectl run dns-test --image=busybox:1.36 --rm -it --restart=Never -- \
          wget -qO- api-svc.backend-ns.svc.cluster.local

        # Or test DNS resolution only
        kubectl run dns-test --image=busybox:1.36 --rm -it --restart=Never -- \
          nslookup api-svc.backend-ns.svc.cluster.local
        ```

??? question "Exercise 5: NetworkPolicy with Egress Rules"
    Create a NetworkPolicy named `db-access` in the `default` namespace that applies to pods labeled `app: api`. Allow egress only to pods labeled `app: database` on port 5432 and to the cluster DNS (port 53, both TCP and UDP). Deny all other egress traffic.

    ??? success "Solution"
        ```yaml
        apiVersion: networking.k8s.io/v1
        kind: NetworkPolicy
        metadata:
          name: db-access
          namespace: default
        spec:
          podSelector:
            matchLabels:
              app: api
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
                - namespaceSelector: {}
              ports:
                - protocol: UDP
                  port: 53
                - protocol: TCP
                  port: 53
        ```

        ```bash
        kubectl apply -f netpol-egress.yaml
        kubectl describe networkpolicy db-access
        ```

## Kubernetes Documentation References

- [Services](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Ingress Controllers](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/)
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
