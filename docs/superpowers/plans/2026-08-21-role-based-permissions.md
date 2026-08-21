# Role-Based Permissions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every role a View/Add/Edit/Delete permission grid per admin module, enforce it on every admin controller action, let a user's Add/Edit form show and override their role's permissions per-user, and make the "Master Admin" role permanently full-access and unremovable/uneditable — no matter what the DB or a crafted request says.

**Architecture:** A new `usr.RolePermission` table (one row per UserTypeID + module, four bit columns) is the source of truth for role defaults. A new `usr.UserPermissionOverride` table stores optional per-user, per-module overrides (nullable bits — null means "inherit from role"). A static `PermissionCode` module-key list and a `PermissionSet`/`Auth.CheckPermission(...)` helper compute the effective permission (override ?? role default), with "Master Admin" short-circuited in code to always return full access regardless of what's stored. The existing `UserController` (Users + Roles tabs) grows a permissions grid on the Role form and a read/override grid on the User form; `_AdminLayout.cshtml`'s sidebar is filtered by the current session user's effective View permission per module.

**Tech Stack:** ASP.NET Core MVC (.NET 10), Dapper-style `IDBAccess` stored-procedure calls, SQL Server (T-SQL stored procedures, no EF/ORM), Razor views with Tailwind (CDN) + vanilla JS, session-based auth (`Web_Backend/Classes/Auth.cs`).

## Global Constraints

- Every mutating stored procedure follows the existing convention exactly: `@APIKey VARCHAR(100)` gate against `syst.APIKey`, `@LogUserID VARCHAR(20) = ''`, `@RetValue VARCHAR(50) = '' OUT`, `BEGIN TRY/BEGIN TRANSACTION/COMMIT/END TRY` + `BEGIN CATCH/ROLLBACK/RAISERROR('%s. Script: <name>', 16, 1, @ERROR_MESSAGE)/END CATCH`, `SET NOCOUNT ON`.
- Varchar surrogate keys are generated via `EXEC syst.NumberFormat_Get '<schema.table>', '<column>', @PrimaryKey OUT` then `EXEC syst.NumberFormat_Set '<schema.table>'` after insert — never invent a different key scheme.
- New migration files go in `Database/migrations/` as `000N_description.sql`, no `USE [Database]` statement (see `backend/ENVIRONMENTS.md`), numbered one higher than the last existing file (currently `0001_schema_migrations_table.sql` is the only one — this plan adds `0002`).
- `Database/ProtonAdmin_Schema.sql`/`UniversityModule.sql` are **not** touched by this plan — they're the original full-schema idempotent scripts; the new table/proc definitions belong only in the new migration file (per the `ENVIRONMENTS.md` workflow this project just adopted).
- The "Master Admin" role is hardcoded as `UserTypeID = "MASTERADMIN"` (matching the existing varchar(20) column) and is seeded by the migration itself — never created through the UI.
- All new C# files follow existing namespace conventions: models in `Web_Backend.Areas.Admin.Models`, data-access interfaces/implementations in `Web_Backend.Areas.Admin.Data`, static helpers in `Web_Backend.Classes`.
- Every new/changed Razor markup matches the existing Tailwind utility classes and structure already used in `Index.cshtml` (rounded-xl inputs, `#7c3aed` accent, dark: variants, `data-confirm` delete forms) — no new CSS framework or design system.
- No `[Authorize]` attributes — this app has no ASP.NET Core auth middleware wired up; permission checks go through the same `Auth.CheckUser()`-style static-helper pattern already in `Web_Backend/Classes/Auth.cs`.

---

## File Structure

**New files:**
- `Database/migrations/0002_role_permissions.sql` — `usr.RolePermission`, `usr.UserPermissionOverride` tables + their stored procs + seeds Master Admin and gives existing `Admin`/other roles a default all-false grid (admin decides per role afterward).
- `Web_Backend/Areas/Admin/Models/PermissionModule.cs` — static list of module codes/labels (`Universities`, `UserManagement`, `EmailSettings`, `EmailTemplates`).
- `Web_Backend/Areas/Admin/Models/RolePermission.cs` — maps one `usr.RolePermission` row.
- `Web_Backend/Areas/Admin/Models/UserPermissionOverride.cs` — maps one `usr.UserPermissionOverride` row (nullable bools).
- `Web_Backend/Areas/Admin/Models/PermissionGridViewModel.cs` — one row per module with `CanView/CanAdd/CanEdit/CanDelete` (used both for the Role form's editable grid and the User form's override grid); shared by both.
- `Web_Backend/Areas/Admin/Data/IRolePermissionData.cs` / `RolePermissionData.cs` — CRUD against `usr.RolePermission`.
- `Web_Backend/Areas/Admin/Data/IUserPermissionOverrideData.cs` / `UserPermissionOverrideData.cs` — CRUD against `usr.UserPermissionOverride`.
- `Web_Backend/Classes/PermissionCode.cs` — the `const string` module keys, single source of truth shared by seed data, C#, and views.

**Modified files:**
- `Web_Backend/Classes/Auth.cs` — add `HasPermission(string moduleCode, char action)` computing effective permission (Master Admin short-circuit → override ?? role default), reading role defaults + overrides lazily per session (cached on `SessionUser`).
- `Web_Backend/Areas/Admin/Models/SessionUser.cs` — add `Dictionary<string, PermissionGridViewModel> Permissions` (or similar) populated at login so `Auth.HasPermission` doesn't hit the DB on every check.
- `Web_Backend/Areas/Admin/Models/RoleFormViewModel.cs` — add `List<PermissionGridViewModel> Permissions`.
- `Web_Backend/Areas/Admin/Models/AddUserViewModel.cs` / `EditUserViewModel.cs` — add `List<PermissionGridViewModel> PermissionOverrides` (nullable tri-state per checkbox: inherit/on/off).
- `Web_Backend/Areas/Admin/Controllers/AccountController.cs` — on successful login, load role permissions + build `SessionUser.Permissions` before `Auth.SignIn(...)`.
- `Web_Backend/Areas/Admin/Controllers/UserController.cs` — inject the two new data interfaces; populate/save permission grids in `AddRole`/`EditRole`/`Add`/`Edit`; guard Master Admin from edit/delete; gate every action with `Auth.CheckPermission(...)`.
- `Web_Backend/Areas/Admin/Controllers/UniversityController.cs`, `EmailSettingsController.cs`, `EmailTemplateController.cs` — add `Auth.CheckPermission(PermissionCode.X, 'V'|'A'|'E'|'D')` at the top of each action (view/list actions check View, Create actions check Add, Edit actions check Edit, Delete actions check Delete).
- `Web_Backend/Areas/Admin/Views/User/Index.cshtml` — add a permissions grid (checkbox table: modules × View/Add/Edit/Delete) to the Add/Edit Role form, and a read+override grid to the Add/Edit User form; disable/tick-lock everything when the role being edited is Master Admin.
- `Web_Backend/Areas/Admin/Views/Shared/_AdminLayout.cshtml` — filter each sidebar link by `Auth.HasPermission(moduleCode, 'V')` for the current session user.
- `Web_Backend/Program.cs` — register the two new data interfaces in DI.

---

## Task 1: Migration — permission tables, procs, and seed data

**Files:**
- Create: `Database/migrations/0002_role_permissions.sql`
- Test: manual run via `Database/tools/apply-migrations.ps1` against the local dev DB

**Interfaces:**
- Produces: tables `usr.RolePermission(UserTypeID, ModuleCode, CanView, CanAdd, CanEdit, CanDelete)` and `usr.UserPermissionOverride(UserID, ModuleCode, CanView, CanAdd, CanEdit, CanDelete)` (bit, nullable on the override table), stored procs `usr.RolePermission_List`, `usr.RolePermission_Get`, `usr.RolePermission_Save`, `usr.UserPermissionOverride_List`, `usr.UserPermissionOverride_Save`, and a seeded `usr.UserType` row `UserTypeID='MASTERADMIN'`.

- [ ] **Step 1: Write the migration file**

