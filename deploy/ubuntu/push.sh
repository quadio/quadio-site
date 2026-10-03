#!/usr/bin/env bash
# Copy a built public/ archive onto a bare-metal Ubuntu server over SSH.
# The server never talks to GitHub. Run this from a clone (laptop or Actions).
#
#   ./deploy/ubuntu/push.sh --pack --bootstrap --domain www.quad.io user@host
#   ./deploy/ubuntu/push.sh --archive dist/quadio-site.tar.gz user@host
#   ./deploy/ubuntu/push.sh --pack --bootstrap --domain damascus --tls lan user@192.168.0.18
#
# Omit --domain on --bootstrap to listen on :8080.
# --pack builds public/ from this checkout (rsites or zola).
set -euo pipefail

BOOTSTRAP=0
DOMAIN=""
ARCHIVE=""
PACK=0
EMAIL="${CADDY_EMAIL:-}"
TLS_MODE="${SITE_TLS:-}"
SSH_PORT="${SITE_SSH_PORT:-22}"

usage() {
  echo "usage: $0 [--bootstrap] [--domain FQDN] [--tls lan] [--archive FILE] [--pack] [--port N] user@host" >&2
  echo "--domain is the Caddy virtual host on --bootstrap (default :8080)" >&2
  echo "--domain :8080 skips TLS and binds Caddy on that port" >&2
  echo "--tls lan uses Caddy's local CA on a private LAN (no Let's Encrypt)" >&2
  echo "--pack builds a public/ archive from this checkout" >&2
  echo "--archive FILE installs that tarball instead of packing" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bootstrap) BOOTSTRAP=1; shift ;;
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --tls)
      TLS_MODE="${2:-}"
      shift 2
      ;;
    --archive) ARCHIVE="${2:-}"; shift 2 ;;
    --pack) PACK=1; shift ;;
    --port) SSH_PORT="${2:-}"; shift 2 ;;
    -h | --help) usage ;;
    --) shift; break ;;
    -*) usage ;;
    *) break ;;
  esac
done

TARGET_HOST="${1:-}"
if [[ -z "$TARGET_HOST" ]]; then
  usage
fi
if [[ -n "$TLS_MODE" ]]; then
  TLS_MODE="${TLS_MODE,,}"
  if [[ "$TLS_MODE" != "lan" && "$TLS_MODE" != "internal" ]]; then
    echo "--tls must be lan (Caddy local CA on a private network)" >&2
    exit 1
  fi
