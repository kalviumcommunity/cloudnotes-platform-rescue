#!/usr/bin/env bash
# Pre-timer tooling and cache rehearsal; no student repairs.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
fail() { echo "SETUP FAILED: $*" >&2; exit 1; }
for tool in python3 git curl; do command -v "$tool" >/dev/null || fail "Install $tool before timing."; done
case "$(uname -s)" in Linux|Darwin) ;; *) fail 'Use Linux, macOS or WSL2; native Windows shells unsupported.';; esac
mkdir -p .lab
# Keep generated setup files out of Git without altering assessed .gitignore.
grep -qxF '.lab/' .git/info/exclude || printf '\n.lab/\n' >> .git/info/exclude
REPO=$(basename "$(git remote get-url origin)" .git)
case "$REPO" in
  notes-terraform-repair|cloudnotes-release-repair|cloudnotes-ca-release)
    command -v terraform >/dev/null || fail 'Install Terraform 1.5+ below 2.0 before timing.'
    terraform version -json > .lab/terraform-version.json
    python3 - <<'PY'
import json
v=tuple(map(int,json.load(open('.lab/terraform-version.json'))['terraform_version'].split('.')[:2]))
assert (1,5) <= v < (2,0), 'Use Terraform >=1.5 and <2'
PY
    mkdir -p .lab/provider-cache
    if [ "$REPO" = cloudnotes-ca-release ]; then
      # Actual Google provider init; root expression fault does not block init.
      TF_PLUGIN_CACHE_DIR="$ROOT/.lab/provider-cache" terraform -chdir=terraform init -backend=false
    else
      # Broken module interfaces may block real init. Rehearse built-in provider
      # separately, without editing or accepting arbitrary errors in assessed tree.
      mkdir -p .lab/terraform-probe
      printf 'resource "terraform_data" "setup" { input = "setup-only" }\n' > .lab/terraform-probe/main.tf
      terraform -chdir=.lab/terraform-probe init -backend=false
      terraform -chdir=.lab/terraform-probe validate
    fi
    ;;
esac
if [ "$REPO" = notes-terraform-repair ]; then
  echo 'SETUP READY: isolated Terraform probe passed; assessed init/validate/plan failures remain repair work.'
  exit 0
fi
command -v docker >/dev/null || fail 'Install Docker Engine and Compose v2 before timing.'
docker info >/dev/null 2>&1 || fail 'Start Docker engine before timing.'
docker compose version
docker compose up --help | grep -q -- --wait || fail 'Upgrade Compose v2 to support --wait.'
case "$REPO" in
  cloudnotes-release-repair) IMAGES='python:3.12-slim-bookworm postgres:16-bookworm registry:2'; PORTS='8080 5050';;
  cloudnotes-ca-release) IMAGES='node:22-bookworm node:22-bookworm-slim registry:2'; PORTS='8080 5001';;
  notes-container-release) IMAGES='python:3.12 python:3.12-slim postgres:16-alpine redis:7-alpine registry:2'; PORTS='8080 5050';;
  cloudnotes-workload-rescue) IMAGES='python:3.12-slim-bookworm'; PORTS='';;
  cloudnotes-platform-rescue) IMAGES='python:3.12-slim-bookworm nginx:alpine prom/prometheus:v3.5.0'; PORTS='';;
  *) fail 'Unrecognized starter; run from its Git clone.';;
esac
python3 - $PORTS <<'PY'
import socket,sys
for port in map(int,sys.argv[1:]):
    with socket.socket() as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try: s.bind(('0.0.0.0',port))
        except OSError as e: raise SystemExit(f'Port {port} unavailable: {e}. Stop only your own previous lab, then retry before timer.')
PY
for image in $IMAGES; do docker pull "$image"; done
# Build only supplied, correct build stage. Actual dependency layers reused by repair build.
case "$REPO" in
  cloudnotes-release-repair|notes-container-release|cloudnotes-ca-release)
    docker build --target build -t "${REPO}-build-cache:local" .
    ;;
esac
case "$REPO" in
  cloudnotes-release-repair|cloudnotes-ca-release|notes-container-release)
    case "$REPO" in
      cloudnotes-ca-release) PORT=5001;; *) PORT=5050;;
    esac
    NAME="$REPO-preflight-registry"
    docker container inspect "$NAME" >/dev/null 2>&1 && fail "Container $NAME exists; stop only your own previous setup before retry."
    docker run -d --label "cloud.lab=$REPO" --name "$NAME" -p "127.0.0.1:$PORT:5000" registry:2
    trap 'docker rm -f "$NAME" >/dev/null' EXIT
    for attempt in $(seq 1 30); do curl -fsS "http://localhost:$PORT/v2/" >/dev/null && break; sleep 1; done
    curl -fsS "http://localhost:$PORT/v2/" >/dev/null
    # Actual engine push/pull: catches loopback HTTP registry incompatibility.
    docker tag registry:2 "localhost:$PORT/setup-probe:local"
    docker push "localhost:$PORT/setup-probe:local"
    docker image rm "localhost:$PORT/setup-probe:local"
    docker pull "localhost:$PORT/setup-probe:local"
    docker rm -f "$NAME" >/dev/null
    trap - EXIT
    ;;
esac
echo 'PREREQUISITES READY: image pulls and applicable dependency/registry rehearsal complete.'
