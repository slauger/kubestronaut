#!/usr/bin/env bash
set -euo pipefail

# CKS Lab: Seccomp Profiles
# Installs a custom seccomp profile and deploys test workloads.

SECCOMP_DIR="/var/lib/kubelet/seccomp/profiles"

echo "=== CKS Lab: Seccomp Profiles ==="

echo "[1/3] Installing seccomp profiles..."
mkdir -p "${SECCOMP_DIR}"

# A restrictive profile that blocks dangerous syscalls
cat > "${SECCOMP_DIR}/cks-lab-restricted.json" <<'JSON'
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_AARCH64"],
  "syscalls": [
    {
      "names": [
        "accept", "accept4", "access", "arch_prctl", "bind", "brk",
        "capget", "capset", "chdir", "chmod", "chown", "close",
        "connect", "dup", "dup2", "dup3", "epoll_create", "epoll_create1",
        "epoll_ctl", "epoll_pwait", "epoll_wait", "eventfd", "eventfd2",
        "execve", "exit", "exit_group", "faccessat", "faccessat2",
        "fchmod", "fchmodat", "fchown", "fchownat", "fcntl", "fdatasync",
        "flock", "fstat", "fstatfs", "fsync", "ftruncate", "futex",
        "getcwd", "getdents", "getdents64", "getegid", "geteuid",
        "getgid", "getgroups", "getpeername", "getpgrp", "getpid",
        "getppid", "getpriority", "getrandom", "getresgid", "getresuid",
        "getrlimit", "getsockname", "getsockopt", "gettid", "gettimeofday",
        "getuid", "ioctl", "kill", "listen", "lseek", "lstat",
        "madvise", "membarrier", "mincore", "mkdir", "mkdirat", "mmap",
        "mprotect", "mremap", "msgctl", "msgget", "msgsnd", "munmap",
        "nanosleep", "newfstatat", "open", "openat", "pipe", "pipe2",
        "poll", "ppoll", "prctl", "pread64", "preadv", "prlimit64",
        "pwrite64", "pwritev", "read", "readlink", "readlinkat", "readv",
        "recvfrom", "recvmsg", "rename", "renameat", "renameat2",
        "restart_syscall", "rmdir", "rt_sigaction", "rt_sigprocmask",
        "rt_sigreturn", "sched_getaffinity", "sched_yield", "select",
        "sendfile", "sendmsg", "sendto", "set_robust_list",
        "set_tid_address", "setgid", "setgroups", "setitimer",
        "setsockopt", "setuid", "sigaltstack", "socket", "socketpair",
        "splice", "stat", "statfs", "statx", "symlink", "symlinkat",
        "sysinfo", "tgkill", "timerfd_create", "timerfd_settime",
        "umask", "uname", "unlink", "unlinkat", "utimensat", "wait4",
        "waitid", "write", "writev"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
JSON

# An audit profile that logs all syscalls (useful for building allowlists)
cat > "${SECCOMP_DIR}/audit-all.json" <<'JSON'
{
  "defaultAction": "SCMP_ACT_LOG"
}
JSON

echo "Profiles installed at ${SECCOMP_DIR}/"
ls -la "${SECCOMP_DIR}/"

echo "[2/3] Deploying test pod without seccomp..."
kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: Pod
metadata:
  name: no-seccomp
  labels:
    app: seccomp-test
spec:
  containers:
    - name: nginx
      image: nginx:alpine
MANIFEST

echo "[3/3] Waiting for pod..."
kubectl wait --for=condition=Ready pod/no-seccomp --timeout=60s

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Seccomp profiles installed:"
echo "  ${SECCOMP_DIR}/cks-lab-restricted.json  (allowlist - blocks dangerous syscalls)"
echo "  ${SECCOMP_DIR}/audit-all.json            (logs all syscalls for debugging)"
echo ""
echo "Test pod deployed: no-seccomp (no seccomp restrictions)"
echo ""
echo "Your task:"
echo "  1. Create a pod 'seccomp-restricted' that uses the 'cks-lab-restricted' profile"
echo "     Hint: use spec.securityContext.seccompProfile with type: Localhost"
echo "     and localhostProfile: profiles/cks-lab-restricted.json"
echo ""
echo "  2. Create a pod 'seccomp-audit' that uses the 'audit-all' profile"
echo "     Run commands inside it and check syslog for audit entries:"
echo "     journalctl -k | grep 'audit' | tail -20"
echo ""
echo "  3. Create a pod 'seccomp-runtime' that uses RuntimeDefault seccomp:"
echo "     spec.securityContext.seccompProfile.type: RuntimeDefault"
echo ""
echo "  4. Compare: which pod can run 'unshare --user' (creates user namespace)?"
echo "     kubectl exec no-seccomp -- unshare --user id"
echo "     kubectl exec seccomp-restricted -- unshare --user id"
