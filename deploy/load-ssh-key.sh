#!/usr/bin/env bash
# Load an SSH private key for GitHub Actions deploys.
# GitHub secrets often arrive as one line; OpenSSH then fails with
# `error in libcrypto`. This script unwraps quotes, restores PEM line
# breaks, and ssh-adds the result.
#
#   SSH_PRIVATE_KEY='...' bash deploy/load-ssh-key.sh
set -euo pipefail

KEYFILE="${SSH_KEY_FILE:-$HOME/.ssh/id_deploy}"

die() {
  echo "$*" >&2
  exit 1
}

[[ -n "${SSH_PRIVATE_KEY:-}" ]] || die "SSH_PRIVATE_KEY is empty"

raw="$(printf '%s' "$SSH_PRIVATE_KEY" | tr -d '\r')"
raw="${raw#"${raw%%[![:space:]]*}"}"
raw="${raw%"${raw##*[![:space:]]}"}"
if [[ ${#raw} -ge 2 && ${raw:0:1} == '"' && ${raw: -1} == '"' ]]; then
  raw="${raw:1:${#raw}-2}"
elif [[ ${#raw} -ge 2 && ${raw:0:1} == "'" && ${raw: -1} == "'" ]]; then
  raw="${raw:1:${#raw}-2}"
fi

BEGIN_RE='-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----'
END_RE='-----END [A-Z0-9 ]*PRIVATE KEY-----'

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

first="$(printf '%s\n' "$raw" | head -n1)"
if [[ "$first" =~ ^-----BEGIN\ [A-Z0-9\ ]*PRIVATE\ KEY-----$ ]]; then
  printf '%s\n' "$raw" >"$TMP"
elif begin="$(printf '%s' "$raw" | grep -o -e "^${BEGIN_RE}")" \
  && end="$(printf '%s' "$raw" | grep -o -e "${END_RE}$")" \
  && [[ -n "$begin" && -n "$end" ]]; then
  body="${raw#"$begin"}"
  body="${body%"$end"}"
  body="$(printf '%s' "$body" | tr -d '[:space:]')"
  {
    printf '%s\n' "$begin"
    printf '%s' "$body" | fold -w 70
    printf '\n%s\n' "$end"
  } >"$TMP"
else
  printf '%s\n' "$raw" >"$TMP"
fi

if grep -qE '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-|sk-ssh-|sk-ecdsa-)' "$TMP"; then
  die "SSH_PRIVATE_KEY looks like a public key (.pub). Paste the private key, including -----BEGIN ... PRIVATE KEY-----."
fi
if ! grep -q 'BEGIN .*PRIVATE KEY' "$TMP"; then
  die "SSH_PRIVATE_KEY is not an OpenSSH/PEM private key (missing BEGIN PRIVATE KEY)."
fi
if grep -q 'ENCRYPTED' "$TMP"; then
  die "SSH_PRIVATE_KEY is passphrase-protected; use a key with an empty passphrase."
fi

install -d -m 0700 "$(dirname "$KEYFILE")"
cp "$TMP" "$KEYFILE"
chmod 0600 "$KEYFILE"

if ! ssh-keygen -y -f "$KEYFILE" >/dev/null 2>&1; then
  die "SSH_PRIVATE_KEY could not be parsed (error in libcrypto). Re-paste the full private key with its original newlines."
fi

if [[ "${SSH_SKIP_AGENT:-}" == "1" ]]; then
  exit 0
fi

eval "$(ssh-agent -s)"
ssh-add "$KEYFILE"
if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "SSH_AUTH_SOCK=${SSH_AUTH_SOCK}"
    echo "SSH_AGENT_PID=${SSH_AGENT_PID}"
  } >>"$GITHUB_ENV"
fi
