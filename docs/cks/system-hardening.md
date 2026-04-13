# System Hardening (10%)

This domain covers OS-level and container runtime security mechanisms that restrict what processes inside containers can do. You need to understand AppArmor profiles, seccomp profiles, syscall filtering, reducing the host attack surface, and preventing containers from accessing host namespaces.

## Key Concepts

### Reducing the Attack Surface

Minimizing the attack surface of cluster nodes is a fundamental security practice. Every unnecessary service, package, or open port is a potential attack vector.

```bash
# List all running services
systemctl list-units --type=service --state=running

# Disable unnecessary services
sudo systemctl stop <service-name>
sudo systemctl disable <service-name>

# List open ports
sudo ss -tlnp
sudo netstat -tlnp

# Remove unnecessary packages
sudo apt list --installed
sudo apt remove <package-name>

# Check for setuid/setgid binaries (potential privilege escalation)
find / -perm -4000 -type f 2>/dev/null
find / -perm -2000 -type f 2>/dev/null
```

!!! tip "Exam Tip"
    The exam may ask you to identify and disable unnecessary services or processes on a node. Use `systemctl` to list and disable services, and `ss -tlnp` to identify open ports and the processes listening on them.

### Host Namespace Restrictions

Containers should not share the host's PID, network, or IPC namespaces unless absolutely necessary. Sharing host namespaces breaks container isolation.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: restricted-pod
spec:
  # All of these should be false (or omitted, as false is the default)
  hostNetwork: false
  hostPID: false
  hostIPC: false
  containers:
    - name: app
      image: nginx:latest
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
```

!!! warning "Common Pitfall"
    A pod with `hostPID: true` can see all processes on the node. A pod with `hostNetwork: true` can access all network interfaces on the node, including listening services on `127.0.0.1`. The exam may ask you to identify and fix pods that use these insecure settings.

### AppArmor Profiles

AppArmor (Application Armor) is a Linux kernel security module that restricts the capabilities of programs. Kubernetes supports loading AppArmor profiles to confine containers.

#### AppArmor Profile Modes

| Mode | Description |
|---|---|
| `enforce` | The profile is enforced; violations are blocked and logged |
| `complain` | Violations are logged but not blocked (useful for testing) |
| `unconfined` | No restrictions are applied |

#### Managing AppArmor Profiles

```bash
# Check AppArmor status
sudo aa-status

# List loaded profiles
sudo aa-status | grep profiles

# Load a profile
sudo apparmor_parser -q /etc/apparmor.d/my-profile

# Load a profile in enforce mode (default)
sudo apparmor_parser -q /etc/apparmor.d/my-profile

# Load a profile in complain mode
sudo apparmor_parser -C /etc/apparmor.d/my-profile

# Remove a profile
sudo apparmor_parser -R /etc/apparmor.d/my-profile
```

#### Writing an AppArmor Profile

```bash
# /etc/apparmor.d/k8s-deny-write
#include <tunables/global>