```sql
-- Adds role-based permission tables (View/Add/Edit/Delete per module) and a
-- per-user override layer, plus seeds the Master Admin role. Master Admin's
-- full access is also hardcoded in Auth.HasPermission (Web_Backend/Classes/
-- Auth.cs) — the seeded rows here are for display/consistency only; the
-- code path never actually reads them for that one role.
--
-- No USE statement — see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF SCHEMA_ID('usr') IS NULL EXEC('CREATE SCHEMA [usr]')
GO

-- ============================================================
-- Tables
-- ============================================================
IF OBJECT_ID('usr.RolePermission') IS NULL
BEGIN
    CREATE TABLE [usr].[RolePermission](
        [UserTypeID]  [varchar](20) NOT NULL,
        [ModuleCode]  [varchar](40) NOT NULL,
        [CanView]     [bit]         NOT NULL DEFAULT (0),
        [CanAdd]      [bit]         NOT NULL DEFAULT (0),
        [CanEdit]     [bit]         NOT NULL DEFAULT (0),
        [CanDelete]   [bit]         NOT NULL DEFAULT (0),
        CONSTRAINT [PK_usr_RolePermission] PRIMARY KEY CLUSTERED ([UserTypeID], [ModuleCode])
    )
END
GO

IF OBJECT_ID('usr.UserPermissionOverride') IS NULL
BEGIN
    CREATE TABLE [usr].[UserPermissionOverride](
        [UserID]      [varchar](50) NOT NULL,
        [ModuleCode]  [varchar](40) NOT NULL,
        -- NULL means "inherit the role's default for this module/action".
        [CanView]     [bit]         NULL,
        [CanAdd]      [bit]         NULL,
        [CanEdit]     [bit]         NULL,
        [CanDelete]   [bit]         NULL,
        CONSTRAINT [PK_usr_UserPermissionOverride] PRIMARY KEY CLUSTERED ([UserID], [ModuleCode])
    )
END
GO

-- ============================================================
-- Seed: Master Admin role (immutable; also hardcoded in Auth.cs)
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM usr.UserType WHERE UserTypeID = 'MASTERADMIN')
BEGIN
    INSERT INTO usr.UserType (UserTypeID, UserTypeName, Description, IsActive, CreatedDate)
    VALUES ('MASTERADMIN', 'Master Admin', 'Full access to every module. Cannot be edited or deleted.', 'A', GETDATE())
END
GO

-- ============================================================
-- Stored procedures — usr.RolePermission
-- ============================================================
IF OBJECT_ID('usr.RolePermission_List') IS NOT NULL DROP PROCEDURE usr.RolePermission_List
GO
CREATE PROCEDURE [usr].[RolePermission_List]
(
    @APIKey     VARCHAR(100),
    @UserTypeID VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT UserTypeID, ModuleCode, CanView, CanAdd, CanEdit, CanDelete
        FROM usr.RolePermission
        WHERE UserTypeID = @UserTypeID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: usr.RolePermission_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('usr.RolePermission_Save') IS NOT NULL DROP PROCEDURE usr.RolePermission_Save
GO
CREATE PROCEDURE [usr].[RolePermission_Save]
(
    @APIKey     VARCHAR(100),
    @UserTypeID VARCHAR(20),
    @ModuleCode VARCHAR(40),
    @CanView    BIT,
    @CanAdd     BIT,
    @CanEdit    BIT,
    @CanDelete  BIT,
    @LogUserID  VARCHAR(20) = '',
    @RetValue   VARCHAR(50) = '' OUT
)
AS
BEGIN
    SET NOCOUNT ON

    BEGIN TRY
        BEGIN TRANSACTION

        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        IF @UserTypeID = 'MASTERADMIN'
        BEGIN
            ;THROW 50000, 'Master Admin permissions cannot be changed', 1;
        END

        IF EXISTS (SELECT 1 FROM usr.RolePermission WHERE UserTypeID = @UserTypeID AND ModuleCode = @ModuleCode)
        BEGIN
            UPDATE usr.RolePermission
            SET CanView = @CanView, CanAdd = @CanAdd, CanEdit = @CanEdit, CanDelete = @CanDelete
            WHERE UserTypeID = @UserTypeID AND ModuleCode = @ModuleCode
        END
        ELSE
        BEGIN
            INSERT INTO usr.RolePermission (UserTypeID, ModuleCode, CanView, CanAdd, CanEdit, CanDelete)
            VALUES (@UserTypeID, @ModuleCode, @CanView, @CanAdd, @CanEdit, @CanDelete)
        END

        SET @RetValue = @UserTypeID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: usr.RolePermission_Save', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- Stored procedures — usr.UserPermissionOverride
-- ============================================================
IF OBJECT_ID('usr.UserPermissionOverride_List') IS NOT NULL DROP PROCEDURE usr.UserPermissionOverride_List
GO
CREATE PROCEDURE [usr].[UserPermissionOverride_List]
(
    @APIKey VARCHAR(100),
    @UserID VARCHAR(50)
)
AS
BEGIN
    SET NOCOUNT ON

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT UserID, ModuleCode, CanView, CanAdd, CanEdit, CanDelete
        FROM usr.UserPermissionOverride
        WHERE UserID = @UserID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: usr.UserPermissionOverride_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('usr.UserPermissionOverride_Save') IS NOT NULL DROP PROCEDURE usr.UserPermissionOverride_Save
GO
CREATE PROCEDURE [usr].[UserPermissionOverride_Save]
(
    @APIKey     VARCHAR(100),
    @UserID     VARCHAR(50),
    @ModuleCode VARCHAR(40),
    @CanView    BIT = NULL,
    @CanAdd     BIT = NULL,
    @CanEdit    BIT = NULL,
    @CanDelete  BIT = NULL,
    @LogUserID  VARCHAR(20) = '',
    @RetValue   VARCHAR(50) = '' OUT
)
AS
BEGIN
    SET NOCOUNT ON

    BEGIN TRY
        BEGIN TRANSACTION

        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        IF EXISTS (SELECT 1 FROM usr.UserPermissionOverride WHERE UserID = @UserID AND ModuleCode = @ModuleCode)
        BEGIN
            UPDATE usr.UserPermissionOverride
            SET CanView = @CanView, CanAdd = @CanAdd, CanEdit = @CanEdit, CanDelete = @CanDelete
            WHERE UserID = @UserID AND ModuleCode = @ModuleCode
        END
        ELSE
        BEGIN
            INSERT INTO usr.UserPermissionOverride (UserID, ModuleCode, CanView, CanAdd, CanEdit, CanDelete)
            VALUES (@UserID, @ModuleCode, @CanView, @CanAdd, @CanEdit, @CanDelete)
        END

        SET @RetValue = @UserID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: usr.UserPermissionOverride_Save', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
```

- [ ] **Step 2: Apply it to the local dev DB**

Run (from `Database/tools/`):
```powershell
./apply-migrations.ps1 -Server "VS-PW0C7J84\DUSHMAN001" -Database "Proton_Admin" -UserId "sa" -Password "vsdush*8902*#"
```
Expected output: `Applying 0002_role_permissions.sql...` then `Done.`

- [ ] **Step 3: Verify the objects exist**

Run against the same DB (via `sqlcmd` or SSMS):
```sql
SELECT * FROM usr.UserType WHERE UserTypeID = 'MASTERADMIN';
SELECT OBJECT_ID('usr.RolePermission_Save'), OBJECT_ID('usr.UserPermissionOverride_Save');
```
Expected: one row for Master Admin; both `OBJECT_ID` calls return non-null.

- [ ] **Step 4: Commit**

```bash
git add Database/migrations/0002_role_permissions.sql
git commit -m "Add role/user permission tables, procs, and Master Admin seed"
```

---

## Task 2: Permission module list and C# models

**Files:**
- Create: `Web_Backend/Classes/PermissionCode.cs`
- Create: `Web_Backend/Areas/Admin/Models/PermissionModule.cs`
- Create: `Web_Backend/Areas/Admin/Models/RolePermission.cs`
- Create: `Web_Backend/Areas/Admin/Models/UserPermissionOverride.cs`
- Create: `Web_Backend/Areas/Admin/Models/PermissionGridViewModel.cs`
- Test: `dotnet build` (no automated unit test project exists in this repo; verified by compilation + later integration steps)

**Interfaces:**
- Consumes: nothing new.
- Produces: `PermissionCode.All` (ordered `(string Code, string Label)[]`), `PermissionCode.Universities/UserManagement/EmailSettings/EmailTemplates` consts; `RolePermission { UserTypeID, ModuleCode, CanView, CanAdd, CanEdit, CanDelete }`; `UserPermissionOverride { UserID, ModuleCode, bool? CanView, bool? CanAdd, bool? CanEdit, bool? CanDelete }`; `PermissionGridViewModel { ModuleCode, ModuleLabel, bool? CanView, bool? CanAdd, bool? CanEdit, bool? CanDelete }` (used with non-null values for the Role grid, nullable tri-state for the User override grid).

- [ ] **Step 1: Create `PermissionCode.cs`**

```csharp
namespace Web_Backend.Classes
{
    // Single source of truth for admin module keys used by the permission
    // system — role defaults, user overrides, and the seed migration all key
    // off these exact strings. Add a new module here (and to All) whenever a
    // new admin controller needs its own View/Add/Edit/Delete gate.
    public static class PermissionCode
    {
        public const string Universities = "Universities";
        public const string UserManagement = "UserManagement";
        public const string EmailSettings = "EmailSettings";
        public const string EmailTemplates = "EmailTemplates";

        public static readonly (string Code, string Label)[] All =
        {
            (Universities, "Universities"),
            (UserManagement, "User Management"),
            (EmailSettings, "Email Settings"),
            (EmailTemplates, "Email Templates"),
        };
    }
}
```

- [ ] **Step 2: Create `PermissionModule.cs`**

```csharp
namespace Web_Backend.Areas.Admin.Models
{
    // One row of the module list paired with a role's or user's permission
    // flags — the shape PermissionGridViewModel builds on for both the Role
    // form (fixed booleans) and the User form (nullable tri-state overrides).
    public class PermissionModule
    {
        public string Code { get; set; } = "";
        public string Label { get; set; } = "";
    }
}
```

