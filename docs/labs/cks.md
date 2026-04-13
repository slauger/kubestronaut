# CKS Hands-On Labs

18 practical labs covering all 6 CKS exam domains. Each lab deploys a realistic scenario on your cluster — you solve the tasks hands-on, just like in the exam.

**Prerequisites:** Complete the [Lab Cluster Setup](index.md) before starting any lab.

## Cluster Setup (15%)

??? question "Lab: Restrict Traffic with CiliumNetworkPolicy"
    A multi-tier application (frontend, backend, database) is running in namespace `microservices`. An external test pod runs in the `default` namespace.

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/cilium-network-policy/setup.sh)
    ```

    **Task:**

    1. Apply a default deny all ingress and egress `CiliumNetworkPolicy` in `microservices`
    2. Allow `frontend` to reach `backend` on port 80
    3. Allow `backend` to reach `database` on port 80
    4. Allow DNS egress for all pods (to `kube-system` for kube-dns)
    5. Verify: `frontend` can reach `backend` but **not** `database` directly
    6. Verify: `external` pod in `default` namespace cannot reach any microservice

    ??? success "Solution"
        Default deny all traffic:

        ```yaml
        # default-deny.yaml
        apiVersion: cilium.io/v2
        kind: CiliumNetworkPolicy
        metadata:
          name: default-deny
          namespace: microservices
        spec:
          endpointSelector: {}
          ingress:
            - {}
          egress:
            - {}
        ```

        !!! note
            An empty `ingress: [{}]` / `egress: [{}]` with `endpointSelector: {}` means "select all pods, allow nothing" — Cilium treats the presence of an ingress/egress section as "only allow what's listed". An empty list means nothing is allowed.

        Actually, for a true default deny, use this pattern:

        ```yaml
        # default-deny.yaml
        apiVersion: cilium.io/v2
        kind: CiliumNetworkPolicy
        metadata:
          name: default-deny
          namespace: microservices
        spec:
          endpointSelector: {}
          ingressDeny:
            - fromEntities:
                - world
                - cluster
          egressDeny:
            - toEntities:
                - world
                - cluster
        ```

        Or use the simpler approach with empty ingress/egress rules that implicitly denies:

        ```yaml
        # default-deny.yaml
        apiVersion: cilium.io/v2
        kind: CiliumNetworkPolicy
        metadata:
          name: default-deny
          namespace: microservices
        spec:
          endpointSelector: {}
          ingress: []
          egress: []
        ```

        Allow DNS egress for all pods:

        ```yaml
        # allow-dns.yaml
        apiVersion: cilium.io/v2
        kind: CiliumNetworkPolicy
        metadata:
          name: allow-dns
          namespace: microservices
        spec:
          endpointSelector: {}
          egress:
            - toEndpoints:
                - matchLabels:
                    io.kubernetes.pod.namespace: kube-system
                    k8s-app: kube-dns
              toPorts:
                - ports:
                    - port: "53"
                      protocol: UDP
        ```

        Allow frontend to backend:

        ```yaml
        # allow-frontend-to-backend.yaml
        apiVersion: cilium.io/v2
        kind: CiliumNetworkPolicy
        metadata:
          name: allow-frontend-to-backend
          namespace: microservices
        spec:
          endpointSelector:
            matchLabels:
              app: frontend
          egress:
            - toEndpoints:
                - matchLabels:
                    app: backend
              toPorts:
                - ports:
                    - port: "80"
                      protocol: TCP
        ---
        apiVersion: cilium.io/v2
        kind: CiliumNetworkPolicy
        metadata:
          name: backend-allow-from-frontend
          namespace: microservices
        spec:
          endpointSelector:
            matchLabels:
              app: backend
          ingress:
            - fromEndpoints:
                - matchLabels:
                    app: frontend
              toPorts:
                - ports:
                    - port: "80"
                      protocol: TCP
        ```

        Allow backend to database:

        ```yaml
        # allow-backend-to-database.yaml
        apiVersion: cilium.io/v2
        kind: CiliumNetworkPolicy
        metadata:
          name: allow-backend-to-database
          namespace: microservices
        spec:
          endpointSelector:
            matchLabels:
              app: backend
          egress:
            - toEndpoints:
                - matchLabels:
                    app: database
              toPorts:
                - ports:
                    - port: "80"
                      protocol: TCP
        ---
        apiVersion: cilium.io/v2
        kind: CiliumNetworkPolicy
        metadata:
          name: database-allow-from-backend
          namespace: microservices
        spec:
          endpointSelector:
            matchLabels:
              app: database
          ingress:
            - fromEndpoints:
                - matchLabels:
                    app: backend
              toPorts:
                - ports:
                    - port: "80"
                      protocol: TCP
        ```

        ```bash
        kubectl apply -f default-deny.yaml
        kubectl apply -f allow-dns.yaml
        kubectl apply -f allow-frontend-to-backend.yaml
        kubectl apply -f allow-backend-to-database.yaml

        # Verify: frontend -> backend (should WORK)
        kubectl -n microservices exec deploy/frontend -- wget -qO- --timeout=3 http://backend
        # Expected: HTML output from httpd

        # Verify: frontend -> database (should FAIL)
        kubectl -n microservices exec deploy/frontend -- wget -qO- --timeout=3 http://database
        # Expected: timeout

        # Verify: external -> frontend (should FAIL)
        kubectl exec external -- wget -qO- --timeout=3 http://frontend.microservices
        # Expected: timeout
        ```

??? question "Lab: Understand NetworkPolicy Merge Behavior"
    Multiple NetworkPolicies can target the same pod. Understanding how they combine is critical for the exam.

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/netpol-merge/setup.sh)
    ```

    **Task:**

    1. Create a default deny ingress policy for all pods in `netpol-merge`
    2. Create Policy A: allow ingress to `web` from pods with label `team=internal` on port 80
    3. Create Policy B: allow ingress to `web` from pods with label `app=monitoring` on port 80
    4. Predict and verify which clients can reach `web`

    ??? success "Solution"
        ```yaml
        # default-deny.yaml
        apiVersion: networking.k8s.io/v1
        kind: NetworkPolicy
        metadata:
          name: default-deny-ingress
          namespace: netpol-merge
        spec:
          podSelector: {}
          policyTypes:
            - Ingress
        ---
        # policy-a.yaml - allow from team=internal
        apiVersion: networking.k8s.io/v1
        kind: NetworkPolicy
        metadata:
          name: allow-internal-to-web
          namespace: netpol-merge
        spec:
          podSelector:
            matchLabels:
              app: web
          policyTypes:
            - Ingress
          ingress:
            - from:
                - podSelector:
                    matchLabels:
                      team: internal
              ports:
                - protocol: TCP
                  port: 80
        ---
        # policy-b.yaml - allow from app=monitoring
        apiVersion: networking.k8s.io/v1
        kind: NetworkPolicy
        metadata:
          name: allow-monitoring-to-web
          namespace: netpol-merge
        spec:
          podSelector:
            matchLabels:
              app: web
          policyTypes:
            - Ingress
          ingress:
            - from:
                - podSelector:
                    matchLabels:
                      app: monitoring
              ports:
                - protocol: TCP
                  port: 80
        ```

        ```bash
        kubectl apply -f default-deny.yaml
        kubectl apply -f policy-a.yaml
        kubectl apply -f policy-b.yaml

        # client-internal (team=internal) -> web: ALLOWED by Policy A
        kubectl -n netpol-merge exec client-internal -- wget -qO- --timeout=3 http://web
        # Expected: nginx HTML

        # monitoring (app=monitoring) -> web: ALLOWED by Policy B
        kubectl -n netpol-merge exec monitoring -- wget -qO- --timeout=3 http://web
        # Expected: nginx HTML

        # client-external (team=external) -> web: DENIED by both
        kubectl -n netpol-merge exec client-external -- wget -qO- --timeout=3 http://web
        # Expected: timeout
        ```

        **Key insight**: Multiple NetworkPolicies targeting the same pod are **unioned** (OR logic). If _any_ policy allows the traffic, it is permitted. Policies never conflict — they only add more allowed paths.

