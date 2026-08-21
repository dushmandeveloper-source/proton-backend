# Local vs. hosted environments

This project runs against different databases and API URLs depending on
where it's running. Nothing needs to be toggled by hand — each environment
picks up its own config automatically.

## Backend (this repo)

ASP.NET Core layers config files by `ASPNETCORE_ENVIRONMENT`:
`appsettings.json` (base, committed) is loaded first, then
`appsettings.{Environment}.json` overrides it.

| Environment | Trigger | Config file | Database used |
|---|---|---|---|
| Local (`dotnet run`) | `ASPNETCORE_ENVIRONMENT=Development` (set in `Properties/launchSettings.json`) | `appsettings.Development.json` (gitignored) | Local SQL Server (`VS-PW0C7J84\DUSHMAN001`, DB `Proton_Admin`) |
| Hosted (published to the live site) | `ASPNETCORE_ENVIRONMENT=Production` (the IIS host's default) | `appsettings.Production.json` (gitignored) | Hosted SQL Server (`sql5112.site4now.net`, DB `db_aa66ca_protondb`) |

Both `appsettings.Development.json` and `appsettings.Production.json` are
gitignored because they hold real credentials. `appsettings.json` (the base,
committed file) intentionally has **empty** `DBSettings` — it must never hold
a real password, since it's the one file that ships in git.

**First-time local setup:** copy `Web_Backend/appsettings.Development.json.example`
to `Web_Backend/appsettings.Development.json` and fill in your local SQL
Server credentials.

**Publishing to the live host:** run `dotnet publish -c Release -o publish`
from `Web_Backend/`, then upload the contents of `publish/` via FileZilla
(or your FTP client) to the live site, overwriting the existing files —
including `appsettings.Production.json`. The IIS host runs in Production by
default, so it picks up the hosted DB and CORS origins automatically. Since
`appsettings.Production.json` is gitignored, `git push` alone never updates
the live server — you must re-publish and re-upload for backend config
changes (like a new CORS origin) to take effect.

## Frontend (`Proton` repo)

Vite reads `VITE_API_BASE_URL` to decide which backend API to call
(`frontend/src/data/universitiesApi.js`).

| Environment | Config file | API used |
|---|---|---|
| Local (`npm run dev`) | `.env` (gitignored) | `http://localhost:5080` (local backend) |
| Vercel build (`npm run build`, mode=production) | `.env.production` (committed) | `https://dushman-002-site3.gtempurl.com` (hosted backend) |

`.env.production` is committed on purpose — Vercel builds from git and Vite
only bakes in `VITE_` vars at build time, so the hosted API URL has to live
in a file the build actually sees.

## Keeping CORS in sync

The backend only accepts cross-origin API calls from origins listed in
`ApplicationSettings:PublicSiteOrigins`. When the frontend's hosted URL
changes (e.g. a new Vercel domain), add it to `PublicSiteOrigins` in
`appsettings.Production.json` and re-publish/re-upload the backend.

## Database schema changes (migrations)

Every database change — new table, new column, new stored procedure — gets
its own numbered file under `Database/migrations/`, e.g.
`0002_add_university_gallery_sort_order.sql`. Never edit an already-numbered
file after it's been applied anywhere; add a new one instead, the same way
`ProtonAdmin_Schema.sql`/`UniversityModule.sql` already do for full-schema
idempotent scripts (this just gives each individual change its own file so
you can update the hosted DB by running only what's new).

**Rules for a migration file:**
- Name it `NNNN_short_description.sql`, `NNNN` zero-padded and one higher
  than the last file in the folder.
- No `USE [Database]` statement — the tooling already connects to the right
  database; a hardcoded `USE` would break it on the hosted DB (different
  name from local).
- Make it idempotent where practical (`IF OBJECT_ID(...) IS NULL`, etc.),
  matching the existing schema scripts' style — cheap insurance if it's ever
  re-run by hand.

**Applying migrations locally** — runs immediately against the target DB
and records each one in `syst.SchemaMigrations`:
```powershell
Database/tools/apply-migrations.ps1 -Server "VS-PW0C7J84\DUSHMAN001" -Database "Proton_Admin" -UserId "sa" -Password "..."
```

**Checking status locally, without publishing** — `-Status` connects and
reports only; it never applies or writes anything. Use this to see what a
database is on right now:
```powershell
Database/tools/apply-migrations.ps1 -Server "VS-PW0C7J84\DUSHMAN001" -Database "Proton_Admin" -UserId "sa" -Password "..." -Status
```
Same flags work with the hosted DB's server/database/credentials (see
`appsettings.Production.json`) if you want to check what's applied there
*before* running `dotnet publish` — you don't have to publish first just to
find out.

**At publish time**, `dotnet publish` automatically regenerates
`Database/generated/pending-migrations.sql` — every migration not yet
recorded in the hosted DB's `syst.SchemaMigrations`, concatenated into one
script (see the `GeneratePendingMigrations` target in `Web_Backend.csproj`).
This file is gitignored — it's a snapshot for whatever DB
`appsettings.Production.json` currently points at, not source. After
uploading the publish output via FileZilla, open that generated file in
SSMS (or run it with `sqlcmd`) against the hosted database to bring its
schema up to date. It self-records each migration as it runs, so running it
again later only picks up whatever's new since.

**Summary of the three modes:**

| Mode | Command flag | Applies changes? | When to use |
|---|---|---|---|
| Apply | *(none)* | Yes, immediately | Local dev, after adding a new migration file |
| Generate | `-GenerateOnly` | No — writes a combined script to disk | Automatically run by `dotnet publish`; can also be run manually against any DB |
| Status | `-Status` | No — read-only report | Check what's applied/pending on any DB (local or hosted) at any time, without publishing |

## Role-based permissions

Every admin module (Universities, User Management, Email Settings, Email
Templates) has independent View/Add/Edit/Delete permissions, set per role on
the Role form (User Management → Roles & Permissions → Edit) and optionally
overridden per individual user on that user's Add/Edit form.

- **Master Admin** (`UserTypeID = 'MASTERADMIN'`) always has full access to
  every module. This is hardcoded in `Auth.HasPermission`
  (`Web_Backend/Classes/Auth.cs`) — not just pre-ticked in the UI — so it
  can't be narrowed by editing the database directly. Its Edit-role form
  shows every box ticked and disabled, and it has no Delete button in the
  Roles list.
- A user's **effective permission** for a module/action is: their personal
  override if one exists, otherwise their role's default, otherwise
  (implicitly) false. Overrides are stored in `usr.UserPermissionOverride`
  as nullable bits — `NULL` means "inherit from the role."
- Permissions are computed once at login and cached on the session
  (`SessionUser.Permissions`) — a role or override change takes effect the
  next time the affected user logs in, not instantly for an already-active
  session.
- To add a new permission-gated module: add a `(Code, Label)` pair to
  `PermissionCode.All` (`Web_Backend/Classes/PermissionCode.cs`), then call
  `Auth.CheckPermission(PermissionCode.YourModule, 'V'|'A'|'E'|'D')` at the
  top of that module's controller actions.
