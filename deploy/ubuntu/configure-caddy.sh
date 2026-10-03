#!/usr/bin/env bash
# Install the quadio-site virtual host into Caddy without replacing other sites.
# Safe on a host that already serves Burton, docs, or Rabun from sibling snippets.
#
#   sudo ./configure-caddy.sh
#
# Env:
#   SITE_DOMAIN       hostname (required unless persisted in site.env; :port skips TLS)
#   SITE_TLS          lan|internal uses Caddy's local CA (private LAN)
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

tls_is_lan() {
  local mode="${SITE_TLS:-}"
  [[ "${mode,,}" == "lan" || "${mode,,}" == "internal" ]]
}

resolve_persisted() {
  local explicit_domain="${SITE_DOMAIN:-}"
  local explicit_tls="${SITE_TLS:-}"
  load_site_env
  if [[ -n "$explicit_domain" ]]; then
    SITE_DOMAIN="$explicit_domain"
  fi
  if [[ -n "$explicit_tls" ]]; then
    SITE_TLS="$explicit_tls"
  fi
}

resolve_domain() {
  if [[ -n "${SITE_DOMAIN:-}" ]]; then
    printf '%s' "$SITE_DOMAIN"
    return
  fi
  if [[ -n "${SITE_HEALTH_HOST:-}" ]]; then
    printf '%s' "$SITE_HEALTH_HOST"
    return
  fi
  if [[ "${SITE_HEALTH_URL:-}" == *":8080"* ]]; then
    printf '%s' ":8080"
    return
  fi
  echo "set SITE_DOMAIN to a hostname that is not already a Caddy site (or :8080)" >&2
  exit 1
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

snippet_claims_domain() {
  local file="$1"
  local domain="$2"
  awk -v d="$domain" '
    /^[[:space:]]*#/ { next }
    /\{/ {
      line = $0
      sub(/[[:space:]]*\{.*/, "", line)
      n = split(line, a, ",")
      for (i = 1; i <= n; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[i])
        if (a[i] == d) { found = 1; exit }
      }
    }
    END { exit found ? 0 : 1 }
  ' "$file"
}

colliding_snippet() {
  local domain="$1"
  local f
  shopt -s nullglob
  for f in "${CADDY_DIR}/sites-enabled/"*; do
    [[ -f "$f" ]] || continue
    [[ "$f" == "$SNIPPET" ]] && continue
    if snippet_claims_domain "$f" "$domain"; then
      printf '%s' "$f"
      return 0
    fi
  done
  return 1
}

inject_tls() {
  local src="$1"
  local dest="$2"
  if tls_is_lan; then
    awk '
      /tls / { has_tls = 1 }
      $0 ~ /^}/ && !inserted && !has_tls {
        print "\ttls internal"
        inserted = 1
      }
      { print }
    ' "$src" >"$dest"
    return
  fi
  cat "$src" >"$dest"
}

write_snippet() {
  local domain="$1"
  local apex tmp rendered
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
    chmod 0644 "$SNIPPET"
    return
  fi
  if tls_is_lan; then
    apex=""
  else
    apex="$(apex_for "$domain")"
  fi
  rendered="$(mktemp)"
  tmp="$(mktemp)"
  if [[ -n "$apex" ]]; then
    sed -e "s#placeholder\\.example\\.com#${domain}#g" \
      -e "s#apex\\.example\\.com#${apex}#g" \
      "${SCRIPT_DIR}/quadio-site.caddy" >"$rendered"
  else
    sed -e "s#placeholder\\.example\\.com#${domain}#g" \
      -e '/^apex.example.com {/,/^}$/d' \
      "${SCRIPT_DIR}/quadio-site.caddy" >"$rendered"
  fi
  inject_tls "$rendered" "$tmp"
  mv "$tmp" "$SNIPPET"
  rm -f "$rendered"
  chmod 0644 "$SNIPPET"
}

write_site_env() {
  local domain="$1"
  install -d -m 0755 "$(dirname "$SITE_ENV")"
  {
    if [[ "$domain" == :* ]]; then
      printf 'SITE_HEALTH_URL=http://127.0.0.1%s/\n' "$domain"
    else
      printf 'SITE_HEALTH_URL=http://127.0.0.1/\nSITE_HEALTH_HOST=%s\n' "$domain"
    fi
    printf 'SITE_DOMAIN=%s\n' "$domain"
    if [[ -n "${SITE_TLS:-}" ]]; then
      printf 'SITE_TLS=%s\n' "$SITE_TLS"
    fi
  } >"$SITE_ENV"
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
      echo "{"
      if [[ -n "${CADDY_EMAIL:-}" ]]; then
        printf '\temail %s\n' "$CADDY_EMAIL"
      fi
      printf '\tkey_type p256\n'
      echo "}"
      echo
      printf '%s\n' "$IMPORT_LINE"
    } >"$CADDYFILE"
  else
    printf '\n%s\n' "$IMPORT_LINE" >>"$CADDYFILE"
  fi
  chmod 0644 "$CADDYFILE"
}

resolve_persisted
DOMAIN="$(resolve_domain)"
if other="$(colliding_snippet "$DOMAIN")"; then
  echo "Caddy already serves ${DOMAIN} from ${other}." >&2
  echo "Pass a unique --domain so quadio-site can share this Caddy (for example www.${DOMAIN})." >&2
  exit 1
fi

if id caddy >/dev/null 2>&1; then
  install -d -m 0755 -o caddy -g caddy "$WEBROOT"
else
  install -d -m 0755 "$WEBROOT"
fi

prev=""
if [[ -f "$SNIPPET" ]]; then
  prev="$(mktemp)"
  cp "$SNIPPET" "$prev"
fi

write_snippet "$DOMAIN"
ensure_caddyfile_import
write_site_env "$DOMAIN"

if command -v caddy >/dev/null 2>&1; then
  if ! caddy validate --config "$CADDYFILE" >/dev/null 2>&1; then
    echo "Caddyfile is invalid after writing ${SNIPPET}; rolled back" >&2
    caddy validate --config "$CADDYFILE" >&2 || true
    if [[ -n "$prev" ]]; then
      mv "$prev" "$SNIPPET"
    else
      rm -f "$SNIPPET"
    fi
    exit 1
  fi
fi
if [[ -n "$prev" ]]; then
  rm -f "$prev"
fi

if [[ "$DOMAIN" == :* ]]; then
  echo "Caddy listen ${DOMAIN} → ${WEBROOT} (${SNIPPET})"
elif tls_is_lan; then
  echo "Caddy virtual host ${DOMAIN} → ${WEBROOT} (${SNIPPET}, tls internal)"
else
  echo "Caddy virtual host ${DOMAIN} → ${WEBROOT} (${SNIPPET})"
fi