- [ ] **Step 3: Create `RolePermission.cs`**

```csharp
namespace Web_Backend.Areas.Admin.Models
{
    // Maps usr.RolePermission_List / usr.RolePermission_Save output.
    public class RolePermission
    {
        public string UserTypeID { get; set; } = "";
        public string ModuleCode { get; set; } = "";
        public bool CanView { get; set; }
        public bool CanAdd { get; set; }
        public bool CanEdit { get; set; }
        public bool CanDelete { get; set; }
    }
}
```

- [ ] **Step 4: Create `UserPermissionOverride.cs`**

```csharp
namespace Web_Backend.Areas.Admin.Models
{
    // Maps usr.UserPermissionOverride_List output. Null on any flag means
    // "inherit the role's default for this module/action" — only non-null
    // flags actually override anything.
    public class UserPermissionOverride
    {
        public string UserID { get; set; } = "";
        public string ModuleCode { get; set; } = "";
        public bool? CanView { get; set; }
        public bool? CanAdd { get; set; }
        public bool? CanEdit { get; set; }
        public bool? CanDelete { get; set; }
    }
}
```

- [ ] **Step 5: Create `PermissionGridViewModel.cs`**

```csharp
namespace Web_Backend.Areas.Admin.Models
{
    // One row per module in the permissions grid shown on both the Role form
    // (CanView/CanAdd/CanEdit/CanDelete always non-null — the role's actual
    // defaults) and the User form (any flag left null means "inherit from
    // the user's role" — only ticked/unticked flags become a per-user
    // override row in usr.UserPermissionOverride).
    public class PermissionGridViewModel
    {
        public string ModuleCode { get; set; } = "";
        public string ModuleLabel { get; set; } = "";
        public bool? CanView { get; set; }
        public bool? CanAdd { get; set; }
        public bool? CanEdit { get; set; }
        public bool? CanDelete { get; set; }

        public static List<PermissionGridViewModel> BuildFromRole(List<RolePermission> rolePermissions)
        {
            var byModule = rolePermissions.ToDictionary(p => p.ModuleCode);
            return PermissionCode.All.Select(m => new PermissionGridViewModel
            {
                ModuleCode = m.Code,
                ModuleLabel = m.Label,
                CanView = byModule.TryGetValue(m.Code, out var p) && p.CanView,
                CanAdd = byModule.TryGetValue(m.Code, out p) && p.CanAdd,
                CanEdit = byModule.TryGetValue(m.Code, out p) && p.CanEdit,
                CanDelete = byModule.TryGetValue(m.Code, out p) && p.CanDelete,
            }).ToList();
        }

        public static List<PermissionGridViewModel> BuildOverridesFromUser(List<UserPermissionOverride> overrides)
        {
            var byModule = overrides.ToDictionary(p => p.ModuleCode);
            return PermissionCode.All.Select(m => new PermissionGridViewModel
            {
                ModuleCode = m.Code,
                ModuleLabel = m.Label,
                CanView = byModule.TryGetValue(m.Code, out var p) ? p.CanView : null,
                CanAdd = byModule.TryGetValue(m.Code, out p) ? p.CanAdd : null,
                CanEdit = byModule.TryGetValue(m.Code, out p) ? p.CanEdit : null,
                CanDelete = byModule.TryGetValue(m.Code, out p) ? p.CanDelete : null,
            }).ToList();
        }
    }
}
```

- [ ] **Step 6: Build**

Run: `cd "Web_Backend" && dotnet build`
Expected: `Build succeeded. 0 Warning(s) 0 Error(s)`

- [ ] **Step 7: Commit**

```bash
git add Web_Backend/Classes/PermissionCode.cs Web_Backend/Areas/Admin/Models/PermissionModule.cs Web_Backend/Areas/Admin/Models/RolePermission.cs Web_Backend/Areas/Admin/Models/UserPermissionOverride.cs Web_Backend/Areas/Admin/Models/PermissionGridViewModel.cs
git commit -m "Add permission module list and permission grid models"
```

---

## Task 3: Data-access layer for permissions

**Files:**
- Create: `Web_Backend/Areas/Admin/Data/IRolePermissionData.cs`
- Create: `Web_Backend/Areas/Admin/Data/RolePermissionData.cs`
- Create: `Web_Backend/Areas/Admin/Data/IUserPermissionOverrideData.cs`
- Create: `Web_Backend/Areas/Admin/Data/UserPermissionOverrideData.cs`
- Modify: `Web_Backend/Program.cs`

**Interfaces:**
- Consumes: `RolePermission`, `UserPermissionOverride` (Task 2); `IDBAccess` (`DBAccess/IDBAccess.cs`); `AppData.GetAPIKey()` (`Web_Backend/Classes/AppData.cs`).
- Produces: `IRolePermissionData.GetForRole(string userTypeId)`, `IRolePermissionData.Save(RolePermission permission)`; `IUserPermissionOverrideData.GetForUser(string userId)`, `IUserPermissionOverrideData.Save(UserPermissionOverride ov)`. Both registered in DI so controllers can inject them.

- [ ] **Step 1: Create `IRolePermissionData.cs`**

```csharp
using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IRolePermissionData
    {
        Task<List<RolePermission>> GetForRole(string userTypeId);
        Task Save(RolePermission permission);
    }
}
```

- [ ] **Step 2: Create `RolePermissionData.cs`**

```csharp
using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class RolePermissionData : IRolePermissionData
    {
        private readonly IDBAccess db;

        public RolePermissionData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<List<RolePermission>> GetForRole(string userTypeId) =>
            db.GetList<RolePermission, object>("usr.RolePermission_List", new
            {
                APIKey = AppData.GetAPIKey(),
                UserTypeID = userTypeId
            });

        public Task Save(RolePermission permission) =>
            db.ExecuteNonQuery("usr.RolePermission_Save", new
            {
                APIKey = AppData.GetAPIKey(),
                permission.UserTypeID,
                permission.ModuleCode,
                permission.CanView,
                permission.CanAdd,
                permission.CanEdit,
                permission.CanDelete
            });
    }
}
```

- [ ] **Step 3: Create `IUserPermissionOverrideData.cs`**

```csharp
using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IUserPermissionOverrideData
    {
        Task<List<UserPermissionOverride>> GetForUser(string userId);
        Task Save(UserPermissionOverride ov);
    }
}
```

- [ ] **Step 4: Create `UserPermissionOverrideData.cs`**

```csharp
using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class UserPermissionOverrideData : IUserPermissionOverrideData
    {
        private readonly IDBAccess db;

        public UserPermissionOverrideData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<List<UserPermissionOverride>> GetForUser(string userId) =>
            db.GetList<UserPermissionOverride, object>("usr.UserPermissionOverride_List", new
            {
                APIKey = AppData.GetAPIKey(),
                UserID = userId
            });

        public Task Save(UserPermissionOverride ov) =>
            db.ExecuteNonQuery("usr.UserPermissionOverride_Save", new
            {
                APIKey = AppData.GetAPIKey(),
                ov.UserID,
                ov.ModuleCode,
                ov.CanView,
                ov.CanAdd,
                ov.CanEdit,
                ov.CanDelete
            });
    }
}
```

- [ ] **Step 5: Register both in `Program.cs`**

Find this block in `Web_Backend/Program.cs`:
```csharp
builder.Services.AddTransient<IUniversityData, UniversityData>();
```
Add immediately after it:
```csharp
builder.Services.AddTransient<IUniversityData, UniversityData>();
builder.Services.AddTransient<IRolePermissionData, RolePermissionData>();
builder.Services.AddTransient<IUserPermissionOverrideData, UserPermissionOverrideData>();
```

- [ ] **Step 6: Build**

Run: `cd "Web_Backend" && dotnet build`
Expected: `Build succeeded. 0 Warning(s) 0 Error(s)`

- [ ] **Step 7: Commit**

```bash
git add Web_Backend/Areas/Admin/Data/IRolePermissionData.cs Web_Backend/Areas/Admin/Data/RolePermissionData.cs Web_Backend/Areas/Admin/Data/IUserPermissionOverrideData.cs Web_Backend/Areas/Admin/Data/UserPermissionOverrideData.cs Web_Backend/Program.cs
git commit -m "Add permission data-access classes and register them in DI"
```

---

## Task 4: Auth.HasPermission + SessionUser permission cache + login wiring

**Files:**
- Modify: `Web_Backend/Areas/Admin/Models/SessionUser.cs`
- Modify: `Web_Backend/Classes/Auth.cs`
- Modify: `Web_Backend/Areas/Admin/Controllers/AccountController.cs`

**Interfaces:**
- Consumes: `IRolePermissionData.GetForRole` and `IUserPermissionOverrideData.GetForUser` (Task 3), `PermissionGridViewModel.BuildFromRole`/`BuildOverridesFromUser` (Task 2), `PermissionCode` (Task 2).
- Produces: `SessionUser.Permissions` (`Dictionary<string, PermissionGridViewModel>` keyed by module code, effective — already merged override-over-role); `Auth.HasPermission(string moduleCode, char action)` where `action` is `'V'|'A'|'E'|'D'`; `Auth.CheckPermission(string moduleCode, char action)` (throws `UnauthorizedAccessException` like `Auth.CheckUser()` does, for controllers to call the same way).

