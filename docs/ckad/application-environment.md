# Application Environment, Configuration and Security (25%)

This is the highest-weighted domain in the CKAD exam. It covers how to configure applications using ConfigMaps and Secrets, secure them with SecurityContexts and ServiceAccounts, and manage resource consumption with requests, limits, LimitRanges, and ResourceQuotas. Mastering these topics is critical for exam success.

## Key Concepts

### ConfigMaps

ConfigMaps store non-confidential configuration data as key-value pairs. They can be consumed as environment variables, command-line arguments, or configuration files mounted into pods.

=== "Imperative"

    ```bash
    # Create from literal values
    kubectl create configmap app-config \
      --from-literal=APP_ENV=production \
      --from-literal=LOG_LEVEL=info

    # Create from a file
    kubectl create configmap nginx-config --from-file=nginx.conf

    # Create from a directory (each file becomes a key)
    kubectl create configmap config-dir --from-file=./config/

    # Create from an env file
    kubectl create configmap env-config --from-env-file=app.env

    # View a ConfigMap
    kubectl get configmap app-config -o yaml
    kubectl describe configmap app-config
    ```

=== "Declarative"

    ```yaml
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: app-config
    data:
      APP_ENV: production
      LOG_LEVEL: info
      config.yaml: |
        server:
          port: 8080
          timeout: 30s
    ```

#### Using ConfigMaps in Pods

**As environment variables:**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  containers:
    - name: app
      image: nginx:1.27
      env:
        # Single key from ConfigMap
        - name: APP_ENV
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: APP_ENV
      envFrom:
        # All keys from ConfigMap as env vars
        - configMapRef:
            name: app-config
```

**As a mounted volume:**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  containers:
    - name: app
      image: nginx:1.27
      volumeMounts:
        - name: config-volume
          mountPath: /etc/config
  volumes:
    - name: config-volume
      configMap:
        name: app-config
```

!!! tip "Exam Tip"
    When mounting a ConfigMap as a volume, each key becomes a file in the mount directory. If you only need specific keys, use `items` to select them. ConfigMaps mounted as volumes are updated automatically when the ConfigMap changes (with a delay), while environment variables require a pod restart.

### Secrets

Secrets store sensitive data such as passwords, tokens, and certificates. They are similar to ConfigMaps but are base64-encoded and intended for confidential data.

=== "Imperative"

    ```bash
    # Create from literal values
    kubectl create secret generic db-credentials \
      --from-literal=username=admin \
      --from-literal=password=s3cret

    # Create from a file
    kubectl create secret generic tls-cert --from-file=cert.pem --from-file=key.pem

    # Create a Docker registry secret
    kubectl create secret docker-registry regcred \
      --docker-server=registry.example.com \
      --docker-username=user \
      --docker-password=pass

    # View a Secret (values are base64-encoded)
    kubectl get secret db-credentials -o yaml

    # Decode a Secret value
    kubectl get secret db-credentials -o jsonpath='{.data.password}' | base64 -d
    ```

=== "Declarative"

    ```yaml
    apiVersion: v1
    kind: Secret
    metadata:
      name: db-credentials
    type: Opaque
    stringData:         # Use stringData for plain text (auto-encoded)
      username: admin
      password: s3cret
    ```

    Using base64-encoded `data` field:

    ```yaml
    apiVersion: v1
    kind: Secret
    metadata:
      name: db-credentials
    type: Opaque
    data:
      username: YWRtaW4=      # echo -n "admin" | base64
      password: czNjcmV0      # echo -n "s3cret" | base64
    ```

#### Using Secrets in Pods

**As environment variables:**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  containers:
    - name: app
      image: myapp:1.0
      env:
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: username
        - name: DB_PASS
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: password
      envFrom:
        - secretRef:
            name: db-credentials
```

**As a mounted volume:**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  containers:
    - name: app
      image: myapp:1.0
      volumeMounts:
        - name: secret-volume
          mountPath: /etc/secrets
          readOnly: true
  volumes:
    - name: secret-volume
      secret:
        secretName: db-credentials
```

