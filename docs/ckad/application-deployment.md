# Application Deployment (20%)

This domain covers the full lifecycle of deploying applications on Kubernetes: creating Deployments, performing rolling updates, rollbacks, and scaling, as well as advanced deployment strategies like blue/green and canary. It also includes packaging applications with Helm and customizing manifests with Kustomize.

## Key Concepts

### Deployments

Deployments manage ReplicaSets and provide declarative updates for Pods. They are the most common way to run stateless applications on Kubernetes.

=== "Imperative"

    ```bash
    # Create a Deployment
    kubectl create deployment nginx-deploy --image=nginx:1.27 --replicas=3

    # Scale a Deployment
    kubectl scale deployment nginx-deploy --replicas=5

    # Update the image
    kubectl set image deployment/nginx-deploy nginx=nginx:1.28

    # Check rollout status
    kubectl rollout status deployment/nginx-deploy

    # View rollout history
    kubectl rollout history deployment/nginx-deploy

    # Rollback to the previous version
    kubectl rollout undo deployment/nginx-deploy

    # Rollback to a specific revision
    kubectl rollout undo deployment/nginx-deploy --to-revision=2

    # Pause and resume a rollout
    kubectl rollout pause deployment/nginx-deploy
    kubectl rollout resume deployment/nginx-deploy
    ```

=== "Declarative"

    ```yaml
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: nginx-deploy
    spec:
      replicas: 3
      selector:
        matchLabels:
          app: nginx
      template:
        metadata:
          labels:
            app: nginx
        spec:
          containers:
            - name: nginx
              image: nginx:1.27
              ports:
                - containerPort: 80
              resources:
                requests:
                  cpu: 100m
                  memory: 128Mi
                limits:
                  cpu: 250m
                  memory: 256Mi
    ```

!!! tip "Exam Tip"
    Always use `kubectl rollout status` to verify a deployment update completed successfully. When asked to update an image, use `kubectl set image` for speed. Record the change with `--record` is deprecated; instead, use annotations if you need to track the reason for a change.

### Rolling Update Strategy

The default deployment strategy is `RollingUpdate`. It gradually replaces old pods with new ones.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rolling-app
spec:
  replicas: 4
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
  selector:
    matchLabels:
      app: rolling-app
  template:
    metadata:
      labels:
        app: rolling-app
    spec:
      containers:
        - name: app
          image: nginx:1.27
```

Key fields:

- `maxSurge`: Maximum number of pods created above the desired count during an update (absolute number or percentage)
- `maxUnavailable`: Maximum number of pods that can be unavailable during an update (absolute number or percentage)
- `Recreate` strategy: Terminates all existing pods before creating new ones (causes downtime)

```bash
# View the strategy of an existing Deployment
kubectl describe deployment rolling-app | grep -A 3 Strategy

# Use Recreate strategy (for stateful apps that cannot run multiple versions)
kubectl patch deployment rolling-app -p '{"spec":{"strategy":{"type":"Recreate"}}}'
```

### Blue/Green Deployments

Blue/green deployments run two identical environments. Traffic is switched from the old version (blue) to the new version (green) by updating the Service selector.

```yaml
# Blue deployment (current production)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-blue
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
      version: blue
  template:
    metadata:
      labels:
        app: myapp
        version: blue
    spec:
      containers:
        - name: app
          image: myapp:1.0
---
# Green deployment (new version)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-green
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
      version: green
  template:
    metadata:
      labels:
        app: myapp
        version: green
    spec:
      containers:
        - name: app
          image: myapp:2.0
---
# Service initially pointing to blue
apiVersion: v1
kind: Service
metadata:
  name: myapp-svc
spec:
  selector:
    app: myapp
    version: blue  # Change to "green" to switch traffic
  ports:
    - port: 80
      targetPort: 8080
```

```bash
# Switch traffic from blue to green
kubectl patch service myapp-svc -p '{"spec":{"selector":{"version":"green"}}}'

# Verify the switch
kubectl describe svc myapp-svc | grep Selector

# If green works, delete blue
kubectl delete deployment app-blue
```

### Canary Deployments

Canary deployments route a small percentage of traffic to the new version before fully rolling it out. This is achieved by running both versions behind the same Service with different replica counts.

```yaml
# Stable deployment (majority of traffic)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-stable
spec:
  replicas: 9
  selector:
    matchLabels:
      app: myapp
      track: stable
  template:
    metadata:
      labels:
        app: myapp
        track: stable
    spec:
      containers:
        - name: app
          image: myapp:1.0