fi
if [[ -n "$EMAIL" ]] && ! [[ "$EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
  echo "CADDY_EMAIL does not look like an email address: ${EMAIL}" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_OPTS=(-o Port="$SSH_PORT" -o ServerAliveInterval=15)
if [[ -n "${SITE_SSH_KNOWN_HOSTS:-}" ]]; then
  SSH_OPTS+=(-o StrictHostKeyChecking=yes -o UserKnownHostsFile="$SITE_SSH_KNOWN_HOSTS")
else
  SSH_OPTS+=(-o StrictHostKeyChecking=accept-new)
fi

remote() {
  ssh "${SSH_OPTS[@]}" "$TARGET_HOST" "$@"
}

remote_sudo() {
  if [[ -t 0 ]]; then
    ssh -t "${SSH_OPTS[@]}" "$TARGET_HOST" "$@"
  else
    ssh "${SSH_OPTS[@]}" "$TARGET_HOST" "$@"
  fi
}

pack_checkout() {
  local pack_script pack_log
  pack_script="${SCRIPT_DIR}/pack.sh"
  if [[ ! -f "$pack_script" ]]; then
    echo "missing ${pack_script}" >&2
    exit 1
  fi
  pack_log="$(mktemp)"
  if ! bash "$pack_script" | tee "$pack_log"; then
    rm -f "$pack_log"
    exit 1
  fi
  ARCHIVE="$(sed -n 's/^packed //p' "$pack_log" | tail -n1)"
  rm -f "$pack_log"
  if [[ -z "$ARCHIVE" || ! -f "$ARCHIVE" ]]; then
    echo "pack.sh did not produce an archive" >&2
    exit 1
  fi
}

if [[ "$PACK" -eq 1 ]]; then
  if [[ -n "$ARCHIVE" ]]; then
    echo "use --pack or --archive, not both" >&2
    exit 1
  fi
  pack_checkout
fi

if [[ -z "$ARCHIVE" ]]; then
  echo "pass --archive FILE or --pack" >&2
  usage
fi
if [[ ! -f "$ARCHIVE" ]]; then
  echo "archive not found: ${ARCHIVE}" >&2
  exit 1
fi

REMOTE_DIR="${SITE_REMOTE_DIR:-/var/tmp/quadio-site-push-$$}"
ARCHIVE_BYTES=$(wc -c <"$ARCHIVE" | tr -d ' ')
avail="$(remote "df -B1 --output=avail /var/tmp 2>/dev/null | tail -n1 | tr -d ' '" || true)"
if [[ "$avail" =~ ^[0-9]+$ ]] && ((avail < ARCHIVE_BYTES + 1048576)); then
  echo "server does not have enough space for $(basename "$ARCHIVE") (${ARCHIVE_BYTES} bytes; ${avail} available in /var/tmp)" >&2
  echo "remove leftover /var/tmp/quadio-site-push-* dirs, or free disk on /" >&2
  exit 1
fi
echo "uploading $(basename "$ARCHIVE") (${ARCHIVE_BYTES} bytes) to ${TARGET_HOST}:${REMOTE_DIR}"
remote "mkdir -p $(printf '%q' "$REMOTE_DIR")/deploy"
scp "${SSH_OPTS[@]}" "$ARCHIVE" "${TARGET_HOST}:${REMOTE_DIR}/site.tar.gz"
if [[ -f "${ARCHIVE}.sha256" ]]; then
  scp "${SSH_OPTS[@]}" -q "${ARCHIVE}.sha256" "${TARGET_HOST}:${REMOTE_DIR}/site.tar.gz.sha256"
fi
scp "${SSH_OPTS[@]}" -q -r "${SCRIPT_DIR}/." "${TARGET_HOST}:${REMOTE_DIR}/deploy/"
remote "chmod +x $(printf '%q' "$REMOTE_DIR")/deploy/bootstrap.sh $(printf '%q' "$REMOTE_DIR")/deploy/install.sh $(printf '%q' "$REMOTE_DIR")/deploy/configure-caddy.sh $(printf '%q' "$REMOTE_DIR")/deploy/pack.sh"

REMOTE_ARCHIVE="${REMOTE_DIR}/site.tar.gz"
if [[ "$BOOTSTRAP" -eq 1 ]]; then
  echo "bootstrapping ${TARGET_HOST}${DOMAIN:+ (Caddy vhost ${DOMAIN})}"
  remote_sudo "sudo env SITE_ARCHIVE=$(printf '%q' "$REMOTE_ARCHIVE") SITE_DOMAIN=$(printf '%q' "$DOMAIN") SITE_ENABLE_UFW=$(printf '%q' "${SITE_ENABLE_UFW:-}") SITE_TLS=$(printf '%q' "$TLS_MODE") CADDY_EMAIL=$(printf '%q' "$EMAIL") bash $(printf '%q' "$REMOTE_DIR")/deploy/bootstrap.sh"
else
  echo "installing quadio-site on ${TARGET_HOST}"
  remote_sudo "sudo env SITE_ARCHIVE=$(printf '%q' "$REMOTE_ARCHIVE") SITE_DOMAIN=$(printf '%q' "$DOMAIN") SITE_TLS=$(printf '%q' "$TLS_MODE") bash $(printf '%q' "$REMOTE_DIR")/deploy/install.sh"
fi
remote "rm -rf $(printf '%q' "$REMOTE_DIR")"
echo "done"
