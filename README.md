# CloudNotes Platform Rescue

Five independent local release checks fail. Repair only the files assigned below; application and checks are supplied. Your assessment contains tasks and marking criteria.

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

## Instructor preparation — before timer

Free tools: Python 3, Docker Engine, kubectl, local Kubernetes, Nginx and Prometheus/promtool. Docker Desktop optional only if its free-use licence applies. A free editor and PDF exporter suffice.

1. Prepare an isolated local cluster/context and Docker environment for each candidate. Check sufficient memory/disk and that `10.231.240.0/24` does not overlap existing networks. These fixed client addresses require a dedicated network; do not share simultaneous candidates on one Docker daemon.
2. Retrieve free images before exam: `python:3.12-slim-bookworm`, `nginx:alpine`, `prom/prometheus:v3.5.0`. Ensure Python 3 and kubectl work. No image downloads during timer.
3. Run `bash scripts/prepare.sh` after making fixture/client images available in all cluster nodes. The helper builds fixture image without changing student files. For a dedicated Docker-backed kind node, `PREPARE_CLUSTER_IMAGES=1 KIND_NODE=<node-container> bash scripts/prepare.sh` can load both images. Other clusters: load fixture/client images with cluster's supported image loader, then rerun preparation. No live cloud Kubernetes.
4. Client must be Ready; application startup failure is intended. Check all five broken states and independently repaired copies on actual lab machines before exam. Confirm no solution files or prepared repairs are exposed to students. Do not rerun preparation during student work: it reapplies starter manifests.
5. Namespace defaults to `cloudnotes-platform`; instructor may assign an isolated namespace with `NAMESPACE=...` for preparation and Task 4 checks. Do not change unrelated cluster resources. Instructor handles cleanup after evidence is saved.

All tasks execute locally. Initial internet retrieval is free but must happen before exam. No GCP account, Terraform provider, billing, registry login, hosted CI, or paid tool is part of assessment. The 50-minute target needs student piloting; automated checks are not measured student solve time.
