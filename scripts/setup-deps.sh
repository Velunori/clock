#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd -P)
python3 -m venv "$repo_dir/.venv"
"$repo_dir/.venv/bin/python" -m pip install --disable-pip-version-check --no-cache-dir -r "$repo_dir/requirements.txt"
echo 'Calendar dependencies installed in the private clock environment.'
