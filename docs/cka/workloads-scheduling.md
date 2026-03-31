# Workloads & Scheduling (15%)

This domain covers the core workload resources in Kubernetes and how the scheduler places pods onto nodes. You need to understand how to create, manage, and scale different workload types, configure resource constraints, and influence scheduling decisions using selectors, affinities, taints, and tolerations.

## Key Concepts

### Deployments

Deployments manage ReplicaSets and provide declarative updates for pods. They are the most common workload resource.

=== "Imperative"

    ```bash
    # Create a deployment
    kubectl create deployment nginx --image=nginx:1.25 --replicas=3

    # Scale a deployment
    kubectl scale deployment nginx --replicas=5

    # Update the image (triggers a rolling update)
    kubectl set image deployment/nginx nginx=nginx:1.26

    # Check rollout status
    kubectl rollout status deployment/nginx

    # View rollout history
    kubectl rollout history deployment/nginx

    # Rollback to the previous revision
    kubectl rollout undo deployment/nginx

    # Rollback to a specific revision
    kubectl rollout undo deployment/nginx --to-revision=2

    # Pause and resume a rollout
    kubectl rollout pause deployment/nginx
    kubectl rollout resume deployment/nginx
    ```

=== "Declarative"

    ```yaml
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: nginx
      labels:
        app: nginx
    spec:
      replicas: 3
      strategy:
        type: RollingUpdate
        rollingUpdate:
          maxSurge: 1
          maxUnavailable: 0
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
            image: nginx:1.25
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
    Use `kubectl create deployment` with `--dry-run=client -o yaml` to quickly generate a base YAML manifest, then edit it to add fields like strategy, resources, or volumes. This is much faster than writing YAML from scratch.

### DaemonSets

DaemonSets ensure that a copy of a pod runs on every (or selected) node. Common use cases include log collectors, monitoring agents, and network plugins.

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentd
  namespace: kube-system
  labels:
    app: fluentd
spec:
  selector:
    matchLabels:
      app: fluentd
  template:
    metadata:
      labels:
        app: fluentd
    spec:
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      containers:
      - name: fluentd
        image: fluentd:v1.16
        resources:
          requests:
            cpu: 100m
            memory: 200Mi
          limits:
            memory: 200Mi
        volumeMounts:
        - name: varlog
          mountPath: /var/log
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
```

```bash
# List DaemonSets
kubectl get daemonsets -A

# Check DaemonSet status
kubectl describe daemonset fluentd -n kube-system
```

### StatefulSets

StatefulSets manage stateful applications with stable network identities, persistent storage, and ordered deployment/scaling.

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  serviceName: mysql
  replicas: 3
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        ports:
        - containerPort: 3306
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: password
        volumeMounts:
        - name: data
          mountPath: /var/lib/mysql
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
```

Key characteristics:

- Pods get stable names: `mysql-0`, `mysql-1`, `mysql-2`
- Pods are created in order (0, 1, 2) and deleted in reverse order
- Each pod gets its own PersistentVolumeClaim
- Requires a headless Service (`clusterIP: None`)

### Jobs and CronJobs

=== "Job"

    ```yaml
    apiVersion: batch/v1
    kind: Job
    metadata:
      name: batch-process
    spec:
      completions: 5
      parallelism: 2
      backoffLimit: 3
      activeDeadlineSeconds: 120
      template:
        spec:
          restartPolicy: Never
          containers:
          - name: worker
            image: busybox
            command: ["sh", "-c", "echo Processing item && sleep 10"]
    ```

    ```bash
    # Create a job imperatively
    kubectl create job batch-process --image=busybox -- sh -c "echo done"

    # Check job status
    kubectl get jobs
    kubectl describe job batch-process

    # View completed pods
    kubectl get pods --selector=job-name=batch-process
    ```

=== "CronJob"

    ```yaml
    apiVersion: batch/v1
    kind: CronJob
    metadata:
      name: daily-backup
    spec:
      schedule: "0 2 * * *"
      successfulJobsHistoryLimit: 3
      failedJobsHistoryLimit: 1
      concurrencyPolicy: Forbid
      jobTemplate:
        spec:
          template:
            spec:
              restartPolicy: OnFailure
              containers:
              - name: backup
                image: busybox
                command: ["sh", "-c", "echo Running backup at $(date)"]
    ```

    ```bash
    # Create a CronJob imperatively
    kubectl create cronjob daily-backup --image=busybox \
      --schedule="0 2 * * *" -- sh -c "echo backup"

    # List CronJobs
    kubectl get cronjobs
    ```

### Resource Requests and Limits

Resource requests and limits control how much CPU and memory a container can use.

- **Requests**: The guaranteed amount of resources allocated to the container (used for scheduling)
- **Limits**: The maximum amount of resources a container can use

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: resource-demo
spec:
  containers:
  - name: app
    image: nginx
    resources:
      requests:
        cpu: 250m        # 0.25 CPU cores
        memory: 128Mi    # 128 MiB
      limits:
        cpu: 500m        # 0.5 CPU cores
        memory: 256Mi    # 256 MiB
```

