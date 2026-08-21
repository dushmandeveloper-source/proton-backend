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
