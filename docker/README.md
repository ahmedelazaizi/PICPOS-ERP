# PicPos cloud — TEST stack (Docker, Windows)

**Test only.** Default passwords and keys are in `docker-compose.yml` on purpose. Production deployment is a separate checklist (`docs/mobile/ARCHITECTURE-I.md` §12).

## What it runs

| Service | Image | Host port | Notes |
|---|---|---|---|
| `postgres` | `postgres:16-alpine` | `55432` | db `picpos_cloud`, user `picpos`, password `picpos_test_only`, volume `pgdata` |
| `api` | built from `../server/Dockerfile` (Dart AOT on `scratch`) | `18080` | migrations run at start; `SEED_DEMO=true` seeds a demo company; WhatsApp provider = `mock` |

Host port 8080 is not used because the PicPos desktop LAN server already listens there.

## Start (Docker Desktop on Windows)

```powershell
cd D:\PICPOS-ERP\docker
docker compose up -d --build
docker compose ps                        # both services should show (healthy)
curl.exe http://localhost:18080/health   # {"status":"ok","db":"ok","whatsappProvider":"mock"}
```

End-to-end smoke (pairing → login → bootstrap → push → replay → sales return (+ over-return rejected) → visits → token rotation → pull → WhatsApp mock):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\smoke.ps1
```

Logs and stop:

```powershell
docker compose logs -f api               # mock WhatsApp messages are logged as [whatsapp:mock]
docker compose down                      # keep data
docker compose down -v                   # also delete the database volume
```

## Demo data (`server/lib/src/seed.dart`)

- Company `00000000-0000-4000-8000-000000000001`, default tax 16 %.
- Rep 1 `…0000000000a1` PIN `1234`: route «خط الشمال» with customers `…c1` (credit limit 100, WhatsApp opt-in `+962790000001`) and `…c2` (no limit); van stock water 50, bread 20; receipt book `R-1001..1050`.
- Rep 2 `…0000000000a2` PIN `5678`: route «خط الجنوب» with customer `…c3`; van stock water 10; book `R-2001..2050`.
- Number series: invoices `VS-` and returns `VR-`, blocks of 500 per device.
- Pricing (I-2): water wholesale price 2.20 (for `price_level='wholesale'` customers); default price list `…e1` «قائمة الكميات»: bread ≥ 10 → 0.90. Prices are tax-exclusive (`companies.prices_include_tax = false`).

## Pairing a device by hand

```powershell
$k = @{ 'x-admin-key' = 'test-admin-key' }
Invoke-RestMethod -Method Post http://localhost:18080/admin/pairing-codes -Headers $k -ContentType application/json `
  -Body '{"companyGlobalId":"00000000-0000-4000-8000-000000000001","employeeGlobalId":"00000000-0000-4000-8000-0000000000a1"}'
```

Enter the code in the app (server URL `http://10.0.2.2:18080` from the Android emulator; your PC's LAN IP from a phone).

## Server tests

The server integration tests use this Postgres (host port 55432), each test in its own schema:

```powershell
docker compose up -d postgres
cd ..\server
D:\Cash\develop\flutter\bin\cache\dart-sdk\bin\dart.exe test
```