!!! tip "Exam Tip"
    Use `stringData` instead of `data` in Secret manifests to avoid having to manually base64-encode values. Kubernetes encodes them automatically. For the exam, know how to create Secrets both imperatively and declaratively, and how to consume them as env vars and volumes.

### SecurityContext

SecurityContext defines privilege and access control settings for pods and containers. These are critical for running secure applications.

#### Pod-Level SecurityContext

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
spec:
  securityContext:
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000
    runAsNonRoot: true
  containers:
    - name: app
      image: nginx:1.27
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop:
            - ALL
          add:
            - NET_BIND_SERVICE
```

Key SecurityContext fields:

| Field | Level | Description |
|---|---|---|
| `runAsUser` | Pod/Container | UID to run the container process |
| `runAsGroup` | Pod/Container | GID for the container process |
| `runAsNonRoot` | Pod/Container | Reject container if running as root |
| `fsGroup` | Pod | GID for volume ownership |
| `readOnlyRootFilesystem` | Container | Mount root filesystem as read-only |
| `allowPrivilegeEscalation` | Container | Prevent child processes from gaining more privileges |
| `capabilities` | Container | Add or drop Linux capabilities |

```bash
# Verify the user running inside a container
kubectl exec secure-pod -- id

# Check if root filesystem is read-only
kubectl exec secure-pod -- touch /test-file
# Should fail with "Read-only file system"
```

!!! tip "Exam Tip"
    Container-level `securityContext` overrides pod-level settings for the same fields. When the exam asks you to "ensure the container runs as a non-root user", set `runAsNonRoot: true` at the pod level and/or `runAsUser: 1000` at the container level. Always drop `ALL` capabilities and only add the specific ones needed.

### ServiceAccounts

ServiceAccounts provide an identity for processes running in pods. They are used to authenticate with the Kubernetes API and external services.

```bash
# Create a ServiceAccount
kubectl create serviceaccount app-sa

# List ServiceAccounts
kubectl get serviceaccounts

# View details
kubectl describe serviceaccount app-sa

# Create a token for a ServiceAccount
kubectl create token app-sa
```

Using a ServiceAccount in a Pod:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  serviceAccountName: app-sa
  automountServiceAccountToken: false  # Disable if API access is not needed
  containers:
    - name: app
      image: myapp:1.0
```

!!! tip "Exam Tip"
    By default, pods use the `default` ServiceAccount. If the exam asks you to run a pod with a specific ServiceAccount, set `serviceAccountName` in the pod spec. Set `automountServiceAccountToken: false` when the application does not need to communicate with the Kubernetes API -- this follows the principle of least privilege.

### Resource Requests and Limits

Resource requests and limits control how much CPU and memory a container can use.

- **Requests**: The guaranteed minimum resources for a container. Used for scheduling decisions.
- **Limits**: The maximum resources a container can use. Exceeding memory limits kills the container; exceeding CPU limits throttles it.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: resource-pod
spec:
  containers:
    - name: app
      image: nginx:1.27
      resources:
        requests:
          cpu: 100m        # 0.1 CPU core
          memory: 128Mi    # 128 MiB
        limits:
          cpu: 500m        # 0.5 CPU core
          memory: 256Mi    # 256 MiB
```

```bash
# View resource usage of pods
kubectl top pods

# View resource usage of nodes
kubectl top nodes

# Check resource requests/limits of a pod
kubectl describe pod resource-pod | grep -A 5 "Limits\|Requests"
```

CPU units:

- `1` = 1 CPU core
- `100m` = 0.1 CPU core (100 millicores)
- `500m` = 0.5 CPU core

Memory units:

- `128Mi` = 128 mebibytes
- `1Gi` = 1 gibibyte
- `256M` = 256 megabytes (decimal, less common)

### LimitRanges

LimitRanges set default and enforceable resource constraints for individual containers within a namespace.

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: dev
spec:
  limits:
    - type: Container
      default:          # Default limits if not specified
        cpu: 500m
        memory: 256Mi
      defaultRequest:   # Default requests if not specified
        cpu: 100m
        memory: 128Mi
      max:              # Maximum allowed
        cpu: "2"
        memory: 1Gi
      min:              # Minimum allowed
        cpu: 50m
        memory: 64Mi
```

