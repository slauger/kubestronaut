# Application Observability and Maintenance (15%)

This domain covers monitoring, debugging, and maintaining applications running on Kubernetes. You need to understand health probes (liveness, readiness, startup), how to access logs and metrics, debugging techniques using kubectl, API deprecations, and how to interpret resource status fields.

## Key Concepts

### Probes

Probes are periodic checks that Kubernetes performs on containers to determine their health and readiness. There are three types of probes, each serving a different purpose.

#### Liveness Probe

Determines if a container is still running. If the liveness probe fails, Kubernetes kills the container and restarts it according to the pod's restart policy.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: liveness-example
spec:
  containers:
    - name: app
      image: nginx:1.27
      livenessProbe:
        httpGet:
          path: /healthz
          port: 8080
        initialDelaySeconds: 15
        periodSeconds: 10
        timeoutSeconds: 3
        failureThreshold: 3
        successThreshold: 1
```

#### Readiness Probe

Determines if a container is ready to accept traffic. If the readiness probe fails, the pod is removed from Service endpoints but is not restarted. Traffic stops flowing to the pod until the probe succeeds again.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: readiness-example
spec:
  containers:
    - name: app
      image: nginx:1.27
      readinessProbe:
        httpGet:
          path: /ready
          port: 8080
        initialDelaySeconds: 5
        periodSeconds: 5
        failureThreshold: 3
```

#### Startup Probe

Used for slow-starting containers. While the startup probe is active, liveness and readiness probes are disabled. Once the startup probe succeeds, the other probes take over.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: startup-example
spec:
  containers:
    - name: app
      image: myapp:1.0
      startupProbe:
        httpGet:
          path: /healthz
          port: 8080
        initialDelaySeconds: 10
        periodSeconds: 10
        failureThreshold: 30   # 30 * 10 = 300s max startup time
      livenessProbe:
        httpGet:
          path: /healthz
          port: 8080
        periodSeconds: 10
      readinessProbe:
        httpGet:
          path: /ready
          port: 8080
        periodSeconds: 5
```

#### Probe Mechanisms

Probes support three check mechanisms:

=== "HTTP GET"

    ```yaml
    livenessProbe:
      httpGet:
        path: /healthz
        port: 8080
        httpHeaders:
          - name: Custom-Header
            value: Awesome
    ```

=== "TCP Socket"

    ```yaml
    livenessProbe:
      tcpSocket:
        port: 3306
    ```

=== "Command (exec)"

    ```yaml
    livenessProbe:
      exec:
        command:
          - cat
          - /tmp/healthy
    ```

Probe timing parameters:

| Parameter | Description | Default |
|---|---|---|
| `initialDelaySeconds` | Seconds before the first probe | 0 |
| `periodSeconds` | How often to perform the probe | 10 |
| `timeoutSeconds` | Seconds before the probe times out | 1 |
| `failureThreshold` | Consecutive failures before taking action | 3 |
| `successThreshold` | Consecutive successes to be considered successful | 1 |

!!! tip "Exam Tip"
    The key difference: **liveness** restarts the container on failure, **readiness** removes the pod from service endpoints. Use startup probes for applications that take a long time to initialize. On the exam, set `initialDelaySeconds` appropriately to avoid premature failures. Use `kubectl describe pod` to check probe status and failure messages in the Events section.

### Logging

Kubernetes captures stdout and stderr from containers. Use `kubectl logs` to access these logs.

```bash
# View logs of a pod
kubectl logs my-pod

# View logs of a specific container in a multi-container pod
kubectl logs my-pod -c sidecar

# Follow logs in real time
kubectl logs my-pod -f

# View logs from the previous instance of a container (after restart)
kubectl logs my-pod --previous

# View last N lines
kubectl logs my-pod --tail=50

# View logs since a specific time
kubectl logs my-pod --since=1h
kubectl logs my-pod --since-time=2024-01-01T00:00:00Z

# View logs from all pods matching a label
kubectl logs -l app=webapp --all-containers=true

