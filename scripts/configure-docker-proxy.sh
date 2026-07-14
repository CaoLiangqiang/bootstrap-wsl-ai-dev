#!/usr/bin/env bash
set -Eeuo pipefail

proxy_url=""
no_proxy_value="localhost,127.0.0.1,::1"
run_test=0

usage() {
  printf '%s\n' +    'Usage: sudo bash configure-docker-proxy.sh --proxy URL [--no-proxy LIST] [--test]' +    'Creates a systemd drop-in for the rootful Docker daemon and restarts Docker.'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --proxy)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }
      proxy_url="$2"
      shift 2
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

if [ "$(id -u)" -ne 0 ]; then
  printf 'Run this script with sudo. Do not provide the sudo password to an agent.\n' >&2
  exit 1
fi

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

printf '[1/4] Verify Docker Registry through the proxy\n'
status="$(curl --proxy "$proxy_url" --connect-timeout 6 --max-time 20 --silent --show-error --output /dev/null --write-out '%{http_code}' https://registry-1.docker.io/v2/)"
case "$status" in
  200|401) ;;
  *)
    printf 'Proxy preflight returned HTTP %s; refusing to restart Docker.\n' "$status" >&2
    exit 1
    ;;
esac

escaped_proxy="$(printf '%s' "$proxy_url" | sed 's/%/%%/g')"
escaped_no_proxy="$(printf '%s' "$no_proxy_value" | sed 's/%/%%/g')"
drop_in_dir="/etc/systemd/system/docker.service.d"
drop_in_file="$drop_in_dir/http-proxy.conf"

printf '[2/4] Write the Docker systemd proxy drop-in\n'
install -m 0755 -d "$drop_in_dir"
printf '%s\n' +  '[Service]' +  "Environment=\"HTTP_PROXY=$escaped_proxy\"" +  "Environment=\"HTTPS_PROXY=$escaped_proxy\"" +  "Environment=\"NO_PROXY=$escaped_no_proxy\"" +  > "$drop_in_file"
chmod 0644 "$drop_in_file"

printf '[3/4] Reload systemd and restart Docker\n'
systemctl daemon-reload
systemctl restart docker
systemctl is-active --quiet docker

printf '[4/4] Verify daemon state\n'
docker version --format 'Server={{.Server.Version}}'
if [ "$run_test" -eq 1 ]; then
  docker run --rm hello-world
fi

printf 'Docker daemon proxy configured in %s\n' "$drop_in_file"
printf 'The proxy value is intentionally omitted from this output.\n'
