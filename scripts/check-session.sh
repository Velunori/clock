#!/usr/bin/env bash
# Run in the desktop terminal. --restart explicitly requests one shell restart.
set -euo pipefail
[[ $# == 0 || ( $# == 1 && $1 == --restart ) ]] || { echo 'Usage: check-session.sh [--restart]' >&2; exit 1; }
check_dir=$(mktemp -d)
active_test_panel=""
cleanup() {
  omarchy-shell velunori hideSettings >/dev/null 2>&1 || true
  omarchy-shell shell hide velunori.clock >/dev/null 2>&1 || true
  if [[ -n "$active_test_panel" ]]; then omarchy-shell shell hide "$active_test_panel" >/dev/null 2>&1 || true; fi
  rm -rf "$check_dir"
}
trap cleanup EXIT
touch "$check_dir/start"
version=$(pacman -Q quickshell 2>/dev/null || true)
echo "$version"
if [[ "$version" == 'quickshell 0.3.2.r7.g2b4501a-1' ]]; then
  echo 'Known Omarchy scanner race is present in this package; a passing smoke test does not rule it out.'
  echo 'https://github.com/omacom/omarchy/issues/16167'
fi
if [[ ${1:-} == --restart ]]; then omarchy restart shell; fi

wait_json() {
  local target=$1 expression=$2 expected=${3:-} result attempt
  for attempt in {1..40}; do
    if result=$(omarchy-shell "$target" status 2>/dev/null) &&
      python3 -c "import json, sys; data=json.load(sys.stdin); expected=sys.argv[1]; sys.exit(0 if $expression else 1)" "$expected" <<< "$result" 2>/dev/null; then
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
wait_json velunori 'not any(w["id"] == "omarchy.indicators" for w in data["widgets"])'
echo 'PASS: legacy hover controls are absent from all bar surfaces.'
wait_json velunori 'not any(w["id"] in ("omarchy.monitor", "omarchy.power", "omarchy.audio") and w["visible"] for w in data["widgets"])'
echo 'PASS: hardware controls are hosted by Control Center instead of bar icons.'
omarchy-shell velunori settings
wait_json velunori 'data.get("controlCenterOpened")'
echo 'PASS: Control Center opened.'
omarchy-shell velunori hideSettings
wait_json velunori 'not data.get("controlCenterOpened")'
echo 'PASS: Control Center closed.'
panels=$(omarchy-shell velunori status | python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin).get("availableControlPanels", [])))')
while IFS= read -r panel; do
  [[ -n "$panel" ]] || continue
  active_test_panel="$panel"
  [[ $(omarchy-shell shell summon "$panel" '{}') == ok ]]
  wait_json velunori 'data.get("activePanel") == expected' "$panel"
  omarchy-shell shell hide "$panel"
  wait_json velunori 'data.get("activePanel") != expected' "$panel"
  active_test_panel=""
  echo "PASS: hosted $panel panel opened and closed."
done <<< "$panels"
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
