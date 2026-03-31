# Troubleshooting (30%)

Troubleshooting is the largest domain on the CKA exam at 30%. You must be able to diagnose and fix issues across all layers of a Kubernetes cluster: nodes, control plane components, workloads, networking, and storage. This domain tests your ability to methodically identify root causes and apply fixes under time pressure.

## Key Concepts

### Troubleshooting Methodology

Follow a systematic approach:

1. **Identify** the symptoms (what is failing?)
2. **Gather** information (events, logs, describe, status)
3. **Isolate** the component (node, pod, service, control plane)
4. **Fix** the root cause
5. **Verify** the fix

### Node Troubleshooting

```bash
# Check node status
kubectl get nodes
kubectl describe node <node-name>

# Check node conditions
kubectl get nodes -o wide

# Common node conditions to check
# - Ready: kubelet is healthy and ready to accept pods
# - MemoryPressure: node is running low on memory
# - DiskPressure: node is running low on disk space
# - PIDPressure: too many processes on the node
# - NetworkUnavailable: network for the node is not configured
```

#### Node NotReady Troubleshooting

```bash
# SSH to the node and check kubelet status
systemctl status kubelet

# Check kubelet logs
journalctl -u kubelet -f
journalctl -u kubelet --no-pager | tail -50

# Common fixes
sudo systemctl restart kubelet
sudo systemctl enable kubelet

# Check kubelet configuration
cat /var/lib/kubelet/config.yaml

# Check if container runtime is running
systemctl status containerd
sudo systemctl restart containerd

# Check certificates
openssl x509 -in /var/lib/kubelet/pki/kubelet-client-current.pem -noout -dates
```

!!! tip "Exam Tip"
    When a node shows `NotReady`, always start by checking the `kubelet` service on that node. The most common causes are: kubelet not running, kubelet misconfiguration, container runtime not running, or expired certificates.

### Pod Troubleshooting

#### Common Pod Failure States

| Status | Meaning | Common Causes |
|---|---|---|
| **Pending** | Pod cannot be scheduled | Insufficient resources, node selector mismatch, taints, PVC not bound |
| **CrashLoopBackOff** | Container keeps crashing and restarting | Application error, wrong command, missing config/secrets |
| **ImagePullBackOff** | Cannot pull the container image | Wrong image name/tag, private registry without credentials, network issues |
| **ErrImagePull** | Initial image pull failure | Same as ImagePullBackOff |
| **CreateContainerError** | Container creation failed | Missing ConfigMap/Secret, security context issues |
| **OOMKilled** | Container exceeded memory limit | Memory limit too low, memory leak in application |
| **Error** | Container exited with an error | Application crashed, check logs |
| **Evicted** | Pod was evicted from the node | Node under resource pressure |

#### Debugging Pending Pods

```bash
# Check why the pod is pending
kubectl describe pod <pod-name>

# Look at the Events section for scheduling failures
# Common messages:
# - "Insufficient cpu" / "Insufficient memory"
# - "no nodes available to schedule pods"
# - "node(s) had taint ... that the pod didn't tolerate"
# - "persistentvolumeclaim ... not found"

# Check available resources on nodes
kubectl describe nodes | grep -A 5 "Allocated resources"
kubectl top nodes
```

#### Debugging CrashLoopBackOff

```bash
# Check pod events
kubectl describe pod <pod-name>

# Check container logs (current attempt)
kubectl logs <pod-name>
kubectl logs <pod-name> -c <container-name>

# Check logs from the previous crash
kubectl logs <pod-name> --previous

# Check if the container command/entrypoint is correct
kubectl get pod <pod-name> -o yaml | grep -A 5 "command\|args"

# Interactive debugging - exec into a running container
kubectl exec -it <pod-name> -- /bin/sh

# Check environment variables and mounted volumes
kubectl exec <pod-name> -- env
kubectl exec <pod-name> -- ls /path/to/mounted/volume
```

#### Debugging ImagePullBackOff

