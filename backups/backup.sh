#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DUMP_ROOT="/srv/backups/database-dumps"
POSTGRES_DUMP_DIR="${DUMP_ROOT}/postgres"
MONGO_DUMP_DIR="${DUMP_ROOT}/mongo"
TIMESTAMP="$(date -u +"%Y%m%dT%H%M%SZ")"

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

mkdir -p "${POSTGRES_DUMP_DIR}" "${MONGO_DUMP_DIR}"

if docker compose ps --status running --services | grep -qx postgres; then
  echo "Creating Postgres logical dump..."
  docker compose exec -T postgres pg_dumpall \
    --username "${POSTGRES_USER}" \
    > "${POSTGRES_DUMP_DIR}/pg_dumpall-${TIMESTAMP}.sql"

  ln -sfn "pg_dumpall-${TIMESTAMP}.sql" "${POSTGRES_DUMP_DIR}/latest.sql"
else
  echo "Postgres container is not running; skipping Postgres dump."
fi

if docker compose ps --status running --services | grep -qx mongo; then
  echo "Creating MongoDB archive dump..."
  docker compose exec -T mongo mongodump \
    --username "${MONGO_INITDB_ROOT_USERNAME}" \
    --password "${MONGO_INITDB_ROOT_PASSWORD}" \
    --authenticationDatabase admin \
    --archive \
    > "${MONGO_DUMP_DIR}/mongodump-${TIMESTAMP}.archive"

  ln -sfn "mongodump-${TIMESTAMP}.archive" "${MONGO_DUMP_DIR}/latest.archive"
else
  echo "MongoDB container is not running; skipping MongoDB dump."
fi

echo "Running restic backup..."
docker compose run --rm --entrypoint restic restic-backup backup \
  /srv/apps \
  /srv/infra \
  /srv/backups/database-dumps \
  --exclude-file /excludes.txt

echo "Applying restic retention policy..."
docker compose run --rm --entrypoint restic restic-backup forget \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 6 \
  --prune

echo "Backup complete."
