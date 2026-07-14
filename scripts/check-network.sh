#!/usr/bin/env bash
set -uo pipefail

mode="environment"
proxy_url=""

usage() {
  printf '%s\n' +    'Usage: check-network.sh [--direct | --proxy URL]' +    '  no option     honor the current curl proxy environment' +    '  --direct      bypass all proxy environment variables' +    '  --proxy URL   force one HTTP/HTTPS proxy without printing credentials'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --direct)
      mode="direct"
      shift
      ;;
    --proxy)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }
      mode="proxy"
      proxy_url="$2"
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

if [ "$mode" = "proxy" ]; then
  case "$proxy_url" in
    http://*|https://*) ;;
    *)
      printf 'Proxy URL must begin with http:// or https://\n' >&2
      exit 2
      ;;
  esac
fi

probe() {
  label="$1"
  url="$2"
  expected="$3"
  format='%{http_code} %{time_connect} %{time_total} %{remote_ip}'

  case "$mode" in
    direct)
      result="$(curl --proxy '' --connect-timeout 6 --max-time 20 --silent --show-error --location --output /dev/null --write-out "$format" "$url" 2>&1)"
      status="$?"
      ;;
    proxy)
      result="$(curl --proxy "$proxy_url" --connect-timeout 6 --max-time 20 --silent --show-error --location --output /dev/null --write-out "$format" "$url" 2>&1)"
      status="$?"
      ;;
    *)
      result="$(curl --connect-timeout 6 --max-time 20 --silent --show-error --location --output /dev/null --write-out "$format" "$url" 2>&1)"
      status="$?"
      ;;
  esac

  if [ "$status" -ne 0 ]; then
    printf '%-18s FAIL curl=%s %s\n' "$label" "$status" "$result"
    return
  fi

  code="$(printf '%s' "$result" | cut -d ' ' -f1)"
  case ",$expected," in
    *,"$code",*)
      verdict="OK"
      ;;
    *)
      verdict="HTTP?"
      ;;
  esac
  printf '%-18s %-5s %s\n' "$label" "$verdict" "$result"
}

printf 'Mode: %s\n' "$mode"
printf '%-18s %-5s %s\n' 'Endpoint' 'State' 'HTTP  connect  total  remote-ip'
probe 'GitHub' 'https://github.com/' '200'
probe 'Docker Registry' 'https://registry-1.docker.io/v2/' '200,401'
probe 'Docker packages' 'https://download.docker.com/linux/ubuntu/' '200'
probe 'npm Registry' 'https://registry.npmjs.org/' '200'
probe 'Astral' 'https://astral.sh/' '200'

printf '\nDocker Registry 401 means the network path is healthy but authentication was not supplied.\n'
