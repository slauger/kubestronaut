#!/usr/bin/env bash
set -euo pipefail

# CKS Lab: Secret Encryption at Rest
# Creates test secrets and verifies they are stored unencrypted in etcd,
# so the student can then configure EncryptionConfiguration.

NAMESPACE="encryption-test"

echo "=== CKS Lab: Secret Encryption at Rest ==="

echo "[1/3] Creating namespace ${NAMESPACE}..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "[2/3] Creating test secrets..."
kubectl -n "${NAMESPACE}" create secret generic db-credentials \
  --from-literal=username=admin \
  --from-literal=password=S3cretP@ssw0rd-12345 \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" create secret generic api-token \
  --from-literal=token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.FAKE_TOKEN \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[3/3] Verifying secrets are readable from etcd (unencrypted)..."
echo ""

# Check if etcd certs are available
if [[ -f /etc/kubernetes/pki/etcd/ca.crt ]]; then
  echo "Reading secret directly from etcd:"
  ETCDCTL_API=3 etcdctl get /registry/secrets/${NAMESPACE}/db-credentials \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    | hexdump -C | grep -i "s3cret" || echo "(password pattern not found in hexdump - encryption may already be active)"
  echo ""
fi

echo "=== Setup Complete ==="
echo ""
echo "Test secrets created in namespace '${NAMESPACE}':"
echo "  - db-credentials (username=admin, password=S3cretP@ssw0rd-12345)"
echo "  - api-token"
echo ""
echo "Your task:"
echo "  1. Verify secrets are stored UNENCRYPTED in etcd using etcdctl:"
echo "     ETCDCTL_API=3 etcdctl get /registry/secrets/${NAMESPACE}/db-credentials \\"
echo "       --endpoints=https://127.0.0.1:2379 \\"
echo "       --cacert=/etc/kubernetes/pki/etcd/ca.crt \\"
echo "       --cert=/etc/kubernetes/pki/etcd/server.crt \\"
echo "       --key=/etc/kubernetes/pki/etcd/server.key | hexdump -C"
echo ""
echo "  2. Create an EncryptionConfiguration with aescbc provider"
echo "  3. Configure the API server to use it (--encryption-provider-config)"
echo "  4. Re-encrypt all existing secrets: kubectl get secrets -A -o json | kubectl replace -f -"
echo "  5. Verify the secret is now ENCRYPTED in etcd (hexdump should show 'enc:aescbc' prefix)"
