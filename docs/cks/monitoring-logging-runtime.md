# Monitoring, Logging and Runtime Security (20%)

This domain covers detecting and responding to security threats at runtime. You need to know how to use Falco for behavioral monitoring, configure API server audit logging, enforce immutable containers, perform behavioral analytics, and investigate runtime security incidents. At 20% of the exam weight, this is one of the most critical domains.

## Key Concepts

### Falco

Falco is an open-source runtime security tool originally created by Sysdig and now a CNCF project. It detects unexpected application behavior and threats at runtime by monitoring Linux system calls using kernel modules or eBPF.

#### Falco Architecture

Falco operates by:

1. Capturing system calls from the kernel (via kernel module or eBPF probe)
2. Evaluating syscalls against a set of rules
3. Alerting when a rule condition is matched

#### Falco Rules

Falco rules define what behavior to detect. Each rule has a condition (written in Falco's filter syntax), an output template, and a priority level.

```yaml
# Example: Detect shell execution in a container
- rule: Terminal shell in container
  desc: >
    A shell was used as the entrypoint/exec point into a container
    with an attached terminal.
  condition: >
    spawned_process and container
    and shell_procs and proc.tty != 0
    and container_entrypoint
    and not user_expected_terminal_shell_in_container_conditions
  output: >
    A shell was spawned in a container with an attached terminal
    (evt_type=%evt.type user=%user.name user_uid=%user.uid
    user_loginuid=%user.loginuid process=%proc.name
    proc_exepath=%proc.exepath parent=%proc.pname
    command=%proc.cmdline terminal=%proc.tty exe_flags=%evt.arg.flags
    %container.info)
  priority: NOTICE
  tags: [container, shell, mitre_execution]
```

#### Key Falco Rule Elements

| Element | Description |
|---|---|
| `rule` | Name of the rule |
| `desc` | Human-readable description |
| `condition` | Filter expression that triggers the rule |
| `output` | Template for the alert message |
| `priority` | Severity: `EMERGENCY`, `ALERT`, `CRITICAL`, `ERROR`, `WARNING`, `NOTICE`, `INFORMATIONAL`, `DEBUG` |
| `tags` | Labels for categorization |
| `enabled` | Whether the rule is active (default: `true`) |

#### Common Falco Condition Macros

| Macro | Meaning |
|---|---|
| `spawned_process` | A new process was created |
| `container` | The event occurred inside a container |
| `shell_procs` | The process is a shell (bash, sh, zsh, etc.) |
| `sensitive_files` | Access to sensitive files like `/etc/shadow`, `/etc/passwd` |
| `open_write` | A file was opened for writing |
| `open_read` | A file was opened for reading |
| `outbound` | An outbound network connection was made |
| `inbound` | An inbound network connection was received |

#### Writing Custom Falco Rules

```yaml
# /etc/falco/falco_rules.local.yaml

# Detect reading of sensitive files
- rule: Read sensitive file in container
  desc: Detect reading of sensitive files inside containers
  condition: >
    open_read and container
    and (fd.name startswith /etc/shadow or
         fd.name startswith /etc/password or
         fd.name startswith /root/.ssh)
  output: >
    Sensitive file read in container
    (file=%fd.name user=%user.name command=%proc.cmdline
    container_id=%container.id container_name=%container.name
    image=%container.image.repository)
  priority: WARNING
  tags: [filesystem, container]

# Detect package management in a running container
- rule: Package management in container
  desc: Detect package management tools running in a container
  condition: >
    spawned_process and container
    and (proc.name in (apt, apt-get, yum, dnf, apk, pip, npm))
  output: >
    Package management detected in container
    (command=%proc.cmdline container=%container.name
    image=%container.image.repository)
  priority: ERROR
  tags: [process, container, mitre_persistence]

# Detect writing to /etc directory
- rule: Write below etc in container
  desc: Detect writing to /etc directory inside containers
  condition: >
    open_write and container
    and fd.name startswith /etc
    and not proc.name in (systemd, dockerd)
  output: >
    File written below /etc in container
    (file=%fd.name user=%user.name command=%proc.cmdline
    container=%container.name image=%container.image.repository)
  priority: ERROR
  tags: [filesystem, container, mitre_persistence]
```

#### Managing Falco

```bash
# Check Falco status
sudo systemctl status falco

# Start/stop/restart Falco
sudo systemctl start falco
sudo systemctl stop falco
sudo systemctl restart falco

# View Falco logs
sudo journalctl -u falco
sudo cat /var/log/syslog | grep falco

# Test Falco with a rule violation
kubectl exec -it <pod-name> -- bash
# Inside the pod:
cat /etc/shadow

# Check Falco output for the alert
sudo tail -f /var/log/syslog | grep falco

# Validate Falco rules syntax
falco --validate /etc/falco/falco_rules.local.yaml

# Run Falco with custom rules file
falco -r /etc/falco/falco_rules.local.yaml
```

#### Falco Configuration

```yaml
# /etc/falco/falco.yaml (key settings)

# Rule files to load (order matters - later files override earlier ones)
rules_file:
  - /etc/falco/falco_rules.yaml
  - /etc/falco/falco_rules.local.yaml

# Output channels
stdout_output:
  enabled: true

file_output:
  enabled: true
  filename: /var/log/falco/events.log

syslog_output:
  enabled: true

# Log level
log_level: info

# Priority filter: only output events at this level or above
priority: debug
```

!!! tip "Exam Tip"
    Falco documentation is accessible during the exam. Focus on understanding how to modify existing rules and write simple custom rules in `/etc/falco/falco_rules.local.yaml`. Know the priority levels and the most common macros (`spawned_process`, `container`, `open_write`, `open_read`). Always restart Falco after changing rules.

!!! warning "Common Pitfall"
    Custom rules should go in `/etc/falco/falco_rules.local.yaml`, not in the main `/etc/falco/falco_rules.yaml`. The main file is overwritten during Falco upgrades. The local file is loaded after the main file and can override rules.

### Audit Logging

Kubernetes API server audit logging records a chronological set of activities affecting the cluster. Audit logs are essential for security investigations and compliance.

#### Audit Policy

The audit policy defines what events are recorded and what data is included.

```yaml
# /etc/kubernetes/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # Do not log requests to the following endpoints
  - level: None
    nonResourceURLs:
      - /healthz*
      - /version
      - /readyz*
      - /livez*

  # Do not log watch requests by the system
  - level: None
    users: ["system:kube-proxy"]
    verbs: ["watch"]
    resources:
      - group: ""
        resources: ["endpoints", "services", "services/status"]

  # Log Secret access at Metadata level (do not log request/response body)
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets", "configmaps", "tokenreviews"]

  # Log pod creation and deletion at RequestResponse level
  - level: RequestResponse
    resources:
      - group: ""
        resources: ["pods"]
    verbs: ["create", "delete"]

  # Log RBAC changes at RequestResponse level
  - level: RequestResponse
    resources:
      - group: "rbac.authorization.k8s.io"
        resources: ["clusterroles", "clusterrolebindings", "roles", "rolebindings"]

  # Log everything else at Request level
  - level: Request
    omitStages:
      - RequestReceived
```

#### Audit Backends

| Backend | Description |
|---|---|
| **Log backend** | Writes events to a file on disk |
| **Webhook backend** | Sends events to an external HTTP API |

```yaml
# /etc/kubernetes/manifests/kube-apiserver.yaml
spec:
  containers:
    - command:
        - kube-apiserver
        # Log backend
        - --audit-policy-file=/etc/kubernetes/audit-policy.yaml
        - --audit-log-path=/var/log/kubernetes/audit/audit.log
        - --audit-log-maxage=30
        - --audit-log-maxbackup=10
        - --audit-log-maxsize=100
        # Webhook backend (optional, can be used alongside log backend)
        - --audit-webhook-config-file=/etc/kubernetes/audit-webhook.yaml
        - --audit-webhook-batch-max-wait=5s
```

#### Analyzing Audit Logs

```bash
# View recent audit events
sudo tail -100 /var/log/kubernetes/audit/audit.log | jq .

# Find all events for a specific user
sudo cat /var/log/kubernetes/audit/audit.log | \
  jq 'select(.user.username == "system:serviceaccount:default:compromised-sa")'

# Find all Secret access events
sudo cat /var/log/kubernetes/audit/audit.log | \
  jq 'select(.objectRef.resource == "secrets")'

# Find all failed authentication attempts
sudo cat /var/log/kubernetes/audit/audit.log | \
  jq 'select(.responseStatus.code >= 400)'

# Find all create/delete operations on pods
sudo cat /var/log/kubernetes/audit/audit.log | \
  jq 'select(.objectRef.resource == "pods" and (.verb == "create" or .verb == "delete"))'
```

#### Audit Event Structure

```json
{
  "apiVersion": "audit.k8s.io/v1",
  "kind": "Event",
  "level": "RequestResponse",
  "auditID": "12345-67890",
  "stage": "ResponseComplete",
  "requestURI": "/api/v1/namespaces/default/pods",
  "verb": "create",
  "user": {
    "username": "admin",
    "groups": ["system:masters"]
  },
  "objectRef": {
    "resource": "pods",
    "namespace": "default",
    "name": "test-pod",
    "apiVersion": "v1"
  },
  "responseStatus": {
    "code": 201
  },
  "requestReceivedTimestamp": "2024-01-15T10:30:00.000000Z",
  "stageTimestamp": "2024-01-15T10:30:00.500000Z"
}
```

### Immutable Containers

Immutable containers cannot modify their filesystem at runtime. This prevents attackers from installing tools, modifying configuration, or persisting malware.

#### Enforcing Immutability with readOnlyRootFilesystem

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: immutable-app
spec:
  containers:
    - name: app
      image: nginx:1.25
      securityContext:
        readOnlyRootFilesystem: true
        runAsNonRoot: true
        runAsUser: 1000
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
      # Mount writable volumes only where needed
      volumeMounts:
        - name: tmp
          mountPath: /tmp
        - name: cache
          mountPath: /var/cache/nginx
        - name: run
          mountPath: /var/run
  volumes:
    - name: tmp
      emptyDir: {}
    - name: cache
      emptyDir: {}
    - name: run
      emptyDir: {}
```

!!! tip "Exam Tip"
    When enabling `readOnlyRootFilesystem`, many applications require writable directories for temporary files, caches, or PID files. Use `emptyDir` volumes for these paths. Common paths that need to be writable: `/tmp`, `/var/run`, `/var/cache`, `/var/log`.

!!! warning "Common Pitfall"
    Setting `readOnlyRootFilesystem: true` without providing writable volumes for directories your application needs will cause the application to crash. Test thoroughly and check application logs if a pod enters CrashLoopBackOff after enabling this setting.

#### Making Existing Deployments Immutable

```bash
# Patch a deployment to use readOnlyRootFilesystem
kubectl patch deployment myapp -n production --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/securityContext/readOnlyRootFilesystem",
    "value": true
  }
]'

