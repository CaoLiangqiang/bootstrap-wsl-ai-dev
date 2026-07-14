#!/usr/bin/env bash
set -Eeuo pipefail

target_user=""

usage() {
  printf '%s\n' +    'Usage: sudo bash install-docker-engine.sh [--user USER]' +    'Installs Docker Engine from the official Docker Ubuntu repository.' +    'The script refuses to remove conflicting packages automatically.'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --user)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }
      target_user="$2"
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

if [ "$(id -u)" -ne 0 ]; then
  printf 'Run this script with sudo. Do not provide the sudo password to an agent.\n' >&2
  exit 1
fi

if [ -z "$target_user" ]; then
  target_user="${SUDO_USER:-}"
fi
if [ -z "$target_user" ] || [ "$target_user" = "root" ]; then
  printf 'Unable to identify the non-root target user; pass --user USER.\n' >&2
  exit 1
fi
if ! id "$target_user" >/dev/null 2>&1; then
  printf 'Target user does not exist: %s\n' "$target_user" >&2
  exit 1
fi

. /etc/os-release
if [ "${ID:-}" != "ubuntu" ]; then
  printf 'This installer supports Ubuntu only; detected: %s\n' "${ID:-unknown}" >&2
  exit 1
fi
codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
if [ -z "$codename" ]; then
  printf 'Unable to determine the Ubuntu codename.\n' >&2
  exit 1
fi

conflicts=""
for package in docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc; do
  if dpkg -s "$package" >/dev/null 2>&1; then
    conflicts="$conflicts $package"
  fi
done
if [ -n "$conflicts" ]; then
  printf 'Conflicting packages are installed:%s\n' "$conflicts" >&2
  printf 'Review their data and remove them explicitly before rerunning this script.\n' >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

printf '[1/5] Install repository prerequisites\n'
apt-get update
apt-get install -y ca-certificates curl

printf '[2/5] Configure the official Docker repository\n'
install -m 0755 -d /etc/apt/keyrings
curl --fail --silent --show-error --location --retry 3 +  https://download.docker.com/linux/ubuntu/gpg +  --output /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

architecture="$(dpkg --print-architecture)"
printf '%s\n' +  'Types: deb' +  'URIs: https://download.docker.com/linux/ubuntu' +  "Suites: $codename" +  'Components: stable' +  "Architectures: $architecture" +  'Signed-By: /etc/apt/keyrings/docker.asc' +  > /etc/apt/sources.list.d/docker.sources

printf '[3/5] Install Docker Engine, Buildx, and Compose\n'
apt-get update
apt-get install -y +  docker-ce +  docker-ce-cli +  containerd.io +  docker-buildx-plugin +  docker-compose-plugin

printf '[4/5] Enable and start Docker\n'
systemctl enable --now docker

printf '[5/5] Add %s to the docker group\n' "$target_user"
usermod -aG docker "$target_user"

docker --version
docker compose version
systemctl is-active --quiet docker
printf 'Docker is active. Open a new WSL login shell before testing non-root access.\n'