- [ ] **Step 1: Add `Permissions` to `SessionUser.cs`**

```csharp
namespace Web_Backend.Areas.Admin.Models
{
    public class SessionUser
    {
        public string Id { get; set; } = "";
        public string Name { get; set; } = "";
        public string Email { get; set; } = "";
        public string Role { get; set; } = "";

        // Effective permissions (role default with any per-user override
        // already applied), computed once at sign-in — see AccountController
        // and Auth.HasPermission. Keyed by PermissionCode module string.
        public Dictionary<string, PermissionGridViewModel> Permissions { get; set; } = new();
    }
}
```

- [ ] **Step 2: Add `HasPermission`/`CheckPermission` to `Auth.cs`**

Replace the whole file with:
```csharp
using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Classes
{
    // Session-based auth helper, checked at the top of each controller action.
    // Mirrors the LMS reference project's static Auth.CheckUser()/CheckUserRole()
    // pattern instead of [Authorize]/cookie authentication middleware.
    public static class Auth
    {
        // Matches the seeded UserTypeID in Database/migrations/0002_role_permissions.sql.
        // Hardcoded here (not just seeded with all-true rows) so full access
        // can never be revoked by editing the database directly.
        public const string MasterAdminRoleId = "MASTERADMIN";

        private static IHttpContextAccessor _accessor = null!;

        public static void Initialize(IHttpContextAccessor accessor)
        {
            _accessor = accessor;
        }

        private static ISession Session => _accessor.HttpContext!.Session;

        public static void SignIn(SessionUser user)
        {
            Session.SetObject("CurrentUser", user);
        }

        public static void SignOut()
        {
            Session.Clear();
        }

        public static SessionUser? GetUser() => Session.GetObject<SessionUser>("CurrentUser");

        public static string GetUserId() => GetUser()?.Id ?? "";

        public static bool IsLoggedIn() => GetUser() != null;

        // Throws to short-circuit the action; caught by the global exception
        // middleware / redirected via a filter. Kept intentionally simple
        // (no DB-backed roles yet) until real accounts exist.
        public static void CheckUser()
        {
            if (!IsLoggedIn())
                throw new UnauthorizedAccessException("Not logged in.");
        }

        public static void CheckUserRole(string role)
        {
            CheckUser();
            var user = GetUser();
            if (user?.Role != role)
                throw new UnauthorizedAccessException($"Requires role: {role}");
        }

        // action: 'V' = View, 'A' = Add, 'E' = Edit, 'D' = Delete.
        // Master Admin always returns true, regardless of what's stored —
        // that role's access can't be narrowed by editing the database.
        public static bool HasPermission(string moduleCode, char action)
        {
            var user = GetUser();
            if (user == null) return false;
            if (user.Role == MasterAdminRoleId) return true;

            if (!user.Permissions.TryGetValue(moduleCode, out var grid)) return false;

            return action switch
            {
                'V' => grid.CanView ?? false,
                'A' => grid.CanAdd ?? false,
                'E' => grid.CanEdit ?? false,
                'D' => grid.CanDelete ?? false,
                _ => false
            };
        }

        public static void CheckPermission(string moduleCode, char action)
        {
            CheckUser();
            if (!HasPermission(moduleCode, action))
                throw new UnauthorizedAccessException($"Missing '{action}' permission for module '{moduleCode}'.");
        }
    }
}
```

- [ ] **Step 3: Build effective permissions at login in `AccountController.cs`**

First read the file to find the exact login success block:

Run: `Grep -n "Auth.SignIn" "Web_Backend/Areas/Admin/Controllers/AccountController.cs"`

Then, immediately before the `Auth.SignIn(new SessionUser { ... })` call, insert the permission-building logic. Inject `IRolePermissionData` and `IUserPermissionOverrideData` into the controller's constructor (alongside its existing dependencies), then build the effective grid like this before constructing `SessionUser`:

```csharp
var rolePermissions = await rolePermissionRep.GetForRole(user.UserTypeID);
var overrides = await userPermissionOverrideRep.GetForUser(user.UserID);
var overrideByModule = overrides.ToDictionary(o => o.ModuleCode);

var effective = PermissionCode.All.ToDictionary(
    m => m.Code,
    m =>
    {
        var role = rolePermissions.FirstOrDefault(p => p.ModuleCode == m.Code);
        var ov = overrideByModule.TryGetValue(m.Code, out var o) ? o : null;
        return new PermissionGridViewModel
        {
            ModuleCode = m.Code,
            ModuleLabel = m.Label,
            CanView = ov?.CanView ?? role?.CanView ?? false,
            CanAdd = ov?.CanAdd ?? role?.CanAdd ?? false,
            CanEdit = ov?.CanEdit ?? role?.CanEdit ?? false,
            CanDelete = ov?.CanDelete ?? role?.CanDelete ?? false,
        };
    });
```

Then add `Permissions = effective` to the `SessionUser` object literal being passed to `Auth.SignIn(...)`. Add `using Web_Backend.Classes;` at the top of the file if not already present (for `PermissionCode`).

- [ ] **Step 4: Build**

Run: `cd "Web_Backend" && dotnet build`
Expected: `Build succeeded. 0 Warning(s) 0 Error(s)`

- [ ] **Step 5: Manual login smoke test**