## Cluster Hardening (15%)

??? question "Lab: Create a ValidatingWebhookConfiguration"
    A webhook server is running in namespace `webhook` that rejects pods without `runAsNonRoot: true` in their security context.

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/validating-webhook/setup.sh)
    ```

    **Task:**

    1. Get the CA bundle from the webhook-server TLS secret in namespace `webhook`
    2. Create a `ValidatingWebhookConfiguration` that:
        - Points to service `webhook-server` in namespace `webhook`, path `/validate`
        - Uses the CA bundle from step 1
        - Only applies to pods in namespace `webhook-test` (use `namespaceSelector`)
        - Uses `failurePolicy: Fail`
    3. Test: Create a pod in `webhook-test` **without** `runAsNonRoot` — should be **denied**
    4. Test: Create a pod in `webhook-test` **with** `runAsNonRoot: true` — should be **allowed**

    ??? success "Solution"
        Get the CA bundle:

        ```bash
        CA_BUNDLE=$(kubectl -n webhook get secret webhook-server-tls \
          -o jsonpath='{.data.tls\.crt}')
        echo "${CA_BUNDLE}"
        ```

        Create the `ValidatingWebhookConfiguration`:

        ```yaml
        # validating-webhook.yaml
        apiVersion: admissionregistration.k8s.io/v1
        kind: ValidatingWebhookConfiguration
        metadata:
          name: enforce-run-as-non-root
        webhooks:
          - name: enforce-run-as-non-root.webhook.svc
            admissionReviewVersions: ["v1"]
            sideEffects: None
            failurePolicy: Fail
            clientConfig:
              service:
                name: webhook-server
                namespace: webhook
                path: /validate
              caBundle: <CA_BUNDLE from above>
            rules:
              - operations: ["CREATE"]
                apiGroups: [""]
                apiVersions: ["v1"]
                resources: ["pods"]
            namespaceSelector:
              matchLabels:
                kubernetes.io/metadata.name: webhook-test
        ```

        ```bash
        # Apply (replace <CA_BUNDLE> with the actual value)
        kubectl apply -f validating-webhook.yaml

        # Test: pod WITHOUT runAsNonRoot (should be DENIED)
        kubectl -n webhook-test run test-denied --image=nginx
        # Expected: Error - container 'test-denied' must set
        #           securityContext.runAsNonRoot to true

        # Test: pod WITH runAsNonRoot (should be ALLOWED)
        kubectl -n webhook-test run test-allowed --image=nginx \
          --overrides='{"spec":{"securityContext":{"runAsNonRoot":true}}}'
        # Expected: pod/test-allowed created
        ```

??? question "Lab: Troubleshoot a Crashed API Server"
    The API server has been misconfigured and is no longer starting. Diagnose and fix the issue without using `kubectl` (which won't work while the API server is down).

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/apiserver-crash/setup.sh)
    ```

    !!! warning
        This lab intentionally breaks the API server. A backup of the manifest is saved automatically.

    **Task:**

    1. Diagnose why the API server is not starting (without `kubectl`)
    2. Fix the misconfiguration in `/etc/kubernetes/manifests/kube-apiserver.yaml`
    3. Verify the API server recovers

    ??? success "Solution"
        When `kubectl` is not available, use these tools to diagnose:

        ```bash
        # Check if the API server container is crash-looping
        crictl ps -a | grep apiserver

        # Read the container logs
        CONTAINER_ID=$(crictl ps -a --name kube-apiserver -q | head -1)
        crictl logs ${CONTAINER_ID}
        # The error message will point to the misconfiguration

        # Check kubelet logs for static pod errors
        journalctl -u kubelet --since '5 minutes ago' | grep -i error | tail -20

        # Inspect the manifest directly
        cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep -E 'admission|etcd-servers|tls-cert'
        ```

        Common misconfigurations and fixes:

        - **Invalid admission plugin**: Remove the unknown plugin name from `--enable-admission-plugins`
        - **Wrong etcd endpoint**: Fix `--etcd-servers` to `https://127.0.0.1:2379`
        - **Missing certificate**: Fix `--tls-cert-file` to the correct path (e.g., `/etc/kubernetes/pki/apiserver.crt`)

        ```bash
        # Fix the manifest
        sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml

        # Wait for recovery (kubelet watches the manifest directory)
        crictl ps | grep apiserver
        # Once the container is running:
        kubectl get nodes
        ```

        If stuck, restore the backup:

        ```bash
        sudo cp /etc/kubernetes/kube-apiserver.yaml.backup \
          /etc/kubernetes/manifests/kube-apiserver.yaml
        ```

