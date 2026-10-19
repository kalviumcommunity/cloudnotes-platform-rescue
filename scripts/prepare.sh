#!/bin/bash
# Instructor only; prepares dependencies, never repairs student files.
set -euo pipefail
cd "$(dirname "$0")/.."
export NAMESPACE="${NAMESPACE:-cloudnotes-platform}"
docker image inspect python:3.12-slim-bookworm nginx:alpine prom/prometheus:v3.5.0 >/dev/null
docker network inspect platform-rescue-net >/dev/null 2>&1 || docker network create --subnet 10.231.240.0/24 platform-rescue-net
docker rm -f platform-backend >/dev/null 2>&1 || true
docker run -d --name platform-backend --network platform-rescue-net --network-alias backend \
  -e APP_MODE=production -v "$PWD/app:/app:ro" -w /app python:3.12-slim-bookworm python server.py
# Independent fixture image keeps Task 4 separate from the Task 3 build.
docker rm -f platform-fixture-seed >/dev/null 2>&1 || true
docker create --name platform-fixture-seed python:3.12-slim-bookworm python /server.py >/dev/null
docker cp app/server.py platform-fixture-seed:/server.py
docker commit platform-fixture-seed cloudnotes-platform-ready:1.0.0 >/dev/null
docker rm platform-fixture-seed >/dev/null
# Instructor must load fixture and Python client images into every cluster node before continuing.
if [[ "${PREPARE_CLUSTER_IMAGES:-0}" == 1 ]]; then
  : "${KIND_NODE:?Set KIND_NODE to the dedicated local Docker-backed cluster node}"
  docker save cloudnotes-platform-ready:1.0.0 python:3.12-slim-bookworm | docker exec -i "$KIND_NODE" ctr -n k8s.io images import -
fi
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NAMESPACE" apply -f k8s/client.yaml
kubectl -n "$NAMESPACE" wait --for=condition=Ready pod/client --timeout=90s
kubectl -n "$NAMESPACE" apply -f k8s/
echo 'Preparation complete. Starter application is intentionally not Ready.'