# Add emptyDir volumes for writable directories
kubectl edit deployment myapp -n production
# Add volumes and volumeMounts as needed
```

### Behavioral Analytics

Behavioral analytics involves establishing baselines of normal activity and detecting deviations that may indicate a security breach.

#### Indicators of Compromise in Kubernetes

| Indicator | Description | Detection Method |
|---|---|---|
| Unexpected process execution | Shells, package managers, or tools running in production containers | Falco rules |
| Unusual network connections | Outbound connections to unknown IPs, unusual ports | NetworkPolicies, Falco |
| File system modifications | Writing to sensitive directories in immutable containers | `readOnlyRootFilesystem`, Falco |
| Privilege escalation attempts | Attempts to gain root access or additional capabilities | Falco, audit logs |
| Abnormal API access patterns | Unusual ServiceAccount activity, excessive API calls | Audit logs |
| Cryptomining indicators | High CPU usage, connections to mining pools | Resource monitoring, Falco |

#### Detecting Anomalous Behavior

```bash
# Check for pods running with excessive privileges
kubectl get pods -A -o json | jq '.items[] | select(
  .spec.containers[].securityContext.privileged == true
) | .metadata.namespace + "/" + .metadata.name'

# Check for pods with host network access
kubectl get pods -A -o json | jq '.items[] | select(
  .spec.hostNetwork == true
) | .metadata.namespace + "/" + .metadata.name'

