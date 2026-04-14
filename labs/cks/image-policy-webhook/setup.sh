#!/usr/bin/env bash
set -euo pipefail

# CKS Lab: ImagePolicyWebhook
# Deploys an ImageReview webhook server that allows only images from
# docker.io/library/ and registry.k8s.io/

CERT_DIR="/etc/kubernetes/admission"
SERVICE_NAME="image-policy"
NAMESPACE="default"
FQDN="${SERVICE_NAME}.${NAMESPACE}.svc"

echo "=== CKS Lab: ImagePolicyWebhook Setup ==="

# --- Generate TLS certificates ---
echo "[1/4] Generating TLS certificates for ${FQDN}..."
TMPDIR=$(mktemp -d)

openssl genrsa -out "${TMPDIR}/ca.key" 2048 2>/dev/null
openssl req -x509 -new -nodes -key "${TMPDIR}/ca.key" \
  -subj "/CN=image-policy-ca" -days 365 -out "${TMPDIR}/ca.crt" 2>/dev/null

openssl genrsa -out "${TMPDIR}/server.key" 2048 2>/dev/null

cat > "${TMPDIR}/csr.conf" <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
CN = ${FQDN}

[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${SERVICE_NAME}
DNS.2 = ${SERVICE_NAME}.${NAMESPACE}
DNS.3 = ${FQDN}
DNS.4 = ${FQDN}.cluster.local
EOF

openssl req -new -key "${TMPDIR}/server.key" \
  -out "${TMPDIR}/server.csr" -config "${TMPDIR}/csr.conf" 2>/dev/null

openssl x509 -req -in "${TMPDIR}/server.csr" \
  -CA "${TMPDIR}/ca.crt" -CAkey "${TMPDIR}/ca.key" -CAcreateserial \
  -out "${TMPDIR}/server.crt" -days 365 \
  -extensions v3_req -extfile "${TMPDIR}/csr.conf" 2>/dev/null

# --- Copy CA cert for API server access ---
echo "[2/4] Installing CA certificate to ${CERT_DIR}..."
sudo mkdir -p "${CERT_DIR}"
sudo cp "${TMPDIR}/ca.crt" "${CERT_DIR}/webhook-ca.crt"

# --- Create TLS Secret and deploy webhook server ---
echo "[3/4] Deploying ImageReview webhook server..."

kubectl delete secret image-policy-tls --ignore-not-found >/dev/null 2>&1
kubectl create secret tls image-policy-tls \
  --cert="${TMPDIR}/server.crt" \
  --key="${TMPDIR}/server.key"

kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: ConfigMap
metadata:
  name: image-policy-server
  namespace: default
data:
  server.py: |
    import json, ssl, http.server

    ALLOWED_PREFIXES = ["docker.io/library/", "registry.k8s.io/"]

    # Images without a registry prefix (e.g. "nginx:latest") are from docker.io/library/
    def is_allowed(image):
        if "/" not in image.split(":")[0]:
            return True
        return any(image.startswith(p) for p in ALLOWED_PREFIXES)

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))

            # Handle ImageReview API (spec.containers[].image)
            containers = body.get("spec", {}).get("containers", [])
            images = [c.get("image", "") for c in containers if c.get("image")]

            allowed = True
            reason = ""
            for img in images:
                if not is_allowed(img):
                    allowed = False
                    reason = f"image {img} is not from an allowed registry"
                    break

            review = {
                "apiVersion": "imagepolicy.k8s.io/v1alpha1",
                "kind": "ImageReview",
                "status": {
                    "allowed": allowed,
                    "reason": reason,
                }
            }

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(review).encode())

        def log_message(self, format, *args):
            print(f"[image-policy] {args[0]}")

    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain("/tls/tls.crt", "/tls/tls.key")

    server = http.server.HTTPServer(("0.0.0.0", 8443), Handler)
    server.socket = ctx.wrap_socket(server.socket, server_side=True)
    print("ImageReview server listening on :8443")
    server.serve_forever()
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: image-policy
  namespace: default
  labels:
    app: image-policy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: image-policy
  template:
    metadata:
      labels:
        app: image-policy
    spec:
      containers:
        - name: server
          image: python:3-slim
          command: ["python3", "/app/server.py"]
          ports:
            - containerPort: 8443
          volumeMounts:
            - name: tls
              mountPath: /tls
              readOnly: true
            - name: server-code
              mountPath: /app
              readOnly: true
      volumes:
        - name: tls
          secret:
            secretName: image-policy-tls
        - name: server-code
          configMap:
            name: image-policy-server
---
apiVersion: v1
kind: Service
metadata:
  name: image-policy
  namespace: default
spec:
  selector:
    app: image-policy
  ports:
    - port: 8443
      targetPort: 8443
      protocol: TCP
MANIFEST

# --- Wait for pod to be ready ---
echo "[4/4] Waiting for webhook server to be ready..."
kubectl rollout status deployment/image-policy --timeout=120s

# --- Cleanup temp files ---
rm -rf "${TMPDIR}"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "The ImageReview webhook server is running at:"
echo "  https://${FQDN}:8443/validate"
echo ""
echo "Allowed image prefixes:"
echo "  - docker.io/library/ (including short names like 'nginx')"
echo "  - registry.k8s.io/"
echo ""
echo "CA certificate installed at:"
echo "  ${CERT_DIR}/webhook-ca.crt"
echo ""
echo "Your task:"
echo "  1. Create an AdmissionConfiguration at ${CERT_DIR}/admission-config.yaml"
echo "  2. Create a kubeconfig for the webhook at ${CERT_DIR}/imagepolicy-kubeconfig.yaml"
echo "     (CA cert: ${CERT_DIR}/webhook-ca.crt, server: https://${FQDN}:8443/validate)"
echo "  3. Enable ImagePolicyWebhook in the kube-apiserver with --admission-control-config-file"
echo "  4. Set defaultAllow: false so unknown images are rejected"
echo "  5. Verify: kubectl run nginx --image=nginx should WORK"
echo "  6. Verify: kubectl run evil --image=evil.io/malware should be DENIED"
