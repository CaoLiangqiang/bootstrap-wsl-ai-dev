#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/check-config-windows-paths.sh"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/config-path-test.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

safe_project="$test_dir/safe-project.toml"
cat > "$safe_project" <<'EOF'
[projects."/mnt/f/code/shared-project"]
trust_level = "trusted"

data_dir = "/mnt/c/shared-data"
EOF
bash "$script" "$safe_project" >/dev/null \
  || fail 'shared project and data paths were rejected'

unsafe_shim="$test_dir/unsafe-shim.json"
cat > "$unsafe_shim" <<'EOF'
{
  "command": "/mnt/c/Users/test/AppData/Roaming/npm/tool.cmd"
}
EOF
if bash "$script" "$unsafe_shim" >/dev/null; then
  fail 'Windows npm command shim was accepted'
fi

unsafe_command="$test_dir/unsafe-command.toml"
cat > "$unsafe_command" <<'EOF'
command = "/mnt/c/Tools/node"
EOF
if bash "$script" "$unsafe_command" >/dev/null; then
  fail 'Windows command setting was accepted'
fi

unsafe_drive="$test_dir/unsafe-drive.json"
cat > "$unsafe_drive" <<'EOF'
{
  "executable": "C:\\Program Files\\nodejs\\node.exe"
}
EOF
if bash "$script" "$unsafe_drive" >/dev/null; then
  fail 'Windows drive executable was accepted'
fi

unsafe_forward_drive="$test_dir/unsafe-forward-drive.toml"
cat > "$unsafe_forward_drive" <<'EOF'
binary = "C:/Tools/nodejs/node.exe"
EOF
if bash "$script" "$unsafe_forward_drive" >/dev/null; then
  fail 'forward-slash Windows drive executable was accepted'
fi

unsafe_cmd_key="$test_dir/unsafe-cmd-key.json"
cat > "$unsafe_cmd_key" <<'EOF'
{
  "cmd": "/mnt/c/Tools/node"
}
EOF
if bash "$script" "$unsafe_cmd_key" >/dev/null; then
  fail 'Windows path in a cmd setting was accepted'
fi

printf 'PASS: shared project paths are allowed and Windows commands are rejected\n'