??? question "Lab: Handle CertificateSigningRequests"
    Two CSRs have been submitted to the cluster. One is a legitimate developer request, the other is a suspicious attempt to gain cluster-admin access. Inspect, approve/deny, and configure access.

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/csr/setup.sh)
    ```

    **Task:**

    1. Inspect both pending CSRs — decode the request to see the subject (CN and O)
    2. Identify the suspicious CSR (`O=system:masters` = cluster-admin!) and **deny** it
    3. **Approve** the legitimate developer CSR
    4. Extract the signed certificate
    5. Create a kubeconfig entry for the developer and verify RBAC works (access to `development` namespace only)

    ??? success "Solution"
        Inspect the CSRs:

        ```bash
        kubectl get csr
        # NAME              AGE   SIGNERNAME                            REQUESTOR          CONDITION
        # admin-backdoor    ...   kubernetes.io/kube-apiserver-client   kubernetes-admin   Pending
        # developer-jane    ...   kubernetes.io/kube-apiserver-client   kubernetes-admin   Pending

        # Decode the subject of each CSR
        kubectl get csr developer-jane -o jsonpath='{.spec.request}' \
          | base64 -d | openssl req -noout -subject
        # subject=CN=developer-jane, O=development

        kubectl get csr admin-backdoor -o jsonpath='{.spec.request}' \
          | base64 -d | openssl req -noout -subject
        # subject=CN=admin-backdoor, O=system:masters
        # DANGER: O=system:masters grants cluster-admin!
        ```

        Deny the suspicious CSR, approve the legitimate one:

        ```bash
        kubectl certificate deny admin-backdoor
        kubectl certificate approve developer-jane

        kubectl get csr
        # admin-backdoor: Denied
        # developer-jane: Approved,Issued
        ```

        Extract the signed certificate:

        ```bash
        kubectl get csr developer-jane -o jsonpath='{.status.certificate}' \
          | base64 -d > /root/csr-lab/developer.crt

        # Verify the certificate
        openssl x509 -in /root/csr-lab/developer.crt -noout -subject -issuer
        # subject=CN=developer-jane, O=development
        # issuer=CN=kubernetes (signed by cluster CA)
        ```

        Configure kubeconfig and verify access:

        ```bash
        # Add credentials
        kubectl config set-credentials developer-jane \
          --client-certificate=/root/csr-lab/developer.crt \
          --client-key=/root/csr-lab/developer.key

        # Add context
        kubectl config set-context developer \
          --cluster=kubernetes \
          --user=developer-jane \
          --namespace=development

        # Test: should work (Role grants access to development namespace)
        kubectl --context=developer get pods -n development
        # No resources found in development namespace.

        # Test: should be denied (no access outside development)
        kubectl --context=developer get pods -n kube-system
        # Error from server (Forbidden)

        kubectl --context=developer get nodes
        # Error from server (Forbidden)

        # Verify with can-i
        kubectl auth can-i create deployments \
          --as=developer-jane -n development
        # yes

        kubectl auth can-i create deployments \
          --as=developer-jane -n default
        # no
        ```

## System Hardening (10%)

??? question "Lab: Restrict a Pod with AppArmor"
    Apply an AppArmor profile to a pod that restricts filesystem writes and shell execution.

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/apparmor/setup.sh)
    ```

    **Task:**

    1. Verify the `cks-lab-nginx` AppArmor profile is loaded: `aa-status | grep cks-lab`
    2. Create a pod `nginx-apparmor` that uses the `cks-lab-nginx` profile
    3. Verify writes to `/etc/` are **denied**
    4. Verify shell execution (`bash`) is **denied**
    5. Verify nginx still serves traffic normally

    ??? success "Solution"
        ```yaml
        # nginx-apparmor.yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: nginx-apparmor
        spec:
          containers:
            - name: nginx
              image: nginx:alpine
              securityContext:
                appArmorProfile:
                  type: Localhost
                  localhostProfile: cks-lab-nginx
        ```

        ```bash
        kubectl apply -f nginx-apparmor.yaml
        kubectl wait --for=condition=Ready pod/nginx-apparmor --timeout=60s

        # Verify writes to /etc are denied
        kubectl exec nginx-apparmor -- sh -c 'echo test > /etc/test.txt'
        # Expected: Permission denied

        # Compare with the unrestricted pod
        kubectl exec nginx-no-apparmor -- sh -c 'echo test > /etc/test.txt'
        # Expected: succeeds (no AppArmor)

        # Verify shell execution is denied
        kubectl exec nginx-apparmor -- bash
        # Expected: Permission denied (or OCI runtime error)

        # Verify nginx still works
        kubectl exec nginx-apparmor -- wget -qO- http://localhost
        # Expected: nginx welcome page
        ```

