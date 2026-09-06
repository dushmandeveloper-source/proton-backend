-- Fixes a real bug surfaced by the admin "Reset Password" action's recent
-- fix (Areas/Admin/Controllers/UserController.cs, StudentController.cs,
-- LecturerController.cs's ResetAndSendPassword/ResetPassword actions): those
-- actions looked up the existing usr.UserAuth row by the user's CURRENT
-- Email via usr.UserAuth_Login, which only matches when UserAuth.Email/
-- Username is still in sync with usr.Users.Email. Editing a user's email
-- elsewhere (Admin/Profile, Student/Lecturer edit forms) updates usr.Users
-- but never touches usr.UserAuth's own Email/Username columns, so a user
-- who changed their email ended up with the reset action not finding their
-- real auth row (email mismatch) and creating a SECOND, orphaned
-- usr.UserAuth row instead — leaving two rows for one UserID, and
-- usr.UserAuth_Login's un-ordered `SELECT TOP 1` deciding which one
-- actually gets used to log in, unpredictably.
--
-- The fix: look up the existing auth row by UserID (the real foreign key
-- relationship, never stale) instead of by email, and have the reset
-- actions pass that AuthID + the CURRENT email into UserAuth_AddEdit so the
-- row's Username/Email are corrected back in sync at the same time the
-- password is reset — self-healing the mismatch instead of duplicating it.
--
-- No USE statement — see Database/tools/apply-migrations.ps1.

IF OBJECT_ID('usr.UserAuth_FindByUserId') IS NOT NULL DROP PROCEDURE usr.UserAuth_FindByUserId
GO
CREATE PROCEDURE [usr].[UserAuth_FindByUserId]
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

        SELECT TOP 1
            UA.AuthID,
            UA.UserID,
            UA.Username,
            UA.PasswordHash,
            UA.PasswordSalt,
            UA.FailedLoginCount,
            UA.IsLocked,
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
        WHERE UA.UserID = @UserID
          AND UA.LoginType = 'PASSWORD'
        ORDER BY UA.CreatedDate DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: usr.UserAuth_FindByUserId', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
