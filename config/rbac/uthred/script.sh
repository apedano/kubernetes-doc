#!/bin/bash

set -e

# Configurable name
NAME="uthred"
KEY_FILE="${NAME}.key"
CSR_FILE="${NAME}.csr"
BASE64_FILE="${NAME}_csr.b64"
YAML_FILE="${NAME}-csr.yaml"

echo "🔐 Generating private key..."
openssl genrsa -out "$KEY_FILE" 2048

echo "📜 Generating PEM-formatted CSR..."
openssl req -new -key "$KEY_FILE" -subj "/CN=${NAME}" -out "$CSR_FILE"

echo "🔄 Base64-encoding the CSR..."
# Use -w 0 for GNU/Linux, macOS users can use base64 without -w
if base64 --help 2>&1 | grep -q -- "-w"; then
    #this makes sure the the line wrap is disabled, therefore the output is in one line only
    base64 -w 0 "$CSR_FILE" > "$BASE64_FILE"
else
    base64 "$CSR_FILE" | tr -d '\n' > "$BASE64_FILE"
fi

echo "📦 Generating Kubernetes CSR manifest..."
cat <<EOF > "$YAML_FILE"
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${NAME}-csr
spec:
  request: $(cat "$BASE64_FILE")
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
    - client auth
EOF

echo "✅ Done! Apply with:"
echo "kubectl apply -f ${YAML_FILE}"