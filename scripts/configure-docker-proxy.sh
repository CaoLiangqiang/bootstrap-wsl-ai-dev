#!/usr/bin/env bash
set -Eeuo pipefail

mode=""
proxy_url=""
no_proxy_value="localhost,127.0.0.1,::1"
run_test=0
drop_in_file="/etc/systemd/system/docker.service.d/http-proxy.conf"
had_drop_in=0
changed=0
had_hello_image=0
proxy_backup=""
rendered_file=""

usage() {
  printf '%s\n' \
    'Usage:' \
    '  sudo bash configure-docker-proxy.sh --proxy URL [--no-proxy LIST] [--test]' \
    '  sudo bash configure-docker-proxy.sh --clear [--test]' \
    '' \
    'Configures or removes the rootful Docker daemon systemd proxy transactionally.' \
    'Validation failure restores the previous drop-in.' \
    '' \
    '  --proxy URL  set one HTTP/HTTPS proxy after a reachability preflight' \
    '  --clear      remove the fixed daemon proxy' \
    '  --no-proxy   set the exclusion list used with --proxy' \
    '  --test       pull and run hello-world, then remove it if it was not present' \
    '  --file PATH  operate on another drop-in path (useful for review and testing)'
}

select_mode() {
  requested="$1"
  if [ -n "$mode" ]; then
    printf 'Choose exactly one of --proxy or --clear.\n' >&2
    exit 2
  fi
  mode="$requested"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --proxy)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }
      select_mode "set"
      proxy_url="$2"
      shift 2
      ;;
    --clear)
      select_mode "clear"
      shift
      ;;
    --no-proxy)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }
      no_proxy_value="$2"
      shift 2
      ;;
    --test)
      run_test=1
      shift
      ;;
    --file)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }
      drop_in_file="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$mode" ]; then
  usage >&2
  exit 2
fi
if [ "$mode" = "clear" ] && [ "$no_proxy_value" != "localhost,127.0.0.1,::1" ]; then
  printf '%s\n' '--no-proxy is valid only with --proxy.' >&2
  exit 2
fi
if [ "$(id -u)" -ne 0 ]; then
  printf 'Run this script with sudo. Do not provide the sudo password to an agent.\n' >&2
  exit 1
fi
if ! systemctl cat docker.service >/dev/null 2>&1; then
  printf 'docker.service is not installed.\n' >&2
  exit 1
fi

if [ "$mode" = "set" ]; then
  case "$proxy_url" in
    http://*|https://*) ;;
    *)
      printf 'Proxy URL must begin with http:// or https://\n' >&2
      exit 2
      ;;
  esac
  if printf '%s' "$proxy_url$no_proxy_value" | grep -q '[[:space:]"]'; then
    printf 'Proxy values must not contain whitespace or double quotes.\n' >&2
    exit 2
  fi

  printf '[1/5] Verify Docker Registry through the requested proxy\n'
  if ! status="$(curl --proxy "$proxy_url" --connect-timeout 6 --max-time 20 \
      --silent --show-error --output /dev/null --write-out '%{http_code}' \
      https://registry-1.docker.io/v2/)"; then
    printf 'Proxy preflight failed; refusing to restart Docker.\n' >&2
    exit 1
  fi
  case "$status" in
    200|401) ;;
    *)
      printf 'Proxy preflight returned HTTP %s; refusing to restart Docker.\n' "$status" >&2
      exit 1
      ;;
  esac
else
  printf '[1/5] Prepare to remove the fixed Docker daemon proxy\n'
fi

drop_in_dir="$(dirname "$drop_in_file")"
proxy_backup="$(mktemp "${TMPDIR:-/tmp}/docker-http-proxy.XXXXXX")"
rendered_file="$(mktemp "${TMPDIR:-/tmp}/docker-http-proxy-rendered.XXXXXX")"

rollback() {
  status="$1"
  trap - ERR INT TERM

  if [ "$changed" -eq 1 ]; then
    printf '\nDocker proxy validation failed; restoring the previous drop-in.\n' >&2
    if [ "$had_drop_in" -eq 1 ]; then
      install -m 0755 -d "$drop_in_dir"
      cp --preserve=all "$proxy_backup" "$drop_in_file" || true
    else
      rm -f "$drop_in_file"
      rmdir "$drop_in_dir" 2>/dev/null || true
    fi
    systemctl daemon-reload || true
    systemctl restart docker || true
  fi

  if [ "$run_test" -eq 1 ] && [ "$had_hello_image" -eq 0 ]; then
    docker image rm hello-world:latest >/dev/null 2>&1 || true
  fi
  rm -f "$proxy_backup" "$rendered_file"
  exit "$status"
}

trap 'rollback $?' ERR
trap 'rollback 130' INT
trap 'rollback 143' TERM

if [ -e "$drop_in_file" ]; then
  cp --preserve=all "$drop_in_file" "$proxy_backup"
  had_drop_in=1
fi
if [ "$run_test" -eq 1 ] && docker image inspect hello-world:latest >/dev/null 2>&1; then
  had_hello_image=1
fi

printf '[2/5] Apply the requested Docker proxy state\n'
changed=1
if [ "$mode" = "set" ]; then
  escaped_proxy="$(printf '%s' "$proxy_url" | sed 's/%/%%/g')"
  escaped_no_proxy="$(printf '%s' "$no_proxy_value" | sed 's/%/%%/g')"
  printf '%s\n' \
    '[Service]' \
    "Environment=\"HTTP_PROXY=$escaped_proxy\"" \
    "Environment=\"HTTPS_PROXY=$escaped_proxy\"" \
    "Environment=\"NO_PROXY=$escaped_no_proxy\"" \
    > "$rendered_file"
  install -m 0755 -d "$drop_in_dir"
  install -m 0644 "$rendered_file" "$drop_in_file"
else
  rm -f "$drop_in_file"
  rmdir "$drop_in_dir" 2>/dev/null || true
fi

printf '[3/5] Reload systemd and restart Docker\n'
systemctl daemon-reload
systemctl restart docker
systemctl is-active --quiet docker

printf '[4/5] Verify the effective daemon proxy state\n'
effective_proxy="$(docker info --format '{{.HTTPProxy}}|{{.HTTPSProxy}}')"
if [ "$mode" = "set" ]; then
  if [ "$effective_proxy" != "$proxy_url|$proxy_url" ]; then
    printf 'Docker did not load the requested proxy from the drop-in.\n' >&2
    rollback 1
  fi
elif [ -n "${effective_proxy//|/}" ]; then
  printf 'Docker still reports a proxy from another configuration source.\n' >&2
  rollback 1
fi

printf '[5/5] Validate Docker daemon operation\n'
docker version --format 'Server={{.Server.Version}}'
if [ "$run_test" -eq 1 ]; then
  timeout 120 docker pull hello-world:latest
  timeout 60 docker run --rm hello-world:latest
  if [ "$had_hello_image" -eq 0 ]; then
    docker image rm hello-world:latest >/dev/null || true
  fi
fi

trap - ERR INT TERM
rm -f "$proxy_backup" "$rendered_file"

if [ "$mode" = "set" ]; then
  printf 'Docker daemon proxy configured in %s\n' "$drop_in_file"
  printf 'The proxy value is intentionally omitted from this output.\n'
else
  printf 'Docker daemon fixed proxy removed from %s\n' "$drop_in_file"
fi
