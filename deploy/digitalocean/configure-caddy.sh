#!/usr/bin/env bash
# Install the quadio-site virtual host into Caddy without replacing other sites.
# Safe on a droplet that already serves Burton, docs, or other Caddy hosts.
#
#   sudo ./configure-caddy.sh
#
# Env:
#   SITE_DOMAIN       hostname (default www.quad.io, or last value in site.env)
#   SITE_CADDY_DIR    Caddy config dir (default /etc/caddy)
#   SITE_WEBROOT      published tree (default /var/www/quadio-site)
#   SITE_ENV_FILE     health-check env file (default /etc/quadio-site/site.env)
#   CADDY_EMAIL       optional ACME contact; written only when this script creates Caddyfile
set -euo pipefail

SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [[ -z "$SCRIPT_DIR" || ! -f "${SCRIPT_DIR}/quadio-site.caddy" ]]; then
  echo "configure-caddy.sh must sit next to quadio-site.caddy" >&2
  exit 1
fi

CADDY_DIR="${SITE_CADDY_DIR:-/etc/caddy}"
WEBROOT="${SITE_WEBROOT:-/var/www/quadio-site}"
SITE_ENV="${SITE_ENV_FILE:-/etc/quadio-site/site.env}"
SNIPPET="${CADDY_DIR}/sites-enabled/quadio-site.caddy"
CADDYFILE="${CADDY_DIR}/Caddyfile"
IMPORT_LINE="import ${CADDY_DIR}/sites-enabled/*"

load_site_env() {
  if [[ -f "$SITE_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$SITE_ENV"
  fi
}

resolve_domain() {
  if [[ -n "${SITE_DOMAIN:-}" ]]; then
    printf '%s' "$SITE_DOMAIN"
    return
  fi
  load_site_env
  if [[ -n "${SITE_HEALTH_HOST:-}" ]]; then
    printf '%s' "$SITE_HEALTH_HOST"
    return
  fi
  if [[ "${SITE_HEALTH_URL:-}" == *":8080"* ]]; then
    printf '%s' ":8080"
    return
  fi
  printf '%s' "www.quad.io"
}

apex_for() {
  local domain="$1"
  if [[ "$domain" == www.* ]]; then
    printf '%s' "${domain#www.}"
  fi
}

caddyfile_is_replaceable() {
  local f="$1"
  if [[ ! -s "$f" ]]; then
    return 0
  fi
  if grep -qF "$IMPORT_LINE" "$f"; then
    return 1
  fi
  if grep -qF 'root * /usr/share/caddy' "$f"; then
    return 0
  fi
  return 1
}

write_snippet() {
  local domain="$1"
  local apex
  apex="$(apex_for "$domain")"
  install -d -m 0755 "${CADDY_DIR}/sites-enabled"
  if [[ "$domain" == :* ]]; then
    cat >"$SNIPPET" <<EOF
${domain} {
	root * ${WEBROOT}
	encode gzip zstd
	try_files {path} {path}/ /404.html
	file_server
}
EOF
  elif [[ -n "$apex" ]]; then
    sed -e "s#placeholder\\.example\\.com#${domain}#g" \
      -e "s#apex\\.example\\.com#${apex}#g" \
      "${SCRIPT_DIR}/quadio-site.caddy" >"$SNIPPET"
  else
    sed -e "s#placeholder\\.example\\.com#${domain}#g" \
      -e '/^apex.example.com {/,/^}$/d' \
      "${SCRIPT_DIR}/quadio-site.caddy" >"$SNIPPET"
  fi
  chmod 0644 "$SNIPPET"
}

write_site_env() {
  local domain="$1"
  install -d -m 0755 "$(dirname "$SITE_ENV")"
  if [[ "$domain" == :* ]]; then
    printf 'SITE_HEALTH_URL=http://127.0.0.1%s/\n' "$domain" >"$SITE_ENV"
  else
    printf 'SITE_HEALTH_URL=http://127.0.0.1/\nSITE_HEALTH_HOST=%s\n' "$domain" >"$SITE_ENV"
  fi
  chmod 0644 "$SITE_ENV"
}

ensure_caddyfile_import() {
  if [[ -f "$CADDYFILE" ]] && grep -qF "$IMPORT_LINE" "$CADDYFILE"; then
    return
  fi
  if caddyfile_is_replaceable "$CADDYFILE"; then
    if [[ -s "$CADDYFILE" ]]; then
      cp "$CADDYFILE" "${CADDYFILE}.bak-quadio-site"
    fi
    {
      if [[ -n "${CADDY_EMAIL:-}" ]]; then
        printf '{\n\temail %s\n}\n' "$CADDY_EMAIL"
      fi
      printf '%s\n' "$IMPORT_LINE"
    } >"$CADDYFILE"
  else
    printf '\n%s\n' "$IMPORT_LINE" >>"$CADDYFILE"
  fi
  chmod 0644 "$CADDYFILE"
}

DOMAIN="$(resolve_domain)"
if id caddy >/dev/null 2>&1; then
  install -d -m 0755 -o caddy -g caddy "$WEBROOT"
else
  install -d -m 0755 "$WEBROOT"
fi
write_snippet "$DOMAIN"
ensure_caddyfile_import
write_site_env "$DOMAIN"

echo "Caddy virtual host ${DOMAIN} → ${WEBROOT} (${SNIPPET})"
