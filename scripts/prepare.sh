#!/usr/bin/env bash
# Compatibility entrypoint: isolated self-service preparation only.
set -euo pipefail
exec bash "$(dirname "$0")/prepare-lab.sh" "$@"
