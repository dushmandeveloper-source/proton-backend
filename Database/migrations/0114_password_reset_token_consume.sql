-- 0114_password_reset_token_consume.sql
--
-- Security:
--  * usr.PasswordResetToken.Token now holds a SHA-256 (base64) of the
--    emailed token, computed in C# (PasswordResetData) -- no schema change,
--    the column is varchar(200). Tokens issued before this deploy were stored
--    raw and will no longer match; they expire within 30 minutes anyway, so
--    they are simply invalidated here.
--  * usr.PasswordResetToken_Consume marks a token used and returns it in a
--    single UPDATE ... OUTPUT, replacing the old Validate-then-MarkUsed pair
--    so two simultaneous requests with one link can't both reset.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO

UPDATE usr.PasswordResetToken SET IsUsed = 1 WHERE IsUsed = 0
GO

IF OBJECT_ID('usr.PasswordResetToken_Consume') IS NOT NULL DROP PROCEDURE usr.PasswordResetToken_Consume
GO
CREATE PROCEDURE [usr].[PasswordResetToken_Consume]
(
    @APIKey VARCHAR(100),
    @Token  VARCHAR(200)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        UPDATE usr.PasswordResetToken
        SET IsUsed = 1
        OUTPUT inserted.TokenID, inserted.AuthID, inserted.Email, inserted.Token,
               inserted.ExpiresAt, inserted.IsUsed, inserted.CreatedDate
        WHERE Token = @Token
          AND IsUsed = 0
          AND ExpiresAt > GETUTCDATE()
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: usr.PasswordResetToken_Consume', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
