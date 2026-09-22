# Database operations

The application uses SQLite. The database file is always named `ocpp.db` inside
the directory configured by `DATA_DIR`.

## Local development

Run the server with the helper script:

```powershell
.\run-local.ps1
```

If `data_manual` exists, the script uses it automatically. To choose a stable
database location outside the repository, use:

```powershell
.\run-local.ps1 -DataDir "C:\EVData\ocpp" -Port 9000
```

The script prints the exact database path before starting Uvicorn. Do not use a
new empty directory when you expect existing users, wallets, or transactions.

## Docker

The Compose file stores `/app/data` in the persistent volume `ocpp-data`.
These commands keep the database:

```powershell
docker compose up -d
docker compose restart
```

Do not run `docker compose down -v` unless the database volume is intentionally
being deleted. Use the Admin > Backup screen before moving or rebuilding the
deployment.

## Git

SQLite files and runtime data are intentionally excluded from Git. This keeps
credentials and production data out of the repository. Back up `ocpp.db` and
the `backups` directory separately, or use the built-in Admin > Backup screen.
