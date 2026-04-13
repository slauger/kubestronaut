#!/usr/bin/env bash
set -euo pipefail

# CKS Lab: Conftest for Dockerfiles
# Creates sample Dockerfiles and OPA/Rego policies for static analysis.

LABDIR="/root/conftest-lab"

echo "=== CKS Lab: Conftest for Dockerfiles ==="

echo "[1/3] Checking conftest installation..."
if ! command -v conftest &>/dev/null; then
  echo "Installing conftest..."
  PLATFORM=$(uname -m)
  case "${PLATFORM}" in
    aarch64) PLATFORM="arm64" ;;
    x86_64)  PLATFORM="amd64" ;;
  esac
  curl -fsSL "https://github.com/open-policy-agent/conftest/releases/download/v0.57.0/conftest_0.57.0_Linux_${PLATFORM}.tar.gz" \
    | tar xz -C /usr/local/bin conftest
  chmod +x /usr/local/bin/conftest
fi
echo "conftest version: $(conftest --version)"

echo "[2/3] Creating lab directory and sample Dockerfiles..."
mkdir -p "${LABDIR}/policy" "${LABDIR}/dockerfiles"

# Insecure Dockerfile 1: Multiple issues
cat > "${LABDIR}/dockerfiles/Dockerfile.insecure" <<'EOF'
FROM ubuntu:latest
RUN apt-get update && apt-get install -y curl wget gcc make netcat-traditional
COPY . /app
WORKDIR /app
ENV DB_PASSWORD=supersecret123
RUN make build
EXPOSE 22 80 8080
CMD ["./app"]
EOF

# Insecure Dockerfile 2: Some issues
cat > "${LABDIR}/dockerfiles/Dockerfile.partial" <<'EOF'
FROM node:20
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD ["node", "server.js"]
EOF

# Secure Dockerfile (reference)
cat > "${LABDIR}/dockerfiles/Dockerfile.secure" <<'EOF'
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o app .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /app/app /app
USER 65534:65534
EXPOSE 8080
ENTRYPOINT ["/app"]
EOF

echo "[3/3] Creating starter OPA policy..."
cat > "${LABDIR}/policy/dockerfile.rego" <<'REGO'
package main

# TASK: Complete these rules and add more!

# Rule: Deny use of 'latest' tag
deny[msg] {
  input[i].Cmd == "from"
  val := input[i].Value[0]
  endswith(val, ":latest")
  msg := sprintf("Stage %d: Do not use ':latest' tag: '%s'", [i, val])
}

# TODO: Add a rule that denies ENV instructions containing "PASSWORD" or "SECRET"
# TODO: Add a rule that denies EXPOSE 22 (SSH port)
# TODO: Add a rule that requires a USER instruction (non-root)
# TODO: Add a rule that denies installation of curl, wget, or netcat
REGO

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Lab directory: ${LABDIR}"
echo ""
echo "Sample Dockerfiles:"
echo "  ${LABDIR}/dockerfiles/Dockerfile.insecure  (multiple issues)"
echo "  ${LABDIR}/dockerfiles/Dockerfile.partial    (some issues)"
echo "  ${LABDIR}/dockerfiles/Dockerfile.secure     (reference)"
echo ""
echo "Starter policy: ${LABDIR}/policy/dockerfile.rego"
echo ""
echo "Test the starter rule:"
echo "  conftest test ${LABDIR}/dockerfiles/Dockerfile.insecure --policy ${LABDIR}/policy"
echo "  (should catch :latest tag)"
echo ""
echo "Your task:"
echo "  1. Complete the TODOs in ${LABDIR}/policy/dockerfile.rego:"
echo "     - Deny ENV with PASSWORD/SECRET"
echo "     - Deny EXPOSE 22"
echo "     - Require USER instruction"
echo "     - Deny curl/wget/netcat in RUN"
echo ""
echo "  2. Run conftest against all three Dockerfiles:"
echo "     conftest test ${LABDIR}/dockerfiles/ --policy ${LABDIR}/policy"
echo ""
echo "  3. Dockerfile.insecure should have the most failures"
echo "  4. Dockerfile.secure should pass all checks"
