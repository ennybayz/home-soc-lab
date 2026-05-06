#!/usr/bin/env bash
# teardown.sh - stop and remove the lab stack.
# Pass --wipe to also delete named volumes and generated certs.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT/docker"

if [[ "${1:-}" == "--wipe" ]]; then
  echo "==> Removing containers and volumes"
  docker compose down -v
  echo "==> Removing generated certs"
  rm -rf wazuh/config/wazuh_indexer_ssl_certs/*
else
  echo "==> Removing containers (keeping volumes)"
  docker compose down
  echo "    pass --wipe to also delete volumes and certs"
fi
