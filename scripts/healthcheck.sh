#!/usr/bin/env bash

set -euo pipefail

URL="${HEALTHCHECK_URL:-http://localhost/health/}"

echo "Checking application health at: $URL"

response="$(curl --fail --silent --show-error "$URL")"

echo "Health response: $response"

if [[ "$response" != *'"status": "healthy"'* ]]; then
    echo "Health check failed: unexpected response"
    exit 1
fi

echo "Health check passed"
