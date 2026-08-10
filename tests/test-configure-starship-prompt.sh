#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_wrapper="$repo_root/scripts/configure-starship-prompt.sh"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-starship-prompt-test.XXXXXX")"
cleanup() { rm -rf "$test_dir"; }
trap cleanup EXIT

wrapper="$test_dir/bootstrap-wsl-ai-dev/scripts/configure-starship-prompt.sh"
mkdir -p "$(dirname "$wrapper")"
cp "$source_wrapper" "$wrapper"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
expect_failure() { if "$@" >/dev/null 2>&1; then fail "expected failure: $*"; fi; }

skill_dir="$test_dir/setup-starship-catppuccin"
mkdir -p "$skill_dir/scripts" "$skill_dir/assets/starship" "$skill_dir/assets/fonts"
printf '%s\n' 'theme' > "$skill_dir/assets/starship/catppuccin-powerline.toml"
printf '%s\n' 'license' > "$skill_dir/assets/fonts/OFL.txt"
cat > "$skill_dir/scripts/configure-starship.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$DELEGATE_OUTPUT"
EOF
chmod 0755 "$skill_dir/scripts/configure-starship.sh"

bash "$wrapper" --help | grep -F -- '--skill-dir' >/dev/null
expect_failure bash "$wrapper" --skill-dir
expect_failure bash "$wrapper" --skill-dir '' --check
expect_failure env HOME="$test_dir/missing-home" bash "$wrapper" --check
DELEGATE_OUTPUT="$test_dir/explicit.txt" bash "$wrapper" --skill-dir "$skill_dir" --install --with-windows
grep -Fx -- '--install' "$test_dir/explicit.txt" >/dev/null || fail 'install action was not forwarded'
grep -Fx -- '--with-windows' "$test_dir/explicit.txt" >/dev/null || fail 'Windows option was not forwarded'

DELEGATE_OUTPUT="$test_dir/env.txt" SETUP_STARSHIP_CATPPUCCIN_DIR="$skill_dir" bash "$wrapper" --check
grep -Fx -- '--check' "$test_dir/env.txt" >/dev/null || fail 'environment-selected skill was not invoked'

agent_home="$test_dir/agent-home"
mkdir -p "$agent_home/.agents/skills"
ln -s "$skill_dir" "$agent_home/.agents/skills/setup-starship-catppuccin"
DELEGATE_OUTPUT="$test_dir/agent-home.txt" HOME="$agent_home" CODEX_HOME="$test_dir/missing-codex" \
  SETUP_STARSHIP_CATPPUCCIN_DIR='' bash "$wrapper" --check
grep -Fx -- '--check' "$test_dir/agent-home.txt" >/dev/null \
  || fail 'standard global Agent Skill installation was not invoked'

rm "$skill_dir/assets/fonts/OFL.txt"
expect_failure env DELEGATE_OUTPUT="$test_dir/incomplete.txt" bash "$wrapper" --skill-dir "$skill_dir" --check

printf 'PASS: bootstrap Starship adapter discovers, validates, and delegates to the standalone skill\n'
