#!/usr/bin/env bash
set -euo pipefail

# CKS Lab: ValidatingWebhookConfiguration
# Deploys an AdmissionReview webhook server that rejects pods
# without runAsNonRoot: true

SERVICE_NAME="webhook-server"
NAMESPACE="webhook"
FQDN="${SERVICE_NAME}.${NAMESPACE}.svc"

echo "=== CKS Lab: ValidatingWebhookConfiguration Setup ==="

# --- Generate TLS certificates ---
echo "[1/5] Generating TLS certificates for ${FQDN}..."
TMPDIR=$(mktemp -d)

openssl genrsa -out "${TMPDIR}/ca.key" 2048 2>/dev/null
openssl req -x509 -new -nodes -key "${TMPDIR}/ca.key" \
  -subj "/CN=webhook-ca" -days 365 -out "${TMPDIR}/ca.crt" 2>/dev/null

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
EOF

openssl req -new -key "${TMPDIR}/server.key" \
  -out "${TMPDIR}/server.csr" -config "${TMPDIR}/csr.conf" 2>/dev/null

openssl x509 -req -in "${TMPDIR}/server.csr" \
  -CA "${TMPDIR}/ca.crt" -CAkey "${TMPDIR}/ca.key" -CAcreateserial \
  -out "${TMPDIR}/server.crt" -days 365 \
  -extensions v3_req -extfile "${TMPDIR}/csr.conf" 2>/dev/null

CA_BUNDLE=$(base64 < "${TMPDIR}/ca.crt" | tr -d '\n')

# --- Create namespace and resources ---
echo "[2/5] Creating namespace ${NAMESPACE}..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "[3/5] Creating test namespace webhook-test..."
kubectl create namespace webhook-test --dry-run=client -o yaml | kubectl apply -f -

echo "[4/5] Deploying webhook server..."

kubectl -n "${NAMESPACE}" delete secret webhook-server-tls --ignore-not-found >/dev/null 2>&1
kubectl -n "${NAMESPACE}" create secret tls webhook-server-tls \
  --cert="${TMPDIR}/server.crt" \
  --key="${TMPDIR}/server.key"

kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: ConfigMap
metadata:
  name: webhook-server
  namespace: webhook
data:
  server.py: |
    import json, ssl, http.server

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            request = body.get("request", {})
            uid = request.get("uid", "")
            obj = request.get("object", {})

            allowed = True
            message = ""

            # Check all containers for runAsNonRoot
            spec = obj.get("spec", {})
            pod_security = spec.get("securityContext", {})
            containers = spec.get("containers", [])

            for c in containers:
                container_sc = c.get("securityContext", {})
                run_as_non_root = container_sc.get("runAsNonRoot",
                    pod_security.get("runAsNonRoot", None))
                if run_as_non_root is not True:
                    allowed = False
                    message = (
                        f"container '{c['name']}' must set "
                        f"securityContext.runAsNonRoot to true"
                    )
                    break

            review = {
                "apiVersion": "admission.k8s.io/v1",
                "kind": "AdmissionReview",
                "response": {
                    "uid": uid,
                    "allowed": allowed,
                }
            }
            if not allowed:
                review["response"]["status"] = {
                    "code": 403,
                    "message": message,
                }

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(review).encode())

        def log_message(self, format, *args):
            print(f"[webhook] {args[0]}")

    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain("/tls/tls.crt", "/tls/tls.key")

    server = http.server.HTTPServer(("0.0.0.0", 8443), Handler)
    server.socket = ctx.wrap_socket(server.socket, server_side=True)
    print("Validating webhook server listening on :8443")
    server.serve_forever()
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webhook-server
  namespace: webhook
  labels:
    app: webhook-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: webhook-server
  template:
    metadata:
      labels:
        app: webhook-server
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
            secretName: webhook-server-tls
        - name: server-code
          configMap:
            name: webhook-server
---
apiVersion: v1
kind: Service
metadata:
  name: webhook-server
  namespace: webhook
spec:
  selector:
    app: webhook-server
  ports:
    - port: 443
      targetPort: 8443
      protocol: TCP
MANIFEST

echo "[5/5] Waiting for webhook server to be ready..."
kubectl -n "${NAMESPACE}" rollout status deployment/webhook-server --timeout=120s

# --- Cleanup temp files ---
rm -rf "${TMPDIR}"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "The validating webhook server is running at:"
echo "  https://webhook-server.webhook.svc/validate"
echo ""
echo "CA Bundle (base64-encoded, use for caBundle field):"
echo "  ${CA_BUNDLE}"
echo ""
echo "You can also get it from the TLS secret:"
echo "  kubectl -n webhook get secret webhook-server-tls -o jsonpath='{.data.tls\\.crt}'"
echo ""
echo "Your task:"
echo "  1. Create a ValidatingWebhookConfiguration that:"
echo "     - Targets service webhook-server in namespace webhook, path /validate"
echo "     - Uses the CA bundle above"
echo "     - Only applies to namespace webhook-test (use namespaceSelector)"
echo "     - Uses failurePolicy: Fail"
echo "  2. Test: create a pod in webhook-test WITHOUT runAsNonRoot (should be DENIED)"
echo "  3. Test: create a pod in webhook-test WITH runAsNonRoot: true (should WORK)"