??? question "Lab: Apply a Custom Seccomp Profile"
    Use seccomp profiles to restrict which system calls a container can make.

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/seccomp/setup.sh)
    ```

    **Task:**

    1. Create a pod `seccomp-restricted` that uses the custom `cks-lab-restricted.json` profile via `Localhost` type
    2. Create a pod `seccomp-runtime` that uses the `RuntimeDefault` seccomp profile
    3. Compare: which pods can run `unshare --user` (creates a new user namespace)?
    4. Use the `audit-all.json` profile on a pod and inspect the syslog for audited syscalls

    ??? success "Solution"
        ```yaml
        # seccomp-restricted.yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: seccomp-restricted
        spec:
          securityContext:
            seccompProfile:
              type: Localhost
              localhostProfile: profiles/cks-lab-restricted.json
          containers:
            - name: nginx
              image: nginx:alpine
        ---
        # seccomp-runtime.yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: seccomp-runtime
        spec:
          securityContext:
            seccompProfile:
              type: RuntimeDefault
          containers:
            - name: nginx
              image: nginx:alpine
        ---
        # seccomp-audit.yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: seccomp-audit
        spec:
          securityContext:
            seccompProfile:
              type: Localhost
              localhostProfile: profiles/audit-all.json
          containers:
            - name: nginx
              image: nginx:alpine
        ```

        ```bash
        kubectl apply -f seccomp-restricted.yaml
        kubectl apply -f seccomp-runtime.yaml
        kubectl apply -f seccomp-audit.yaml

        # Test: unshare (creates user namespace)
        kubectl exec no-seccomp -- unshare --user id
        # May succeed (no seccomp restrictions)

        kubectl exec seccomp-restricted -- unshare --user id
        # Expected: Operation not permitted (unshare syscall blocked)

        kubectl exec seccomp-runtime -- unshare --user id
        # Expected: Operation not permitted (blocked by RuntimeDefault)

        # Check audit log for syscalls from audit pod
        kubectl exec seccomp-audit -- wget -qO- http://localhost
        journalctl -k --since '1 minute ago' | grep 'audit' | tail -20
        # Shows all syscalls made by the container
        ```

??? question "Lab: Trace Container Syscalls with strace"
    Use `strace` and `crictl` to analyze the syscall behavior of containers and identify suspicious activity.

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/strace/setup.sh)
    ```

    **Task:**

    1. Find the PID of the `web-server` container on the host using `crictl`
    2. Use `strace` to trace syscalls and generate a summary
    3. Trace network, file, and process syscalls separately
    4. Compare the `web-server` and `crypto-miner-sim` pods' syscall patterns
    5. Based on the analysis, identify which syscalls a seccomp profile should block

    ??? success "Solution"
        ```bash
        # Find the web-server container PID
        CONTAINER_ID=$(crictl ps --name nginx --namespace strace-lab -q | head -1)
        PID=$(crictl inspect ${CONTAINER_ID} | jq .info.pid)
        echo "Web server PID: ${PID}"

        # Trace all syscalls with summary (run for a few seconds, then Ctrl+C)
        timeout 5 strace -f -c -p ${PID} 2>&1 || true
        # Shows a table of syscall counts, time spent, errors

        # Trace network syscalls only
        timeout 5 strace -f -e trace=network -p ${PID} 2>&1 | head -20 || true

        # Trace file syscalls only
        timeout 5 strace -f -e trace=file -p ${PID} 2>&1 | head -20 || true

        # Now trace the suspicious crypto-miner-sim pod
        MINER_ID=$(crictl ps --name miner --namespace strace-lab -q | head -1)
        MINER_PID=$(crictl inspect ${MINER_ID} | jq .info.pid)

        timeout 5 strace -f -c -p ${MINER_PID} 2>&1 || true
        # Notice: many more read() calls to /dev/urandom
        # and more write() calls than a normal web server
        ```

        Key differences to look for:

        - **web-server**: Mostly `epoll_wait`, `accept4`, `write` (serving HTTP)
        - **crypto-miner-sim**: Heavy `read` from `/dev/urandom`, `write` to `/dev/null`, `nanosleep` (simulated mining pattern)

        A seccomp profile to block the suspicious behavior could deny `read` on `/dev/urandom` in bulk, though in practice you would use Falco for detection and seccomp for prevention of specific dangerous syscalls like `ptrace`, `mount`, or `unshare`.