# Look for unusual processes in containers
kubectl exec <pod> -- ps aux

# Check for unexpected network connections
kubectl exec <pod> -- netstat -tlnp 2>/dev/null || \
kubectl exec <pod> -- ss -tlnp

# Review container logs for suspicious activity
kubectl logs <pod> --tail=100
kubectl logs <pod> --previous  # logs from previous container instance
```

### Investigating Container Runtime Issues

When a security incident is detected, systematic investigation is required.

#### Investigation Workflow

```bash
# 1. Identify the suspicious pod
kubectl get pods -A -o wide | grep <suspicious-indicator>

# 2. Get pod details
kubectl describe pod <pod-name> -n <namespace>

# 3. Check container processes
kubectl exec <pod-name> -n <namespace> -- ps aux

# 4. Check network connections
kubectl exec <pod-name> -n <namespace> -- netstat -tlnp

# 5. Check filesystem changes (if not read-only)
kubectl exec <pod-name> -n <namespace> -- find / -mmin -60 -type f 2>/dev/null

# 6. Check environment variables for leaked secrets
kubectl exec <pod-name> -n <namespace> -- env

# 7. Review pod logs
kubectl logs <pod-name> -n <namespace> --tail=200
kubectl logs <pod-name> -n <namespace> --previous

# 8. Check events related to the pod
kubectl get events -n <namespace> --field-selector involvedObject.name=<pod-name>

