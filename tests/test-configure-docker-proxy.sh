#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/configure-docker-proxy.sh"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/docker-proxy-test.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

fake_bin="$test_dir/bin"
mkdir -p "$fake_bin"

cat > "$fake_bin/id" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-u" ]; then
  printf '0\n'
else
  /usr/bin/id "$@"
fi
EOF

cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '401'
EOF

cat > "$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$DOCKER_PROXY_TEST_LOG"
exit 0
EOF

cat > "$fake_bin/docker" <<'EOF'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >> "$DOCKER_PROXY_TEST_LOG"
case "${1:-}" in
  info)
    if [ -f "$DOCKER_PROXY_TEST_FILE" ]; then
      proxy="$(sed -n 's/^Environment="HTTP_PROXY=\(.*\)"$/\1/p' "$DOCKER_PROXY_TEST_FILE")"
      proxy="${proxy//%%/%}"
      printf '%s|%s\n' "$proxy" "$proxy"
    else
      printf '|\n'
    fi
    ;;
  image)
    case "${2:-}" in
      inspect) exit 1 ;;
      rm) exit 0 ;;
    esac
    ;;
  pull)
    [ "${FAKE_DOCKER_PULL_FAIL:-0}" -eq 0 ]
    ;;
  run)
    exit 0
    ;;
  version)
    printf 'Server=29.test\n'
    ;;
esac
EOF
chmod +x "$fake_bin"/*

export PATH="$fake_bin:$PATH"
export DOCKER_PROXY_TEST_LOG="$test_dir/commands.log"
export DOCKER_PROXY_TEST_FILE="$test_dir/http-proxy.conf"

bash "$script" \
  --proxy http://127.0.0.1:7000 \
  --file "$DOCKER_PROXY_TEST_FILE" \
  --test > "$test_dir/set.out"
grep -Fq 'Environment="HTTP_PROXY=http://127.0.0.1:7000"' "$DOCKER_PROXY_TEST_FILE" \
  || fail 'proxy drop-in was not rendered'
[ "$(stat -c '%a' "$DOCKER_PROXY_TEST_FILE")" = "644" ] \
  || fail 'proxy drop-in mode is not 644'
grep -Fq 'docker pull hello-world:latest' "$DOCKER_PROXY_TEST_LOG" \
  || fail 'daemon pull validation was not run'

bash "$script" --clear --file "$DOCKER_PROXY_TEST_FILE" > "$test_dir/clear.out"
[ ! -e "$DOCKER_PROXY_TEST_FILE" ] || fail 'clear mode left the proxy drop-in behind'

cat > "$DOCKER_PROXY_TEST_FILE" <<'EOF'
[Service]
Environment="HTTP_PROXY=http://old-proxy:9000"
Environment="HTTPS_PROXY=http://old-proxy:9000"
EOF
cp "$DOCKER_PROXY_TEST_FILE" "$test_dir/original.conf"

if FAKE_DOCKER_PULL_FAIL=1 bash "$script" \
    --proxy http://127.0.0.1:7001 \
    --file "$DOCKER_PROXY_TEST_FILE" \
    --test > "$test_dir/rollback.out" 2>&1; then
  fail 'failed daemon validation returned success'
fi
cmp -s "$DOCKER_PROXY_TEST_FILE" "$test_dir/original.conf" \
  || fail 'failed validation did not restore the original drop-in'

printf 'PASS: Docker proxy set, clear, test, and rollback paths are transactional\n'