??? question "Lab: Harden the Docker Daemon"
    The Docker daemon on this node has been configured insecurely. Identify and fix the security issues.

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/docker-hardening/setup.sh)
    ```

    **Task:**

    1. Identify that the Docker daemon is listening on TCP port 2375 **without TLS** — anyone on the network can control your containers
    2. Identify that the Docker socket `/var/run/docker.sock` is owned by `root:docker` — any user in the `docker` group has effective root access
    3. Fix both issues:
        - Remove the TCP socket listener
        - Change the socket group to `root`
    4. Verify: TCP port 2375 is closed, socket is `root:root`

    ??? success "Solution"
        Identify the issues:

        ```bash
        # TCP socket exposed (unauthenticated!)
        ss -tlnp | grep 2375
        # 0.0.0.0:2375 - anyone can connect

        # Prove the risk: unauthenticated API access
        curl -s http://localhost:2375/version | jq .
        # Returns Docker version info without any auth

        # Socket permissions too permissive
        ls -la /var/run/docker.sock
        # srw-rw---- 1 root docker - the "docker" group has full access
        ```

        Fix the TCP socket — find and edit the systemd override:

        ```bash
        # Find where the TCP flag is configured
        systemctl cat docker.service | grep tcp
        # Shows: ExecStart=/usr/bin/dockerd -H fd:// -H tcp://0.0.0.0:2375 ...

        # Edit the override
        sudo vi /etc/systemd/system/docker.service.d/override.conf
        ```

        ```ini
        # Remove -H tcp://0.0.0.0:2375
        [Service]
        ExecStart=
        ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock
        ```

        Fix the socket permissions:

        ```bash
        sudo vi /etc/systemd/system/docker.socket.d/override.conf
        ```

        ```ini
        [Socket]
        SocketGroup=root
        SocketMode=0660
        ```

        Apply and verify:

        ```bash
        sudo systemctl daemon-reload
        sudo systemctl restart docker.socket docker

        # Verify TCP is closed
        ss -tlnp | grep 2375
        # Expected: no output (port closed)

        curl http://localhost:2375/version
        # Expected: connection refused

        # Verify socket permissions
        ls -la /var/run/docker.sock
        # Expected: srw-rw---- 1 root root
        ```

        **Why `root:docker` is dangerous:** The Docker socket grants full control over the Docker daemon. Any user in the `docker` group can mount the host root filesystem and gain root:

        ```bash
        # This is what an attacker in the "docker" group can do:
        docker run -v /:/host alpine chroot /host
        # Instant root shell on the host
        ```

## Minimize Microservice Vulnerabilities (20%)

??? question "Lab: Encrypt Secrets at Rest in etcd"
    Secrets in your cluster are currently stored unencrypted in etcd. Configure encryption at rest and verify it works.

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/etcd-encryption/setup.sh)
    ```

    **Task:**

    1. Confirm secrets are stored **unencrypted** in etcd using `etcdctl` and `hexdump`
    2. Generate a 32-byte encryption key and create an `EncryptionConfiguration` with `aescbc` provider
    3. Configure the API server to use `--encryption-provider-config`
    4. Re-encrypt all existing secrets so they are encrypted retroactively
    5. Verify secrets are now **encrypted** in etcd (hexdump should show `k8s:enc:aescbc` prefix)

    ??? success "Solution"
        Verify secrets are unencrypted:

        ```bash
        ETCDCTL_API=3 etcdctl get /registry/secrets/encryption-test/db-credentials \
          --endpoints=https://127.0.0.1:2379 \
          --cacert=/etc/kubernetes/pki/etcd/ca.crt \
          --cert=/etc/kubernetes/pki/etcd/server.crt \
          --key=/etc/kubernetes/pki/etcd/server.key | hexdump -C | head -20
        # You should see "S3cretP@ssw0rd-12345" in plaintext
        ```

        Generate encryption key and create config:

        ```bash
        ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)
        sudo mkdir -p /etc/kubernetes/enc
        ```

        ```yaml
        # /etc/kubernetes/enc/encryption-config.yaml
        apiVersion: apiserver.config.k8s.io/v1
        kind: EncryptionConfiguration
        resources:
          - resources:
              - secrets
            providers:
              - aescbc:
                  keys:
                    - name: key1
                      secret: <ENCRYPTION_KEY from above>
              - identity: {}
        ```

        Update API server manifest:

        ```bash
        sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml
        ```

        ```yaml
        spec:
          containers:
            - command:
                - kube-apiserver
                - --encryption-provider-config=/etc/kubernetes/enc/encryption-config.yaml
              volumeMounts:
                - name: enc-config
                  mountPath: /etc/kubernetes/enc
                  readOnly: true
          volumes:
            - name: enc-config
              hostPath:
                path: /etc/kubernetes/enc
                type: DirectoryOrCreate
        ```

        ```bash
        # Wait for API server to restart
        kubectl get pods -n kube-system -w

        # Re-encrypt all existing secrets
        kubectl get secrets --all-namespaces -o json | kubectl replace -f -

        # Verify encryption in etcd
        ETCDCTL_API=3 etcdctl get /registry/secrets/encryption-test/db-credentials \
          --endpoints=https://127.0.0.1:2379 \
          --cacert=/etc/kubernetes/pki/etcd/ca.crt \
          --cert=/etc/kubernetes/pki/etcd/server.crt \
          --key=/etc/kubernetes/pki/etcd/server.key | hexdump -C | head -5
        # Should show "k8s:enc:aescbc" prefix instead of plaintext
        ```

