#!/bin/bash

set -euo pipefail

# Enable debug mode if DEBUG env var is set
[[ -n "${DEBUG:-}" ]] && set -x

# Ensure a cluster name is provided
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <cluster-name>"
    exit 1
fi

CLUSTER_NAME="$1"

# Create a temporary directory and clean up on exit
TEMP_DIR=$(mktemp -d -t eks-cert-XXXX)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Get the OIDC provider URL for the EKS cluster
OIDC_PROVIDER=$(aws eks describe-cluster \
    --name "$CLUSTER_NAME" \
    --query "cluster.identity.oidc.issuer" \
    --output text)

# Extract JWKS hostname from OIDC issuer URL
JWKS_HOST=$(curl -s "${OIDC_PROVIDER}/.well-known/openid-configuration" \
    | jq -r '.jwks_uri' \
    | sed -E 's#^https?://([^/]+).*#\1#')

# Extract all certificates into separate files
CERTS=$(openssl s_client \
    -servername "$JWKS_HOST" \
    -showcerts \
    -connect "$JWKS_HOST:443" < /dev/null 2>/dev/null \
    | awk -v dir="$TEMP_DIR" '
        /BEGIN CERTIFICATE/ {f = sprintf("%s/cert%03d.crt", dir, ++n)}
        f {print > f}
        /END CERTIFICATE/ {f = ""}')

# Identify the last cert file as the root CA
ROOT_CA=$(ls -1 "$TEMP_DIR"/*.crt | tail -n1)

# Extract SHA1 fingerprint without colons
THUMBPRINT=$(openssl x509 -in "$ROOT_CA" -noout -fingerprint | cut -d= -f2 | tr -d ':')

# Output JSON
printf '{"thumbprint": "%s"}\n' "$THUMBPRINT"
