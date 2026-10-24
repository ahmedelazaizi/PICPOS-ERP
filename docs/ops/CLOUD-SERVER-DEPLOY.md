# Cloud server - production deployment (TLS, secrets, database)

Audit finding **SEC-014**. The shipped `docker/docker-compose.yml` is a **TEST stack** (test-only secrets,
loopback-bound). Do not use it as is in production.

## Transport: pick ONE

| Option | Config | Notes |
|---|---|---|
| **A. Reverse proxy terminates TLS** (recommended) | `BIND_ADDRESS=127.0.0.1` on the server; Caddy / nginx on 443 | The server then listens on loopback only; the startup warning disappears. |
| **B. The server terminates TLS** | `TLS_CERT_FILE=/run/secrets/fullchain.pem` `TLS_KEY_FILE=/run/secrets/privkey.pem` (optional `TLS_KEY_PASSWORD`) | PEM files; renew by restarting the process. A half-configured pair (only one of the two) aborts startup (exit 78). |

If neither is set the server still starts (so the test stack keeps working) but logs
`[security] WARNING: plain HTTP on ...` on every start.

### Caddy example (option A)

```
cloud.example.com {
    reverse_proxy 127.0.0.1:8080
}
```

Caddy obtains and renews a public certificate automatically. The mobile apps (`UrlPolicy.release`) only
accept `https://` cloud URLs, so a public certificate is required.

## Secrets

* `TOKEN_SECRET` >= 32 chars (otherwise a random one is used and sessions reset on restart),
  `ADMIN_KEY` >= 24 chars (or empty to disable `/admin/*`). Generate with `openssl rand -hex 32`.
* Never use `ALLOW_WEAK_ADMIN_KEY` outside throw-away test stacks.
* Source secrets from the platform secret store (Docker/Kubernetes secrets, systemd credentials), not from
  files in the repository.

## Database

* `DB_SSL=true` for any database that is not on the same host/private network.
* Back up with `docs/ops/POSTGRES-BACKUP.md`.

## Verify

```
curl -sS https://cloud.example.com/health
curl -sS -o NUL -w "%{http_code}" http://cloud.example.com:8080/health   # must NOT be reachable from the internet
```

## Tests

`server/test/tls_config_test.dart` (config parsing, no silent fallback). The TLS handshake itself is
`dart:io` / BoringSSL behaviour and was not re-tested end to end here.
