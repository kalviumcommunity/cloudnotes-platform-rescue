#!/usr/bin/env bash
# Isolated student-owned infrastructure, outside timed repairs.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
REPO=$(basename "$(git remote get-url origin)" .git)
fail() { echo "SETUP FAILED: $*" >&2; exit 1; }
case "$REPO" in
 cloudnotes-workload-rescue) CLUSTER=cloudnotes-ca4; NAMESPACE=cloudnotes-rescue;;
 cloudnotes-platform-rescue) CLUSTER=cloudnotes-endsem; NAMESPACE=cloudnotes-platform;;
 *) fail 'Wrong starter clone.';;
esac
[ ! -e .lab/prepared ] || fail 'Already prepared. Do not rerun during repairs; use README cleanup for fresh attempt.'
bash scripts/prerequisites.sh
mkdir -p .lab/bin
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$(uname -m)" in arm64|aarch64) HOST_ARCH=arm64;; x86_64|amd64) HOST_ARCH=amd64;; *) fail 'Unsupported host architecture.';; esac
case "$(docker info --format '{{.Architecture}}')" in arm64|aarch64) ARCH=arm64;; x86_64|amd64) ARCH=amd64;; *) fail 'Unsupported Docker architecture.';; esac
fetch() {
  local url="$1" output="$2" checksum_url="$3"
  curl -fL --retry 3 --retry-all-errors --connect-timeout 20 "$url" -o "$output.download"
  curl -fL --retry 3 "$checksum_url" -o "$output.sha256"
  python3 - "$output.download" "$output.sha256" <<'PY'
import hashlib,pathlib,sys
assert hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest()==pathlib.Path(sys.argv[2]).read_text().split()[0], 'Binary checksum mismatch'
PY
  mv "$output.download" "$output"; chmod +x "$output"
}
[ -x .lab/bin/kind ] || fetch "https://kind.sigs.k8s.io/dl/v0.27.0/kind-$OS-$HOST_ARCH" .lab/bin/kind "https://kind.sigs.k8s.io/dl/v0.27.0/kind-$OS-$HOST_ARCH.sha256sum"
# Match server minor; do not rely on incompatible host kubectl.
[ -x .lab/bin/kubectl ] || fetch "https://dl.k8s.io/release/v1.32.2/bin/$OS/$HOST_ARCH/kubectl" .lab/bin/kubectl "https://dl.k8s.io/release/v1.32.2/bin/$OS/$HOST_ARCH/kubectl.sha256"
KIND="$ROOT/.lab/bin/kind"
export PATH="$ROOT/.lab/bin:$PATH" KUBECONFIG="$ROOT/.lab/kubeconfig" NAMESPACE
# Never adopt any existing cluster, even one with same name.
if [ ! -e .lab/cluster-owned ]; then
  if "$KIND" get clusters | grep -qx "$CLUSTER"; then fail "Cluster $CLUSTER already exists. Do not delete/adopt unknown clusters; use separate Docker engine."; fi
  touch .lab/cluster-owned
fi
if ! "$KIND" get clusters | grep -qx "$CLUSTER"; then
  "$KIND" create cluster --name "$CLUSTER" --image kindest/node:v1.32.2 --kubeconfig "$KUBECONFIG" --wait 180s
fi
"$KIND" get kubeconfig --name "$CLUSTER" > "$KUBECONFIG"
chmod 600 "$KUBECONFIG"
kubectl config use-context "kind-$CLUSTER"
kubectl wait --for=condition=Ready nodes --all --timeout=180s
kubectl get nodes -o json > .lab/nodes.json
python3 - <<'PY'
import json
for node in json.load(open('.lab/nodes.json'))['items']:
    a=node['status']['allocatable']; cpu=a['cpu']; mem=a['memory']
    cpu=float(cpu[:-1])/1000 if cpu.endswith('m') else float(cpu)
    assert cpu>=2, 'Need at least 2 allocatable CPUs'
    factors={'Ki':1024,'Mi':1024**2,'Gi':1024**3}
    size=next((float(mem[:-2])*v for k,v in factors.items() if mem.endswith(k)),0)
    assert size>=2*1024**3, 'Need at least 2 GiB allocatable RAM'
