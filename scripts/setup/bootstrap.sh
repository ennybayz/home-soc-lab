#!/usr/bin/env bash
# bootstrap.sh - first-time bring-up of the home SOC lab.
# Generates SSL certificates, builds custom images, then starts the stack.
#
# Usage:  ./scripts/setup/bootstrap.sh
# Re-run is idempotent - the cert generator skips already-issued certs.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DOCKER_DIR="$REPO_ROOT/docker"

cd "$DOCKER_DIR"

echo "==> [1/5] Checking prerequisites"
command -v docker >/dev/null || { echo "Docker is required"; exit 1; }
docker compose version >/dev/null || { echo "Docker Compose v2 is required"; exit 1; }

echo "==> [2/5] Tuning host vm.max_map_count for the Wazuh indexer"
if [[ "$(uname)" == "Linux" ]]; then
  current=$(sysctl -n vm.max_map_count)
  if [[ "$current" -lt 262144 ]]; then
    echo "    raising vm.max_map_count from $current to 262144 (sudo required)"
    sudo sysctl -w vm.max_map_count=262144
  fi
else
  echo "    skipping - non-Linux host. On Docker Desktop this is set inside the VM."
fi

echo "==> [3/5] Preparing .env"
if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "    .env copied from .env.example - edit it to rotate the demo passwords"
fi

echo "==> [4/5] Generating SSL certificates"
docker compose -f generate-certs.yml run --rm generator
echo "    certs written to $DOCKER_DIR/wazuh/config/wazuh_indexer_ssl_certs/"

echo "==> [5/5] Building images and starting stack"
docker compose pull
docker compose build
docker compose up -d

echo
echo "Stack is starting. Give it ~2 minutes for the indexer to become healthy."
echo "Dashboard:    https://localhost (admin / value of INDEXER_PASSWORD)"
echo "DVWA:         http://localhost:8080  (login admin / password)"
echo "Ubuntu host:  ssh -p 2222 labuser@localhost  (password: Password1)"
