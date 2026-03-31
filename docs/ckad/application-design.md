# Application Design and Build (20%)

This domain focuses on the core building blocks of Kubernetes applications: designing pods with multiple containers, building container images, and using workload resources like Jobs and CronJobs. You need to understand multi-container patterns, how to define and use persistent storage from the application side, and Dockerfile best practices.

## Key Concepts

### Multi-Container Pod Patterns

Pods can contain multiple containers that share networking and storage. The most common multi-container patterns are:

- **Sidecar**: A helper container that extends the main container's functionality (e.g., log shipping, proxy, syncing files)
- **Init Container**: A container that runs to completion before the main application containers start (e.g., database migrations, config fetching)
- **Ambassador**: A proxy container that abstracts access to external services (e.g., connecting to different databases in different environments)
- **Adapter**: A container that transforms or normalizes output from the main container (e.g., reformatting logs)

#### Init Containers

Init containers run sequentially before application containers start. They are useful for setup tasks.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-init
spec:
  initContainers:
    - name: init-db-check
      image: busybox:1.36
      command: ['sh', '-c', 'until nslookup db-service.default.svc.cluster.local; do echo waiting for db; sleep 2; done']
  containers:
    - name: app
      image: nginx:1.27
      ports:
        - containerPort: 80
```

#### Sidecar Container

A sidecar runs alongside the main container for the entire lifecycle of the pod.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-sidecar
spec:
  containers:
    - name: app
      image: nginx:1.27
      volumeMounts:
        - name: shared-logs
          mountPath: /var/log/nginx
    - name: log-shipper
      image: busybox:1.36
      command: ['sh', '-c', 'tail -F /var/log/nginx/access.log']
      volumeMounts:
        - name: shared-logs
          mountPath: /var/log/nginx
  volumes:
    - name: shared-logs
      emptyDir: {}
```

!!! tip "Exam Tip"
    The exam may not explicitly name the pattern (sidecar, ambassador, adapter). Instead, it will describe what needs to happen and you must design the correct multi-container pod. Focus on understanding when to use shared volumes vs. shared networking between containers.

### Building Container Images

Understanding Dockerfile syntax is essential. You may be asked to inspect, fix, or create a Dockerfile.

#### Dockerfile Best Practices

```dockerfile
# Use specific base image tags, not :latest
FROM python:3.12-slim

# Set a working directory
WORKDIR /app

# Copy dependency file first for better layer caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Use a non-root user
RUN useradd -r appuser
USER appuser

# Expose the application port
EXPOSE 8080

# Use ENTRYPOINT for the main process, CMD for default arguments
ENTRYPOINT ["python"]
CMD ["app.py"]
```

Key best practices:

- Use multi-stage builds to reduce image size
- Minimize layers by combining RUN instructions
- Use `.dockerignore` to exclude unnecessary files
- Use specific image tags instead of `latest`
- Run as a non-root user
- Order layers from least to most frequently changing for cache efficiency

#### Multi-Stage Build Example

```dockerfile
# Build stage
FROM golang:1.22 AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /app/server .

# Runtime stage
FROM alpine:3.20
COPY --from=builder /app/server /usr/local/bin/server
USER 1000
ENTRYPOINT ["server"]
```

### Jobs

Jobs create one or more pods and ensure a specified number of them successfully terminate. Use Jobs for batch processing, one-time tasks, or any work that needs to run to completion.

=== "Imperative"

    ```bash
    # Create a simple Job
    kubectl create job my-job --image=busybox -- sh -c "echo Hello World"

    # Create a Job with specific completions and parallelism
    kubectl create job batch-job --image=busybox -- sh -c "echo processing"

    # View Job status
    kubectl get jobs
    kubectl describe job my-job

    # View logs of the Job's pod
    kubectl logs job/my-job
    ```

=== "Declarative"

    ```yaml
    apiVersion: batch/v1
    kind: Job
    metadata:
      name: batch-job
    spec:
      completions: 5
      parallelism: 2
      backoffLimit: 4
      activeDeadlineSeconds: 120
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: worker
              image: busybox:1.36
              command: ['sh', '-c', 'echo "Processing item" && sleep 5']
    ```

Key Job fields:

