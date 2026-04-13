# Supply Chain Security (20%)

This domain covers securing the entire software supply chain, from writing Dockerfiles to scanning images, enforcing image policies, signing artifacts, and generating software bills of materials. At 20% of the exam weight, supply chain security reflects the growing importance of securing what runs in your cluster, not just how it runs.

## Key Concepts

### Image Scanning with Trivy

Trivy is an open-source vulnerability scanner developed by Aqua Security. It scans container images, filesystems, and Kubernetes resources for known vulnerabilities (CVEs), misconfigurations, and embedded secrets.

#### Scanning Container Images

```bash
# Scan an image for vulnerabilities
trivy image nginx:latest

# Scan with severity filter
trivy image --severity HIGH,CRITICAL nginx:latest

# Scan and output in JSON format
trivy image --format json --output results.json nginx:latest

# Scan and fail if critical vulnerabilities are found (useful in CI/CD)
trivy image --exit-code 1 --severity CRITICAL nginx:latest

# Scan a specific image and ignore unfixed vulnerabilities
trivy image --ignore-unfixed nginx:1.25

# Scan an image from a private registry
trivy image --username myuser --password mypass registry.example.com/myapp:v1.0
```

#### Scanning Kubernetes Resources

```bash
# Scan a Kubernetes cluster for misconfigurations
trivy k8s --report summary cluster

# Scan a specific namespace
trivy k8s --namespace production --report all

# Scan a specific resource
trivy k8s --namespace default deployment/nginx
```

#### Scanning Filesystem and Config Files

```bash
# Scan a project directory for misconfigurations
trivy fs --security-checks vuln,config /path/to/project

# Scan a Dockerfile
trivy config Dockerfile

# Scan Kubernetes manifests
trivy config /path/to/k8s-manifests/
```

!!! tip "Exam Tip"
    Trivy documentation is accessible during the exam. Focus on the `trivy image` command with `--severity` and `--exit-code` flags. The exam may ask you to identify images with critical vulnerabilities and take action (e.g., delete pods using vulnerable images).

### Static Analysis of Manifests

Static analysis tools inspect Kubernetes manifests and Dockerfiles for security issues without running them.

#### kubesec

kubesec is a security risk analysis tool for Kubernetes resources. It assigns a score based on security best practices.

```bash
# Scan a manifest file
kubesec scan pod.yaml

# Scan from stdin
cat pod.yaml | kubesec scan -

# Scan via the online API
curl -sSX POST --data-binary @pod.yaml https://v2.kubesec.io/scan
```

Example output interpretation:

```json
{
  "score": -30,
  "scoring": {
    "critical": [
      {
        "id": "Privileged",
        "selector": "containers[] .securityContext .privileged == true",
        "reason": "Privileged containers can access all host devices"
      }
    ],
    "advise": [
      {
        "id": "RunAsNonRoot",
        "selector": "containers[] .securityContext .runAsNonRoot == true",
        "reason": "Force the running image to run as a non-root user"
      }
    ]
  }
}
```

#### KubeLinter

KubeLinter is a static analysis tool that checks Kubernetes YAML files and Helm charts against a set of best practices, with a focus on security and production readiness.

```bash
# Lint a single manifest
kube-linter lint pod.yaml

# Lint an entire directory of manifests
kube-linter lint manifests/

# Lint a Helm chart
kube-linter lint mychart/

# List all available checks
kube-linter checks list

# Run only specific checks
kube-linter lint --include run-as-non-root,no-read-only-root-fs pod.yaml

# Exclude specific checks
kube-linter lint --exclude unset-cpu-requirements,unset-memory-requirements manifests/
```

KubeLinter checks for common security issues such as:

| Check | What It Detects |
|---|---|
| `run-as-non-root` | Containers not configured to run as non-root |
| `no-read-only-root-fs` | Missing `readOnlyRootFilesystem: true` |
| `privilege-escalation-container` | `allowPrivilegeEscalation` not set to `false` |
| `privileged-container` | Containers running in privileged mode |
| `sensitive-host-mounts` | Host path mounts to sensitive directories |
| `dangling-service` | Services with no matching pods |
| `latest-tag` | Images using the `latest` tag |

!!! tip "Exam Tip"
    KubeLinter was added to the CKS curriculum in 2024. It complements kubesec by providing a broader set of checks including Helm chart analysis. Know how to run it against manifests and interpret the output.

#### conftest

conftest is a testing tool for configuration files using Open Policy Agent (OPA) Rego policies.

```bash
# Test Kubernetes manifests against custom policies
conftest test deployment.yaml

# Test a Dockerfile
conftest test Dockerfile

# Test with a specific policy directory
conftest test --policy /path/to/policies deployment.yaml
```

