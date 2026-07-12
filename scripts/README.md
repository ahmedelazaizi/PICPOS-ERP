# scripts/

Developer + admin utilities. PowerShell-first because the project targets Windows.

## Git hooks (Spec 130)

`scripts/git-hooks/` ships a `pre-commit` dispatcher + per-spec PowerShell hooks.
All hooks are **warning-only** — none of them block commits. They exist to remind
the dev of out-of-band steps (run integration tests, refresh PG schema, etc.).

### One-time installation

```powershell
git config core.hooksPath scripts/git-hooks
```

That's it — git will now invoke `scripts/git-hooks/pre-commit` on every commit.
The dispatcher chains the per-spec PowerShell scripts.

### Verify

```powershell
# Touch a Drift schema file.
Add-Content lib/data/database/database.dart "// noop"
git add lib/data/database/database.dart
git commit -m "test hook"
# Expect a yellow Spec 130 reminder box. Commit still succeeds.
```

To remove the customization later:

```powershell
git config --unset core.hooksPath
```

### Per-hook list

- `pre-commit-schema-parity.ps1` — **Spec 130**. Reminds the dev to run the
  PG schema-parity integration tests when any `lib/data/database/*.dart`
  file is staged. Per Clarification Q5, warning-only.

When a new Spec needs its own pre-commit reminder, add a sibling
`pre-commit-<spec>.ps1` and append a call to it from the `pre-commit`
dispatcher.

## Other scripts (pre-existing — not part of Spec 130)

- `CLEAN_INSTALL.bat` — full wipe + reinstall path for testers.
- `FIX_ADMIN_PASSWORD.bat` — operator-side admin password recovery.
- `check_coverage.dart` — flutter test coverage helper.
- `clean_install_reset.ps1` — partial reset (keeps backups).
- `generate_self_signed_cert.ps1` — TLS cert generation for client/server.
- `install_client_cert.ps1` — install a server-issued client cert.
- `metrics.ps1` — local performance metrics dump.
- `reset_pg_admin_password.ps1` + `.sql` — operator-side PG admin recovery.
