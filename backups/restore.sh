#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$(mkdir -p "${1:-/srv/restore/latest}" && cd "${1:-/srv/restore/latest}" && pwd)"
SNAPSHOT="${2:-latest}"
CONTAINER_TARGET="/restore-target"

cd "${ROOT_DIR}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

if [[ -f backups/restic.env ]]; then
  set -a
  # shellcheck disable=SC1091
  source backups/restic.env
  set +a
fi

echo "Restoring snapshot '${SNAPSHOT}' to '${TARGET}'..."
docker compose run --rm \
  --volume "${TARGET}:${CONTAINER_TARGET}" \
  --entrypoint restic \
  restic-backup restore "${SNAPSHOT}" \
  --target "${CONTAINER_TARGET}"

cat <<EOF
Restore complete.

Files were restored under:
  ${TARGET}

Database dumps, if present, are under:
  ${TARGET}/srv/backups/database-dumps

Review the restored files before copying them back into /srv/apps or /srv/infra.
EOF
