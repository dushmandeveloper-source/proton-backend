-- Per-user UI preferences (key/value), e.g. which admin dashboard sections a
-- user has hidden ("dashboard.hidden" = "finance,exams"). Stored server-side
-- so the choice survives logout/login and follows the user across devices.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF OBJECT_ID('usr.UserPreference') IS NULL
BEGIN
    CREATE TABLE [usr].[UserPreference](
        [UserID]      [varchar](50)    NOT NULL,
        [PrefKey]     [varchar](100)   NOT NULL,
        [PrefValue]   [nvarchar](2000) NOT NULL,
        [UpdatedDate] [datetime]       NOT NULL DEFAULT (GETDATE()),
        CONSTRAINT [PK_usr_UserPreference] PRIMARY KEY CLUSTERED ([UserID], [PrefKey])
    )
END
GO

IF OBJECT_ID('usr.UserPreference_Get') IS NOT NULL DROP PROCEDURE usr.UserPreference_Get
GO
CREATE PROCEDURE [usr].[UserPreference_Get] (@APIKey VARCHAR(100), @UserID VARCHAR(50), @PrefKey VARCHAR(100))
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        SELECT PrefValue FROM usr.UserPreference WHERE UserID = @UserID AND PrefKey = @PrefKey
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: usr.UserPreference_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('usr.UserPreference_Set') IS NOT NULL DROP PROCEDURE usr.UserPreference_Set
GO
CREATE PROCEDURE [usr].[UserPreference_Set] (@APIKey VARCHAR(100), @UserID VARCHAR(50), @PrefKey VARCHAR(100), @PrefValue NVARCHAR(2000))
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        UPDATE usr.UserPreference SET PrefValue = ISNULL(@PrefValue, ''), UpdatedDate = GETDATE() WHERE UserID = @UserID AND PrefKey = @PrefKey
        IF @@ROWCOUNT = 0
            INSERT INTO usr.UserPreference (UserID, PrefKey, PrefValue, UpdatedDate) VALUES (@UserID, @PrefKey, ISNULL(@PrefValue, ''), GETDATE())
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: usr.UserPreference_Set', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