```bash
# Check the exact error message
kubectl describe pod <pod-name> | grep -A 10 "Events"

# Verify the image name and tag exist
# Check for typos in the image name

# For private registries, check if imagePullSecrets is configured
kubectl get pod <pod-name> -o yaml | grep -A 3 imagePullSecrets

# Create a docker registry secret if needed
kubectl create secret docker-registry regcred \
  --docker-server=registry.example.com \
  --docker-username=user \
  --docker-password=pass
```

### Service and Networking Troubleshooting

```bash
# Check if the service exists and has the right selector
kubectl get svc <service-name>
kubectl describe svc <service-name>

# Check if endpoints are populated (pods are selected)
kubectl get endpoints <service-name>

# If no endpoints: the service selector does not match any pod labels
kubectl get pods --show-labels

# Test connectivity from within the cluster
kubectl run tmp-debug --rm -it --image=busybox:1.36 -- sh
# Inside the pod:
wget -qO- http://<service-name>:<port>
nslookup <service-name>

# Check if kube-proxy is running
kubectl get pods -n kube-system | grep kube-proxy

# Check kube-proxy logs
kubectl logs -n kube-system <kube-proxy-pod>

# Check iptables rules (on the node)
sudo iptables -t nat -L KUBE-SERVICES -n
```

!!! tip "Exam Tip"
    When a service is not working, check these in order: (1) Does the service exist? (2) Does the service have endpoints? (3) Do the endpoints match the pod IPs? (4) Are the pods actually running? (5) Is kube-proxy running? (6) Can you reach the pod directly by IP?

### Control Plane Troubleshooting

Control plane components run as static pods in `/etc/kubernetes/manifests/` on the control plane node.

```bash
# Check control plane pod status
kubectl get pods -n kube-system

# Check individual component logs
kubectl logs -n kube-system kube-apiserver-<node>
kubectl logs -n kube-system kube-controller-manager-<node>
kubectl logs -n kube-system kube-scheduler-<node>
kubectl logs -n kube-system etcd-<node>

# If kubectl is not working (API server down), check static pod manifests directly
ls /etc/kubernetes/manifests/
cat /etc/kubernetes/manifests/kube-apiserver.yaml

# Check component status via crictl (if kubectl is unavailable)
sudo crictl pods | grep kube-system
sudo crictl ps -a

# Check kubelet logs for static pod issues
journalctl -u kubelet | grep -i error
```

#### Common Control Plane Issues

```bash
# API Server not starting
# - Check the manifest for syntax errors
cat /etc/kubernetes/manifests/kube-apiserver.yaml

# - Check certificate paths and validity
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -dates

# - Check etcd connectivity
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member list

# Scheduler not scheduling pods
# - Check scheduler logs
kubectl logs -n kube-system kube-scheduler-<node>
# - Common fix: correct the manifest or restart kubelet

# Controller Manager issues
# - Check logs for errors
kubectl logs -n kube-system kube-controller-manager-<node>
```

!!! tip "Exam Tip"
    If you edit a static pod manifest in `/etc/kubernetes/manifests/`, the kubelet will automatically detect the change and restart the pod. If it does not restart, check `journalctl -u kubelet` for errors. A common mistake is introducing YAML syntax errors into the manifest.

### Application Log Analysis

```bash
# View pod logs
kubectl logs <pod-name>

# View logs for a specific container in a multi-container pod
kubectl logs <pod-name> -c <container-name>

# Follow logs in real time
kubectl logs -f <pod-name>

# View logs from the previous container instance
kubectl logs <pod-name> --previous

# View last N lines
kubectl logs <pod-name> --tail=50

# View logs since a specific time
kubectl logs <pod-name> --since=1h
kubectl logs <pod-name> --since-time="2024-01-15T10:00:00Z"

# View logs from all pods with a specific label
kubectl logs -l app=nginx --all-containers=true
```

### Cluster Component Logs

```bash
# kubelet logs (systemd-based)
journalctl -u kubelet -f
journalctl -u kubelet --since "1 hour ago"

# Container runtime logs
journalctl -u containerd -f

# kube-proxy logs
kubectl logs -n kube-system -l k8s-app=kube-proxy

# CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns

# etcd logs
kubectl logs -n kube-system etcd-<node>

# Check system logs on the node
journalctl -xe
dmesg | tail
```

### Debugging Tools Reference