# View logs from a Job
kubectl logs job/my-job
```

!!! tip "Exam Tip"
    Use `kubectl logs <pod> --previous` to see logs from a crashed or restarted container. This is essential for debugging CrashLoopBackOff issues. When dealing with multi-container pods, always specify the container name with `-c`.

### Monitoring

The `kubectl top` command requires the Metrics Server to be installed in the cluster.

```bash
# View resource usage of pods
kubectl top pods
kubectl top pods -n kube-system
kubectl top pods --sort-by=cpu
kubectl top pods --sort-by=memory

# View resource usage of a specific pod
kubectl top pod my-pod

# View resource usage of containers within a pod
kubectl top pod my-pod --containers

# View resource usage of nodes
kubectl top nodes
```

```bash
# Check if Metrics Server is running
kubectl get deployment metrics-server -n kube-system

# View the resource requests and limits vs actual usage
kubectl describe node <node-name> | grep -A 5 "Allocated resources"
```

### Debugging

Effective debugging involves inspecting pod state, checking events, and executing commands inside containers.

#### kubectl describe

```bash
# Describe a pod (shows events, conditions, container status)
kubectl describe pod my-pod

# Key sections to look at:
# - Status: Current pod phase (Pending, Running, Failed, etc.)
# - Conditions: PodScheduled, Initialized, ContainersReady, Ready
# - Events: Scheduling, pulling images, probe failures, OOM kills
# - Container State: Waiting (reason), Running, Terminated (reason, exit code)
```

#### kubectl exec

```bash
# Execute a command in a running container
kubectl exec my-pod -- ls /app

# Open an interactive shell
kubectl exec -it my-pod -- /bin/sh
kubectl exec -it my-pod -- /bin/bash

# Execute in a specific container of a multi-container pod
kubectl exec -it my-pod -c sidecar -- /bin/sh

# Common debugging commands inside a container
kubectl exec my-pod -- env                 # Check environment variables
kubectl exec my-pod -- cat /etc/resolv.conf  # Check DNS config
kubectl exec my-pod -- wget -qO- localhost:8080  # Test application
```

#### kubectl port-forward

```bash
# Forward a local port to a pod
kubectl port-forward pod/my-pod 8080:80

# Forward to a Service
kubectl port-forward svc/my-service 8080:80

# Forward to a Deployment
kubectl port-forward deployment/my-deploy 8080:80

# Listen on all interfaces (not just localhost)
kubectl port-forward --address 0.0.0.0 pod/my-pod 8080:80
```

#### Common Debugging Workflow

```bash
# 1. Check pod status
kubectl get pods -o wide

# 2. Look at pod events and conditions
kubectl describe pod <pod-name>

# 3. Check container logs
kubectl logs <pod-name>
kubectl logs <pod-name> --previous  # If container restarted

# 4. Check if the application is responding
kubectl exec <pod-name> -- wget -qO- localhost:<port>

# 5. Check service endpoints
kubectl get endpoints <service-name>

# 6. Test connectivity from another pod
kubectl run debug --image=busybox:1.36 --rm -it --restart=Never -- wget -qO- <service-name>:<port>

# 7. Check resource usage
kubectl top pod <pod-name>
```

!!! tip "Exam Tip"
    When debugging during the exam, always start with `kubectl describe pod` to check Events. Common issues: `ImagePullBackOff` (wrong image name/tag), `CrashLoopBackOff` (application error, check logs), `Pending` (insufficient resources or unschedulable, check events), `ContainerCreating` stuck (volume mount issues, secret not found). Use `kubectl get events --sort-by=.metadata.creationTimestamp` to see recent cluster events.

### API Deprecations

Kubernetes regularly deprecates and removes API versions. Understanding API deprecations is important for maintaining manifests.

```bash
# Check available API versions
kubectl api-versions

# Check available API resources and their versions
kubectl api-resources

# Check if a specific resource has deprecated versions
kubectl explain deployment

