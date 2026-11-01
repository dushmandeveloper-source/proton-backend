-- 0112_timed_login_lockout.sql
--
-- Security: 5 wrong passwords used to set usr.UserAuth.IsLocked = 1 with no
-- expiry, so anyone who knew an email (e.g. the admin's) could lock that
-- account out for good by typing 5 bad passwords. The 5th failure now locks
-- the account for 15 minutes instead (LockedUntil, UTC) and resets the
-- counter. IsLocked = 1 stays as the admin's own manual/permanent lock and
-- is still cleared by usr.UserAuth_Unlock (which now also clears
-- LockedUntil).
--
-- usr.UserAuth_Login reports IsLocked = 1 while either lock applies, so the
-- C# login paths (AuthApiController.Login, PortalSignIn) need no change.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO

IF COL_LENGTH('usr.UserAuth', 'LockedUntil') IS NULL
    ALTER TABLE usr.UserAuth ADD LockedUntil DATETIME NULL
GO

IF OBJECT_ID('usr.UserAuth_RecordLoginResult') IS NOT NULL DROP PROCEDURE usr.UserAuth_RecordLoginResult
GO
CREATE PROCEDURE [usr].[UserAuth_RecordLoginResult]
(
    @APIKey   varchar(100),
    @AuthID   varchar(20),
    @Success  bit
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

        IF @Success = 1
        BEGIN
            UPDATE usr.UserAuth
            SET LastLoginAt = GETDATE(), FailedLoginCount = 0, LockedUntil = NULL
            WHERE AuthID = @AuthID
        END
        ELSE
        BEGIN
            UPDATE usr.UserAuth
            SET FailedLoginCount = CASE WHEN ISNULL(FailedLoginCount, 0) + 1 >= 5 THEN 0 ELSE ISNULL(FailedLoginCount, 0) + 1 END,
                LockedUntil = CASE WHEN ISNULL(FailedLoginCount, 0) + 1 >= 5 THEN DATEADD(MINUTE, 15, GETUTCDATE()) ELSE LockedUntil END
            WHERE AuthID = @AuthID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE varchar(4000)= ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR ('%s. Script: usr.UserAuth_RecordLoginResult', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('usr.UserAuth_Login') IS NOT NULL DROP PROCEDURE usr.UserAuth_Login
GO
CREATE PROCEDURE [usr].[UserAuth_Login]
(
    @APIKey          varchar(100),
    @UsernameOrEmail varchar(150)
)
AS
BEGIN
    SET NOCOUNT ON

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        -- Returns the auth + salt regardless of password match; the caller
        -- (C#) recomputes the PBKDF2 hash with the stored salt and compares,
        -- since the hash cannot be verified in T-SQL.
        SELECT TOP 1
            UA.AuthID,
            UA.UserID,
            UA.Username,
            UA.PasswordHash,
            UA.PasswordSalt,
            UA.FailedLoginCount,
            CAST(CASE WHEN UA.IsLocked = 1 OR UA.LockedUntil > GETUTCDATE() THEN 1 ELSE 0 END AS bit) AS IsLocked,
            UA.IsActive AS AuthIsActive,
            U.FullName,
            U.Email,
            U.Phone,
            U.UserTypeID,
            UT.UserTypeName,
            U.IsActive AS UserIsActive
        FROM usr.UserAuth UA
        INNER JOIN usr.Users U ON U.UserID = UA.UserID
        LEFT JOIN usr.UserType UT ON UT.UserTypeID = U.UserTypeID
        WHERE UA.LoginType = 'PASSWORD'
          AND (UA.Username = @UsernameOrEmail OR UA.Email = @UsernameOrEmail)
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE varchar(4000)= ERROR_MESSAGE();
        RAISERROR ('%s. Script: usr.UserAuth_Login', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('usr.UserAuth_Unlock') IS NOT NULL DROP PROCEDURE usr.UserAuth_Unlock
GO
CREATE PROCEDURE [usr].[UserAuth_Unlock]
(
    @APIKey   VARCHAR(100),
    @AuthID   VARCHAR(20),
    @RetValue VARCHAR(50) = '' OUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            THROW 50000, 'Invalid API Key', 1;
        END

        UPDATE usr.UserAuth
        SET IsLocked = 0,
            LockedUntil = NULL,
            FailedLoginCount = 0,
            UpdatedDate = GETDATE()
        WHERE AuthID = @AuthID;

        SET @RetValue = @AuthID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: usr.UserAuth_Unlock', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