| Tool | Purpose | Example |
|---|---|---|
| `kubectl describe` | Detailed resource info and events | `kubectl describe pod my-pod` |
| `kubectl logs` | Container stdout/stderr | `kubectl logs my-pod --previous` |
| `kubectl exec` | Run commands inside a container | `kubectl exec -it my-pod -- sh` |
| `kubectl top` | Resource usage (requires metrics-server) | `kubectl top pods --sort-by=memory` |
| `kubectl get events` | Cluster events sorted by time | `kubectl get events --sort-by='.lastTimestamp'` |
| `kubectl debug` | Create debug containers | `kubectl debug -it my-pod --image=busybox` |
| `crictl` | Debug container runtime | `sudo crictl ps -a` |
| `journalctl` | Systemd service logs | `journalctl -u kubelet -f` |

```bash
# kubectl describe - look at Events section at the bottom
kubectl describe pod <pod-name>
kubectl describe node <node-name>
kubectl describe svc <service-name>

# kubectl top - requires metrics-server
kubectl top nodes
kubectl top pods
kubectl top pods --sort-by=cpu
kubectl top pods --sort-by=memory -A

# kubectl get events - useful overview of what happened
kubectl get events --sort-by='.lastTimestamp'
kubectl get events -n <namespace> --field-selector type=Warning
kubectl get events --field-selector involvedObject.name=<pod-name>

# kubectl debug - ephemeral debug container
kubectl debug -it <pod-name> --image=busybox --target=<container-name>

# crictl - when kubectl is not available (API server down)
sudo crictl pods
sudo crictl ps -a
sudo crictl logs <container-id>
sudo crictl inspect <container-id>
```

### Common Troubleshooting Scenarios

#### Scenario: Worker Node NotReady

```bash
# 1. Check node status
kubectl get nodes
kubectl describe node <node-name>

# 2. SSH to the node and check kubelet
systemctl status kubelet

# 3. If kubelet is not running, check logs and start it
journalctl -u kubelet | tail -20
sudo systemctl start kubelet
sudo systemctl enable kubelet

# 4. If kubelet keeps crashing, check the config
cat /var/lib/kubelet/config.yaml
# Look for wrong paths, bad certificate references, etc.

# 5. Check container runtime
systemctl status containerd
```

#### Scenario: Pod Stuck in Pending with Taints

```bash
# 1. Describe the pod to see why it is pending
kubectl describe pod <pod-name>
# Look for: "node(s) had taint ... that the pod didn't tolerate"

# 2. Check node taints
kubectl describe node <node-name> | grep -A 5 Taints

# 3. Fix: either add a toleration to the pod or remove the taint
kubectl taint nodes <node-name> <key>:<effect>-
```

#### Scenario: Service Has No Endpoints

```bash
# 1. Check the service selector
kubectl describe svc <svc-name>
# Note the Selector field

# 2. Check if any pods match the selector
kubectl get pods -l <selector-key>=<selector-value>

# 3. Fix: either update the service selector or the pod labels
kubectl label pod <pod-name> <key>=<value>
```

## Practice Exercises

??? question "Exercise 1: Fix a Broken Node"
    A worker node `node01` shows status `NotReady`. Investigate and fix the issue.

    ??? success "Solution"
        ```bash
        # Check the node status
        kubectl describe node node01

        # SSH to node01
        ssh node01

        # Check kubelet status
        systemctl status kubelet

        # If kubelet is stopped/failed:
        sudo systemctl start kubelet
        sudo systemctl enable kubelet

        # If kubelet is crashing, check the logs
        journalctl -u kubelet --no-pager | tail -30

        # Common fixes:
        # - Wrong kubelet config path: fix /var/lib/kubelet/config.yaml
        # - Container runtime not running: sudo systemctl restart containerd
        # - Certificate issues: check /var/lib/kubelet/pki/

        # Verify the fix
        kubectl get nodes
        ```

