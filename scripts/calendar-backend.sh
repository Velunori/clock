#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd -P)
calendar_python=python3
if [[ -x "$repo_dir/.venv/bin/python" ]]; then calendar_python="$repo_dir/.venv/bin/python"; fi
exec "$calendar_python" "$repo_dir/calendar_backend.py"
