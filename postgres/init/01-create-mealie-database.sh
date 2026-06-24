#!/usr/bin/env bash
set -euo pipefail

: "${MEALIE_POSTGRES_PASSWORD:?MEALIE_POSTGRES_PASSWORD must be set}"

psql -v ON_ERROR_STOP=1 \
  --username "${POSTGRES_USER}" \
  --dbname "${POSTGRES_DB}" \
  -v mealie_password="${MEALIE_POSTGRES_PASSWORD}" <<'EOSQL'
SELECT format('CREATE ROLE mealie LOGIN PASSWORD %L', :'mealie_password')
WHERE NOT EXISTS (
  SELECT FROM pg_catalog.pg_roles WHERE rolname = 'mealie'
)
\gexec

ALTER ROLE mealie WITH LOGIN PASSWORD :'mealie_password';

SELECT 'CREATE DATABASE mealie OWNER mealie'
WHERE NOT EXISTS (
  SELECT FROM pg_database WHERE datname = 'mealie'
)
\gexec

GRANT ALL PRIVILEGES ON DATABASE mealie TO mealie;
EOSQL