- `completions`: Number of successful completions required
- `parallelism`: Number of pods running concurrently
- `backoffLimit`: Number of retries before marking as failed
- `activeDeadlineSeconds`: Maximum runtime for the Job
- `restartPolicy`: Must be `Never` or `OnFailure` (not `Always`)

### CronJobs

CronJobs create Jobs on a scheduled basis using cron syntax.

=== "Imperative"

    ```bash
    # Create a CronJob that runs every 5 minutes
    kubectl create cronjob my-cron --image=busybox --schedule="*/5 * * * *" -- sh -c "echo Hello"

    # List CronJobs
    kubectl get cronjobs

    # View CronJob details
    kubectl describe cronjob my-cron
    ```

=== "Declarative"

    ```yaml
    apiVersion: batch/v1
    kind: CronJob
    metadata:
      name: cleanup-job
    spec:
      schedule: "0 */6 * * *"
      concurrencyPolicy: Forbid
      successfulJobsHistoryLimit: 3
      failedJobsHistoryLimit: 1
      jobTemplate:
        spec:
          template:
            spec:
              restartPolicy: OnFailure
              containers:
                - name: cleanup
                  image: busybox:1.36
                  command: ['sh', '-c', 'echo "Running cleanup at $(date)"']
    ```

Key CronJob fields:

- `schedule`: Cron expression (`minute hour day-of-month month day-of-week`)
- `concurrencyPolicy`: `Allow`, `Forbid`, or `Replace`
- `successfulJobsHistoryLimit`: Number of completed Jobs to retain
- `failedJobsHistoryLimit`: Number of failed Jobs to retain

### PersistentVolumeClaims

From the application developer perspective, PersistentVolumeClaims (PVCs) are used to request storage without needing to know the underlying storage details.

=== "Imperative"

    ```bash
    # There is no direct imperative command for PVC creation.
    # Generate YAML and apply it:
    cat <<EOF | kubectl apply -f -
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: app-data
    spec:
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: 1Gi
    EOF
    ```

=== "Declarative"

    ```yaml
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: app-data
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: standard
      resources:
        requests:
          storage: 1Gi
    ---
    apiVersion: v1
    kind: Pod
    metadata:
      name: app-with-storage
    spec:
      containers:
        - name: app
          image: nginx:1.27
          volumeMounts:
            - name: data
              mountPath: /usr/share/nginx/html
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: app-data
    ```

Access modes:

- `ReadWriteOnce` (RWO): Mounted as read-write by a single node
- `ReadOnlyMany` (ROX): Mounted as read-only by many nodes
- `ReadWriteMany` (RWX): Mounted as read-write by many nodes

!!! tip "Exam Tip"
    On the exam, if a StorageClass is available, the PVC will be dynamically provisioned. You typically only need to create the PVC and reference it in your Pod spec. Use `kubectl get storageclass` to check which StorageClasses are available.

## Practice Exercises

??? question "Exercise 1: Create a Pod with an Init Container"
    Create a pod named `web-app` in the `default` namespace. It should have an init container that creates a file `/work-dir/index.html` with the content "Hello from init". The main container should be `nginx:1.27` and serve that file. Use an `emptyDir` volume shared between both containers.

    ??? success "Solution"
        ```yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: web-app
        spec:
          initContainers:
            - name: init
              image: busybox:1.36
              command: ['sh', '-c', 'echo "Hello from init" > /work-dir/index.html']
              volumeMounts:
                - name: workdir
                  mountPath: /work-dir
          containers:
            - name: nginx
              image: nginx:1.27
              volumeMounts:
                - name: workdir
                  mountPath: /usr/share/nginx/html
          volumes:
            - name: workdir
              emptyDir: {}
        ```

        ```bash
        kubectl apply -f web-app.yaml
        kubectl exec web-app -- curl -s localhost
        ```

