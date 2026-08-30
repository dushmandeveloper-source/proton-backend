-- ============================================================
-- Migration 0018: defense-in-depth guard against deactivating the
-- Student / Instructor roles directly through usr.UserType_AddEdit.
-- ============================================================
-- Mirrors the guard already added to usr.UserType_Delete in migration
-- 0014 (blocking delete of Admin/Student/Instructor there). A real dev-data
-- incident showed the Student and Instructor usr.UserType rows had ended up
-- IsActive='I' via this very proc's @IsActive parameter (the app-level
-- EditRole action only blocked renaming/deleting, not deactivating) —
-- adding the guard at the app layer alone isn't enough, since anything else
-- that calls this sproc directly needs the same protection.
--
-- Preserves every other existing behavior of usr.UserType_AddEdit exactly
-- (see baseline definition in ProtonAdmin_Schema.sql) — only adds a check
-- before the UPDATE branch. Admin is intentionally NOT included here (only
-- Student/Instructor), consistent with the app-level EditRole guard.
IF OBJECT_ID('usr.UserType_AddEdit') IS NOT NULL DROP PROCEDURE usr.UserType_AddEdit
GO
CREATE PROCEDURE [usr].[UserType_AddEdit]
(
    @APIKey       VARCHAR(100),
    @UserTypeID   VARCHAR(20),
    @UserTypeName NVARCHAR(100),
    @Description  NVARCHAR(500) = '',
    @IsActive     CHAR(1)       = 'A',
    @LogUserID    VARCHAR(20)   = '',
    @RetValue     VARCHAR(50)   = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM usr.UserType WHERE UserTypeID = @UserTypeID)
        BEGIN
            IF EXISTS (SELECT 1 FROM usr.UserType WHERE UserTypeName = @UserTypeName)
            BEGIN
                ;THROW 50000, 'User type name already exists', 1;
            END

            DECLARE @PrimaryKey VARCHAR(20) = @UserTypeID
            IF @PrimaryKey = ''
            BEGIN
                EXEC syst.NumberFormat_Get 'usr.UserType', 'UserTypeID', @PrimaryKey OUT
            END

            INSERT INTO usr.UserType (UserTypeID, UserTypeName, Description, IsActive, CreatedDate)
            VALUES (@PrimaryKey, @UserTypeName, @Description, @IsActive, GETDATE())

            EXEC syst.NumberFormat_Set 'usr.UserType'

            SET @RetValue = @PrimaryKey
        END
        ELSE
        BEGIN
            IF EXISTS (SELECT 1 FROM usr.UserType WHERE UserTypeName = @UserTypeName AND UserTypeID <> @UserTypeID)
            BEGIN
                ;THROW 50000, 'User type name already exists', 1;
            END

            IF @IsActive = 'I' AND EXISTS (SELECT 1 FROM usr.UserType WHERE UserTypeID = @UserTypeID AND UserTypeName IN ('Student', 'Instructor'))
            BEGIN
                ;THROW 50000, 'This role cannot be deactivated', 1;
            END

            UPDATE usr.UserType
            SET UserTypeName = @UserTypeName,
                Description  = @Description,
                IsActive     = @IsActive
            WHERE UserTypeID = @UserTypeID

            SET @RetValue = @UserTypeID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: usr.UserType_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
