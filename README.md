# Personal Infra

Docker Compose infrastructure for a small personal VPS on Vultr.

This repo is intended to own shared platform services:

- Postgres for app databases
- MongoDB for apps that need a document database
- Redis for caches and queues
- Caddy for HTTPS reverse proxying
- Uptime Kuma for monitoring
- Restic for encrypted offsite backups

Application repos should stay separate and join the shared Docker network when
they need these services.

## Vultr Server

A small Vultr Cloud Compute instance is enough for several lightweight personal
apps. Start with Ubuntu LTS and resize later if CPU, memory, or disk pressure
become real.

Suggested baseline:

- Ubuntu 24.04 LTS
- 1-2 vCPU
- 2 GB RAM minimum, 4 GB if you expect heavier apps
- SSH key login
- DNS `A` records pointed at the instance IP
- Vultr firewall allowing inbound `22`, `80`, and `443`

A Vultr reserved IP is optional. It is useful if you expect to rebuild or move
the instance and want DNS to stay stable.

Vultr snapshots are useful for quick server rollback, but they are not a
replacement for Restic offsite backups.

## Server Prep

Install Docker and the Compose plugin on the VPS:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Create the host directories used by bind mounts:

```bash
sudo mkdir -p /srv/apps /srv/infra /srv/backups/database-dumps
sudo chown -R "$USER":"$USER" /srv/apps /srv/infra /srv/backups
```

## Configuration

Copy the example env file and replace every secret:

```bash
cp .env.example .env
```

Minimum values to set:

- `POSTGRES_PASSWORD`
- `MONGO_INITDB_ROOT_PASSWORD`
- `REDIS_PASSWORD`
- `MEALIE_POSTGRES_PASSWORD`
- `RESTIC_REPOSITORY`
- `RESTIC_PASSWORD`
- S3-compatible credentials if your Restic repository uses S3

The default Caddy config only responds on port `80` with a simple health
message. When you are ready to route real domains, copy the example:

```bash
cp caddy/Caddyfile.example caddy/Caddyfile
```

Then update the Compose mount or set `CADDYFILE_PATH=./caddy/Caddyfile` in
`.env`.

## Start The Stack

```bash
docker compose pull
docker compose up -d
docker compose ps
```

MongoDB and Redis are optional Compose profiles and do not start by default.
Start them only when an app needs them:

```bash
docker compose --profile mongo --profile redis up -d
```

Databases are only exposed on the private Docker network. Do not add public
`5432`, `27017`, or `6379` port mappings unless you have a specific secured
use case.

## App Repository Integration

Each app repo should define its own Compose file and join the shared network:

```yaml
services:
  my-app:
    image: example/my-app:latest
    networks:
      - shared
    environment:
      DATABASE_URL: postgres://my_app:change-me@personal-infra-postgres:5432/my_app
      REDIS_URL: redis://:change-me@personal-infra-redis:6379/0

networks:
  shared:
    external: true
    name: personal-infra-shared
```

Use one database and one database user per app.

## Mealie

This stack creates a dedicated Postgres database and user for Mealie:

- database: `mealie`
- user: `mealie`
- password: `MEALIE_POSTGRES_PASSWORD`
- host from app containers: `personal-infra-postgres`
- port: `5432`

Set these values in the Mealie app repository:

```env
DB_ENGINE=postgres
POSTGRES_SERVER=personal-infra-postgres
POSTGRES_PORT=5432
POSTGRES_DB=mealie
POSTGRES_USER=mealie
POSTGRES_PASSWORD=<same value as MEALIE_POSTGRES_PASSWORD>
```

The Mealie Compose service should join the external
`personal-infra-shared` network and listen internally on port `9000`.

Postgres only runs scripts in `postgres/init` when the data directory is first
created. If Postgres is already initialized, run the equivalent user/database
creation commands manually with `psql`.

Expose Mealie through Caddy with the recipes subdomain:

```caddyfile
recipes.grantlonie.com {
	reverse_proxy mealie:9000
}
```

## Listen

This stack creates a dedicated Postgres database and user for Listen:

- database: `listen`
- user: `listen`
- password: `LISTEN_POSTGRES_PASSWORD`
- host from app containers: `personal-infra-postgres`
- port: `5432`

Set this value in the Listen app repository:

```env
DATABASE_URL=postgresql+psycopg://listen:<same value as LISTEN_POSTGRES_PASSWORD>@personal-infra-postgres:5432/listen
```

The Listen Compose services should join the external
`personal-infra-shared` network. Caddy should route API traffic to
`listen-backend:8000` and frontend traffic to `listen-frontend:80`:

```caddyfile
listen.grantlonie.com {
	reverse_proxy /api/* listen-backend:8000
	reverse_proxy /health listen-backend:8000
	reverse_proxy listen-frontend:80
}
```

As with Mealie, the Postgres init script only runs when the data directory is
first created. If Postgres is already initialized, run the equivalent
user/database creation commands manually with `psql`.

For Postgres, copy `postgres/init/01-create-app-databases.sql.example` to a
non-example `.sql` file before the first Postgres startup, or create users and
databases manually later with `psql`.

For MongoDB, copy `mongo/init/01-create-app-users.js.example` to a non-example
`.js` file before the first Mongo startup, or create users manually later with
`mongosh`.

## Backups

Restic stores encrypted, deduplicated snapshots in remote storage such as
Backblaze B2, Cloudflare R2, AWS S3, Wasabi, or an SFTP target.

Initialize the Restic repository once:

```bash
docker compose run --rm --entrypoint restic restic-backup init
```

Run a backup:

```bash
./backups/backup.sh
```

The backup script:

- Creates a Postgres `pg_dumpall` logical dump.
- Creates a MongoDB archive dump.
- Backs up `/srv/apps`, `/srv/infra`, and `/srv/backups/database-dumps`.
- Applies retention for 7 daily, 4 weekly, and 6 monthly snapshots.

Schedule it with cron or a systemd timer. A simple cron example:

```cron
15 3 * * * cd /srv/infra/personal-infra && ./backups/backup.sh >> /var/log/personal-infra-backup.log 2>&1
```

## Restore

Restore the latest snapshot into a review directory:

```bash
./backups/restore.sh /srv/restore/latest
```

Restore a specific snapshot:

```bash
./backups/restore.sh /srv/restore/2026-restore abc12345
```

Review restored files before copying them back into `/srv/apps` or `/srv/infra`.
For databases, restore from the logical dumps under
`/srv/backups/database-dumps` in the restored snapshot.

Test restore early. A backup that has never been restored is only a backup
theory.

## Security Notes

- Keep database ports private to Docker.
- Use strong unique passwords in `.env`.
- Do not commit `.env`, `backups/restic.env`, or real Caddy configs with
  private domains/secrets.
- Keep the VPS patched.
- Protect admin dashboards with strong app auth, Tailscale, Cloudflare Access,
  Authelia, or Authentik.
- Monitor disk usage. Databases and uploads can fill small VPS disks quickly.

## Layout

Host data is organized around bind mounts:

```text
/srv/
  apps/
    app-name/
      data/
      uploads/
  infra/
    postgres/
    mongo/
    redis/
    caddy/
    uptime-kuma/
  backups/
    database-dumps/
```

Repo layout:

```text
personal-infra/
  docker-compose.yml
  .env.example
  caddy/
  backups/
  postgres/
  mongo/
  monitoring/
```