Example Rego policy for conftest:

```rego
# policy/deployment.rego
package main

deny[msg] {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
  not container.securityContext.runAsNonRoot
  msg := sprintf("Container %s must set runAsNonRoot to true", [container.name])
}

deny[msg] {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
  endswith(container.image, ":latest")
  msg := sprintf("Container %s must not use ':latest' tag", [container.name])
}
```

### Image Allowlisting

Image allowlisting restricts which container images can be deployed to the cluster.

#### ImagePolicyWebhook

The `ImagePolicyWebhook` admission controller validates images against an external policy server.

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

```yaml
# /etc/kubernetes/admission/imagepolicy-kubeconfig.yaml
apiVersion: v1
kind: Config
clusters:
  - name: image-policy-server
    cluster:
      server: https://image-policy.example.com:8443/validate
      certificate-authority: /etc/kubernetes/admission/ca.crt
users:
  - name: api-server
    user:
      client-certificate: /etc/kubernetes/admission/client.crt
      client-key: /etc/kubernetes/admission/client.key
contexts:
  - name: default
    context:
      cluster: image-policy-server
      user: api-server
current-context: default
```

Enable in the API server:

```yaml
# /etc/kubernetes/manifests/kube-apiserver.yaml
spec:
  containers:
    - command:
        - kube-apiserver
        - --enable-admission-plugins=NodeRestriction,ImagePolicyWebhook
        - --admission-control-config-file=/etc/kubernetes/admission/admission-config.yaml
```

!!! warning "Common Pitfall"
    If `defaultAllow: false` is set and the webhook server is unreachable, all image deployments will be rejected. Set `defaultAllow: true` during initial setup and testing, then switch to `false` for production enforcement.

#### OPA/Gatekeeper Image Allowlisting

```yaml
# ConstraintTemplate for allowed image registries
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8sallowedregistries
spec:
  crd:
    spec:
      names:
        kind: K8sAllowedRegistries
      validation:
        openAPIV3Schema:
          type: object
          properties:
            registries:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sallowedregistries

        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          not startswith(container.image, input.parameters.registries[_])
          msg := sprintf("Container image %v is not from an allowed registry", [container.image])
        }

        violation[{"msg": msg}] {
          container := input.review.object.spec.initContainers[_]
          not startswith(container.image, input.parameters.registries[_])
          msg := sprintf("Init container image %v is not from an allowed registry", [container.image])
        }
```

```yaml
# Constraint: only allow images from specific registries
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sAllowedRegistries
metadata:
  name: allowed-registries
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
  parameters:
    registries:
      - "registry.internal.example.com/"
      - "docker.io/library/"
```

### Dockerfile Best Practices

Secure Dockerfiles reduce the attack surface of container images.

#### Multi-Stage Builds

```dockerfile
# Build stage
FROM golang:1.22 AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o app .

# Runtime stage - minimal image
FROM alpine:3.19
RUN apk --no-cache add ca-certificates && \
    addgroup -g 1000 -S appgroup && \
    adduser -u 1000 -S appuser -G appgroup
WORKDIR /app
COPY --from=builder /app/app .
USER 1000:1000
EXPOSE 8080
ENTRYPOINT ["./app"]
```

#### Dockerfile Security Checklist

| Practice | Example |
|---|---|
| Use specific image tags | `FROM nginx:1.25.4-alpine` instead of `FROM nginx:latest` |
| Run as non-root | `USER 1000:1000` |
| Use multi-stage builds | Separate build and runtime stages |
| Minimize layers | Combine `RUN` commands with `&&` |
| Use minimal base images | `alpine`, `distroless`, `scratch` |
| Do not store secrets | Never use `COPY secrets.txt .` or `ENV PASSWORD=...` |
| Set read-only filesystem | Use `readOnlyRootFilesystem: true` in pod spec |
| Remove unnecessary tools | Do not install `curl`, `wget`, `netcat` in production images |
| Scan images | Run `trivy image` before pushing |

```dockerfile
# Bad: Multiple security issues
FROM ubuntu:latest
RUN apt-get update && apt-get install -y curl wget netcat
COPY . /app
ENV DB_PASSWORD=mysecret
EXPOSE 22 80
CMD ["/app/start.sh"]

# Good: Follows best practices
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /app/binary /app/binary
USER 65534:65534
EXPOSE 8080
ENTRYPOINT ["/app/binary"]
```

!!! tip "Exam Tip"
    The exam may present a Dockerfile and ask you to identify security issues or fix them. Common issues include: using `latest` tag, running as root, copying secrets, installing unnecessary packages, and not using multi-stage builds.

