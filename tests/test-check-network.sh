#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/check-network.sh"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-check-test.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

cat > "$test_dir/curl" <<'EOF'
#!/usr/bin/env bash
case "${FAKE_CURL_MODE:-ok}" in
  ok)
    printf '200 0.001000 0.002000 127.0.0.1'
    ;;
  http)
    printf '503 0.001000 0.002000 127.0.0.1'
    ;;
  sandbox)
    printf 'curl: (7) failed to open socket: Operation not permitted' >&2
    exit 7
    ;;
  *)
    printf 'curl: (28) Connection timed out' >&2
    exit 28
    ;;
esac
EOF
chmod +x "$test_dir/curl"

PATH="$test_dir:$PATH" FAKE_CURL_MODE=ok \
  bash "$script" --direct > "$test_dir/ok.out"
grep -Fq 'Result: 0 failed endpoint(s)' "$test_dir/ok.out" \
  || fail 'healthy probes did not report zero failures'

if PATH="$test_dir:$PATH" FAKE_CURL_MODE=http \
    bash "$script" --direct > "$test_dir/http.out"; then
  fail 'unexpected HTTP responses returned success'
fi
grep -Fq 'Result: 5 failed endpoint(s)' "$test_dir/http.out" \
  || fail 'unexpected HTTP responses were not counted'

if PATH="$test_dir:$PATH" FAKE_CURL_MODE=sandbox \
    bash "$script" --direct > "$test_dir/sandbox.out" 2>&1; then
  fail 'sandbox-blocked probes returned success'
fi
grep -Fq 'Sandbox-like socket restrictions blocked 5 probe(s)' "$test_dir/sandbox.out" \
  || fail 'sandbox restriction hint was not emitted'

printf 'PASS: network checks return meaningful status and identify sandbox blocking\n'