!!! tip "Exam Tip"
    If a pod is stuck in `Pending` state, check if the cluster has enough resources to fulfill the pod's resource requests. Use `kubectl describe node` to see allocatable resources and current allocations.

### LimitRanges

LimitRanges set default requests/limits and enforce min/max constraints per container in a namespace.

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: resource-limits
  namespace: development
spec:
  limits:
  - type: Container
    default:
      cpu: 500m
      memory: 256Mi
    defaultRequest:
      cpu: 100m
      memory: 128Mi
    max:
      cpu: "2"
      memory: 1Gi
    min:
      cpu: 50m
      memory: 64Mi
```

### ResourceQuotas

ResourceQuotas limit the total resource consumption in a namespace.

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: development
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    pods: "20"
    services: "10"
    persistentvolumeclaims: "10"
```

```bash
# Create a ResourceQuota imperatively
kubectl create quota compute-quota -n development \
  --hard=requests.cpu=4,requests.memory=8Gi,limits.cpu=8,limits.memory=16Gi,pods=20

# Check quota usage
kubectl describe resourcequota compute-quota -n development
```

### Scheduling: nodeSelector

The simplest way to constrain pods to nodes with specific labels.

```bash
# Label a node
kubectl label node worker-1 disktype=ssd
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: ssd-pod
spec:
  nodeSelector:
    disktype: ssd
  containers:
  - name: app
    image: nginx
```

### Scheduling: Node Affinity

More expressive than `nodeSelector`, supporting `In`, `NotIn`, `Exists`, `DoesNotExist`, `Gt`, `Lt` operators.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: affinity-pod
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: topology.kubernetes.io/zone
            operator: In
            values:
            - eu-west-1a
            - eu-west-1b
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 1
        preference:
          matchExpressions:
          - key: disktype
            operator: In
            values:
            - ssd
  containers:
  - name: app
    image: nginx
```

### Taints and Tolerations

Taints are applied to nodes to repel pods. Tolerations are applied to pods to allow scheduling on tainted nodes.

```bash
# Add a taint to a node
kubectl taint nodes worker-1 env=production:NoSchedule

# Remove a taint
kubectl taint nodes worker-1 env=production:NoSchedule-
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: tolerant-pod
spec:
  tolerations:
  - key: "env"
    operator: "Equal"
    value: "production"
    effect: "NoSchedule"
  containers:
  - name: app
    image: nginx
```

Taint effects:

- **NoSchedule**: New pods without a matching toleration are not scheduled on the node
- **PreferNoSchedule**: Soft version -- the scheduler tries to avoid the node but does not guarantee it
- **NoExecute**: Existing pods without a matching toleration are evicted

!!! tip "Exam Tip"
    Remember: taints and tolerations do not guarantee that a pod runs on a specific node. They only prevent pods from being scheduled on tainted nodes. To ensure a pod runs on a specific node, combine tolerations with `nodeSelector` or `nodeAffinity`.

### Static Pods

Static pods are managed directly by the `kubelet` on a specific node, without the API server. They are defined as YAML files in the static pod manifest directory.

```bash
# Find the static pod manifest directory
cat /var/lib/kubelet/config.yaml | grep staticPodPath
# Default: /etc/kubernetes/manifests/

# Create a static pod
cat <<EOF > /etc/kubernetes/manifests/static-nginx.yaml
apiVersion: v1
kind: Pod
metadata:
  name: static-nginx
spec:
  containers:
  - name: nginx
    image: nginx
    ports:
    - containerPort: 80
EOF

# The kubelet will automatically create the pod
# Static pods are visible via the API server with the node name suffix
kubectl get pods
```

!!! tip "Exam Tip"
    Control plane components (`etcd`, `kube-apiserver`, `kube-scheduler`, `kube-controller-manager`) are themselves static pods managed by the kubelet. Their manifests are in `/etc/kubernetes/manifests/`.

### Multiple Schedulers

You can run custom schedulers alongside the default scheduler.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: custom-scheduled-pod
spec:
  schedulerName: my-custom-scheduler
  containers:
  - name: app
    image: nginx
```

```bash
# Check which scheduler scheduled a pod
kubectl get events --field-selector involvedObject.name=custom-scheduled-pod
```

## Practice Exercises