??? question "Lab: Deploy a Pod with gVisor Sandbox"
    Use gVisor to run a container in a sandboxed runtime, isolating it from the host kernel.

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/gvisor-runtime/setup.sh)
    ```

    **Task:**

    1. Create a pod `sandboxed-nginx` that uses `runtimeClassName: gvisor`
    2. Compare kernel messages between the default and sandboxed pod using `dmesg`
    3. Compare kernel versions using `uname -r`
    4. Explain why gVisor improves security over the default runtime

    ??? success "Solution"
        ```yaml
        # sandboxed-nginx.yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: sandboxed-nginx
        spec:
          runtimeClassName: gvisor
          containers:
            - name: nginx
              image: nginx:alpine
        ```

        ```bash
        kubectl apply -f sandboxed-nginx.yaml
        kubectl wait --for=condition=Ready pod/sandboxed-nginx --timeout=60s

        # Compare kernel messages
        kubectl exec default-runtime -- dmesg | head -5
        # Shows Linux kernel boot messages

        kubectl exec sandboxed-nginx -- dmesg | head -5
        # Shows "Starting gVisor" - running in user-space kernel

        # Compare kernel versions
        kubectl exec default-runtime -- uname -r
        # Shows host Linux kernel (e.g., 6.8.0-xxx)

        kubectl exec sandboxed-nginx -- uname -r
        # Shows gVisor kernel version (e.g., 4.4.0)
        ```

        gVisor improves security by intercepting all system calls in a user-space kernel (`Sentry`), preventing the container from directly interacting with the host kernel. Even if a container escape vulnerability exists, the attacker only reaches the gVisor sandbox, not the host.

??? question "Lab: Prevent Privilege Escalation"
    Identify and fix insecure pod configurations that allow privilege escalation.

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/privilege-escalation/setup.sh)
    ```

    **Task:**

    1. Identify all security issues in the three insecure pods in `privesc-lab`
    2. Demonstrate the risks (run `id`, `ps aux`, `mount` inside each pod)
    3. Create hardened replacements with: `runAsNonRoot`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `readOnlyRootFilesystem: true`
    4. Compare behavior with the reference pod `secure-app`

    ??? success "Solution"
        Identify vulnerabilities:

        ```bash
        # insecure-app: runs as root, privilege escalation allowed
        kubectl -n privesc-lab exec insecure-app -- id
        # uid=0(root)

        # privileged-app: full host device access
        kubectl -n privesc-lab exec privileged-app -- mount | wc -l
        # Shows many host mounts

        # hostns-app: sees host processes and network
        kubectl -n privesc-lab exec hostns-app -- ps aux | head
        # Shows ALL host processes (systemd, kubelet, etc.)
        ```

        Create hardened replacements (example for insecure-app):

        ```yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: insecure-app-fixed
          namespace: privesc-lab
        spec:
          containers:
            - name: app
              image: nginx:alpine
              securityContext:
                runAsNonRoot: true
                runAsUser: 101
                allowPrivilegeEscalation: false
                readOnlyRootFilesystem: true
                capabilities:
                  drop: ["ALL"]
              volumeMounts:
                - name: cache
                  mountPath: /var/cache/nginx
                - name: run
                  mountPath: /var/run
                - name: tmp
                  mountPath: /tmp
          volumes:
            - name: cache
              emptyDir: {}
            - name: run
              emptyDir: {}
            - name: tmp
              emptyDir: {}
        ```

        ```bash
        kubectl apply -f insecure-app-fixed.yaml

        # Verify: no longer root
        kubectl -n privesc-lab exec insecure-app-fixed -- id
        # uid=101(nginx)

        # Verify: cannot escalate
        kubectl -n privesc-lab exec insecure-app-fixed -- cat /etc/shadow
        # Permission denied
        ```

## Supply Chain Security (20%)

??? question "Lab: Configure ImagePolicyWebhook"
    A webhook server is running at `https://image-policy.default.svc:8443/validate` that checks container images against an allowlist. Only images from `docker.io/library/` and `registry.k8s.io/` are permitted.

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/image-policy-webhook/setup.sh)
    ```

    **Task:**

    1. Create an `AdmissionConfiguration` at `/etc/kubernetes/admission/admission-config.yaml`
    2. Create a kubeconfig for the webhook at `/etc/kubernetes/admission/imagepolicy-kubeconfig.yaml` (the CA cert is at `/etc/kubernetes/admission/webhook-ca.crt`)
    3. Enable the `ImagePolicyWebhook` admission plugin in `kube-apiserver` with `--admission-control-config-file`
    4. Set `defaultAllow: false` so unknown images are rejected
    5. Verify: `kubectl run nginx --image=nginx` should **work**
    6. Verify: `kubectl run evil --image=evil.io/malware` should be **denied**

    ??? success "Solution"
        Create the admission configuration:

        ```yaml
        # /etc/kubernetes/admission/admission-config.yaml
        apiVersion: apiserver.config.k8s.io/v1
        kind: AdmissionConfiguration
        plugins:
          - name: ImagePolicyWebhook
            configuration:
              imagePolicy:
                kubeConfigFile: /etc/kubernetes/admission/imagepolicy-kubeconfig.yaml
                allowTTL: 50
                denyTTL: 50
                retryBackoff: 500
                defaultAllow: false
        ```

        Create the kubeconfig pointing to the webhook service. Since this is a cluster-internal service, we only need the CA certificate (no client auth required):

        ```yaml
        # /etc/kubernetes/admission/imagepolicy-kubeconfig.yaml
        apiVersion: v1
        kind: Config
        clusters:
          - name: image-policy-server
            cluster:
              server: https://image-policy.default.svc:8443/validate
              certificate-authority: /etc/kubernetes/admission/webhook-ca.crt
        users:
          - name: api-server
            user: {}
        contexts:
          - name: default
            context:
              cluster: image-policy-server
              user: api-server
        current-context: default
        ```

        Update the API server manifest:

        ```bash
        sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml
        ```

        Add the admission plugin and ensure the volume mount exists:

        ```yaml
        spec:
          containers:
            - command:
                - kube-apiserver
                - --enable-admission-plugins=NodeRestriction,ImagePolicyWebhook
                - --admission-control-config-file=/etc/kubernetes/admission/admission-config.yaml
              volumeMounts:
                - name: admission-config
                  mountPath: /etc/kubernetes/admission
                  readOnly: true
          volumes:
            - name: admission-config
              hostPath:
                path: /etc/kubernetes/admission
                type: DirectoryOrCreate
        ```

        ```bash
        # Wait for API server to restart
        kubectl get pods -n kube-system -w

        # Test: allowed image (docker.io/library/nginx)
        kubectl run nginx --image=nginx
        # Expected: pod/nginx created

        # Test: denied image (not in allowlist)
        kubectl run evil --image=evil.io/malware
        # Expected: Error from server (Forbidden): image "evil.io/malware" denied
        ```

??? question "Lab: Static Analysis of Dockerfiles with Conftest"
    Use Conftest with OPA/Rego policies to automatically detect security issues in Dockerfiles.

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/conftest-docker/setup.sh)
    ```

    **Task:**

    1. Run conftest against the insecure Dockerfile with the starter policy (catches `:latest` tag)
    2. Complete the TODO rules in `/root/conftest-lab/policy/dockerfile.rego`:
        - Deny `ENV` instructions containing "PASSWORD" or "SECRET"
        - Deny `EXPOSE 22` (SSH port)
        - Require a `USER` instruction (non-root)
        - Deny installation of `curl`, `wget`, or `netcat` in `RUN` commands
    3. Run conftest against all three Dockerfiles
    4. `Dockerfile.insecure` should have the most violations, `Dockerfile.secure` should pass

    ??? success "Solution"
        ```rego
        # /root/conftest-lab/policy/dockerfile.rego
        package main

        # Deny use of 'latest' tag
        deny[msg] {
          input[i].Cmd == "from"
          val := input[i].Value[0]
          endswith(val, ":latest")
          msg := sprintf("Stage %d: Do not use ':latest' tag: '%s'", [i, val])
        }

        # Deny ENV with PASSWORD or SECRET
        deny[msg] {
          input[i].Cmd == "env"
          val := input[i].Value[0]
          contains(upper(val), "PASSWORD")
          msg := sprintf("ENV contains sensitive key: '%s'", [val])
        }

        deny[msg] {
          input[i].Cmd == "env"
          val := input[i].Value[0]
          contains(upper(val), "SECRET")
          msg := sprintf("ENV contains sensitive key: '%s'", [val])
        }

        # Deny EXPOSE 22
        deny[msg] {
          input[i].Cmd == "expose"
          input[i].Value[j] == "22"
          msg := "Do not expose SSH port 22"
        }

        # Require USER instruction
        deny[msg] {
          not has_user
          msg := "Dockerfile must contain a USER instruction"
        }

        has_user {
          input[i].Cmd == "user"
        }

        # Deny dangerous packages in RUN
        deny[msg] {
          input[i].Cmd == "run"
          val := input[i].Value[0]
          packages := ["curl", "wget", "netcat"]
          pkg := packages[_]
          contains(val, pkg)
          msg := sprintf("Do not install '%s' in production images", [pkg])
        }
        ```

        ```bash
        # Test against insecure Dockerfile (should have many failures)
        conftest test /root/conftest-lab/dockerfiles/Dockerfile.insecure \
          --policy /root/conftest-lab/policy
        # Expected: FAIL for :latest, PASSWORD env, EXPOSE 22, no USER, curl/wget/netcat

        # Test against secure Dockerfile (should pass)
        conftest test /root/conftest-lab/dockerfiles/Dockerfile.secure \
          --policy /root/conftest-lab/policy
        # Expected: 0 failures
        ```

