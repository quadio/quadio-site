#!/usr/bin/env bash
# First-time DigitalOcean droplet setup for quadio-site.
# Must run from a copy of deploy/digitalocean on the droplet (scp).
# Does not fetch the GitHub repo.
#
# Safe on a host that already runs other Caddy sites:
# it installs a www.quad.io virtual host and does not replace
# unrelated site blocks.
#
#   sudo SITE_ARCHIVE=/path/to/quadio-site.tar.gz ./bootstrap.sh
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "run as root" >&2
  exit 1
fi

DOMAIN="${SITE_DOMAIN:-}"
CADDY_EMAIL="${CADDY_EMAIL:-}"
ARCHIVE_PATH="${SITE_ARCHIVE:-}"
ENABLE_UFW="${SITE_ENABLE_UFW:-}"

SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [[ -z "$SCRIPT_DIR" ]]; then
  echo "bootstrap must be run from a file path (do not pipe from curl on a private repo)." >&2
  echo "From a machine that can see GitHub: ./deploy/digitalocean/push.sh --bootstrap root@HOST" >&2
  exit 1
fi

need() {
  local name="$1"
  if [[ ! -f "${SCRIPT_DIR}/${name}" ]]; then
    echo "missing ${SCRIPT_DIR}/${name}" >&2
    exit 1
  fi
}

need quadio-site.caddy
need configure-caddy.sh
need install.sh

ufw_active() {
  command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi '^Status: active'
}

allow_ufw() {
  ufw allow OpenSSH
  if [[ "${1:-}" == :* ]]; then
    ufw allow 8080/tcp
  else
    ufw allow 80/tcp
    ufw allow 443/tcp
  fi
}

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl tar ufw debian-keyring debian-archive-keyring apt-transport-https gpg

caddy_was_present=0
if command -v caddy >/dev/null 2>&1; then
  caddy_was_present=1
else
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  apt-get update
  apt-get install -y caddy
fi

if [[ -n "$CADDY_EMAIL" ]]; then
  printf 'CADDY_EMAIL=%s\n' "$CADDY_EMAIL" >/etc/caddy/caddy.env
  mkdir -p /etc/systemd/system/caddy.service.d
  cat >/etc/systemd/system/caddy.service.d/override.conf <<'EOF'
[Service]
EnvironmentFile=/etc/caddy/caddy.env
EOF
fi

export SITE_DOMAIN="$DOMAIN"
export CADDY_EMAIL
bash "${SCRIPT_DIR}/configure-caddy.sh"
# shellcheck disable=SC1091
source /etc/quadio-site/site.env
SITE_ADDRESS="${SITE_HEALTH_HOST:-:8080}"

if ufw_active; then
  allow_ufw "$SITE_ADDRESS"
elif [[ "$ENABLE_UFW" == "1" || "$ENABLE_UFW" == "true" ]]; then
  allow_ufw "$SITE_ADDRESS"
  ufw --force enable
elif [[ "$caddy_was_present" -eq 0 ]]; then
  allow_ufw "$SITE_ADDRESS"
  ufw --force enable
else
  echo "ufw is inactive and Caddy was already present; not enabling (set SITE_ENABLE_UFW=1 to turn it on)" >&2
fi

systemctl daemon-reload
systemctl enable --now caddy
systemctl reload caddy 2>/dev/null || systemctl restart caddy

if [[ "$SITE_ADDRESS" == :* ]]; then
  echo "quadio-site is reachable on ${SITE_ADDRESS}" >&2
fi

if [[ -z "$ARCHIVE_PATH" ]]; then
  echo "bootstrap finished without a site archive; copy a tarball and run:" >&2
  echo "  sudo SITE_ARCHIVE=/path/to/quadio-site.tar.gz ${SCRIPT_DIR}/install.sh" >&2
  exit 0
fi

SITE_ARCHIVE="$ARCHIVE_PATH" bash "${SCRIPT_DIR}/install.sh"

echo
echo "bootstrap complete."
if [[ -n "${SITE_HEALTH_HOST:-}" ]]; then
  echo "  local:  curl -s -H 'Host: ${SITE_HEALTH_HOST}' ${SITE_HEALTH_URL}"
  echo "  public: https://${SITE_HEALTH_HOST}/"
else
  echo "  local:  curl -s ${SITE_HEALTH_URL}"
fi