??? question "Exercise 2: Create a Job with Completions and Parallelism"
    Create a Job named `parallel-job` that runs the command `echo "Processing batch item"` and completes 6 times with a parallelism of 3. Set a backoff limit of 2.

    ??? success "Solution"
        ```bash
        kubectl create job parallel-job --image=busybox --dry-run=client -o yaml -- sh -c "echo Processing batch item" > job.yaml
        ```

        Edit `job.yaml` to add completions, parallelism, and backoffLimit:

        ```yaml
        apiVersion: batch/v1
        kind: Job
        metadata:
          name: parallel-job
        spec:
          completions: 6
          parallelism: 3
          backoffLimit: 2
          template:
            spec:
              restartPolicy: Never
              containers:
                - name: parallel-job
                  image: busybox
                  command: ['sh', '-c', 'echo Processing batch item']
        ```

        ```bash
        kubectl apply -f job.yaml
        kubectl get jobs parallel-job -w
        ```

??? question "Exercise 3: Create a CronJob"
    Create a CronJob named `log-cleanup` that runs every 15 minutes. It should execute `echo "Cleaning logs at $(date)"` using the `busybox:1.36` image. Set `concurrencyPolicy` to `Forbid` and keep only the last 2 successful job runs.

    ??? success "Solution"
        ```bash
        kubectl create cronjob log-cleanup \
          --image=busybox:1.36 \
          --schedule="*/15 * * * *" \
          --dry-run=client -o yaml \
          -- sh -c 'echo "Cleaning logs at $(date)"' > cronjob.yaml
        ```

        Edit to add concurrencyPolicy and history limits:

        ```yaml
        apiVersion: batch/v1
        kind: CronJob
        metadata:
          name: log-cleanup
        spec:
          schedule: "*/15 * * * *"
          concurrencyPolicy: Forbid
          successfulJobsHistoryLimit: 2
          failedJobsHistoryLimit: 1
          jobTemplate:
            spec:
              template:
                spec:
                  restartPolicy: OnFailure
                  containers:
                    - name: log-cleanup
                      image: busybox:1.36
                      command: ['sh', '-c', 'echo "Cleaning logs at $(date)"']
        ```

        ```bash
        kubectl apply -f cronjob.yaml
        kubectl get cronjobs
        ```

??? question "Exercise 4: Multi-Container Pod with Shared Volume"
    Create a pod named `multi-container` with two containers. The first container (`writer`) should use the `busybox:1.36` image and write the current date to `/data/log.txt` every 5 seconds. The second container (`reader`) should use the `busybox:1.36` image and continuously tail `/data/log.txt`. Both containers should share an `emptyDir` volume mounted at `/data`.

    ??? success "Solution"
        ```yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: multi-container
        spec:
          containers:
            - name: writer
              image: busybox:1.36
              command: ['sh', '-c', 'while true; do date >> /data/log.txt; sleep 5; done']
              volumeMounts:
                - name: shared-data
                  mountPath: /data
            - name: reader
              image: busybox:1.36
              command: ['sh', '-c', 'tail -F /data/log.txt']
              volumeMounts:
                - name: shared-data
                  mountPath: /data
          volumes:
            - name: shared-data
              emptyDir: {}
        ```

        ```bash
        kubectl apply -f multi-container.yaml
        kubectl logs multi-container -c reader -f
        ```

??? question "Exercise 5: PVC and Pod"
    Create a PersistentVolumeClaim named `my-pvc` requesting 500Mi of storage with `ReadWriteOnce` access mode. Then create a pod named `pvc-pod` using `nginx:1.27` that mounts this PVC at `/usr/share/nginx/html`.

    ??? success "Solution"
        ```yaml
        apiVersion: v1
        kind: PersistentVolumeClaim
        metadata:
          name: my-pvc
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 500Mi
        ---
        apiVersion: v1
        kind: Pod
        metadata:
          name: pvc-pod
        spec:
          containers:
            - name: nginx
              image: nginx:1.27
              volumeMounts:
                - name: html
                  mountPath: /usr/share/nginx/html
          volumes:
            - name: html
              persistentVolumeClaim:
                claimName: my-pvc
        ```

        ```bash
        kubectl apply -f pvc-pod.yaml
        kubectl get pvc my-pvc
        kubectl describe pod pvc-pod
        ```

## Kubernetes Documentation References

- [Init Containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)
- [Sidecar Containers](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/)
- [Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [CronJobs](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)
- [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Dockerfile Reference](https://docs.docker.com/reference/dockerfile/)
