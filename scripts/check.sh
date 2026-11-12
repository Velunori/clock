#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd -P)
core_dir="${VELUNORI_CORE_PATH:-$(dirname "$repo_dir")/core}"
layout="${VELUNORI_TEST_LAYOUT:-copy}"
starts="${VELUNORI_TEST_STARTS:-1}"
[[ "$starts" =~ ^[0-9]+$ ]] && (( starts >= 1 && starts <= 20 )) || { echo 'Test starts must be 1..20' >&2; exit 1; }
[[ "$layout" == copy || "$layout" == symlink ]] || { echo 'Unknown test layout' >&2; exit 1; }
[[ -f "$core_dir/kit/Theme.qml" ]] || { echo 'Velunori core 0.2 is required.' >&2; exit 1; }
python3 -m unittest discover -s "$repo_dir/tests" -p 'test_*.py'
node "$repo_dir/tests/calendar.test.mjs"
node "$repo_dir/tests/session-check.test.mjs"
runtime_dir=$(mktemp -d)
trap 'rm -rf "$runtime_dir"' EXIT
chmod 700 "$runtime_dir"
source_dir="$runtime_dir"
if [[ "$layout" == symlink ]]; then source_dir="$runtime_dir/checkouts"; fi
mkdir -p "$source_dir/velunori.clock" "$source_dir/velunori.core"
cp "$repo_dir/"*.qml "$repo_dir/"*.js "$repo_dir/qmldir" "$source_dir/velunori.clock/"
cp -r "$core_dir/kit" "$core_dir/design" "$core_dir/components" "$source_dir/velunori.core/"
if [[ "$layout" == symlink ]]; then
  mv "$source_dir/velunori.clock" "$source_dir/clock"
  mv "$source_dir/velunori.core" "$source_dir/core"
  ln -s core "$source_dir/velunori.core"
  ln -s "$source_dir/clock" "$runtime_dir/velunori.clock"
  ln -s "$source_dir/core" "$runtime_dir/velunori.core"
fi
mkdir -p "$runtime_dir/imports/qs"
shell_dir="${OMARCHY_PATH:-/usr/share/omarchy}/shell"
ln -s "$shell_dir/Commons" "$runtime_dir/imports/qs/Commons"
ln -s "$shell_dir/Ui" "$runtime_dir/imports/qs/Ui"
ln -s "$shell_dir/Commons" "$runtime_dir/Commons"
ln -s "$shell_dir/Ui" "$runtime_dir/Ui"
/usr/lib/qt6/bin/qmllint -I "$runtime_dir/imports" \
  --unqualified info --missing-property warning --incompatible-type info \
  "$runtime_dir/velunori.clock/Widget.qml" "$runtime_dir/velunori.clock/CalendarContent.qml" \
  "$runtime_dir/velunori.core/kit/"*.qml > "$runtime_dir/lint.log" 2>&1 || {
    cat "$runtime_dir/lint.log"; exit 1;
  }
cp "$repo_dir/tests/calendar.qml" "$runtime_dir/shell.qml"
for (( start=1; start<=starts; start++ )); do
env -u WAYLAND_DISPLAY -u DISPLAY XDG_RUNTIME_DIR="$runtime_dir" \
  QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic \
  QT_QUICK_CONTROLS_STYLE=Basic QT_QUICK_BACKEND=software \
  timeout 10s quickshell -p "$runtime_dir/shell.qml" --no-color > "$runtime_dir/ui.log" 2>&1 || {
    cat "$runtime_dir/ui.log"; exit 1;
  }
cat "$runtime_dir/ui.log"
rg -q 'CALENDAR_TEST_PASSED' "$runtime_dir/ui.log"
if rg -q 'CALENDAR_TEST_FAILED|Failed to load|ReferenceError|TypeError|Binding loop|Unable to assign|Ignoring unresolvable import.*velunori' "$runtime_dir/ui.log"; then exit 1; fi
done
echo "Clock checks passed ($layout installation layout; $starts cold starts; OmarchyLoadPatch enabled)."