??? question "Exercise 1: Create and Scale a Deployment"
    Create a deployment named `webapp` with image `httpd:2.4` and 2 replicas. Then scale it to 5 replicas. Finally, update the image to `httpd:2.4.58` and verify the rollout.

    ??? success "Solution"
        ```bash
        # Create the deployment
        kubectl create deployment webapp --image=httpd:2.4 --replicas=2

        # Scale to 5 replicas
        kubectl scale deployment webapp --replicas=5

        # Update the image
        kubectl set image deployment/webapp httpd=httpd:2.4.58

        # Check rollout status
        kubectl rollout status deployment/webapp

        # Verify
        kubectl get deployment webapp
        kubectl get pods -l app=webapp
        ```

??? question "Exercise 2: Configure a Pod with Resource Limits"
    Create a pod named `limited-pod` in the `restricted` namespace using image `nginx`. Set CPU request to 100m, CPU limit to 200m, memory request to 64Mi, and memory limit to 128Mi.

    ??? success "Solution"
        ```bash
        kubectl create namespace restricted

        kubectl run limited-pod -n restricted --image=nginx \
          --dry-run=client -o yaml > limited-pod.yaml
        ```

        Edit `limited-pod.yaml` to add resources:

        ```yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: limited-pod
          namespace: restricted
        spec:
          containers:
          - name: limited-pod
            image: nginx
            resources:
              requests:
                cpu: 100m
                memory: 64Mi
              limits:
                cpu: 200m
                memory: 128Mi
        ```

        ```bash
        kubectl apply -f limited-pod.yaml
        kubectl describe pod limited-pod -n restricted
        ```

??? question "Exercise 3: Taint a Node and Schedule a Tolerant Pod"
    Taint node `worker-2` with `team=backend:NoSchedule`. Create a pod named `backend-app` with image `nginx` that tolerates this taint and is constrained to run only on `worker-2` using `nodeSelector`.

    ??? success "Solution"
        ```bash
        # Taint the node
        kubectl taint nodes worker-2 team=backend:NoSchedule

        # Label the node
        kubectl label nodes worker-2 role=backend
        ```

        ```yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: backend-app
        spec:
          nodeSelector:
            role: backend
          tolerations:
          - key: "team"
            operator: "Equal"
            value: "backend"
            effect: "NoSchedule"
          containers:
          - name: nginx
            image: nginx
        ```

        ```bash
        kubectl apply -f backend-app.yaml
        kubectl get pod backend-app -o wide
        ```

??? question "Exercise 4: Create a CronJob"
    Create a CronJob named `log-cleanup` that runs every 15 minutes, using image `busybox`, executing the command `echo "Cleaning logs at $(date)"`. Set `successfulJobsHistoryLimit` to 2 and `failedJobsHistoryLimit` to 1.

    ??? success "Solution"
        ```bash
        kubectl create cronjob log-cleanup --image=busybox \
          --schedule="*/15 * * * *" \
          --dry-run=client -o yaml \
          -- sh -c 'echo "Cleaning logs at $(date)"' > cronjob.yaml
        ```

        Edit `cronjob.yaml` to add history limits:

        ```yaml
        apiVersion: batch/v1
        kind: CronJob
        metadata:
          name: log-cleanup
        spec:
          schedule: "*/15 * * * *"
          successfulJobsHistoryLimit: 2
          failedJobsHistoryLimit: 1
          jobTemplate:
            spec:
              template:
                spec:
                  restartPolicy: OnFailure
                  containers:
                  - name: log-cleanup
                    image: busybox
                    command:
                    - sh
                    - -c
                    - 'echo "Cleaning logs at $(date)"'
        ```

        ```bash
        kubectl apply -f cronjob.yaml
        kubectl get cronjobs
        ```

??? question "Exercise 5: Create a Static Pod"
    Create a static pod named `static-web` on the control plane node using image `nginx:alpine` on port 80.

    ??? success "Solution"
        ```bash
        # SSH to the control plane node if needed

        # Check the static pod path
        cat /var/lib/kubelet/config.yaml | grep staticPodPath

        # Create the static pod manifest
        cat <<EOF > /etc/kubernetes/manifests/static-web.yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: static-web
        spec:
          containers:
          - name: nginx
            image: nginx:alpine
            ports:
            - containerPort: 80
        EOF

        # Verify (the pod name will have the node name appended)
        kubectl get pods -A | grep static-web
        ```

## Relevant Documentation

- [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [DaemonSets](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)
- [StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [CronJobs](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)
- [Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [LimitRange](https://kubernetes.io/docs/concepts/policy/limit-range/)
- [ResourceQuota](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- [Assigning Pods to Nodes](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/)
- [Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
- [Static Pods](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/)