PY
load_image() {
  docker image save "$1" | docker exec --privileged -i "$CLUSTER-control-plane" ctr --namespace=k8s.io images import --platform "linux/$ARCH" --digests -
}
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
if [ "$REPO" = cloudnotes-workload-rescue ]; then
  docker build -t cloudnotes-workload:1.0.0 .
  load_image cloudnotes-workload:1.0.0
  # Actual temporary PVC consumer checks provisioning and non-root writable storage.
  kubectl -n "$NAMESPACE" apply -f k8s/pvc.yaml
  cat > .lab/storage-check.yaml <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: setup-storage-check
spec:
  restartPolicy: Never
  securityContext:
    runAsUser: 10001
    runAsGroup: 10001
    fsGroup: 10001
  containers:
  - name: check
    image: cloudnotes-workload:1.0.0
    imagePullPolicy: Never
    command: ["python", "-c", "from pathlib import Path; p=Path('/check/.setup-probe'); p.write_text('ok'); assert p.read_text()=='ok'; p.unlink()"]
    volumeMounts:
    - name: data
      mountPath: /check
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: cloudnotes-data
YAML
  kubectl -n "$NAMESPACE" apply -f .lab/storage-check.yaml
  kubectl -n "$NAMESPACE" wait --for=jsonpath='{.status.phase}'=Succeeded pod/setup-storage-check --timeout=180s
  kubectl -n "$NAMESPACE" delete pod setup-storage-check --wait=true
  bash scripts/setup.sh
else
  # Fixed-address tests need dedicated non-overlapping network. No host networking.
  python3 - <<'PY'
import ipaddress,json,subprocess
ids=subprocess.check_output(['docker','network','ls','-q'],text=True).split()
for net in json.loads(subprocess.check_output(['docker','network','inspect',*ids],text=True)) if ids else []:
    if net['Name']=='platform-rescue-net': raise SystemExit('platform-rescue-net already exists; do not adopt unknown network')
    for conf in (net.get('IPAM',{}).get('Config') or []):
        s=conf.get('Subnet')
        if s and ipaddress.ip_network(s).version==4 and ipaddress.ip_network(s).overlaps(ipaddress.ip_network('10.231.240.0/24')):
            raise SystemExit(f'Network overlap: {net["Name"]} {s}; use separate Docker engine before timing')
PY
  for name in platform-backend platform-local-check platform-gateway platform-image-check; do
    docker container inspect "$name" >/dev/null 2>&1 && fail "Container $name exists; do not remove unknown resources."
  done
  docker network create --label cloud.lab=cloudnotes-platform-rescue --subnet 10.231.240.0/24 platform-rescue-net
  # Separate working fixture does not repair assessed Dockerfile.
  cat > .lab/fixture.Dockerfile <<'DOCKER'
FROM python:3.12-slim-bookworm
COPY app/server.py /server.py
CMD ["python", "/server.py"]
DOCKER
  docker build -f .lab/fixture.Dockerfile -t cloudnotes-platform-ready:1.0.0 .
  load_image cloudnotes-platform-ready:1.0.0
  load_image python:3.12-slim-bookworm
  docker run -d --label cloud.lab=cloudnotes-platform-rescue --name platform-backend --network platform-rescue-net --network-alias backend -e APP_MODE=production -v "$ROOT/app:/app:ro" -w /app python:3.12-slim-bookworm python server.py
  docker run --rm --network platform-rescue-net python:3.12-slim-bookworm python -c 'import urllib.request,time; time.sleep(2); assert urllib.request.urlopen("http://backend:8080/health",timeout=5).status==200'
  docker run --rm --entrypoint /bin/promtool prom/prometheus:v3.5.0 --version
  kubectl -n "$NAMESPACE" apply -f k8s/
  kubectl -n "$NAMESPACE" wait --for=condition=Ready pod/client --timeout=180s
fi
printf 'export PATH=%q:"$PATH"\nexport KUBECONFIG=%q\nexport NAMESPACE=%q\n' "$ROOT/.lab/bin" "$KUBECONFIG" "$NAMESPACE" > .lab/env.sh
touch .lab/prepared
echo 'SETUP READY: infrastructure verified; application faults deliberately remain. In EACH task terminal: source .lab/env.sh'