??? question "Lab: Use Image Digests Instead of Tags"
    Mutable image tags like `:latest` are a supply chain risk. Switch deployments to use immutable image digests.

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/image-digest/setup.sh)
    ```

    **Task:**

    1. Find the sha256 digest for the images used by deployments in `digest-lab`
    2. Update both deployments to use `image@sha256:...` instead of tags
    3. Verify pods are running with pinned digests

    ??? success "Solution"
        ```bash
        # Get the digest from running pods
        kubectl -n digest-lab get pods -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\t"}{.status.containerStatuses[0].imageID}{"\n"}{end}'

        # Or use crictl to find digests
        crictl inspecti nginx:latest 2>/dev/null | jq -r '.status.repoDigests[]'
        crictl inspecti httpd:2.4 2>/dev/null | jq -r '.status.repoDigests[]'

        # Update deployments with digests (example - your digests will differ!)
        kubectl -n digest-lab set image deployment/web-latest \
          nginx=nginx@sha256:<digest-from-above>

        kubectl -n digest-lab set image deployment/api-tagged \
          httpd=httpd@sha256:<digest-from-above>

        # Verify
        kubectl -n digest-lab get pods -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}'
        # Should show image@sha256:... format
        ```

        Using digests instead of tags ensures:

        - **Immutability**: The exact same image binary is always pulled
        - **Supply chain integrity**: A compromised registry cannot substitute a different image under the same tag
        - **Reproducibility**: Deployments are deterministic across environments

## Monitoring, Logging & Runtime Security (20%)

??? question "Lab: Write Custom Falco Rules"
    Deploy suspicious workloads and write Falco rules to detect malicious activity.

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/falco-rules/setup.sh)
    ```

    **Task:**

    1. Write a custom Falco rule in `/etc/falco/falco_rules.local.yaml` that detects when a shell is spawned inside a container (priority `WARNING`)
    2. Write a second rule that detects when `/etc/shadow` is read inside a container (priority `ERROR`)
    3. Restart Falco and trigger both rules
    4. Verify the alerts in Falco logs

    ??? success "Solution"
        ```yaml
        # /etc/falco/falco_rules.local.yaml
        - rule: Shell Spawned in Container
          desc: Detect shell execution inside a container
          condition: >
            spawned_process and container
            and proc.name in (sh, bash, dash)
          output: >
            Shell spawned in container
            (container=%container.name image=%container.image.repository
            user=%user.name command=%proc.cmdline pid=%proc.pid)
          priority: WARNING
          tags: [shell, container]

        - rule: Read Sensitive File in Container
          desc: Detect reading of /etc/shadow in a container
          condition: >
            open_read and container
            and fd.name = /etc/shadow
          output: >
            Sensitive file read in container
            (file=%fd.name container=%container.name
            image=%container.image.repository user=%user.name
            command=%proc.cmdline)
          priority: ERROR
          tags: [filesystem, container]
        ```

        ```bash
        # Validate the rules
        sudo falco --validate /etc/falco/falco_rules.local.yaml

        # Restart Falco
        sudo systemctl restart falco

        # Trigger the rules
        kubectl -n falco-lab exec web-app -- sh -c 'cat /etc/shadow'

        # Check Falco alerts
        journalctl -u falco --since '2 minutes ago' | grep -E 'Warning|Error'
        # Should show both "Shell spawned" and "Sensitive file read" alerts
        ```