### Image Signing and Verification

Image signing ensures that container images have not been tampered with and come from a trusted source.

#### Cosign (Sigstore)

Cosign is a tool for signing, verifying, and storing container image signatures.

```bash
# Generate a key pair
cosign generate-key-pair

# Sign an image
cosign sign --key cosign.key registry.example.com/myapp:v1.0

# Verify an image signature
cosign verify --key cosign.pub registry.example.com/myapp:v1.0

# Sign with keyless signing (uses OIDC identity)
cosign sign registry.example.com/myapp:v1.0

# Verify keyless signature
cosign verify \
  --certificate-identity user@example.com \
  --certificate-oidc-issuer https://accounts.google.com \
  registry.example.com/myapp:v1.0

# Attach an SBOM to an image
cosign attach sbom --sbom sbom.spdx registry.example.com/myapp:v1.0
```

#### Enforcing Image Signatures in Kubernetes

Using a policy engine to reject unsigned images:

```yaml
# Kyverno policy to verify image signatures
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signature
spec:
  validationFailureAction: Enforce
  rules:
    - name: verify-signature
      match:
        any:
          - resources:
              kinds:
                - Pod
      verifyImages:
        - imageReferences:
            - "registry.example.com/*"
          attestors:
            - entries:
                - keys:
                    publicKeys: |-
                      -----BEGIN PUBLIC KEY-----
                      MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...
                      -----END PUBLIC KEY-----
```

### Software Bill of Materials (SBOM)

An SBOM is a comprehensive inventory of all components, libraries, and dependencies in a software artifact. It helps identify vulnerable components quickly.

#### SBOM Formats

| Format | Standard | Common Tools |
|---|---|---|
| **SPDX-JSON** | Linux Foundation / ISO standard | `bom`, `trivy`, `syft` |
| **CycloneDX** | OWASP standard | `trivy`, `syft` |

#### Generating SBOMs

```bash
# Generate SPDX-JSON SBOM with bom (Kubernetes project tool)
bom generate --image registry.k8s.io/kube-apiserver:v1.31.0 \
  --format json --output sbom.spdx.json

# Generate SPDX-JSON SBOM with Trivy
trivy image --format spdx-json --output sbom.spdx.json nginx:latest

# Generate CycloneDX SBOM with Trivy
trivy image --format cyclonedx --output sbom.cdx.json nginx:latest

# Generate SBOMs with syft
syft nginx:latest -o spdx-json > sbom.spdx.json
syft nginx:latest -o cyclonedx-json > sbom.cdx.json
```

#### Scanning SBOMs for Vulnerabilities

```bash
# Scan an existing SBOM for known vulnerabilities
trivy sbom sbom.spdx.json

# Scan and output in JSON format
trivy sbom --format json --output results.json sbom.spdx.json

# Scan with severity filter
trivy sbom --severity HIGH,CRITICAL sbom.spdx.json
```

#### Attaching SBOMs to Images

```bash
# Attach an SBOM to an image with cosign
cosign attach sbom --sbom sbom.spdx.json registry.example.com/myapp:v1.0
```

!!! tip "Exam Tip"
    Know the difference between `bom` (generates SPDX-JSON) and `trivy` (generates both SPDX-JSON and CycloneDX). The exam may ask you to generate an SBOM in a specific format and then scan it for vulnerabilities. The typical workflow is: generate SBOM with `bom` or `trivy`, then scan the SBOM file with `trivy sbom`.

## Practice Exercises

??? question "Exercise 1: Scan Images and Remove Vulnerable Pods"
    Scan all images used by pods in the `production` namespace. Identify pods running images with CRITICAL vulnerabilities and delete them.

    ??? success "Solution"
        ```bash
        # List all images used in the production namespace
        kubectl get pods -n production -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{"\n"}{end}{end}'

        # Scan each image for critical vulnerabilities
        trivy image --severity CRITICAL nginx:1.19
        trivy image --severity CRITICAL redis:6.0
        trivy image --severity CRITICAL myapp:v1.0

        # Delete pods using images with CRITICAL vulnerabilities
        kubectl delete pod <pod-name> -n production

        # If controlled by a Deployment, update the image to a patched version
        kubectl set image deployment/<deployment-name> \
          <container-name>=<fixed-image:tag> -n production
        ```

