# CloudNotes Platform Rescue

Five independent local release checks fail. Repair only the files assigned below; application and checks are supplied. Each check exercises a separate release requirement.

## Start

Fork into your own account, clone your fork, and create `fix/platform-release`. Run commands from repository root. Push only to your fork; never push or open a PR against `kalviumcommunity/cloudnotes-platform-rescue`.

## Release requirements

| Task | Editable file(s) | Required behaviour | Check |
|---|---|---|---|
| 1 | `local/start.env` | Application accepts requests from another container on port 8080 and reports production mode. | `python3 scripts/check.py 1` |
| 2 | `network/nginx.conf` | Gateway permits only client `10.231.240.20/32`, blocks every other caller, and forwards HTTP requests to supplied `backend` listening on 8080. Gateway itself listens on 8080. | `python3 scripts/check.py 2` |
| 3 | `Dockerfile` runtime stage | Keep supplied build stage. Copy only packaged server into `/app/server.py`; run as UID:GID `10001:10001`; start packaged server. | `python3 scripts/check.py 3` |
| 4 | `k8s/deployment.yaml`, `k8s/service.yaml` | Use supplied ConfigMap, expose application listener through Service port 80, and make readiness test actual health endpoint. Service request must report production mode. | `python3 scripts/check.py 4` |
| 5 | `monitoring/alerts.yaml` | `cloudnotes_error_ratio` is a fraction. Alert when it stays strictly above 5% for two minutes, with severity `critical`. Normal traffic and brief spikes must not fire. | `python3 scripts/check.py 5` |

Application contract: HTTP `GET /health` on port 8080 returns status `ok` and current mode. `APP_HOST`, `APP_PORT`, `APP_MODE` configure local startup. Kubernetes uses a separate preloaded working image so Task 3 cannot block Task 4.

Each task needs three changed configuration lines. Keep names, supplied scripts/tests, build stage, application, namespace, other manifest settings, and alert name/summary unchanged. Do not delete checks, hardcode successful results, or alter expected test data. Read failures to diagnose; no hidden application bugs. Comments explain intent, not replacement values.

Task 2 implements HTTP network-access rules with Nginx inside an isolated Docker network, not a GCP firewall, OS packet filter, or IAM simulation. The test clients use fixed network addresses. No host firewall edits, privileged containers, host networking, published ports, cloud accounts, or paid services are needed.

## Evidence

One real screenshot per task: relevant changed lines (editor or `git diff`) and actual check output. Task 3 may show the concise build-result summary; Task 4 must show Ready Pod and Service response. Five labelled screenshots in one PDF, below 2 MB. No Markdown report, written explanations, PR, or video required. Never fabricate command output or show credentials.

## Self-service setup — before timer

Use Linux, macOS or WSL2 with Bash, Git, Python 3, curl and running Docker Engine. Host and engine support amd64/arm64. Allow 2 CPUs, 4 GB free memory and 10 GB free disk for Docker. Initial downloads need internet access to GitHub, kind, Kubernetes and image registries. Docker Desktop optional only where its free-use licence applies. Free editor and PDF exporter suffice. No cloud account, paid tool, registry login or host firewall change required.

```bash
bash scripts/prepare-lab.sh
source .lab/env.sh
kubectl -n cloudnotes-platform get pods,svc
```

Setup downloads checksum-verified local kind and matching Kubernetes 1.32.2 kubectl, creates dedicated `cloudnotes-endsem` cluster/private kubeconfig, caches images, builds separate working fixture and imports both fixture and client image. It verifies backend HTTP, promtool availability and Ready Kubernetes client, then applies intentionally broken manifests. No repair files are changed. Start timer only after `SETUP READY`; application startup failure is intentional. Source `.lab/env.sh` in every terminal so checks use isolated cluster and compatible client.

Dedicated Docker network `platform-rescue-net` uses `10.231.240.0/24`. Setup checks Docker-network overlap and refuses pre-existing resource names; also check this subnet against VPN/LAN routes before setup. One candidate per Docker daemon. Do not delete unknown resources to resolve conflicts; use separate engine. Do not rerun setup during repairs. Setup/download failures are prerequisite issues, not planted defects.

After saving evidence, optional cleanup removes only lab resources and practice data:

```bash
.lab/bin/kind delete cluster --name cloudnotes-endsem
docker rm -f platform-backend
docker network rm platform-rescue-net
rm -rf .lab
```

Run cleanup only for resources created by this clone. Checks clean up their own temporary test containers. Use fresh clone for fresh attempt. Never use system prune or delete unrelated clusters.