---
# Canary deployment (small fraction of traffic)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-canary
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
      track: canary
  template:
    metadata:
      labels:
        app: myapp
        track: canary
    spec:
      containers:
        - name: app
          image: myapp:2.0
---
# Service routes to both based on shared label
apiVersion: v1
kind: Service
metadata:
  name: myapp-svc
spec:
  selector:
    app: myapp  # Matches both stable and canary pods
  ports:
    - port: 80
      targetPort: 8080
```

With 9 stable replicas and 1 canary replica, approximately 10% of traffic goes to the new version. Gradually increase canary replicas and decrease stable replicas as confidence grows.

### Helm Basics

Helm is the package manager for Kubernetes. Charts are pre-configured packages of Kubernetes resources.

```bash
# Add a chart repository
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Search for charts
helm search repo nginx
helm search hub wordpress

# Install a chart
helm install my-release bitnami/nginx
helm install my-release bitnami/nginx --namespace web --create-namespace

# Install with custom values
helm install my-release bitnami/nginx --set replicaCount=3
helm install my-release bitnami/nginx -f custom-values.yaml

# List installed releases
helm list
helm list --all-namespaces

# Upgrade a release
helm upgrade my-release bitnami/nginx --set replicaCount=5

# Rollback a release
helm rollback my-release 1

# View release history
helm history my-release

# Uninstall a release
helm uninstall my-release

# Show chart values and documentation
helm show values bitnami/nginx
helm show chart bitnami/nginx

# Generate manifests without installing (dry-run)
helm template my-release bitnami/nginx > manifests.yaml
```

!!! tip "Exam Tip"
    For the CKAD, you need to know how to install, upgrade, rollback, and uninstall Helm releases. You do not need to create charts from scratch, but understanding the basic structure helps. Use `helm show values` to discover configurable parameters.

### Kustomize

Kustomize is built into kubectl and lets you customize Kubernetes manifests without templating. It uses a `kustomization.yaml` file to define overlays and patches.

```bash
# Apply a kustomization directory
kubectl apply -k ./overlay/production/

# Preview what kustomize will generate
kubectl kustomize ./overlay/production/

# Create a kustomization.yaml
# (Kustomize does not have a full imperative creation command;
# you write the file manually)
```

Example directory structure:

```
app/
  base/
    kustomization.yaml
    deployment.yaml
    service.yaml
  overlays/
    dev/
      kustomization.yaml
      replica-patch.yaml
    prod/
      kustomization.yaml
      replica-patch.yaml
```

Base `kustomization.yaml`:

```yaml
# base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
```

Production overlay:

```yaml
# overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namePrefix: prod-
namespace: production
patches:
  - path: replica-patch.yaml
```

```yaml
# overlays/prod/replica-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deploy
spec:
  replicas: 5
