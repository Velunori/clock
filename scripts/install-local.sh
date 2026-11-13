#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd -P)
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy"
plugin_dir="$config_dir/plugins/velunori.clock"
core_dir="$config_dir/plugins/velunori.core"
for executable in omarchy omarchy-shell python3; do
  command -v "$executable" >/dev/null || { echo "Missing: $executable" >&2; exit 1; }
done
python3 - "$core_dir" <<'PY'
import json, pathlib, sys
core = pathlib.Path(sys.argv[1])
try:
    manifest = json.loads((core / 'manifest.json').read_text())
    version = tuple(int(p) for p in manifest['version'].split('.'))
    assert manifest['id'] == 'velunori.core' and version >= (0, 4, 1)
    assert (core / 'kit' / 'Panel.qml').is_file()
except (OSError, ValueError, KeyError, AssertionError):
    sys.exit('Install Velunori core 0.4.1 or later before installing the clock.')
PY
bash "$core_dir/scripts/prepare-dev-layout.sh"
if [[ -e "$plugin_dir" || -L "$plugin_dir" ]]; then
  [[ -L "$plugin_dir" && $(readlink -f "$plugin_dir") == "$repo_dir" ]] || {
    echo "Refusing to overwrite $plugin_dir" >&2; exit 1;
  }
fi
[[ $(omarchy-shell shell ping) == ok ]] || { echo 'Omarchy shell is not running.' >&2; exit 1; }
[[ -f "$config_dir/shell.json" ]] || { echo 'Missing shell.json; configure core first.' >&2; exit 1; }
backup=$(mktemp "$config_dir/shell.json.before-velunori-clock.XXXXXXXX")
cp -p "$config_dir/shell.json" "$backup"
echo "Configuration backup: $backup"
read -r section index old_clock < <(python3 - "$config_dir/shell.json" <<'PY'
import json, sys
layout = json.load(open(sys.argv[1])).get('bar', {}).get('layout', {})
for wanted in ('velunori.clock', 'omarchy.clock'):
    for section in ('left', 'center', 'right'):
        for index, entry in enumerate(layout.get(section, [])):
            if isinstance(entry, dict) and entry.get('id') == wanted:
                print(section, index, int(wanted == 'omarchy.clock'))
                sys.exit()
print('center 0 0')
PY
)
[[ -L "$plugin_dir" ]] || ln -s "$repo_dir" "$plugin_dir"
omarchy-shell shell rescanPlugins
discovered=false
for attempt in {1..25}; do
  if omarchy-shell shell listPlugins | python3 -c '
import json, sys
sys.exit(0 if any(p.get("id") == "velunori.clock" for p in json.load(sys.stdin)) else 1)
'; then discovered=true; break; fi
  sleep 0.2
done
[[ "$discovered" == true ]] || { echo 'Clock discovery failed; original clock remains enabled.' >&2; exit 1; }
omarchy plugin enable velunori.clock --section "$section" --index "$index"
if [[ "$old_clock" == 1 ]]; then omarchy plugin disable omarchy.clock; fi
echo 'Velunori Clock enabled. Restart once to load the updated core API:'
echo '  omarchy restart shell'
