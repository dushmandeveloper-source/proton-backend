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