# 9. Review audit logs for actions by the pod's ServiceAccount
SA_NAME=$(kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.serviceAccountName}')
sudo cat /var/log/kubernetes/audit/audit.log | \
  jq "select(.user.username == \"system:serviceaccount:<namespace>:${SA_NAME}\")"

# 10. Check Falco alerts
sudo cat /var/log/syslog | grep falco | grep <container-id>
```

#### Containment Actions

```bash
# Isolate the pod by removing all network access
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: isolate-compromised-pod
  namespace: <namespace>
spec:
  podSelector:
    matchLabels:
      <label-key>: <label-value>
  policyTypes:
    - Ingress
    - Egress
EOF

# Scale down the affected deployment
kubectl scale deployment <deployment-name> -n <namespace> --replicas=0

# Delete the compromised pod (if not managed by a controller)
kubectl delete pod <pod-name> -n <namespace>

# Revoke the pod's ServiceAccount permissions
kubectl delete rolebinding <binding-name> -n <namespace>
kubectl delete clusterrolebinding <binding-name>
```

## Practice Exercises

??? question "Exercise 1: Write a Falco Rule"
    Write a custom Falco rule that detects when any process inside a container attempts to read files under `/etc/kubernetes/`. The rule should have ERROR priority and include the container name, image, and command in the output.

    ??? success "Solution"
        Add the following to `/etc/falco/falco_rules.local.yaml`:

        ```yaml
        - rule: Read Kubernetes config in container
          desc: >
            Detect attempts to read Kubernetes configuration files
            from within a container
          condition: >
            open_read and container
            and fd.name startswith /etc/kubernetes/
          output: >
            Kubernetes config file read in container
            (file=%fd.name user=%user.name command=%proc.cmdline
            container=%container.name image=%container.image.repository
            pid=%proc.pid)
          priority: ERROR
          tags: [filesystem, container, k8s_config]
        ```

        ```bash
        # Validate the rule syntax
        sudo falco --validate /etc/falco/falco_rules.local.yaml

        # Restart Falco to load the new rule
        sudo systemctl restart falco

        # Test: exec into a pod and try to read kubernetes config
        kubectl exec -it <pod> -- cat /etc/kubernetes/admin.conf

        # Check Falco output
        sudo tail -f /var/log/syslog | grep falco
        ```

??? question "Exercise 2: Create an Audit Policy"
    Create an audit policy that:

    1. Does not log requests to health check endpoints (`/healthz`, `/readyz`, `/livez`)
    2. Logs all Secret operations at `Metadata` level
    3. Logs namespace creation and deletion at `RequestResponse` level
    4. Logs everything else at `Request` level

    Configure the API server to use this policy.

    ??? success "Solution"
        ```yaml
        # /etc/kubernetes/audit-policy.yaml
        apiVersion: audit.k8s.io/v1
        kind: Policy
        rules:
          # Do not log health check endpoints
          - level: None
            nonResourceURLs:
              - /healthz*
              - /readyz*
              - /livez*

          # Log Secret operations at Metadata level
          - level: Metadata
            resources:
              - group: ""
                resources: ["secrets"]

          # Log namespace create/delete at RequestResponse level
          - level: RequestResponse
            resources:
              - group: ""
                resources: ["namespaces"]
            verbs: ["create", "delete"]

          # Log everything else at Request level
          - level: Request
            omitStages:
              - RequestReceived
        ```

        Update the API server manifest:

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

        ```bash
        # Wait for API server to restart
        kubectl get pods -n kube-system -w

        # Verify audit logs are being written
        sudo tail -f /var/log/kubernetes/audit/audit.log | jq .
        ```

??? question "Exercise 3: Make a Deployment Immutable"
    A Deployment named `api-server` in the `production` namespace runs an nginx container. Make it immutable by:

    1. Setting `readOnlyRootFilesystem: true`
    2. Adding writable volumes for nginx's required paths
    3. Ensuring the container runs as non-root

    ??? success "Solution"
        ```bash
        kubectl get deployment api-server -n production -o yaml > api-server.yaml
        ```

        Edit the deployment:

        ```yaml
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: api-server
          namespace: production
        spec:
          replicas: 2
          selector:
            matchLabels:
              app: api-server
          template:
            metadata:
              labels:
                app: api-server
            spec:
              securityContext:
                runAsNonRoot: true
                runAsUser: 101
                runAsGroup: 101
                seccompProfile:
                  type: RuntimeDefault
              containers:
                - name: nginx
                  image: nginx:1.25
                  securityContext:
                    readOnlyRootFilesystem: true
                    allowPrivilegeEscalation: false
                    capabilities:
                      drop:
                        - ALL
                  ports:
                    - containerPort: 8080
                  volumeMounts:
                    - name: tmp
                      mountPath: /tmp
                    - name: cache
                      mountPath: /var/cache/nginx
                    - name: run
                      mountPath: /var/run
              volumes:
                - name: tmp
                  emptyDir: {}
                - name: cache
                  emptyDir: {}
                - name: run
                  emptyDir: {}
        ```

        ```bash
        kubectl apply -f api-server.yaml

        # Verify the pod is running
        kubectl get pods -n production -l app=api-server

        # Verify filesystem is read-only
        kubectl exec -n production <pod-name> -- touch /usr/share/nginx/html/test
        # Expected: Read-only file system error
        ```

??? question "Exercise 4: Investigate a Security Incident"
    A Falco alert indicates that a shell was spawned inside the pod `web-frontend` in the `production` namespace. Investigate the incident and take containment actions.

    ??? success "Solution"
        ```bash
        # 1. Get pod details
        kubectl describe pod web-frontend -n production

        # 2. Check what processes are running
        kubectl exec web-frontend -n production -- ps aux

        # 3. Check for unexpected network connections
        kubectl exec web-frontend -n production -- netstat -tlnp 2>/dev/null

        # 4. Look for recently modified files
        kubectl exec web-frontend -n production -- find / -mmin -30 -type f 2>/dev/null

        # 5. Check container logs
        kubectl logs web-frontend -n production --tail=200

        # 6. Check the ServiceAccount permissions
        SA=$(kubectl get pod web-frontend -n production -o jsonpath='{.spec.serviceAccountName}')
        kubectl auth can-i --list --as=system:serviceaccount:production:${SA}

        # 7. Review Falco alerts for this container
        CONTAINER_ID=$(kubectl get pod web-frontend -n production -o jsonpath='{.status.containerStatuses[0].containerID}' | sed 's/containerd:\/\///')
        sudo cat /var/log/syslog | grep falco | grep ${CONTAINER_ID}

        # 8. Review audit logs
        sudo cat /var/log/kubernetes/audit/audit.log | \
          jq "select(.user.username == \"system:serviceaccount:production:${SA}\")" | \
          jq '{verb, resource: .objectRef.resource, name: .objectRef.name}'

        # 9. Containment: Isolate the pod
        kubectl label pod web-frontend -n production quarantine=true

        cat <<'EOF' | kubectl apply -f -
        apiVersion: networking.k8s.io/v1
        kind: NetworkPolicy
        metadata:
          name: quarantine-web-frontend
          namespace: production
        spec:
          podSelector:
            matchLabels:
              quarantine: "true"
          policyTypes:
            - Ingress
            - Egress
        EOF

        # 10. Delete the compromised pod (deployment will recreate a clean one)
        kubectl delete pod web-frontend -n production
        ```

??? question "Exercise 5: Configure Falco Output Channels"
    Configure Falco to:

    1. Output alerts to a file at `/var/log/falco/alerts.log`
    2. Output alerts to syslog
    3. Disable stdout output
    4. Set the minimum priority to `WARNING`

    ??? success "Solution"
        Edit `/etc/falco/falco.yaml`:

        ```yaml
        # Set minimum priority
        priority: WARNING

        # Disable stdout
        stdout_output:
          enabled: false

        # Enable file output
        file_output:
          enabled: true
          keep_alive: false
          filename: /var/log/falco/alerts.log

        # Enable syslog output
        syslog_output:
          enabled: true
        ```

        ```bash
        # Create the log directory
        sudo mkdir -p /var/log/falco

        # Restart Falco to apply changes
        sudo systemctl restart falco

        # Verify Falco is running with new config
        sudo systemctl status falco

        # Trigger an alert and verify output
        kubectl exec -it <pod> -- bash -c "cat /etc/shadow"

        # Check the file output
        sudo tail /var/log/falco/alerts.log

        # Check the syslog output
        sudo tail /var/log/syslog | grep falco
        ```

## Further Reading

- [Falco Documentation](https://falco.org/docs/)
- [Falco Rules Reference](https://falco.org/docs/reference/rules/)
- [Kubernetes Auditing](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/)
- [Pod Security Context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/overview/)
