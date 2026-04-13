#!/usr/bin/env bash
set -euo pipefail

# CKS Lab: CertificateSigningRequests
# Creates a scenario where the student must handle CSRs:
# - Approve a legitimate CSR
# - Deny a suspicious CSR
# - Use the approved certificate to configure a kubeconfig

LABDIR="/root/csr-lab"

echo "=== CKS Lab: CertificateSigningRequests ==="

echo "[1/3] Preparing key material..."
mkdir -p "${LABDIR}"

# Generate key + CSR for a legitimate developer
openssl genrsa -out "${LABDIR}/developer.key" 2048 2>/dev/null
openssl req -new -key "${LABDIR}/developer.key" \
  -out "${LABDIR}/developer.csr" \
  -subj "/CN=developer-jane/O=development" 2>/dev/null

# Generate key + CSR for a suspicious request (cluster-admin attempt)
openssl genrsa -out "${LABDIR}/suspicious.key" 2048 2>/dev/null
openssl req -new -key "${LABDIR}/suspicious.key" \
  -out "${LABDIR}/suspicious.csr" \
  -subj "/CN=admin-backdoor/O=system:masters" 2>/dev/null

echo "[2/3] Submitting CSRs to Kubernetes API..."

# Clean up any previous CSRs
kubectl delete csr developer-jane admin-backdoor --ignore-not-found >/dev/null 2>&1

# Submit the legitimate CSR
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: developer-jane
spec:
  request: $(base64 < "${LABDIR}/developer.csr" | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
    - client auth
EOF

# Submit the suspicious CSR
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: admin-backdoor
spec:
  request: $(base64 < "${LABDIR}/suspicious.csr" | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
    - client auth
EOF

echo "[3/3] Creating RBAC for the developer..."
kubectl create namespace development --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<'MANIFEST'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: developer
  namespace: development
rules:
  - apiGroups: ["", "apps"]
    resources: ["pods", "deployments", "services"]
    verbs: ["get", "list", "create", "update", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: developer-jane-binding
  namespace: development
subjects:
  - kind: User
    name: developer-jane
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: developer
  apiGroup: rbac.authorization.k8s.io
MANIFEST

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Two CertificateSigningRequests are pending:"
kubectl get csr developer-jane admin-backdoor
echo ""
echo "Lab files: ${LABDIR}/"
echo "  developer.key   - private key for the legitimate developer"
echo "  developer.csr   - CSR for developer-jane (O=development)"
echo "  suspicious.key  - private key for suspicious request"
echo "  suspicious.csr  - CSR for admin-backdoor (O=system:masters!)"
echo ""
echo "Your task:"
echo ""
echo "  1. Inspect both CSRs:"
echo "     kubectl get csr"
echo "     kubectl describe csr developer-jane"
echo "     kubectl describe csr admin-backdoor"
echo "     Hint: decode the request to see the subject:"
echo "     kubectl get csr admin-backdoor -o jsonpath='{.spec.request}' | base64 -d | openssl req -noout -subject"
echo ""
echo "  2. The 'admin-backdoor' CSR has O=system:masters (cluster-admin!)."
echo "     DENY it:  kubectl certificate deny admin-backdoor"
echo ""
echo "  3. The 'developer-jane' CSR is legitimate."
echo "     APPROVE it:  kubectl certificate approve developer-jane"
echo ""
echo "  4. Extract the signed certificate:"
echo "     kubectl get csr developer-jane -o jsonpath='{.status.certificate}' | base64 -d > ${LABDIR}/developer.crt"
echo ""
echo "  5. Create a kubeconfig for developer-jane and verify access:"
echo "     kubectl config set-credentials developer-jane --client-certificate=${LABDIR}/developer.crt --client-key=${LABDIR}/developer.key"
echo "     kubectl config set-context developer --cluster=kubernetes --user=developer-jane --namespace=development"
echo "     kubectl --context=developer get pods -n development"
echo "     kubectl --context=developer get pods -n kube-system  (should be DENIED)"