Run: `dotnet run --urls "http://localhost:5080"` (from `Web_Backend/`), then log in as any existing user via the browser at `http://localhost:5080/Admin/Account/Login`.
Expected: login succeeds with no server error (permissions dictionary is empty/all-false for that role until Task 6 lets an admin tick boxes — that's fine, nothing enforces permissions yet until Task 7).

- [ ] **Step 6: Commit**

```bash
git add Web_Backend/Areas/Admin/Models/SessionUser.cs Web_Backend/Classes/Auth.cs Web_Backend/Areas/Admin/Controllers/AccountController.cs
git commit -m "Compute effective role+override permissions at login"
```

---

## Task 5: Role form — permissions grid (create/edit/save)

**Files:**
- Modify: `Web_Backend/Areas/Admin/Models/RoleFormViewModel.cs`
- Modify: `Web_Backend/Areas/Admin/Controllers/UserController.cs`
- Modify: `Web_Backend/Areas/Admin/Views/User/Index.cshtml`

**Interfaces:**
- Consumes: `IRolePermissionData` (Task 3), `PermissionGridViewModel.BuildFromRole` (Task 2), `Auth.MasterAdminRoleId` (Task 4).
- Produces: `RoleFormViewModel.Permissions` (`List<PermissionGridViewModel>`) populated on `AddRole`/`EditRole` GET, bound and saved on POST; `POST AddRole`/`EditRole` now also calls `rolePermissionRep.Save(...)` once per module row.

- [ ] **Step 1: Add `Permissions` to `RoleFormViewModel.cs`**

```csharp
using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.Admin.Models
{
    public class RoleFormViewModel
    {
        public string UserTypeID { get; set; } = "";

        [Required]
        public string UserTypeName { get; set; } = "";

        public string Description { get; set; } = "";

        public bool IsActive { get; set; } = true;

        public List<PermissionGridViewModel> Permissions { get; set; } = new();
    }
}
```

- [ ] **Step 2: Inject `IRolePermissionData` into `UserController`**

In `Web_Backend/Areas/Admin/Controllers/UserController.cs`, change the constructor:
```csharp
private readonly IUserData userRep;
private readonly IUserAuthData authRep;
private readonly IUserTypeData userTypeRep;
private readonly IEmailSender emailSender;
private readonly IRolePermissionData rolePermissionRep;
private readonly IUserPermissionOverrideData userPermissionOverrideRep;

public UserController(IUserData userRep, IUserAuthData authRep, IUserTypeData userTypeRep,
    IEmailSender emailSender, IRolePermissionData rolePermissionRep, IUserPermissionOverrideData userPermissionOverrideRep)
{
    this.userRep = userRep;
    this.authRep = authRep;
    this.userTypeRep = userTypeRep;
    this.emailSender = emailSender;
    this.rolePermissionRep = rolePermissionRep;
    this.userPermissionOverrideRep = userPermissionOverrideRep;
}
```

- [ ] **Step 3: Populate `Permissions` on `AddRole` GET and default to all-false for a new role**

Replace:
```csharp
[HttpGet]
public async Task<IActionResult> AddRole()
{
    Auth.CheckUser();
    ViewBag.CurrentUser = Auth.GetUser();
    var model = new UserManagementViewModel { ActiveTab = "addRole", RoleForm = new RoleFormViewModel() };
    await PopulateLists(model);
    return View("Index", model);
}
```
with:
```csharp
[HttpGet]
public async Task<IActionResult> AddRole()
{
    Auth.CheckUser();
    ViewBag.CurrentUser = Auth.GetUser();
    var model = new UserManagementViewModel
    {
        ActiveTab = "addRole",
        RoleForm = new RoleFormViewModel
        {
            Permissions = PermissionCode.All.Select(m => new PermissionGridViewModel
            {
                ModuleCode = m.Code,
                ModuleLabel = m.Label,
                CanView = false,
                CanAdd = false,
                CanEdit = false,
                CanDelete = false
            }).ToList()
        }
    };
    await PopulateLists(model);
    return View("Index", model);
}
```
Add `using Web_Backend.Classes;` at the top of the file if not already present.

- [ ] **Step 4: Save permission rows on `AddRole` POST**

In the `AddRole` POST action, after the existing `await userTypeRep.AddEdit(new UserType { ... });` call and before `TempData["SuccessMessage"] = ...`, the new role's ID is needed — `AddEdit` returns it. Change:
```csharp
await userTypeRep.AddEdit(new UserType
{
    UserTypeName = form.UserTypeName,
    Description = form.Description,
    IsActive = form.IsActive ? "A" : "I"
});

TempData["SuccessMessage"] = $"Role '{form.UserTypeName}' created.";
```
to:
```csharp
var newRoleId = await userTypeRep.AddEdit(new UserType
{
    UserTypeName = form.UserTypeName,
    Description = form.Description,
    IsActive = form.IsActive ? "A" : "I"
});

foreach (var module in form.Permissions)
{
    await rolePermissionRep.Save(new RolePermission
    {
        UserTypeID = newRoleId,
        ModuleCode = module.ModuleCode,
        CanView = module.CanView ?? false,
        CanAdd = module.CanAdd ?? false,
        CanEdit = module.CanEdit ?? false,
        CanDelete = module.CanDelete ?? false
    });
}

TempData["SuccessMessage"] = $"Role '{form.UserTypeName}' created.";
```

Also update the two `if (!ModelState.IsValid)` re-render blocks in both `AddRole` POST and `EditRole` POST (see next steps) — they already pass `form` straight through as `RoleForm = form`, and since `form.Permissions` round-trips via model binding (Step 6 covers the binding-friendly view markup), no extra code is needed there.

- [ ] **Step 5: Populate `Permissions` on `EditRole` GET, and block editing Master Admin**

Replace:
```csharp
[HttpGet]
public async Task<IActionResult> EditRole(string id)
{
    Auth.CheckUser();
    ViewBag.CurrentUser = Auth.GetUser();

    var role = await userTypeRep.Get(id);
    if (role == null) return RedirectToAction("Index", new { tab = "roles" });

    var model = new UserManagementViewModel
    {
        ActiveTab = "editRole",
        RoleForm = new RoleFormViewModel
        {
            UserTypeID = role.UserTypeID,
            UserTypeName = role.UserTypeName,
            Description = role.Description,
            IsActive = role.IsActive == "A"
        }
    };
    await PopulateLists(model);
    return View("Index", model);
}
```
with:
```csharp
[HttpGet]
public async Task<IActionResult> EditRole(string id)
{
    Auth.CheckUser();
    ViewBag.CurrentUser = Auth.GetUser();

    var role = await userTypeRep.Get(id);
    if (role == null) return RedirectToAction("Index", new { tab = "roles" });

    var rolePermissions = await rolePermissionRep.GetForRole(id);
    var permissionGrid = id == Auth.MasterAdminRoleId
        ? PermissionCode.All.Select(m => new PermissionGridViewModel
        {
            ModuleCode = m.Code,
            ModuleLabel = m.Label,
            CanView = true,
            CanAdd = true,
            CanEdit = true,
            CanDelete = true
        }).ToList()
        : PermissionGridViewModel.BuildFromRole(rolePermissions);

    var model = new UserManagementViewModel
    {
        ActiveTab = "editRole",
        RoleForm = new RoleFormViewModel
        {
            UserTypeID = role.UserTypeID,
            UserTypeName = role.UserTypeName,
            Description = role.Description,
            IsActive = role.IsActive == "A",
            Permissions = permissionGrid
        }
    };
    await PopulateLists(model);
    return View("Index", model);
}
```

- [ ] **Step 6: Block saving/deleting Master Admin in `EditRole` POST and `DeleteRole`**

At the top of the `EditRole` POST action body (right after `ViewBag.CurrentUser = Auth.GetUser();`), add:
```csharp
if (form.UserTypeID == Auth.MasterAdminRoleId)
{
    TempData["ErrorMessage"] = "The Master Admin role can't be changed.";
    return RedirectToAction("Index", new { tab = "roles" });
}
```
Then, after the existing `await userTypeRep.AddEdit(...)` call in the same action, add the same permission-save loop as Step 4 (using `form.UserTypeID` instead of `newRoleId`):
```csharp
await userTypeRep.AddEdit(new UserType
{
    UserTypeID = form.UserTypeID,
    UserTypeName = form.UserTypeName,
    Description = form.Description,
    IsActive = form.IsActive ? "A" : "I"
});

foreach (var module in form.Permissions)
{
    await rolePermissionRep.Save(new RolePermission
    {
        UserTypeID = form.UserTypeID,
        ModuleCode = module.ModuleCode,
        CanView = module.CanView ?? false,
        CanAdd = module.CanAdd ?? false,
        CanEdit = module.CanEdit ?? false,
        CanDelete = module.CanDelete ?? false
    });
}

TempData["SuccessMessage"] = $"Role '{form.UserTypeName}' updated.";
```

In `DeleteRole`, replace the existing Admin-name check:
```csharp
var role = await userTypeRep.Get(id);
if (role != null && role.UserTypeName.Equals(AdminRoleName, StringComparison.OrdinalIgnoreCase))
{
    TempData["ErrorMessage"] = "The Admin role can't be removed.";
    return RedirectToAction("Index", new { tab = "roles" });
}
```
with:
```csharp
if (id == Auth.MasterAdminRoleId)
{
    TempData["ErrorMessage"] = "The Master Admin role can't be removed.";
    return RedirectToAction("Index", new { tab = "roles" });
}

var role = await userTypeRep.Get(id);
if (role != null && role.UserTypeName.Equals(AdminRoleName, StringComparison.OrdinalIgnoreCase))
{
    TempData["ErrorMessage"] = "The Admin role can't be removed.";
    return RedirectToAction("Index", new { tab = "roles" });
}
```
(Keeps the existing "Admin" guard as-is — it's a separate, already-seeded role — and adds the Master Admin guard alongside it.)

- [ ] **Step 7: Add the permissions grid markup to the Role form in `Index.cshtml`**

In `Web_Backend/Areas/Admin/Views/User/Index.cshtml`, inside the `else` branch that renders the Role form (right after the "Description" `<textarea>` block and before the "Active" checkbox `<label>`), insert:
```html
<div class="space-y-2">
    <label class="text-sm font-medium text-slate-700 dark:text-slate-300">Permissions</label>
    @{ var isMasterAdminRole = roleForm.UserTypeID == "MASTERADMIN"; }
    @if (isMasterAdminRole)
    {
        <p class="text-xs text-slate-500 dark:text-slate-400">Master Admin always has full access to every module — this can't be changed.</p>
    }
    <div class="overflow-x-auto rounded-xl border border-slate-200 dark:border-slate-600">
        <table class="w-full text-left border-collapse">
            <thead>
                <tr class="bg-slate-50 dark:bg-slate-800 text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider">
                    <th class="px-4 py-3">Module</th>
                    <th class="px-4 py-3 text-center">View</th>
                    <th class="px-4 py-3 text-center">Add</th>
                    <th class="px-4 py-3 text-center">Edit</th>
                    <th class="px-4 py-3 text-center">Delete</th>
                </tr>
            </thead>
            <tbody class="divide-y divide-slate-100 dark:divide-slate-700">
                @for (var i = 0; i < roleForm.Permissions.Count; i++)
                {
                    var row = roleForm.Permissions[i];
                    <tr>
                        <td class="px-4 py-3 text-sm font-medium text-slate-700 dark:text-slate-200">
                            @row.ModuleLabel
                            <input type="hidden" name="Permissions[@i].ModuleCode" value="@row.ModuleCode" />
                            <input type="hidden" name="Permissions[@i].ModuleLabel" value="@row.ModuleLabel" />
                        </td>
                        <td class="px-4 py-3 text-center">
                            <input type="checkbox" name="Permissions[@i].CanView" value="true" checked="@(row.CanView ?? isMasterAdminRole)" disabled="@isMasterAdminRole"
                                   class="rounded border-slate-300 dark:border-slate-600 text-[#7c3aed] focus:ring-[#7c3aed]" />
                        </td>
                        <td class="px-4 py-3 text-center">
                            <input type="checkbox" name="Permissions[@i].CanAdd" value="true" checked="@(row.CanAdd ?? isMasterAdminRole)" disabled="@isMasterAdminRole"
                                   class="rounded border-slate-300 dark:border-slate-600 text-[#7c3aed] focus:ring-[#7c3aed]" />
                        </td>
                        <td class="px-4 py-3 text-center">
                            <input type="checkbox" name="Permissions[@i].CanEdit" value="true" checked="@(row.CanEdit ?? isMasterAdminRole)" disabled="@isMasterAdminRole"
                                   class="rounded border-slate-300 dark:border-slate-600 text-[#7c3aed] focus:ring-[#7c3aed]" />
                        </td>
                        <td class="px-4 py-3 text-center">
                            <input type="checkbox" name="Permissions[@i].CanDelete" value="true" checked="@(row.CanDelete ?? isMasterAdminRole)" disabled="@isMasterAdminRole"
                                   class="rounded border-slate-300 dark:border-slate-600 text-[#7c3aed] focus:ring-[#7c3aed]" />
                        </td>
                    </tr>
                }
            </tbody>
        </table>
    </div>
</div>
```
Note: a `disabled` checkbox does not submit its value in the form POST, so Master Admin's grid — even if a request were crafted client-side — is never actually saved for that role anyway (belt-and-suspenders on top of the server-side `EditRole` POST guard from Step 6, which redirects before any save happens).

- [ ] **Step 8: Also disable the Delete-role button and hide the Edit form's save button intent for Master Admin in the Roles list table**

In the same file, in the ROLES PANE table body, change:
```csharp
var isAdminRole = role.UserTypeName.Equals("Admin", StringComparison.OrdinalIgnoreCase);
```
to:
```csharp
var isAdminRole = role.UserTypeName.Equals("Admin", StringComparison.OrdinalIgnoreCase) || role.UserTypeID == "MASTERADMIN";
```
This reuses the existing "Protected" badge and hidden delete-button logic already keyed off `isAdminRole` further down in that same block — no other markup changes needed.

- [ ] **Step 9: Build and manually verify**

Run: `cd "Web_Backend" && dotnet build`
Expected: `Build succeeded. 0 Warning(s) 0 Error(s)`

Then run the app (`dotnet run --urls "http://localhost:5080"`), log in, go to User Management → Roles & Permissions:
1. Click "Add Role", tick a few View/Add checkboxes for two different modules, save. Expected: redirected to the roles list with a success toast.
2. Click Edit on that new role — expected: the same checkboxes you ticked are still ticked.
3. Click Edit on "Master Admin" — expected: every checkbox is ticked and disabled, with the "always has full access" note visible; there is no Delete button for that row in the list.

- [ ] **Step 10: Commit**

```bash
git add Web_Backend/Areas/Admin/Models/RoleFormViewModel.cs Web_Backend/Areas/Admin/Controllers/UserController.cs Web_Backend/Areas/Admin/Views/User/Index.cshtml
git commit -m "Add permissions grid to the Role add/edit form"
```

---

## Task 6: User form — view role permissions + per-user override grid

**Files:**
- Modify: `Web_Backend/Areas/Admin/Models/AddUserViewModel.cs`
- Modify: `Web_Backend/Areas/Admin/Models/EditUserViewModel.cs`
- Modify: `Web_Backend/Areas/Admin/Controllers/UserController.cs`
- Modify: `Web_Backend/Areas/Admin/Views/User/Index.cshtml`

**Interfaces:**
- Consumes: `IUserPermissionOverrideData` (Task 3), `IRolePermissionData` (Task 3), `PermissionGridViewModel.BuildFromRole`/`BuildOverridesFromUser` (Task 2).
- Produces: `AddUserViewModel.PermissionOverrides` / `EditUserViewModel.PermissionOverrides` (`List<PermissionGridViewModel>`, tri-state); saved into `usr.UserPermissionOverride` only for rows where the admin actually touched a checkbox away from "inherit."

- [ ] **Step 1: Add `PermissionOverrides` to `AddUserViewModel.cs`**

```csharp
using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.Admin.Models
{
    public class AddUserViewModel
    {
        [Required]
        public string FirstName { get; set; } = "";

        [Required]
        public string LastName { get; set; } = "";

        [Required, EmailAddress]
        public string Email { get; set; } = "";

        public string Role { get; set; } = "Student";

        public List<PermissionGridViewModel> PermissionOverrides { get; set; } = new();
    }
}
```

- [ ] **Step 2: Add `PermissionOverrides` to `EditUserViewModel.cs`**

```csharp
using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.Admin.Models
{
    public class EditUserViewModel
    {
        [Required]
        public string UserID { get; set; } = "";

        [Required]
        public string FirstName { get; set; } = "";

        [Required]
        public string LastName { get; set; } = "";

        [Required, EmailAddress]
        public string Email { get; set; } = "";

        public string Role { get; set; } = "";

        public bool IsActive { get; set; } = true;

        public List<PermissionGridViewModel> PermissionOverrides { get; set; } = new();
    }
}
```

- [ ] **Step 3: Populate an empty (all-inherit) override grid on `Add` GET**

In `UserController.cs`, replace:
```csharp
[HttpGet]
public async Task<IActionResult> Add()
{
    Auth.CheckUser();
    ViewBag.CurrentUser = Auth.GetUser();
    var model = new UserManagementViewModel { ActiveTab = "addUser", AddUserForm = new AddUserViewModel() };
    await PopulateLists(model);
    return View("Index", model);
}
```
with:
```csharp
[HttpGet]
public async Task<IActionResult> Add()
{
    Auth.CheckUser();
    ViewBag.CurrentUser = Auth.GetUser();
    var model = new UserManagementViewModel
    {
        ActiveTab = "addUser",
        AddUserForm = new AddUserViewModel
        {
            PermissionOverrides = PermissionCode.All.Select(m => new PermissionGridViewModel
            {
                ModuleCode = m.Code,
                ModuleLabel = m.Label
            }).ToList()
        }
    };
    await PopulateLists(model);
    return View("Index", model);
}
```
(No `CanView`/etc. assigned — they default to `null`, meaning "inherit from role," which the view resolves against the currently-selected role's defaults via JS in Step 7.)

- [ ] **Step 4: Save override rows on `Add` POST**

In the `Add` POST action, after the existing:
```csharp
var tempPassword = GenerateTempPassword();
var (hash, salt) = PasswordHasher.Hash(tempPassword);
await authRep.AddEdit("", userId, form.Email, form.Email, hash, salt);
```
insert:
```csharp
foreach (var module in form.PermissionOverrides.Where(m => m.CanView != null || m.CanAdd != null || m.CanEdit != null || m.CanDelete != null))
{
    await userPermissionOverrideRep.Save(new UserPermissionOverride
    {
        UserID = userId,
        ModuleCode = module.ModuleCode,
        CanView = module.CanView,
        CanAdd = module.CanAdd,
        CanEdit = module.CanEdit,
        CanDelete = module.CanDelete
    });
}
```
(Only modules where at least one checkbox was actually touched get a row — everything else stays "inherit from role" implicitly, by having no row at all.)

- [ ] **Step 5: Populate the override grid (existing overrides + role defaults for display) on `Edit` GET**

Replace:
```csharp
[HttpGet]
public async Task<IActionResult> Edit(string id)
{
    Auth.CheckUser();
    ViewBag.CurrentUser = Auth.GetUser();

    var user = await userRep.Get(id);
    if (user == null) return RedirectToAction("Index", new { tab = "users" });

    var model = new UserManagementViewModel
    {
        ActiveTab = "editUser",
        EditUserForm = new EditUserViewModel
        {
            UserID = user.UserID,
            FirstName = user.FirstName,
            LastName = user.LastName,
            Email = user.Email,
            Role = user.UserTypeID,
            IsActive = user.IsActive == "A"
        }
    };
    await PopulateLists(model);
    return View("Index", model);
}
```
with:
```csharp
[HttpGet]
public async Task<IActionResult> Edit(string id)
{
    Auth.CheckUser();
    ViewBag.CurrentUser = Auth.GetUser();

    var user = await userRep.Get(id);
    if (user == null) return RedirectToAction("Index", new { tab = "users" });

    var overrides = await userPermissionOverrideRep.GetForUser(id);

    var model = new UserManagementViewModel
    {
        ActiveTab = "editUser",
        EditUserForm = new EditUserViewModel
        {
            UserID = user.UserID,
            FirstName = user.FirstName,
            LastName = user.LastName,
            Email = user.Email,
            Role = user.UserTypeID,
            IsActive = user.IsActive == "A",
            PermissionOverrides = PermissionGridViewModel.BuildOverridesFromUser(overrides)
        }
    };
    await PopulateLists(model);

    // The view resolves "inherit" cells against the selected role's defaults
    // client-side (Step 7), keyed by UserTypeID — ship every role's grid so
    // the picker can switch roles without a round-trip.
    var allRolePermissions = new Dictionary<string, List<PermissionGridViewModel>>();
    foreach (var role in model.Roles)
    {
        var rp = role.UserTypeID == Auth.MasterAdminRoleId
            ? PermissionCode.All.Select(m => new PermissionGridViewModel { ModuleCode = m.Code, ModuleLabel = m.Label, CanView = true, CanAdd = true, CanEdit = true, CanDelete = true }).ToList()
            : PermissionGridViewModel.BuildFromRole(await rolePermissionRep.GetForRole(role.UserTypeID));
        allRolePermissions[role.UserTypeID] = rp;
    }
    ViewBag.RolePermissionsByRole = allRolePermissions;

    return View("Index", model);
}
```

- [ ] **Step 6: Save override rows on `Edit` POST**

In the `Edit` POST action, after the existing:
```csharp
await userRep.AddEdit(new AppUser
{
    UserID = form.UserID,
    FullName = $"{form.FirstName} {form.LastName}".Trim(),
    FirstName = form.FirstName,
    LastName = form.LastName,
    Email = form.Email,
    UserTypeID = form.Role,
    IsActive = form.IsActive ? "A" : "I"
});
```
insert:
```csharp
foreach (var module in form.PermissionOverrides)
{
    await userPermissionOverrideRep.Save(new UserPermissionOverride
    {
        UserID = form.UserID,
        ModuleCode = module.ModuleCode,
        CanView = module.CanView,
        CanAdd = module.CanAdd,
        CanEdit = module.CanEdit,
        CanDelete = module.CanDelete
    });
}
```
(Every module row is saved here, including all-null ones, which is fine — an all-null row means "inherit everything," equivalent to no override; simpler than Step 4's Add-time filtering since this path already has a full round-tripped list from the form.)

- [ ] **Step 7: Add the role-permissions preview + override grid markup to the User form in `Index.cshtml`**

In `Web_Backend/Areas/Admin/Views/User/Index.cshtml`, inside the `@if (Model.ActiveTab is "addUser" or "editUser")` block, right after the closing `</div>` of the "Assign Role" block (the one with the radio buttons) and before the `@if (isEdit) { ... Active checkbox ... }` block, insert:
```html
<div class="space-y-2">
    <label class="text-sm font-medium text-slate-700 dark:text-slate-300">Permissions</label>
    <p class="text-xs text-slate-500 dark:text-slate-400">
        Shows what the selected role grants. Tick or untick any box to override it for this user only — leave a box as-is to keep inheriting from the role.
    </p>
    @{
        var overrides = isEdit ? Model.EditUserForm!.PermissionOverrides : Model.AddUserForm!.PermissionOverrides;
        var rolePermissionsByRole = ViewBag.RolePermissionsByRole as Dictionary<string, List<PermissionGridViewModel>> ?? new();
    }
    <div class="overflow-x-auto rounded-xl border border-slate-200 dark:border-slate-600">
        <table class="w-full text-left border-collapse" id="user-permission-grid" data-role-defaults="@Html.Raw(System.Text.Json.JsonSerializer.Serialize(rolePermissionsByRole))">
            <thead>
                <tr class="bg-slate-50 dark:bg-slate-800 text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider">
                    <th class="px-4 py-3">Module</th>
                    <th class="px-4 py-3 text-center">View</th>
                    <th class="px-4 py-3 text-center">Add</th>
                    <th class="px-4 py-3 text-center">Edit</th>
                    <th class="px-4 py-3 text-center">Delete</th>
                </tr>
            </thead>
            <tbody class="divide-y divide-slate-100 dark:divide-slate-700">
                @for (var i = 0; i < overrides.Count; i++)
                {
                    var row = overrides[i];
                    <tr data-module="@row.ModuleCode">
                        <td class="px-4 py-3 text-sm font-medium text-slate-700 dark:text-slate-200">
                            @row.ModuleLabel
                            <input type="hidden" name="PermissionOverrides[@i].ModuleCode" value="@row.ModuleCode" />
                            <input type="hidden" name="PermissionOverrides[@i].ModuleLabel" value="@row.ModuleLabel" />
                        </td>
                        @foreach (var action in new[] { "CanView", "CanAdd", "CanEdit", "CanDelete" })
                        {
                            var value = action switch { "CanView" => row.CanView, "CanAdd" => row.CanAdd, "CanEdit" => row.CanEdit, _ => row.CanDelete };
                            <td class="px-4 py-3 text-center">
                                <input type="checkbox" class="user-permission-checkbox rounded border-slate-300 dark:border-slate-600 text-[#7c3aed] focus:ring-[#7c3aed]"
                                       data-action="@action" checked="@(value ?? false)" />
                                <input type="hidden" name="PermissionOverrides[@i].@action" class="user-permission-hidden" value="@(value.HasValue ? value.Value.ToString().ToLower() : "")" />
                            </td>
                        }
                    </tr>
                }
            </tbody>
        </table>
    </div>
</div>
```

- [ ] **Step 8: Wire the role-switch preview + tri-state checkbox behavior in the `@section Scripts` block**

In the same file's existing `@section Scripts { <script> ... </script> }` block, add before the closing `</script>`:
```javascript
// ---------- User permission grid: preview role defaults, track overrides ----------
(function () {
    const table = document.getElementById('user-permission-grid');
    if (!table) return;

    const roleDefaults = JSON.parse(table.dataset.roleDefaults || '{}');

    function applyRoleDefaults(roleId) {
        const defaults = roleDefaults[roleId];
        if (!defaults) return;
        table.querySelectorAll('tr[data-module]').forEach(row => {
            const moduleCode = row.dataset.module;
            const moduleDefaults = defaults.find(d => d.moduleCode === moduleCode || d.ModuleCode === moduleCode);
            if (!moduleDefaults) return;
            row.querySelectorAll('.user-permission-checkbox').forEach(cb => {
                const action = cb.dataset.action;
                const hidden = cb.nextElementSibling;
                // Only repaint cells the admin hasn't explicitly overridden
                // (hidden value still blank) — an existing override must
                // survive switching the role radio back and forth.
                if (hidden.value === '') {
                    const key = action.charAt(0).toLowerCase() + action.slice(1);
                    cb.checked = !!(moduleDefaults[key] ?? moduleDefaults[action]);
                }
            });
        });
    }

    // Any checkbox the admin actually clicks becomes an explicit override
    // from then on, regardless of which role is selected afterward.
    table.querySelectorAll('.user-permission-checkbox').forEach(cb => {
        cb.addEventListener('change', () => {
            const hidden = cb.nextElementSibling;
            hidden.value = cb.checked ? 'true' : 'false';
        });
    });

    document.querySelectorAll('input[name="Role"]').forEach(radio => {
        radio.addEventListener('change', (e) => applyRoleDefaults(e.target.value));
    });

    const checkedRole = document.querySelector('input[name="Role"]:checked');
    if (checkedRole) applyRoleDefaults(checkedRole.value);
})();
```
Note: the hidden input's value round-trips as `"true"`/`"false"`/`""` (empty string), and ASP.NET Core's default model binder treats an empty string for a `bool?` as `null` — matching the "inherit" semantics exactly.

- [ ] **Step 9: Build and manually verify**

Run: `cd "Web_Backend" && dotnet build`
Expected: `Build succeeded. 0 Warning(s) 0 Error(s)`

Then run the app, log in, go to User Management → Users:
1. Click "Add User", pick a role that has some permissions ticked (from Task 5's test) — expected: the permissions grid shows those same boxes ticked, others unticked, none disabled.
2. Switch to a different role radio button — expected: the grid updates to reflect that role's permissions.
3. Tick one extra box that the role doesn't grant, then switch roles again and back — expected: your manually-ticked box stays ticked regardless of role switching (proving it became a sticky override).
4. Save the user, then re-open Edit for that user — expected: the same override is still ticked.

- [ ] **Step 10: Commit**

```bash
git add Web_Backend/Areas/Admin/Models/AddUserViewModel.cs Web_Backend/Areas/Admin/Models/EditUserViewModel.cs Web_Backend/Areas/Admin/Controllers/UserController.cs Web_Backend/Areas/Admin/Views/User/Index.cshtml
git commit -m "Show role permissions and allow per-user overrides on the User form"
```

---

## Task 7: Enforce permissions on controllers + filter the sidebar

**Files:**
- Modify: `Web_Backend/Areas/Admin/Controllers/UniversityController.cs`
- Modify: `Web_Backend/Areas/Admin/Controllers/EmailSettingsController.cs`
- Modify: `Web_Backend/Areas/Admin/Controllers/EmailTemplateController.cs`
- Modify: `Web_Backend/Areas/Admin/Controllers/UserController.cs`
- Modify: `Web_Backend/Areas/Admin/Views/Shared/_AdminLayout.cshtml`

**Interfaces:**
- Consumes: `Auth.CheckPermission(string moduleCode, char action)` and `Auth.HasPermission(string moduleCode, char action)` (Task 4), `PermissionCode` (Task 2).
- Produces: every list/view action in those controllers now calls `Auth.CheckPermission(PermissionCode.X, 'V')` (replacing or supplementing the existing `Auth.CheckUser()`), create actions check `'A'`, edit actions check `'E'`, delete actions check `'D'`; the sidebar only renders a module's link when `Auth.HasPermission(moduleCode, 'V')` is true for the current session user.

- [ ] **Step 1: Locate every `Auth.CheckUser()` call in the three module controllers**

Run: `Grep -n "Auth.CheckUser" "Web_Backend/Areas/Admin/Controllers/UniversityController.cs" "Web_Backend/Areas/Admin/Controllers/EmailSettingsController.cs" "Web_Backend/Areas/Admin/Controllers/EmailTemplateController.cs"`

This lists every action currently gated only by login state — each one needs its `Auth.CheckUser();` line replaced per the mapping below.

- [ ] **Step 2: Replace `Auth.CheckUser()` with `Auth.CheckPermission(...)` in `UniversityController.cs`**

For every action whose name starts with `Index`, `Details`, `List`, or is a bare `[HttpGet]` list/detail view: replace `Auth.CheckUser();` with:
```csharp
Auth.CheckPermission(PermissionCode.Universities, 'V');
```
For every `Add`/`Create` GET or POST action: replace `Auth.CheckUser();` with:
```csharp
Auth.CheckPermission(PermissionCode.Universities, 'A');
```
For every `Edit`/`Update` GET or POST action: replace `Auth.CheckUser();` with:
```csharp
Auth.CheckPermission(PermissionCode.Universities, 'E');
```
For every `Delete` POST action: replace `Auth.CheckUser();` with:
```csharp
Auth.CheckPermission(PermissionCode.Universities, 'D');
```
Add `using Web_Backend.Classes;` at the top of the file if not already present. Apply the same to any gallery/child-record actions in this controller (e.g. adding/removing a university's gallery images) — they gate on `'A'`/`'D'` respectively since they mutate a related record, not the University's own View permission.

- [ ] **Step 3: Repeat the same replacement pattern in `EmailSettingsController.cs`**

Using `PermissionCode.EmailSettings` in place of `PermissionCode.Universities`, same `'V'/'A'/'E'/'D'` mapping by action name.

- [ ] **Step 4: Repeat the same replacement pattern in `EmailTemplateController.cs`**

Using `PermissionCode.EmailTemplates` in place of `PermissionCode.Universities`, same mapping.

- [ ] **Step 5: Apply the same pattern in `UserController.cs`, using `PermissionCode.UserManagement` for every action (Users and Roles both live under this one module)**

- `Index`, `Add` GET, `Edit` GET, `AddRole` GET, `EditRole` GET → `'V'`
- `Add` POST → `'A'`
- `Edit` POST, `SetRole` → `'E'`
- `Delete`, `ResetPassword` → `'D'` for Delete; keep `ResetPassword` on `'E'` (it modifies the user record, doesn't delete anything)
- `AddRole` POST → `'A'`
- `EditRole` POST → `'E'`
- `DeleteRole` → `'D'`

Replace each action's `Auth.CheckUser();` accordingly. Note: `Auth.CheckPermission` already calls `Auth.CheckUser()` internally (Task 4, Step 2), so this is a straight replacement, not an addition.

- [ ] **Step 6: Filter the sidebar in `_AdminLayout.cshtml`**

At the top of the file, in the existing `@{ ... }` block, add:
```csharp
var canViewUniversities = Web_Backend.Classes.Auth.HasPermission(Web_Backend.Classes.PermissionCode.Universities, 'V');
var canViewEmailSettings = Web_Backend.Classes.Auth.HasPermission(Web_Backend.Classes.PermissionCode.EmailSettings, 'V');
var canViewEmailTemplates = Web_Backend.Classes.Auth.HasPermission(Web_Backend.Classes.PermissionCode.EmailTemplates, 'V');
var canViewUserManagement = Web_Backend.Classes.Auth.HasPermission(Web_Backend.Classes.PermissionCode.UserManagement, 'V');
```
Then wrap each corresponding `<a>` block:
```html
@if (canViewUniversities)
{
    <a asp-area="Admin" asp-controller="University" asp-action="Index" ...>
        ...
    </a>
}
```
Apply the same `@if` wrapping to the Email Settings link, the Email Templates link, and the User Management link at the bottom of the sidebar. Leave Dashboard and Log out unwrapped — they stay always-visible to any logged-in user, matching how Dashboard already has no permission concept.

- [ ] **Step 7: Build**

Run: `cd "Web_Backend" && dotnet build`
Expected: `Build succeeded. 0 Warning(s) 0 Error(s)`

- [ ] **Step 8: Manual end-to-end verification**

Run the app, then:
1. Log in as the Master Admin account (or a user with `UserTypeID = MASTERADMIN`) — expected: every sidebar link visible, every action works.
2. Create a role with only `Universities: View` ticked (via Task 5's Role form), create a user with that role and no overrides (via Task 6's User form), log in as that user — expected: sidebar shows only Dashboard, Universities, and Log out; visiting `/Admin/EmailSettings` directly redirects to login (via `UnauthorizedRedirectFilter` catching the thrown `UnauthorizedAccessException`); on the Universities page, there's no way to reach an Add/Edit/Delete action that would succeed if attempted directly (test by navigating to the University Add URL directly — expected redirect/error, not a working form).
3. Edit that user via the Master Admin account and tick `Universities: Add` as an override — log back in as that user — expected: they can now create a university, still can't edit/delete one.

- [ ] **Step 9: Commit**

```bash
git add Web_Backend/Areas/Admin/Controllers/UniversityController.cs Web_Backend/Areas/Admin/Controllers/EmailSettingsController.cs Web_Backend/Areas/Admin/Controllers/EmailTemplateController.cs Web_Backend/Areas/Admin/Controllers/UserController.cs Web_Backend/Areas/Admin/Views/Shared/_AdminLayout.cshtml
git commit -m "Enforce module permissions on every admin action and filter the sidebar"
```

---

## Task 8: Assign an existing user as Master Admin + update docs

**Files:**
- Modify: `Database/migrations/0002_role_permissions.sql` (only if Task 1 already ran on local — otherwise create a follow-up `0003_assign_master_admin.sql`; see Step 1 for which applies)
- Modify: `backend/ENVIRONMENTS.md`

**Interfaces:**
- Consumes: nothing new.
- Produces: at least one real `usr.Users` row with `UserTypeID = 'MASTERADMIN'` so there's an actual account that can log in with full access; a documented note in `ENVIRONMENTS.md` about the permission system.

- [ ] **Step 1: Decide migration numbering**

If Task 1's `0002_role_permissions.sql` has already been applied to the local DB by the time this task starts (it has, per Task 1 Step 2), do **not** edit that file — instead create a new file, since edited-after-applied migrations violate the Global Constraints. Create `Database/migrations/0003_assign_master_admin.sql`:
```sql
-- Promotes one existing user to Master Admin so there's a real account with
-- full access to log in with. Replace the WHERE clause's email before
-- running against a new environment — this migration is intentionally not
-- automatic about *which* user becomes Master Admin.
--
-- No USE statement — see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

UPDATE usr.Users
SET UserTypeID = 'MASTERADMIN'
WHERE Email = 'REPLACE_WITH_YOUR_ADMIN_EMAIL';
```

- [ ] **Step 2: Apply it locally after editing the email**

Edit the `WHERE Email = ...` line to match your actual admin account's email, then run:
```powershell
cd Database/tools
./apply-migrations.ps1 -Server "VS-PW0C7J84\DUSHMAN001" -Database "Proton_Admin" -UserId "sa" -Password "vsdush*8902*#"
```
Expected: `Applying 0003_assign_master_admin.sql...` then `Done.`

- [ ] **Step 3: Verify and log in**

Run: `SELECT UserID, Email, UserTypeID FROM usr.Users WHERE UserTypeID = 'MASTERADMIN';` against the local DB — expect exactly the one row you intended.

Log into the running app as that account — expected: full sidebar, no permission errors anywhere.

- [ ] **Step 4: Document the permission system in `ENVIRONMENTS.md`**

Append this section to `backend/ENVIRONMENTS.md`:
```markdown
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
```

- [ ] **Step 5: Commit**

```bash
git add Database/migrations/0003_assign_master_admin.sql backend/ENVIRONMENTS.md
git commit -m "Promote an account to Master Admin and document the permission system"
```

---

## Self-Review Notes

- **Spec coverage:** "option to access view like add edit delete when creating the role" → Task 5 (Role form grid). "when user is created also there is a option to load the role right when loading show what permission are allowed" → Task 6 Step 7-8 (role-default preview on the User form, live-updating on role switch). "if there is some role permission need to give for specific user we can tick it" → Task 6 (per-user override, tri-state checkboxes that stick once touched). "master admin of current has all role it shouldn't be change he has full access" → Task 1 (seed) + Task 4 (hardcoded `Auth.HasPermission` short-circuit) + Task 5 Steps 6-8 (UI lock) + Task 8 (assigning a real account to it).
- **Placeholder scan:** no TBD/TODO markers; the one intentionally-manual value (`REPLACE_WITH_YOUR_ADMIN_EMAIL` in Task 8) is flagged as something the implementer must edit before running, not left vague about what to put there.
- **Type consistency:** `PermissionGridViewModel` (Task 2) is the single shape used by both the Role grid (Task 5, non-null bools written into it) and the User override grid (Task 6, nullable bools) — verified every task references the same property names (`CanView/CanAdd/CanEdit/CanDelete`, `ModuleCode/ModuleLabel`). `Auth.HasPermission`/`CheckPermission` signatures (Task 4) match every call site added in Task 7. `IRolePermissionData`/`IUserPermissionOverrideData` method names (Task 3) match every call in Tasks 4-6.
