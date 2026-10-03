#!/usr/bin/env bash
# Build a public/ archive from this checkout. Architecture-independent HTML.
# Run from a clone (laptop or Actions). Same tarball shape as the Site workflow.
#
#   ./deploy/ubuntu/pack.sh
#   ./deploy/ubuntu/push.sh --pack user@host
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

usage() {
  echo "usage: $0" >&2
  exit 2
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
fi

if [[ ! -f zola.toml ]]; then
  echo "run pack.sh from a quadio-site checkout (missing zola.toml)" >&2
  exit 1
fi

if [[ -f .gitmodules ]] && command -v git >/dev/null; then
  git submodule update --init --recursive
fi

if command -v rsites >/dev/null 2>&1; then
  rsites build
elif command -v zola >/dev/null 2>&1; then
  zola build
else
  echo "need rsites or zola on PATH" >&2
  exit 1
fi

if [[ ! -f public/index.html ]]; then
  echo "build did not produce public/index.html" >&2
  exit 1
fi

OUT_DIR="${SITE_PACK_DIR:-dist}"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
ARCHIVE="${OUT_DIR}/quadio-site.tar.gz"

tar -C public -czf "$ARCHIVE" .
(cd "$OUT_DIR" && sha256sum "$(basename "$ARCHIVE")" >"$(basename "$ARCHIVE").sha256")

echo "packed ${ARCHIVE}"
echo "checksum ${ARCHIVE}.sha256"