??? question "Exercise 2: Fix a Dockerfile"
    The following Dockerfile has multiple security issues. Identify and fix them.

    ```dockerfile
    FROM ubuntu:latest
    RUN apt-get update && apt-get install -y gcc make curl wget
    COPY . /app
    WORKDIR /app
    ENV API_KEY=sk-1234567890abcdef
    RUN make build
    EXPOSE 22 8080
    CMD ["./app"]
    ```

    ??? success "Solution"
        Issues identified:

        1. Uses `latest` tag
        2. Installs unnecessary packages (curl, wget)
        3. No multi-stage build (build tools in final image)
        4. Secret in ENV variable
        5. Port 22 (SSH) exposed
        6. Runs as root (no USER directive)

        Fixed Dockerfile:

        ```dockerfile
        # Build stage
        FROM ubuntu:22.04 AS builder
        RUN apt-get update && apt-get install -y --no-install-recommends gcc make && \
            rm -rf /var/lib/apt/lists/*
        WORKDIR /app
        COPY . .
        RUN make build

        # Runtime stage
        FROM ubuntu:22.04
        RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && \
            rm -rf /var/lib/apt/lists/* && \
            groupadd -r appgroup && useradd -r -g appgroup -u 1000 appuser
        WORKDIR /app
        COPY --from=builder /app/app .
        USER 1000:1000
        EXPOSE 8080
        ENTRYPOINT ["./app"]
        ```

        Note: The `API_KEY` should be passed at runtime via a Kubernetes Secret, not baked into the image.

??? question "Exercise 3: Configure ImagePolicyWebhook (Hands-On Lab)"
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

??? question "Exercise 4: Sign and Verify a Container Image"
    Sign a container image using cosign and verify the signature.

    ??? success "Solution"
        ```bash
        # Generate a key pair
        cosign generate-key-pair
        # Creates cosign.key (private) and cosign.pub (public)

        # Build and push an image
        docker build -t registry.example.com/myapp:v1.0 .
        docker push registry.example.com/myapp:v1.0

        # Sign the image
        cosign sign --key cosign.key registry.example.com/myapp:v1.0

        # Verify the signature
        cosign verify --key cosign.pub registry.example.com/myapp:v1.0

        # The output shows the verified signature and claims
        ```

??? question "Exercise 5: Enforce Allowed Image Registries with OPA Gatekeeper"
    Using OPA Gatekeeper, create a policy that only allows images from `docker.io/library/` and `registry.internal.io/` in the `production` namespace.

    ??? success "Solution"
        ```yaml
        # constraint-template.yaml
        apiVersion: templates.gatekeeper.sh/v1
        kind: ConstraintTemplate
        metadata:
          name: k8sallowedregistries
        spec:
          crd:
            spec:
              names:
                kind: K8sAllowedRegistries
              validation:
                openAPIV3Schema:
                  type: object
                  properties:
                    registries:
                      type: array
                      items:
                        type: string
          targets:
            - target: admission.k8s.gatekeeper.sh
              rego: |
                package k8sallowedregistries

                violation[{"msg": msg}] {
                  container := input.review.object.spec.containers[_]
                  satisfied := [good | repo = input.parameters.registries[_]; good = startswith(container.image, repo)]
                  not any(satisfied)
                  msg := sprintf("Container image %v is not from an allowed registry. Allowed: %v", [container.image, input.parameters.registries])
                }
        ```

        ```yaml
        # constraint.yaml
        apiVersion: constraints.gatekeeper.sh/v1beta1
        kind: K8sAllowedRegistries
        metadata:
          name: production-allowed-registries
        spec:
          match:
            kinds:
              - apiGroups: [""]
                kinds: ["Pod"]
            namespaces: ["production"]
          parameters:
            registries:
              - "docker.io/library/"
              - "registry.internal.io/"
        ```

        ```bash
        kubectl apply -f constraint-template.yaml
        kubectl apply -f constraint.yaml

        # Test: allowed image
        kubectl run nginx --image=docker.io/library/nginx:1.25 -n production
        # Expected: allowed

        # Test: denied image
        kubectl run hacker --image=evil-registry.io/malware:latest -n production
        # Expected: denied
        ```

??? question "Exercise 6: Static Analysis of Dockerfiles with Conftest (Hands-On Lab)"
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

??? question "Exercise 7: Use Image Digests Instead of Tags (Hands-On Lab)"
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

## Further Reading

- [Trivy Documentation](https://aquasecurity.github.io/trivy/)
- [Sigstore / Cosign Documentation](https://docs.sigstore.dev/)
- [ImagePolicyWebhook](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#imagepolicywebhook)
- [Dockerfile Best Practices](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- [OPA Gatekeeper](https://open-policy-agent.github.io/gatekeeper/website/docs/)
- [Conftest Documentation](https://www.conftest.dev/)
- [SPDX SBOM Specification](https://spdx.dev/)