```bash
# Create a LimitRange
kubectl apply -f limitrange.yaml

# View LimitRanges in a namespace
kubectl get limitranges -n dev
kubectl describe limitrange default-limits -n dev
```

### ResourceQuotas

ResourceQuotas limit the total resource consumption and object count within a namespace.

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: dev-quota
  namespace: dev
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 4Gi
    limits.cpu: "8"
    limits.memory: 8Gi
    pods: "20"
    services: "10"
    persistentvolumeclaims: "5"
    configmaps: "10"
    secrets: "10"
```

```bash
# Create a ResourceQuota
kubectl apply -f quota.yaml

# View ResourceQuota usage
kubectl get resourcequota dev-quota -n dev
kubectl describe resourcequota dev-quota -n dev
```

!!! tip "Exam Tip"
    When a ResourceQuota is active in a namespace, pods must specify resource requests and limits (or the namespace must have a LimitRange with defaults). Otherwise, pod creation will be rejected. If you see "forbidden: failed quota" errors, check if the namespace has a ResourceQuota and ensure your pod spec includes resource requests/limits.

## Practice Exercises

??? question "Exercise 1: ConfigMap as Environment Variables and Volume"
    Create a ConfigMap named `webapp-config` with the keys `DB_HOST=mysql.default.svc` and `DB_PORT=3306`. Create a pod named `webapp` that uses the `nginx:1.27` image and loads both values as environment variables. Also mount the ConfigMap as a volume at `/etc/app-config`.

    ??? success "Solution"
        ```bash
        # Create the ConfigMap
        kubectl create configmap webapp-config \
          --from-literal=DB_HOST=mysql.default.svc \
          --from-literal=DB_PORT=3306
        ```

        ```yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: webapp
        spec:
          containers:
            - name: webapp
              image: nginx:1.27
              envFrom:
                - configMapRef:
                    name: webapp-config
              volumeMounts:
                - name: config
                  mountPath: /etc/app-config
          volumes:
            - name: config
              configMap:
                name: webapp-config
        ```

        ```bash
        kubectl apply -f webapp.yaml

        # Verify environment variables
        kubectl exec webapp -- env | grep DB_

        # Verify volume mount
        kubectl exec webapp -- ls /etc/app-config
        kubectl exec webapp -- cat /etc/app-config/DB_HOST
        ```

??? question "Exercise 2: Secret with Volume Mount"
    Create a Secret named `api-credentials` with `API_KEY=abc123` and `API_SECRET=xyz789`. Create a pod named `api-client` using `busybox:1.36` that mounts the Secret at `/etc/api` as read-only and sleeps for 3600 seconds.

    ??? success "Solution"
        ```bash
        # Create the Secret
        kubectl create secret generic api-credentials \
          --from-literal=API_KEY=abc123 \
          --from-literal=API_SECRET=xyz789
        ```

        ```yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: api-client
        spec:
          containers:
            - name: api-client
              image: busybox:1.36
              command: ['sleep', '3600']
              volumeMounts:
                - name: api-secret
                  mountPath: /etc/api
                  readOnly: true
          volumes:
            - name: api-secret
              secret:
                secretName: api-credentials
        ```

        ```bash
        kubectl apply -f api-client.yaml

        # Verify
        kubectl exec api-client -- ls /etc/api
        kubectl exec api-client -- cat /etc/api/API_KEY
        ```

??? question "Exercise 3: SecurityContext with Non-Root User"
    Create a pod named `secure-app` using the `busybox:1.36` image that runs as user ID 1000, group ID 3000, has a read-only root filesystem, drops all capabilities, and disallows privilege escalation. The container should run `sleep 3600`.

    ??? success "Solution"
        ```yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: secure-app
        spec:
          securityContext:
            runAsUser: 1000
            runAsGroup: 3000
            runAsNonRoot: true
          containers:
            - name: secure-app
              image: busybox:1.36
              command: ['sleep', '3600']
              securityContext:
                readOnlyRootFilesystem: true
                allowPrivilegeEscalation: false
                capabilities:
                  drop:
                    - ALL
        ```

        ```bash
        kubectl apply -f secure-app.yaml

        # Verify user
        kubectl exec secure-app -- id
        # Output: uid=1000 gid=3000

        # Verify read-only filesystem
        kubectl exec secure-app -- touch /tmp/test
        # Should fail: Read-only file system
        ```

??? question "Exercise 4: ServiceAccount and Resource Limits"
    Create a ServiceAccount named `backend-sa` in the `default` namespace. Create a pod named `backend` using `nginx:1.27` that uses this ServiceAccount, disables automatic token mounting, and has resource requests of 100m CPU and 128Mi memory with limits of 200m CPU and 256Mi memory.

    ??? success "Solution"
        ```bash
        # Create ServiceAccount
        kubectl create serviceaccount backend-sa
        ```

        ```yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: backend
        spec:
          serviceAccountName: backend-sa
          automountServiceAccountToken: false
          containers:
            - name: backend
              image: nginx:1.27
              resources:
                requests:
                  cpu: 100m
                  memory: 128Mi
                limits:
                  cpu: 200m
                  memory: 256Mi
        ```

        ```bash
        kubectl apply -f backend.yaml

        # Verify ServiceAccount
        kubectl get pod backend -o jsonpath='{.spec.serviceAccountName}'

        # Verify no token is mounted
        kubectl exec backend -- ls /var/run/secrets/kubernetes.io/serviceaccount 2>&1
        # Should show "No such file or directory"

        # Verify resources
        kubectl describe pod backend | grep -A 4 "Limits\|Requests"
        ```

??? question "Exercise 5: ResourceQuota and LimitRange"
    Create a namespace named `quota-test`. Create a LimitRange that sets default container requests to 100m CPU / 128Mi memory and default limits to 200m CPU / 256Mi memory. Create a ResourceQuota that limits the namespace to a maximum of 1 CPU and 1Gi memory for requests, and 5 pods total. Then create a pod in that namespace without specifying resources and verify the defaults are applied.

    ??? success "Solution"
        ```bash
        # Create namespace
        kubectl create namespace quota-test
        ```

        ```yaml
        # limitrange.yaml
        apiVersion: v1
        kind: LimitRange
        metadata:
          name: default-limits
          namespace: quota-test
        spec:
          limits:
            - type: Container
              default:
                cpu: 200m
                memory: 256Mi
              defaultRequest:
                cpu: 100m
                memory: 128Mi
        ---
        # quota.yaml
        apiVersion: v1
        kind: ResourceQuota
        metadata:
          name: ns-quota
          namespace: quota-test
        spec:
          hard:
            requests.cpu: "1"
            requests.memory: 1Gi
            pods: "5"
        ```

        ```bash
        kubectl apply -f limitrange.yaml
        kubectl apply -f quota.yaml

        # Create a pod without resource specifications
        kubectl run test-pod --image=nginx:1.27 -n quota-test

        # Verify defaults were applied
        kubectl describe pod test-pod -n quota-test | grep -A 4 "Limits\|Requests"

        # Check quota usage
        kubectl describe resourcequota ns-quota -n quota-test
        ```

## Kubernetes Documentation References

- [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Security Context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
- [Service Accounts](https://kubernetes.io/docs/concepts/security/service-accounts/)
- [Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Limit Ranges](https://kubernetes.io/docs/concepts/policy/limit-range/)
- [Resource Quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