??? question "Lab: Enforce Container Immutability"
    Harden a web application deployment to prevent filesystem modifications at runtime.

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/immutability/setup.sh)
    ```

    **Task:**

    1. Demonstrate the problem: modify `mutable-web`'s filesystem and install tools
    2. Create a new Deployment `immutable-web` in namespace `immutability-lab` with:
        - `readOnlyRootFilesystem: true`
        - `emptyDir` volumes for `/var/cache/nginx`, `/var/run`, `/tmp`
        - `runAsNonRoot: true` with `runAsUser: 101` (nginx user)
    3. Verify the filesystem is read-only (writes should fail)
    4. Verify nginx still serves traffic correctly

    ??? success "Solution"
        Demonstrate the vulnerability:

        ```bash
        kubectl -n immutability-lab exec deploy/mutable-web -- \
          sh -c 'echo HACKED > /usr/share/nginx/html/index.html'
        kubectl -n immutability-lab exec deploy/mutable-web -- wget -qO- http://localhost
        # Shows "HACKED" - filesystem was modified!
        ```

        Create the immutable deployment:

        ```yaml
        # immutable-web.yaml
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: immutable-web
          namespace: immutability-lab
        spec:
          replicas: 1
          selector:
            matchLabels:
              app: immutable-web
          template:
            metadata:
              labels:
                app: immutable-web
            spec:
              containers:
                - name: nginx
                  image: nginx:alpine
                  ports:
                    - containerPort: 80
                  securityContext:
                    readOnlyRootFilesystem: true
                    runAsNonRoot: true
                    runAsUser: 101
                    allowPrivilegeEscalation: false
                  volumeMounts:
                    - name: cache
                      mountPath: /var/cache/nginx
                    - name: run
                      mountPath: /var/run
                    - name: tmp
                      mountPath: /tmp
              volumes:
                - name: cache
                  emptyDir: {}
                - name: run
                  emptyDir: {}
                - name: tmp
                  emptyDir: {}
        ```

        ```bash
        kubectl apply -f immutable-web.yaml
        kubectl -n immutability-lab rollout status deployment/immutable-web

        # Verify read-only filesystem
        kubectl -n immutability-lab exec deploy/immutable-web -- \
          sh -c 'echo test > /usr/share/nginx/html/test.txt'
        # Expected: Read-only file system error

        # Verify nginx still works
        kubectl -n immutability-lab exec deploy/immutable-web -- wget -qO- http://localhost
        # Expected: default nginx welcome page

        # Verify package installation is blocked
        kubectl -n immutability-lab exec deploy/immutable-web -- apk add nmap
        # Expected: Read-only file system error
        ```

??? question "Lab: Analyze Falco Alerts"
    Suspicious activity has been detected on the cluster. Analyze the Falco logs to determine what happened, which pods are affected, and what triggered the alerts.

    **Lab Setup** (run on control plane node):

    ```bash
    bash <(curl -fsSL https://raw.githubusercontent.com/slauger/kubestronaut/main/labs/cks/falco-analysis/setup.sh)
    ```

    **Task — answer these questions by reading the Falco logs:**

    1. Which pod wrote to `/dev/shm`? What was the filename?
    2. Which container read `/etc/shadow`?
    3. Which pod attempted to modify files in `/bin/`? What was the exact command?
    4. Which pod read the Kubernetes ServiceAccount token?
    5. List ALL distinct Falco rule names that were triggered

    ??? success "Solution"
        ```bash
        # View all recent Falco alerts
        journalctl -u falco --since '5 minutes ago' --no-pager
        ```

        **Q1: /dev/shm write**

        ```bash
        journalctl -u falco --since '5 minutes ago' | grep -i 'shm'
        ```

        Answer: Pod `data-processor`, container `processor`, wrote file `/dev/shm/hidden_data`. This triggers the Falco rule **"Modify Container Entrypoint"** or **"Write below binary dir"** depending on the Falco version. Writing to `/dev/shm` is suspicious because crypto miners and malware commonly use shared memory for inter-process communication.

        **Q2: /etc/shadow read**

        ```bash
        journalctl -u falco --since '5 minutes ago' | grep -i 'shadow'
        ```

        Answer: Pod `compromised`, container `attacker`. Triggers the rule **"Read sensitive file untrusted"** or **"Read sensitive file trusted after startup"**. Reading `/etc/shadow` is a credential harvesting attempt.

        **Q3: /bin/ modification**

        ```bash
        journalctl -u falco --since '5 minutes ago' | grep -i '/bin/'
        ```

        Answer: Pod `compromised`, command `cp /bin/ls /bin/backdoor`. Triggers **"Write below binary dir"**. An attacker is planting a backdoor binary.

        **Q4: ServiceAccount token read**

        ```bash
        journalctl -u falco --since '5 minutes ago' | grep -i 'serviceaccount\|token'
        ```

        Answer: Pod `compromised`. Reading the SA token allows lateral movement within the cluster (API access with the pod's identity).

        **Q5: Distinct rules triggered**

        ```bash
        journalctl -u falco --since '5 minutes ago' --no-pager \
          | grep -oP '(?<=Rule: ).*?(?=\s|$)' | sort -u
        # Or look for the rule name pattern in the output
        journalctl -u falco --since '5 minutes ago' --no-pager \
          | grep -i 'warning\|error\|critical' | sort -u
        ```

        Typical rules triggered (names may vary by Falco version):

        - `Write below binary dir` (write to /bin/)
        - `Read sensitive file untrusted` or `Read sensitive file trusted after startup` (/etc/shadow)
        - `Contact K8S API Server From Container` (SA token read + API access)
        - `Terminal shell in container` (shell spawned)

## Quick Reference

Available lab names for the `setup.sh` URL:

```
apparmor              conftest-docker       falco-analysis        image-policy-webhook
apiserver-crash       csr                   falco-rules           immutability
cilium-network-policy docker-hardening      gvisor-runtime        netpol-merge
                      etcd-encryption       image-digest          privilege-escalation
                                                                  seccomp
                                                                  strace
                                                                  validating-webhook
```