# Convert a manifest to a newer API version (if kubectl convert plugin is installed)
kubectl convert -f old-deployment.yaml --output-version apps/v1
```

Common deprecation patterns:

| Old API | New API | Resource |
|---|---|---|
| `extensions/v1beta1` | `networking.k8s.io/v1` | Ingress |
| `extensions/v1beta1` | `apps/v1` | Deployment |
| `batch/v1beta1` | `batch/v1` | CronJob |
| `policy/v1beta1` | `policy/v1` | PodDisruptionBudget |

```bash
# Check which API group/version a resource belongs to
kubectl api-resources | grep -i deployment
kubectl api-resources | grep -i ingress

# Validate a manifest against the cluster's API schema
kubectl apply -f manifest.yaml --dry-run=server
```

!!! tip "Exam Tip"
    On the exam, always use the current stable API versions. If you generate YAML from `kubectl` imperative commands, the correct API version is used automatically. If you copy YAML from external sources or old documentation, verify the `apiVersion` is correct. Use `kubectl api-resources` to check the current version for any resource.

### Understanding Resource Status

Being able to read and interpret resource status is essential for debugging.

#### Pod Phases and Status

| Phase | Description |
|---|---|
| `Pending` | Pod accepted but not yet running (scheduling, image pulling) |
| `Running` | At least one container is running |
| `Succeeded` | All containers terminated successfully |
| `Failed` | All containers terminated, at least one failed |
| `Unknown` | Pod state cannot be determined |

#### Common Pod Conditions

```bash
# View pod conditions
kubectl get pod my-pod -o jsonpath='{.status.conditions[*].type}'

# Detailed condition check
kubectl get pod my-pod -o yaml | grep -A 3 conditions
```

| Condition | Description |
|---|---|
| `PodScheduled` | Pod has been scheduled to a node |
| `Initialized` | All init containers completed successfully |
| `ContainersReady` | All containers in the pod are ready |
| `Ready` | Pod is ready to serve requests |

#### Deployment Status

```bash
# Check Deployment conditions
kubectl get deployment my-deploy -o yaml | grep -A 10 conditions

# Quick status check
kubectl rollout status deployment/my-deploy