??? question "Exercise 2: Debug a CrashLoopBackOff Pod"
    A pod named `web-app` in the `production` namespace is in `CrashLoopBackOff`. Find the root cause and fix it.

    ??? success "Solution"
        ```bash
        # Check pod status and events
        kubectl describe pod web-app -n production

        # Check current and previous logs
        kubectl logs web-app -n production
        kubectl logs web-app -n production --previous

        # Common causes and fixes:
        # 1. Wrong command/args - edit the deployment/pod spec
        # 2. Missing ConfigMap/Secret - create the missing resource
        # 3. Application error - fix the configuration
        # 4. OOMKilled - increase memory limits

        # If the container starts but crashes:
        # Try exec into it with a different command
        kubectl debug -it web-app -n production --image=busybox

        # Example fix: if a ConfigMap is missing
        kubectl create configmap app-config --from-literal=key=value -n production

        # Verify
        kubectl get pod web-app -n production -w
        ```

??? question "Exercise 3: Fix a Broken Control Plane Component"
    The `kube-scheduler` is not running. Pods are stuck in `Pending` state. Fix the issue.

    ??? success "Solution"
        ```bash
        # Verify the scheduler is not running
        kubectl get pods -n kube-system | grep scheduler

        # Check the static pod manifest for errors
        cat /etc/kubernetes/manifests/kube-scheduler.yaml

        # Check kubelet logs for scheduler pod errors
        journalctl -u kubelet | grep scheduler

        # Use crictl to check container status
        sudo crictl ps -a | grep scheduler

        # Common fixes:
        # - Fix typos in the manifest (wrong image, wrong path, YAML syntax errors)
        # - Fix incorrect volume mounts or command arguments
        # - Restore a deleted manifest from backup

        # After fixing, the kubelet will automatically restart the pod
        # Verify
        kubectl get pods -n kube-system | grep scheduler
        kubectl get pods | grep Pending
        ```

??? question "Exercise 4: Troubleshoot Service Connectivity"
    A service named `frontend-svc` in the `web` namespace is not routing traffic to its pods. Diagnose and fix the issue.

    ??? success "Solution"
        ```bash
        # Check the service
        kubectl get svc frontend-svc -n web
        kubectl describe svc frontend-svc -n web

        # Check endpoints
        kubectl get endpoints frontend-svc -n web
        # If "none" - the selector does not match any pods

        # Check what labels the pods have
        kubectl get pods -n web --show-labels

        # Compare with the service selector
        # Fix: update labels to match the service selector
        kubectl label pod <pod-name> -n web app=frontend

        # Or fix the service selector
        kubectl edit svc frontend-svc -n web

        # Verify connectivity
        kubectl run test --rm -it --image=busybox:1.36 -n web -- wget -qO- http://frontend-svc
        ```

??? question "Exercise 5: Investigate High Resource Usage"
    Pods in the `monitoring` namespace are being evicted. Find which pods are consuming the most resources and identify the issue.

    ??? success "Solution"
        ```bash
        # Check for evicted pods
        kubectl get pods -n monitoring --field-selector status.phase=Failed

        # Check node resource pressure
        kubectl describe nodes | grep -A 5 "Conditions"

        # Check resource usage
        kubectl top nodes
        kubectl top pods -n monitoring --sort-by=memory
        kubectl top pods -n monitoring --sort-by=cpu

        # Check events for eviction reasons
        kubectl get events -n monitoring --field-selector reason=Evicted

        # Check pod resource requests/limits
        kubectl get pods -n monitoring -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].resources}{"\n"}{end}'

        # Fix: add or adjust resource limits for offending pods
        # Or scale down the number of replicas
        # Or add more nodes to the cluster

        # Clean up evicted pods
        kubectl delete pods -n monitoring --field-selector status.phase=Failed
        ```

## Relevant Documentation

- [Troubleshooting Applications](https://kubernetes.io/docs/tasks/debug/debug-application/)
- [Troubleshooting Clusters](https://kubernetes.io/docs/tasks/debug/debug-cluster/)
- [Debug Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)
- [Debug Services](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/)
- [Debug Running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/)
- [Node Health](https://kubernetes.io/docs/tasks/debug/debug-cluster/monitor-node-health/)
- [Resource Metrics Pipeline](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)
- [Determine the Reason for Pod Failure](https://kubernetes.io/docs/tasks/debug/debug-application/determine-reason-pod-failure/)
