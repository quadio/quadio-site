#!/usr/bin/env bash
# Copy a built public/ archive onto a droplet over SSH. The droplet never talks
# to GitHub. Run this from a clone (laptop or Actions).
#
#   rsites build
#   tar -C public -czf /tmp/quadio-site.tar.gz .
#   ./deploy/digitalocean/push.sh --archive /tmp/quadio-site.tar.gz --bootstrap root@1.2.3.4
#   ./deploy/digitalocean/push.sh --archive /tmp/quadio-site.tar.gz root@1.2.3.4
#
# --domain defaults to www.quad.io on --bootstrap.
set -euo pipefail

BOOTSTRAP=0
DOMAIN=""
ARCHIVE=""
SSH_PORT="${SITE_SSH_PORT:-22}"

usage() {
  echo "usage: $0 --archive FILE [--bootstrap] [--domain FQDN] [--port N] user@host" >&2
  echo "--domain defaults to www.quad.io on --bootstrap" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bootstrap) BOOTSTRAP=1; shift ;;
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --archive) ARCHIVE="${2:-}"; shift 2 ;;
    --port) SSH_PORT="${2:-}"; shift 2 ;;
    -h | --help) usage ;;
    --) shift; break ;;
    -*) usage ;;
    *) break ;;
  esac
done

TARGET_HOST="${1:-}"
if [[ -z "$TARGET_HOST" || -z "$ARCHIVE" ]]; then
  usage
fi
if [[ ! -f "$ARCHIVE" ]]; then
  echo "archive not found: ${ARCHIVE}" >&2
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

REMOTE_DIR="/tmp/quadio-site-push-$$"
remote "mkdir -p $(printf '%q' "$REMOTE_DIR")/deploy"
scp "${SSH_OPTS[@]}" -q "$ARCHIVE" "${TARGET_HOST}:${REMOTE_DIR}/site.tar.gz"
if [[ -f "${ARCHIVE}.sha256" ]]; then
  scp "${SSH_OPTS[@]}" -q "${ARCHIVE}.sha256" "${TARGET_HOST}:${REMOTE_DIR}/site.tar.gz.sha256"
fi
scp "${SSH_OPTS[@]}" -q -r "${SCRIPT_DIR}/." "${TARGET_HOST}:${REMOTE_DIR}/deploy/"
remote "chmod +x $(printf '%q' "$REMOTE_DIR")/deploy/bootstrap.sh $(printf '%q' "$REMOTE_DIR")/deploy/install.sh $(printf '%q' "$REMOTE_DIR")/deploy/configure-caddy.sh"

REMOTE_ARCHIVE="${REMOTE_DIR}/site.tar.gz"
if [[ "$BOOTSTRAP" -eq 1 ]]; then
  if [[ -z "$DOMAIN" ]]; then
    DOMAIN="www.quad.io"
  fi
  echo "bootstrapping ${TARGET_HOST} (Caddy vhost ${DOMAIN})"
  remote_sudo "sudo env SITE_ARCHIVE=$(printf '%q' "$REMOTE_ARCHIVE") SITE_DOMAIN=$(printf '%q' "$DOMAIN") SITE_ENABLE_UFW=$(printf '%q' "${SITE_ENABLE_UFW:-}") CADDY_EMAIL=$(printf '%q' "${CADDY_EMAIL:-}") bash $(printf '%q' "$REMOTE_DIR")/deploy/bootstrap.sh"
else
  echo "installing quadio-site on ${TARGET_HOST}"
  remote_sudo "sudo env SITE_ARCHIVE=$(printf '%q' "$REMOTE_ARCHIVE") bash $(printf '%q' "$REMOTE_DIR")/deploy/install.sh"
fi
remote "rm -rf $(printf '%q' "$REMOTE_DIR")"
echo "done"
