#!/usr/bin/env bash
set -euo pipefail

: "${LISTEN_POSTGRES_PASSWORD:?LISTEN_POSTGRES_PASSWORD must be set}"

psql -v ON_ERROR_STOP=1 \
  --username "${POSTGRES_USER}" \
  --dbname "${POSTGRES_DB}" \
  -v listen_password="${LISTEN_POSTGRES_PASSWORD}" <<'EOSQL'
SELECT format('CREATE ROLE listen LOGIN PASSWORD %L', :'listen_password')
WHERE NOT EXISTS (
  SELECT FROM pg_catalog.pg_roles WHERE rolname = 'listen'
)
\gexec

ALTER ROLE listen WITH LOGIN PASSWORD :'listen_password';

SELECT 'CREATE DATABASE listen OWNER listen'
WHERE NOT EXISTS (
  SELECT FROM pg_database WHERE datname = 'listen'
)
\gexec

GRANT ALL PRIVILEGES ON DATABASE listen TO listen;
EOSQL
