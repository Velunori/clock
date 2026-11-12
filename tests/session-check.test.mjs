import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

function runSessionCheck(crash) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'velunori-session-test-'));
    try {
        const bin = path.join(dir, 'bin');
        fs.mkdirSync(bin);
        const write = (name, source) => fs.writeFileSync(path.join(bin, name), '#!/bin/bash\nset -eu\n' + source, {mode: 0o755});
        write('pacman', 'echo "quickshell fixture"\n');
        write('omarchy', `
if [[ "\${SESSION_TEST_CRASH:-0}" == 1 ]]; then
  mkdir -p "$XDG_CACHE_HOME/quickshell/crashes/fixture"
  echo fixture > "$XDG_CACHE_HOME/quickshell/crashes/fixture/report.txt"
fi
`);
        write('omarchy-shell', `
case "$1:$2" in
  shell:ping) echo ok ;;
  velunori:status) echo '{"ready":true,"widgets":[{"id":"velunori.clock","visible":true,"width":150}]}' ;;
  shell:summon) echo open > "$SESSION_TEST_STATE"; echo ok ;;
  shell:hide) echo closed > "$SESSION_TEST_STATE" ;;
  velunori.clock:status)
    opened=false
    if [[ -f "$SESSION_TEST_STATE" && $(cat "$SESSION_TEST_STATE") == open ]]; then opened=true; fi
    printf '{"instances":[{"opened":%s}]}\n' "$opened" ;;
  *) exit 1 ;;
esac
`);
        return spawnSync('bash', [fileURLToPath(new URL('../scripts/check-session.sh', import.meta.url)), '--restart'], {
            encoding: 'utf8', timeout: 15000,
            env: {...process.env, PATH: bin + path.delimiter + process.env.PATH,
                XDG_CACHE_HOME: path.join(dir, 'cache'), SESSION_TEST_STATE: path.join(dir, 'state'),
                SESSION_TEST_CRASH: crash ? '1' : '0'}
        });
    } finally { fs.rmSync(dir, {recursive: true, force: true}); }
}

test('session checker verifies visible widget and calendar lifecycle', () => {
    const result = runSessionCheck(false);
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.match(result.stdout, /calendar opened/);
    assert.match(result.stdout, /calendar closed/);
});

test('successful restart with a crash report must fail the session check', () => {
    const result = runSessionCheck(true);
    assert.equal(result.status, 1, result.stdout + result.stderr);
    assert.match(result.stderr, /new Quickshell crash report/);
});
