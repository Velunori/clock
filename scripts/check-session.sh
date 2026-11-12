#!/usr/bin/env bash
# Run in the desktop terminal. --restart explicitly requests one shell restart.
set -euo pipefail
[[ $# == 0 || ( $# == 1 && $1 == --restart ) ]] || { echo 'Usage: check-session.sh [--restart]' >&2; exit 1; }
check_dir=$(mktemp -d)
trap 'omarchy-shell shell hide velunori.clock >/dev/null 2>&1 || true; rm -rf "$check_dir"' EXIT
touch "$check_dir/start"
version=$(pacman -Q quickshell 2>/dev/null || true)
echo "$version"
if [[ "$version" == 'quickshell 0.3.2.r7.g2b4501a-1' ]]; then
  echo 'Known Omarchy scanner race is present in this package; a passing smoke test does not rule it out.'
  echo 'https://github.com/omacom/omarchy/issues/16167'
fi
if [[ ${1:-} == --restart ]]; then omarchy restart shell; fi

wait_json() {
  local target=$1 expression=$2 result attempt
  for attempt in {1..40}; do
    if result=$(omarchy-shell "$target" status 2>/dev/null) &&
      python3 -c "import json, sys; data=json.load(sys.stdin); sys.exit(0 if $expression else 1)" <<< "$result" 2>/dev/null; then
      return 0
    fi
    sleep 0.25
  done
  echo "Timed out waiting for $target: $expression" >&2
  return 1
}

[[ $(omarchy-shell shell ping) == ok ]]
wait_json velunori 'data.get("ready") and any(w["id"] == "velunori.clock" and w["visible"] and w["width"] > 0 for w in data["widgets"])'
echo 'PASS: clock is loaded and has visible bar geometry.'
[[ $(omarchy-shell shell summon velunori.clock '{}') == ok ]]
wait_json velunori.clock 'any(w["opened"] for w in data["instances"])'
echo 'PASS: calendar opened through the host.'
omarchy-shell shell hide velunori.clock
wait_json velunori.clock 'data["instances"] and not any(w["opened"] for w in data["instances"])'
echo 'PASS: calendar closed through the host.'

crash_dir="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/crashes"
if [[ -d "$crash_dir" ]] && find "$crash_dir" -type f -name report.txt -newer "$check_dir/start" -print -quit | rg -q .; then
  echo 'FAIL: a new Quickshell crash report appeared, even if the shell recovered.' >&2
  find "$crash_dir" -type f -name report.txt -newer "$check_dir/start" -print >&2
  exit 1
fi
echo 'Session smoke test passed. This does not certify the host race as fixed.'