```

## Practice Exercises

??? question "Exercise 1: Create and Scale a Deployment"
    Create a Deployment named `webapp` with 3 replicas using the `nginx:1.27` image. Then scale it to 5 replicas. Finally, update the image to `nginx:1.28` and verify the rollout completes successfully.

    ??? success "Solution"
        ```bash
        # Create the Deployment
        kubectl create deployment webapp --image=nginx:1.27 --replicas=3

        # Verify
        kubectl get deployment webapp

        # Scale to 5 replicas
        kubectl scale deployment webapp --replicas=5

        # Update the image
        kubectl set image deployment/webapp nginx=nginx:1.28

        # Verify rollout
        kubectl rollout status deployment/webapp
        kubectl get deployment webapp
        ```

??? question "Exercise 2: Rollback a Deployment"
    Using the `webapp` Deployment from Exercise 1, update the image to an invalid image `nginx:invalid-tag`. Watch the rollout fail, then roll back to the previous working version.

    ??? success "Solution"
        ```bash
        # Update to invalid image
        kubectl set image deployment/webapp nginx=nginx:invalid-tag

        # Watch the rollout (it will stall)
        kubectl rollout status deployment/webapp --timeout=30s

        # Check pod status - you'll see ImagePullBackOff
        kubectl get pods -l app=webapp

        # View rollout history
        kubectl rollout history deployment/webapp

        # Rollback to the previous revision
        kubectl rollout undo deployment/webapp

        # Verify the rollback succeeded
        kubectl rollout status deployment/webapp
        kubectl describe deployment webapp | grep Image
        ```

??? question "Exercise 3: Blue/Green Deployment Switch"
    Create two Deployments: `app-v1` (image `nginx:1.27`, label `version: v1`) and `app-v2` (image `nginx:1.28`, label `version: v2`), both with the label `app: myapp` and 2 replicas each. Create a Service named `myapp` that initially points to v1. Then switch the Service to point to v2.

    ??? success "Solution"
        ```bash
        # Create v1 deployment
        kubectl create deployment app-v1 --image=nginx:1.27 --replicas=2 --dry-run=client -o yaml | \
          kubectl label --local -f - version=v1 --dry-run=client -o yaml | \
          kubectl apply -f -

        # It's simpler to use YAML for precise label control:
        ```

        ```yaml
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: app-v1
        spec:
          replicas: 2
          selector:
            matchLabels:
              app: myapp
              version: v1
          template:
            metadata:
              labels:
                app: myapp
                version: v1
            spec:
              containers:
                - name: nginx
                  image: nginx:1.27
        ---
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: app-v2
        spec:
          replicas: 2
          selector:
            matchLabels:
              app: myapp
              version: v2
          template:
            metadata:
              labels:
                app: myapp
                version: v2
            spec:
              containers:
                - name: nginx
                  image: nginx:1.28
        ```

        ```bash
        kubectl apply -f deployments.yaml

        # Create service pointing to v1
        kubectl create service clusterip myapp --tcp=80:80 --dry-run=client -o yaml > svc.yaml
        # Edit selector to: app: myapp, version: v1
        kubectl apply -f svc.yaml

        # Switch to v2
        kubectl patch service myapp -p '{"spec":{"selector":{"app":"myapp","version":"v2"}}}'

        # Verify
        kubectl describe svc myapp | grep Selector
        ```

??? question "Exercise 4: Install and Manage a Helm Release"
    Add the Bitnami Helm repository. Install the `bitnami/nginx` chart as a release named `web-server` in the `web` namespace (create the namespace if needed). Then upgrade it to set `replicaCount=3`. Finally, rollback to revision 1.

    ??? success "Solution"
        ```bash
        # Add repo
        helm repo add bitnami https://charts.bitnami.com/bitnami
        helm repo update

        # Install
        helm install web-server bitnami/nginx --namespace web --create-namespace

        # Verify
        helm list -n web

        # Upgrade
        helm upgrade web-server bitnami/nginx -n web --set replicaCount=3

        # Check history
        helm history web-server -n web

        # Rollback to revision 1
        helm rollback web-server 1 -n web

        # Verify
        helm list -n web
        ```

??? question "Exercise 5: Kustomize Overlay"
    Create a base directory with a simple nginx Deployment (2 replicas) and a Service. Then create a production overlay that changes the namespace to `production`, adds the prefix `prod-`, and increases replicas to 5. Preview the generated manifests.

    ??? success "Solution"
        ```bash
        mkdir -p app/base app/overlays/prod
        ```

        ```yaml
        # app/base/deployment.yaml
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: nginx
        spec:
          replicas: 2
          selector:
            matchLabels:
              app: nginx
          template:
            metadata:
              labels:
                app: nginx
            spec:
              containers:
                - name: nginx
                  image: nginx:1.27
        ```

        ```yaml
        # app/base/service.yaml
        apiVersion: v1
        kind: Service
        metadata:
          name: nginx
        spec:
          selector:
            app: nginx
          ports:
            - port: 80
              targetPort: 80
        ```

        ```yaml
        # app/base/kustomization.yaml
        apiVersion: kustomize.config.k8s.io/v1beta1
        kind: Kustomization
        resources:
          - deployment.yaml
          - service.yaml
        ```

        ```yaml
        # app/overlays/prod/replica-patch.yaml
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: nginx
        spec:
          replicas: 5
        ```

        ```yaml
        # app/overlays/prod/kustomization.yaml
        apiVersion: kustomize.config.k8s.io/v1beta1
        kind: Kustomization
        resources:
          - ../../base
        namespace: production
        namePrefix: prod-
        patches:
          - path: replica-patch.yaml
        ```

        ```bash
        # Preview the generated manifests
        kubectl kustomize app/overlays/prod/

        # Apply when ready
        kubectl apply -k app/overlays/prod/
        ```

## Kubernetes Documentation References

- [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Rolling Updates](https://kubernetes.io/docs/tutorials/kubernetes-basics/update/update-intro/)
- [Helm Documentation](https://helm.sh/docs/)
- [Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)