profile k8s-deny-write flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  # Allow read access to the filesystem
  file,

  # Deny all file write operations
  deny /** w,

  # Allow network access
  network,
}
```

#### Applying AppArmor to a Pod

Starting with Kubernetes v1.30, AppArmor can be set via the `securityContext` field:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: apparmor-pod
spec:
  containers:
    - name: app
      image: nginx:latest
      securityContext:
        appArmorProfile:
          type: Localhost
          localhostProfile: k8s-deny-write
```

For older Kubernetes versions, use annotations:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: apparmor-pod
  annotations:
    container.apparmor.security.beta.kubernetes.io/app: localhost/k8s-deny-write
spec:
  containers:
    - name: app
      image: nginx:latest
```

!!! tip "Exam Tip"
    AppArmor profiles must be loaded on every node where the pod might run. Make sure the profile is loaded using `apparmor_parser` before creating the pod. Use `sudo aa-status` to verify the profile is loaded and in the correct mode.

!!! warning "Common Pitfall"
    If an AppArmor profile is not loaded on the node, the pod will fail to start with an error like `"cannot enforce AppArmor: profile not loaded"`. Always verify profile status with `aa-status` before deploying.

### Seccomp Profiles

Seccomp (Secure Computing Mode) filters the system calls that a container process can make. This limits the kernel attack surface available to container workloads.

#### Seccomp Profile Types

| Type | Description |
|---|---|
| `RuntimeDefault` | Uses the container runtime's default seccomp profile (recommended baseline) |
| `Localhost` | Uses a custom seccomp profile from the node's filesystem |
| `Unconfined` | No seccomp filtering (insecure) |

#### Applying RuntimeDefault Seccomp Profile

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: seccomp-default
spec:
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: app
      image: nginx:latest
```

#### Creating a Custom Seccomp Profile

Custom seccomp profiles are stored on the node at `/var/lib/kubelet/seccomp/profiles/` by default.

```json
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": [
    "SCMP_ARCH_X86_64",
    "SCMP_ARCH_X86",
    "SCMP_ARCH_X32"
  ],
  "syscalls": [
    {
      "names": [
        "accept4",
        "access",
        "arch_prctl",
        "bind",
        "brk",
        "clone",
        "close",
        "connect",
        "epoll_create1",
        "epoll_ctl",
        "epoll_wait",
        "execve",
        "exit_group",
        "fcntl",
        "fstat",
        "futex",
        "getdents64",
        "getpid",
        "getppid",
        "ioctl",
        "listen",
        "lseek",
        "mmap",
        "mprotect",
        "munmap",
        "nanosleep",
        "newfstatat",
        "openat",
        "read",
        "recvfrom",
        "rt_sigaction",
        "rt_sigprocmask",
        "sendto",
        "set_tid_address",
        "setsockopt",
        "socket",
        "stat",
        "write"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
```

#### Applying a Custom Seccomp Profile

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: seccomp-custom
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: profiles/custom-profile.json
  containers:
    - name: app
      image: nginx:latest
```

The `localhostProfile` path is relative to the kubelet's configured seccomp profile root directory (default: `/var/lib/kubelet/seccomp/`).

!!! tip "Exam Tip"
    `RuntimeDefault` is the recommended baseline for all workloads. In the exam, you may be asked to apply a seccomp profile to a pod. If no custom profile is specified, use `RuntimeDefault`. The profile path for `Localhost` type is relative to `/var/lib/kubelet/seccomp/`.

### Syscall Filtering

Seccomp profiles work by filtering syscalls. Understanding the two main default actions is important:

| Default Action | Behavior |
|---|---|
| `SCMP_ACT_ALLOW` | Allow all syscalls by default, then deny specific ones (blocklist approach) |
| `SCMP_ACT_ERRNO` | Deny all syscalls by default, then allow specific ones (allowlist approach - more secure) |
| `SCMP_ACT_LOG` | Allow but log all syscalls (useful for building profiles) |

```bash
# Generate a seccomp profile by tracing syscalls (using strace)
strace -c -f -p $(pidof nginx) -e trace=all 2>&1

# Use the traced syscalls to build a custom seccomp profile
# Only allowlist the syscalls your application actually needs
```

### Combining Security Contexts

A well-hardened pod combines multiple security mechanisms:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: hardened-pod
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000
    seccompProfile:
      type: RuntimeDefault
  hostNetwork: false
  hostPID: false
  hostIPC: false
  containers:
    - name: app
      image: nginx:latest
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop:
            - ALL
        appArmorProfile:
          type: Localhost
          localhostProfile: k8s-deny-write
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

### Kernel Hardening

Linux kernel parameters can be tuned to enhance container security. Kubernetes allows setting safe sysctl parameters at the pod level.

#### Safe vs Unsafe Sysctls

| Category | Examples | Default |
|---|---|---|
| Safe sysctls | `kernel.shm_rmid_forced`, `net.ipv4.ip_local_port_range`, `net.ipv4.tcp_syncookies`, `net.ipv4.ping_group_range` | Allowed |
| Unsafe sysctls | `kernel.msg*`, `kernel.sem`, `net.core.*` | Blocked by default |

```yaml
# Setting safe sysctls at the pod level
apiVersion: v1
kind: Pod
metadata:
  name: sysctl-pod
spec:
  securityContext:
    sysctls:
      - name: net.ipv4.ip_unprivileged_port_start
        value: "0"
      - name: kernel.shm_rmid_forced
        value: "1"
  containers:
    - name: app
      image: nginx:latest
```

To allow unsafe sysctls, configure the kubelet:

```yaml
# /var/lib/kubelet/config.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
allowedUnsafeSysctls:
  - "net.core.somaxconn"
  - "kernel.msg*"
```

!!! tip "Exam Tip"
    Only safe sysctls can be set without kubelet configuration changes. If the exam asks you to set an unsafe sysctl, you need to allow it on the kubelet first via `allowedUnsafeSysctls` in `/var/lib/kubelet/config.yaml`.

### kubelet Security

The kubelet is the node agent running on every node. A misconfigured kubelet can expose sensitive information or allow unauthorized access.

```yaml
# /var/lib/kubelet/config.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
authorization:
  mode: Webhook
readOnlyPort: 0
protectKernelDefaults: true
```

| Setting | Secure Value | Why |
|---|---|---|
| `anonymous.enabled` | `false` | Prevents unauthenticated access to kubelet API |
| `authorization.mode` | `Webhook` | Delegates authorization to the API server (RBAC) |
| `readOnlyPort` | `0` | Disables unauthenticated read-only port 10255 |
| `protectKernelDefaults` | `true` | Fails pods that try to change kernel tunables |

```bash
# Verify anonymous access is disabled
curl -sk https://localhost:10250/pods
# Should return 401 Unauthorized (not pod list)

# Verify read-only port is disabled
curl -s http://localhost:10255/pods
# Should fail to connect

# Check kubelet configuration
cat /var/lib/kubelet/config.yaml | grep -A3 authentication
cat /var/lib/kubelet/config.yaml | grep readOnlyPort
```

!!! warning "Common Pitfall"
    The kubelet read-only port (10255) exposes pod and node information without authentication. Anyone with network access can enumerate all pods on the node. Always verify `readOnlyPort: 0` is set.

### Container Runtime Debugging with crictl

`crictl` is a CLI tool for CRI-compatible container runtimes (containerd, CRI-O). It is essential for debugging containers at the runtime level, especially when `kubectl` is unavailable.

```bash
# List running containers
crictl ps

# List all containers (including exited)
crictl ps -a

# List pods
crictl pods

# Inspect a container (security context, mounts, environment)
crictl inspect <container-id>

# View container logs
crictl logs <container-id>
crictl logs --tail 50 <container-id>

# Execute a command in a container
crictl exec -it <container-id> sh

# List images on the node
crictl images

# Pull an image
crictl pull nginx:latest

# Remove an image
crictl rmi <image-id>

# Get container resource stats
crictl stats
```

```bash
# Debugging a crashed static pod (e.g., API server won't start)
# 1. Find the pod
crictl pods --name kube-apiserver

# 2. Find containers in the pod
crictl ps -a --pod <pod-id>

# 3. Check container logs
crictl logs <container-id>

# 4. Inspect security context
crictl inspect <container-id> | jq '.info.config.linux.security_context'
```

!!! tip "Exam Tip"
    When the API server or kubelet is down and `kubectl` is not working, use `crictl` to debug containers directly on the node. This is especially useful when troubleshooting static pod failures after modifying API server or etcd manifests.

### Static Pod Security

Static pods are managed directly by the kubelet from manifest files, without the API server. The control plane components (API server, controller-manager, scheduler, etcd) run as static pods in kubeadm clusters.

```bash
# Default static pod manifest directory
ls /etc/kubernetes/manifests/
# kube-apiserver.yaml  kube-controller-manager.yaml  kube-scheduler.yaml  etcd.yaml

# Check kubelet static pod path
cat /var/lib/kubelet/config.yaml | grep staticPodPath
# staticPodPath: /etc/kubernetes/manifests
```

#### Securing Static Pod Manifests

```bash
# Verify file permissions (should be root-owned, restricted)
ls -la /etc/kubernetes/manifests/
# Restrict permissions
chmod 600 /etc/kubernetes/manifests/*.yaml
chown root:root /etc/kubernetes/manifests/*.yaml
```

Key security considerations:

- **File permissions**: Static pod manifests should be readable only by root (mode `600`)
- **Path restriction**: Only trusted manifests should exist in the `staticPodPath` directory
- **No admission control**: Static pods bypass most admission controllers including Pod Security Admission and OPA/Gatekeeper
- **Mirror pods**: The kubelet creates read-only mirror pods in the API server for visibility, but they cannot be modified via `kubectl`

!!! warning "Common Pitfall"
    Since static pods bypass admission controllers, a malicious manifest placed in the static pod directory runs without any policy checks. Ensure only authorized users have write access to `/etc/kubernetes/manifests/`. This is why file permissions and node access control are critical.

## Practice Exercises

??? question "Exercise 1: Apply an AppArmor Profile to a Pod"
    Create an AppArmor profile called `k8s-restrict-nginx` that:

    1. Allows all network access
    2. Allows reading files
    3. Denies writing to `/etc/` and `/usr/`

    Load the profile and apply it to a pod running nginx.

    ??? success "Solution"
        Create the AppArmor profile on the node:

        ```bash
        # Create the profile file
        cat > /etc/apparmor.d/k8s-restrict-nginx << 'PROFILE'
        #include <tunables/global>

        profile k8s-restrict-nginx flags=(attach_disconnected,mediate_deleted) {
          #include <abstractions/base>

          file,
          network,

          deny /etc/** w,
          deny /usr/** w,
        }
        PROFILE

        # Load the profile
        sudo apparmor_parser -q /etc/apparmor.d/k8s-restrict-nginx

        # Verify it is loaded
        sudo aa-status | grep k8s-restrict-nginx
        ```

        Create the pod:

        ```yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: nginx-restricted
        spec:
          containers:
            - name: nginx
              image: nginx:latest
              securityContext:
                appArmorProfile:
                  type: Localhost
                  localhostProfile: k8s-restrict-nginx
        ```

        ```bash
        kubectl apply -f nginx-restricted.yaml

        # Test: writing to /etc should fail
        kubectl exec nginx-restricted -- touch /etc/testfile
        # Expected: Permission denied

        # Test: writing to /tmp should work
        kubectl exec nginx-restricted -- touch /tmp/testfile
        # Expected: Success
        ```

??? question "Exercise 2: Apply a Seccomp Profile"
    Apply the `RuntimeDefault` seccomp profile to all containers in the `web` namespace by modifying an existing Deployment named `frontend`.

    ??? success "Solution"
        ```bash
        kubectl get deployment frontend -n web -o yaml > frontend.yaml
        ```

        Edit the pod template spec to add the seccomp profile:

        ```yaml
        spec:
          template:
            spec:
              securityContext:
                seccompProfile:
                  type: RuntimeDefault
              containers:
                - name: frontend
                  # ... existing container spec
        ```

        ```bash
        kubectl apply -f frontend.yaml

        # Verify the pods are recreated with the seccomp profile
        kubectl get pods -n web
        kubectl get pod <pod-name> -n web -o jsonpath='{.spec.securityContext.seccompProfile}'
        # Expected: {"type":"RuntimeDefault"}
        ```

??? question "Exercise 3: Identify and Fix Host Namespace Usage"
    Audit all pods in the cluster for those using `hostNetwork`, `hostPID`, or `hostIPC`. Fix any pods that should not have these settings.

    ??? success "Solution"
        ```bash
        # Find pods with hostNetwork
        kubectl get pods -A -o jsonpath='{range .items[?(@.spec.hostNetwork==true)]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'

        # Find pods with hostPID
        kubectl get pods -A -o jsonpath='{range .items[?(@.spec.hostPID==true)]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'

        # Find pods with hostIPC
        kubectl get pods -A -o jsonpath='{range .items[?(@.spec.hostIPC==true)]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'

        # For each non-system pod found, export and fix
        kubectl get pod <pod-name> -n <namespace> -o yaml > pod-fix.yaml

        # Edit pod-fix.yaml:
        # Remove or set to false: hostNetwork, hostPID, hostIPC

        # Recreate the pod
        kubectl delete pod <pod-name> -n <namespace>
        kubectl apply -f pod-fix.yaml
        ```

??? question "Exercise 4: Create a Custom Seccomp Profile"
    Create a custom seccomp profile that only allows the minimal syscalls needed for a simple `echo "hello"` container using `busybox`. Apply it to a pod.

    ??? success "Solution"
        ```bash
        # Create the seccomp profile directory
        sudo mkdir -p /var/lib/kubelet/seccomp/profiles

        # Create a minimal seccomp profile
        cat > /var/lib/kubelet/seccomp/profiles/busybox-echo.json << 'EOF'
        {
          "defaultAction": "SCMP_ACT_ERRNO",
          "architectures": [
            "SCMP_ARCH_X86_64"
          ],
          "syscalls": [
            {
              "names": [
                "arch_prctl",
                "brk",
                "close",
                "execve",
                "exit_group",
                "fcntl",
                "fstat",
                "futex",
                "getdents64",
                "mmap",
                "mprotect",
                "munmap",
                "newfstatat",
                "openat",
                "read",
                "rt_sigaction",
                "rt_sigprocmask",
                "set_tid_address",
                "write"
              ],
              "action": "SCMP_ACT_ALLOW"
            }
          ]
        }
        EOF
        ```

        ```yaml
        # busybox-seccomp.yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: busybox-seccomp
        spec:
          securityContext:
            seccompProfile:
              type: Localhost
              localhostProfile: profiles/busybox-echo.json
          containers:
            - name: busybox
              image: busybox:latest
              command: ["sh", "-c", "echo hello && sleep 3600"]
        ```

        ```bash
        kubectl apply -f busybox-seccomp.yaml

        # Verify the pod is running
        kubectl get pod busybox-seccomp
        kubectl logs busybox-seccomp
        # Expected: hello
        ```

??? question "Exercise 5: Reduce Node Attack Surface"
    A worker node is running unnecessary services. Identify all listening services, stop and disable any non-essential ones, and verify the changes.

    ??? success "Solution"
        ```bash
        # SSH to the worker node
        ssh node01

        # List all listening TCP ports
        sudo ss -tlnp

        # Example output may show:
        # 0.0.0.0:10250  kubelet        (keep)
        # 0.0.0.0:30000  kube-proxy     (keep)
        # 0.0.0.0:22     sshd           (keep)
        # 0.0.0.0:8090   apache2        (remove if unnecessary)
        # 0.0.0.0:3306   mysqld         (remove if unnecessary)

        # Stop and disable unnecessary services
        sudo systemctl stop apache2
        sudo systemctl disable apache2
        sudo systemctl stop mysql
        sudo systemctl disable mysql

        # Verify the ports are no longer open
        sudo ss -tlnp

        # Remove packages if required
        sudo apt remove apache2 -y
        sudo apt remove mysql-server -y

        # Verify services are disabled
        systemctl is-enabled apache2
        # Expected: disabled (or not found)
        ```

## Further Reading

- [Kubernetes AppArmor Documentation](https://kubernetes.io/docs/tutorials/security/apparmor/)
- [Kubernetes Seccomp Documentation](https://kubernetes.io/docs/tutorials/security/seccomp/)
- [Pod Security Context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
- [Linux Security Modules](https://kubernetes.io/docs/concepts/security/linux-kernel-security-constraints/)
- [Restrict a Container's Syscalls with Seccomp](https://kubernetes.io/docs/tutorials/security/seccomp/)
- [Using Sysctls in a Kubernetes Cluster](https://kubernetes.io/docs/tasks/administer-cluster/sysctl-cluster/)
- [Kubelet Configuration](https://kubernetes.io/docs/reference/config-api/kubelet-config.v1beta1/)
- [crictl Documentation](https://kubernetes.io/docs/tasks/debug/debug-cluster/crictl/)
- [Static Pods](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/)