# View ReplicaSets managed by the Deployment
kubectl get replicasets -l app=my-deploy
```

## Practice Exercises

??? question "Exercise 1: Add Probes to a Pod"
    Create a pod named `health-check` using the `nginx:1.27` image. Add a liveness probe that checks HTTP GET on path `/` and port 80 with an initial delay of 10 seconds and a period of 5 seconds. Add a readiness probe that checks the same endpoint with an initial delay of 5 seconds and a period of 3 seconds.

    ??? success "Solution"
        ```yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: health-check
        spec:
          containers:
            - name: nginx
              image: nginx:1.27
              ports:
                - containerPort: 80
              livenessProbe:
                httpGet:
                  path: /
                  port: 80
                initialDelaySeconds: 10
                periodSeconds: 5
              readinessProbe:
                httpGet:
                  path: /
                  port: 80
                initialDelaySeconds: 5
                periodSeconds: 3
        ```

        ```bash
        kubectl apply -f health-check.yaml

        # Verify probes are configured
        kubectl describe pod health-check | grep -A 5 "Liveness\|Readiness"

        # Check pod is ready
        kubectl get pod health-check
        ```

??? question "Exercise 2: Debug a Failing Pod"
    Create a pod named `failing-pod` using the `busybox:1.36` image with the command `exit 1`. Observe the CrashLoopBackOff. Investigate the issue using `kubectl describe` and `kubectl logs`. Then fix the pod by changing the command to `sleep 3600`.

    ??? success "Solution"
        ```bash
        # Create the failing pod
        kubectl run failing-pod --image=busybox:1.36 --restart=Always -- sh -c "exit 1"

        # Watch it enter CrashLoopBackOff
        kubectl get pod failing-pod -w

        # Investigate
        kubectl describe pod failing-pod
        # Look at Events: Back-off restarting failed container
        # Look at State: Terminated, Exit Code: 1

        kubectl logs failing-pod --previous
        # No output since the container exits immediately

        # Fix the pod: delete and recreate
        kubectl delete pod failing-pod
        kubectl run failing-pod --image=busybox:1.36 -- sleep 3600

        # Verify it's running
        kubectl get pod failing-pod
        ```

??? question "Exercise 3: Exec and Port-Forward"
    Create a Deployment named `debug-app` with 1 replica using `nginx:1.27`. Use `kubectl exec` to create a custom `index.html` file inside the container at `/usr/share/nginx/html/index.html` with the content "Debug Test". Then use `kubectl port-forward` to access the pod on local port 9090 and verify the custom page is served.

    ??? success "Solution"
        ```bash
        # Create the Deployment
        kubectl create deployment debug-app --image=nginx:1.27

        # Wait for the pod to be ready
        kubectl rollout status deployment/debug-app

        # Get the pod name
        POD=$(kubectl get pods -l app=debug-app -o jsonpath='{.items[0].metadata.name}')

        # Write custom index.html
        kubectl exec $POD -- sh -c 'echo "Debug Test" > /usr/share/nginx/html/index.html'

        # Verify from inside the container
        kubectl exec $POD -- cat /usr/share/nginx/html/index.html

        # Port-forward (run in background or separate terminal)
        kubectl port-forward $POD 9090:80 &

        # Test from local machine
        curl localhost:9090
        # Output: Debug Test

        # Stop port-forward
        kill %1
        ```

??? question "Exercise 4: Pod with Startup Probe"
    Create a pod named `slow-start` using the `nginx:1.27` image. Configure a startup probe that checks HTTP GET on path `/` and port 80, with an initial delay of 5 seconds, period of 10 seconds, and failure threshold of 12 (allowing up to 2 minutes for startup). Add a liveness probe that checks the same path every 10 seconds.

    ??? success "Solution"
        ```yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: slow-start
        spec:
          containers:
            - name: nginx
              image: nginx:1.27
              ports:
                - containerPort: 80
              startupProbe:
                httpGet:
                  path: /
                  port: 80
                initialDelaySeconds: 5
                periodSeconds: 10
                failureThreshold: 12
              livenessProbe:
                httpGet:
                  path: /
                  port: 80
                periodSeconds: 10
        ```

        ```bash
        kubectl apply -f slow-start.yaml
        kubectl describe pod slow-start | grep -A 5 "Startup\|Liveness"
        kubectl get pod slow-start
        ```

??? question "Exercise 5: Investigate Resource Usage and Events"
    Create a Deployment named `resource-app` with 2 replicas using `nginx:1.27` with resource requests of 50m CPU and 64Mi memory. After the pods are running, check the resource usage with `kubectl top`, list recent events sorted by timestamp, and verify the pod conditions.

    ??? success "Solution"
        ```bash
        # Create the Deployment with resources
        kubectl create deployment resource-app --image=nginx:1.27 --replicas=2 \
          --dry-run=client -o yaml > deploy.yaml
        ```

        Edit `deploy.yaml` to add resources, then apply:

        ```yaml
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: resource-app
        spec:
          replicas: 2
          selector:
            matchLabels:
              app: resource-app
          template:
            metadata:
              labels:
                app: resource-app
            spec:
              containers:
                - name: nginx
                  image: nginx:1.27
                  resources:
                    requests:
                      cpu: 50m
                      memory: 64Mi
        ```

        ```bash
        kubectl apply -f deploy.yaml
        kubectl rollout status deployment/resource-app

        # Check resource usage (requires metrics-server)
        kubectl top pods -l app=resource-app

        # View recent events
        kubectl get events --sort-by=.metadata.creationTimestamp

        # Check pod conditions
        kubectl get pods -l app=resource-app -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[*].type}{"\n"}{end}'

        # Detailed status
        kubectl get pods -l app=resource-app -o wide
        kubectl describe pod -l app=resource-app | grep -A 3 "Conditions"
        ```

## Kubernetes Documentation References

- [Configure Liveness, Readiness and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Logging Architecture](https://kubernetes.io/docs/concepts/cluster-administration/logging/)
- [Resource Metrics Pipeline](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)
- [Debug Running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/)
- [Kubernetes API Deprecation Policy](https://kubernetes.io/docs/reference/using-api/deprecation-policy/)
- [Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
