#!/usr/bin/env bash
# First-time Ubuntu server setup for quadio-site.
# Must run from a copy of deploy/ubuntu on the server (scp from push.sh).
# Does not fetch the GitHub repo.
#
# This host may already run Burton, docs, or Rabun behind Caddy. Bootstrap
# does not replace a Caddyfile that already has other sites. It does not
# enable ufw unless it is already active or SITE_ENABLE_UFW=1. --domain must
# be a unique Caddy virtual host; a collision is refused instead of restarting
# Caddy.
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
TLS_MODE="${SITE_TLS:-}"
if [[ -n "$TLS_MODE" ]]; then
  TLS_MODE="${TLS_MODE,,}"
  if [[ "$TLS_MODE" != "lan" && "$TLS_MODE" != "internal" ]]; then
    echo "SITE_TLS must be lan (Caddy local CA on a private network)" >&2
    exit 1
  fi
fi

SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [[ -z "$SCRIPT_DIR" ]]; then
  echo "bootstrap must be run from a file path (do not pipe from curl on a private repo)." >&2
  echo "From a machine that can see GitHub: ./deploy/ubuntu/push.sh --bootstrap user@HOST" >&2
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

. /etc/os-release
if [[ "${ID:-}" != ubuntu ]]; then
  echo "this bootstrap targets Ubuntu Server (got ${ID:-unknown})" >&2
  exit 1
fi

ufw_active() {
  command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi '^Status: active'
}

allow_ssh_ufw() {
  if ufw allow OpenSSH 2>/dev/null; then
    return 0
  fi
  ufw allow 22/tcp
}

allow_ufw() {
  allow_ssh_ufw
  if [[ -n "$DOMAIN" && "$DOMAIN" != :* ]]; then
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 443/udp
  else
    ufw allow 8080/tcp
  fi
}

publish_lan_ca() {
  install -d -m 0755 /etc/quadio-site/tls
  local src i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    for src in \
      /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt \
      /var/lib/caddy/pki/authorities/local/root.crt
    do
      if [[ -f "$src" ]]; then
        install -m 0644 -o root -g caddy "$src" /etc/quadio-site/tls/lan-root.crt
        echo "LAN CA: /etc/quadio-site/tls/lan-root.crt (trust this on each device, then open https://${DOMAIN}/)"
        return 0
      fi
    done
    sleep 0.5
  done
  echo "LAN TLS is on; Caddy's local CA was not written yet. After Caddy serves once, copy pki/authorities/local/root.crt from /var/lib/caddy." >&2
}

# Reload a running Caddy. Never restart on a failed reload: restart loads
# the new config from disk and can take down every other virtual host.
apply_caddy() {
  local caddyfile="${SITE_CADDY_DIR:-/etc/caddy}/Caddyfile"
  if command -v caddy >/dev/null 2>&1; then
    if ! caddy validate --config "$caddyfile" >/dev/null 2>&1; then
      echo "Caddyfile is invalid; not changing a running Caddy" >&2
      caddy validate --config "$caddyfile" >&2 || true
      return 1
    fi
  fi
  systemctl daemon-reload
  if systemctl is-active --quiet caddy; then
    systemctl reload caddy
  else
    systemctl enable --now caddy
  fi
}

start_caddy_if_valid() {
  local caddyfile="${SITE_CADDY_DIR:-/etc/caddy}/Caddyfile"
  command -v systemctl >/dev/null 2>&1 || return 0
  systemctl cat caddy.service >/dev/null 2>&1 || return 0
  systemctl is-active --quiet caddy && return 0
  if command -v caddy >/dev/null 2>&1 && caddy validate --config "$caddyfile" >/dev/null 2>&1; then
    echo "starting Caddy with the remaining sites" >&2
    systemctl start caddy || true
  fi
}

export DEBIAN_FRONTEND=noninteractive
apt-get update || echo "warning: apt-get update failed (often a third-party repo such as Caddy); continuing from existing package lists" >&2
apt-get install -y --no-install-recommends ca-certificates curl tar ufw debian-keyring debian-archive-keyring apt-transport-https gpg

configure_caddy() {
  if ! command -v caddy >/dev/null 2>&1; then
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
      | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
      | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
    apt-get update
    apt-get install -y caddy
  fi

  if [[ -n "$CADDY_EMAIL" ]]; then
    printf 'CADDY_EMAIL=%s\n' "$CADDY_EMAIL" >/etc/caddy/caddy.env
    chmod 0640 /etc/caddy/caddy.env
    mkdir -p /etc/systemd/system/caddy.service.d
    cat >/etc/systemd/system/caddy.service.d/override.conf <<'EOF'
[Service]
EnvironmentFile=/etc/caddy/caddy.env
EOF
  fi

  export SITE_DOMAIN="$DOMAIN"
  export SITE_TLS="$TLS_MODE"
  export CADDY_EMAIL
  if ! bash "${SCRIPT_DIR}/configure-caddy.sh"; then
    start_caddy_if_valid
    exit 1
  fi
  apply_caddy
  if [[ "${TLS_MODE}" == "lan" || "${TLS_MODE}" == "internal" ]]; then
    publish_lan_ca
  fi
}

if [[ -n "$DOMAIN" ]]; then
  configure_caddy
else
  DOMAIN=":8080"
  echo "no SITE_DOMAIN set; serving on :8080" >&2
  configure_caddy
fi

# shellcheck disable=SC1091
source /etc/quadio-site/site.env

if ufw_active; then
  allow_ufw
elif [[ "$ENABLE_UFW" == "1" || "$ENABLE_UFW" == "true" ]]; then
  allow_ufw
  ufw --force enable
else
  echo "ufw is inactive; not enabling (set SITE_ENABLE_UFW=1 on a fresh box if you want bootstrap to turn it on)" >&2
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
  if [[ "${TLS_MODE}" == "lan" || "${TLS_MODE}" == "internal" ]]; then
    echo "  LAN CA: /etc/quadio-site/tls/lan-root.crt (trust on each device)"
    echo "  Caddy stores the local CA under /var/lib/caddy; do not wipe that directory."
  fi
else
  echo "  local:  curl -s ${SITE_HEALTH_URL}"
fi
