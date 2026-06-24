# Monitoring

This stack includes Uptime Kuma for basic health checks.

After the stack is running, expose Uptime Kuma through Caddy by copying
`caddy/Caddyfile.example` to `caddy/Caddyfile`, adding a real hostname, and
setting `CADDYFILE_PATH=./caddy/Caddyfile` in `.env`.

Recommended checks:

- Public HTTPS endpoints for each app.
- Internal container endpoints where useful, such as `http://mealie:9000`.
- Backup freshness, using a custom push monitor from your backup job.
- Disk usage alerts from the VPS provider or a small local script.

Keep the Uptime Kuma dashboard private. Use a strong password and consider
placing it behind Tailscale, Cloudflare Access, Authelia, or Authentik.
