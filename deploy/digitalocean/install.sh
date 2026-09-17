#!/usr/bin/env bash
# Install a built public/ archive and reload Caddy.
# The droplet does not need GitHub access or rsites.
#
# Usage:
#   sudo SITE_ARCHIVE=/path/to/quadio-site.tar.gz ./install.sh
set -euo pipefail

SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [[ -z "${SITE_HEALTH_URL:-}" && -f /etc/quadio-site/site.env ]]; then
  # shellcheck disable=SC1091
  source /etc/quadio-site/site.env
fi

WEBROOT="${SITE_WEBROOT:-/var/www/quadio-site}"
HEALTH_URL="${SITE_HEALTH_URL:-http://127.0.0.1/}"
if [[ -n "${SITE_HEALTH_HOST:-}" ]]; then
  HEALTH_HOST="$SITE_HEALTH_HOST"
elif [[ "$HEALTH_URL" == *":8080"* ]]; then
  HEALTH_HOST=""
else
  HEALTH_HOST="www.quad.io"
fi
ARCHIVE_PATH="${SITE_ARCHIVE:-}"
SKIP_HEALTH="${SITE_SKIP_HEALTH:-}"

if [[ "$(id -u)" -ne 0 ]]; then
  parent="$(dirname "$WEBROOT")"
  if [[ ! -w "$parent" && ! -w "$WEBROOT" ]]; then
    exec sudo --preserve-env=SITE_WEBROOT,SITE_HEALTH_URL,SITE_HEALTH_HOST,SITE_ARCHIVE,SITE_SKIP_HEALTH,SITE_DOMAIN,SITE_CADDY_DIR,SITE_ENV_FILE,CADDY_EMAIL "$0" "$@"
  fi
fi

if [[ -z "$ARCHIVE_PATH" || ! -f "$ARCHIVE_PATH" ]]; then
  echo "set SITE_ARCHIVE to a tarball of public/ on this machine" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp "$ARCHIVE_PATH" "$TMP/site.tar.gz"
SUM="${ARCHIVE_PATH}.sha256"
if [[ -f "$SUM" ]]; then
  expected="$(awk '{print $1}' "$SUM")"
  actual="$(sha256sum "$TMP/site.tar.gz" | awk '{print $1}')"
  if [[ "$expected" != "$actual" ]]; then
    echo "checksum mismatch for ${ARCHIVE_PATH}" >&2
    exit 1
  fi
fi

STAGE="${WEBROOT}.next"
rm -rf "$STAGE"
mkdir -p "$STAGE"
tar -xzf "$TMP/site.tar.gz" -C "$STAGE"
if [[ ! -f "$STAGE/index.html" ]]; then
  echo "archive did not contain index.html" >&2
  exit 1
fi

mkdir -p "$(dirname "$WEBROOT")"
if [[ -d "$WEBROOT" ]]; then
  rm -rf "${WEBROOT}.prev"
  mv "$WEBROOT" "${WEBROOT}.prev"
fi
mv "$STAGE" "$WEBROOT"
chmod -R a+rX "$WEBROOT"
if id caddy >/dev/null 2>&1; then
  chown -R caddy:caddy "$WEBROOT"
fi

should_configure_caddy=0
if [[ -n "$SCRIPT_DIR" && -f "${SCRIPT_DIR}/configure-caddy.sh" ]]; then
  if [[ -n "${SITE_CADDY_DIR:-}" ]]; then
    should_configure_caddy=1
  elif [[ "$(id -u)" -eq 0 && -d /etc/caddy ]]; then
    should_configure_caddy=1
  fi
fi
if [[ "$should_configure_caddy" -eq 1 ]]; then
  bash "${SCRIPT_DIR}/configure-caddy.sh"
  site_env="${SITE_ENV_FILE:-/etc/quadio-site/site.env}"
  if [[ -f "$site_env" ]]; then
    # shellcheck disable=SC1090
    source "$site_env"
    HEALTH_URL="${SITE_HEALTH_URL:-$HEALTH_URL}"
    if [[ -n "${SITE_HEALTH_HOST:-}" ]]; then
      HEALTH_HOST="$SITE_HEALTH_HOST"
    elif [[ "$HEALTH_URL" == *":8080"* ]]; then
      HEALTH_HOST=""
    fi
  fi
fi

if command -v systemctl >/dev/null && systemctl cat caddy.service >/dev/null 2>&1; then
  systemctl reload caddy.service 2>/dev/null || systemctl restart caddy.service
fi

echo "quadio-site installed at ${WEBROOT}"

if [[ -n "$SKIP_HEALTH" ]]; then
  exit 0
fi

if command -v systemctl >/dev/null && systemctl is-active --quiet caddy.service 2>/dev/null; then
  curl_args=(-fsS)
  if [[ -n "$HEALTH_HOST" ]]; then
    curl_args+=(-H "Host: ${HEALTH_HOST}")
  fi
  for _ in $(seq 1 20); do
    if curl "${curl_args[@]}" "$HEALTH_URL" >/dev/null 2>&1; then
      echo "site is healthy at ${HEALTH_URL}"
      exit 0
    fi
    sleep 1
  done
  echo "site installed but ${HEALTH_URL} did not become ready" >&2
  systemctl status caddy.service --no-pager >&2 || true
  exit 1
fi

echo "site installed; run bootstrap.sh to install Caddy if this is a new host"
