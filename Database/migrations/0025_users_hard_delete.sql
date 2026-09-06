-- 0025_users_hard_delete.sql
--
-- Adds usr.Users_HardDelete: a genuine permanent delete for user accounts,
-- alongside the existing usr.Users_Delete (which is a soft delete — it only
-- flips IsActive to 'I' and the row stays queryable via "Show deactivated").
--
-- Admins had no way to actually remove an account, so test/mistaken
-- registrations accumulated forever in User Management. This proc removes the
-- account and everything that exists purely to support it (auth row, reset
-- tokens, permission overrides, and the student profile), but deliberately
-- REFUSES when the account is referenced by real business records —
-- course registrations, batch assignments, reschedule requests, uploaded
-- lecture materials. Those carry history that shouldn't silently vanish, so
-- the admin is told to deactivate instead.

IF OBJECT_ID('usr.Users_HardDelete') IS NOT NULL DROP PROCEDURE usr.Users_HardDelete
GO
CREATE PROCEDURE [usr].[Users_HardDelete]
(
    @APIKey    VARCHAR(100),
    @ID        VARCHAR(20),
    @LogUserID VARCHAR(20) = '',
    @RetValue  VARCHAR(50) = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM usr.Users WHERE UserID = @ID)
        BEGIN
            ;THROW 50000, 'That user no longer exists.', 1;
        END

        -- An account can't delete itself out from under the current session.
        IF @LogUserID <> '' AND @LogUserID = @ID
        BEGIN
            ;THROW 50000, 'You cannot permanently delete the account you are signed in with.', 1;
        END

        -- Never leave the system with no Master Admin to sign in as.
        IF EXISTS (SELECT 1 FROM usr.Users WHERE UserID = @ID AND UserTypeID = 'MASTERADMIN')
           AND (SELECT COUNT(*) FROM usr.Users WHERE UserTypeID = 'MASTERADMIN' AND IsActive = 'A') <= 1
        BEGIN
            ;THROW 50000, 'This is the last active Master Admin account and cannot be deleted.', 1;
        END

        DECLARE @StudentID VARCHAR(20) =
            (SELECT TOP 1 StudentID FROM mst.Student WHERE UserID = @ID);

        -- ----- Refuse when real history hangs off this account -----
        IF @StudentID IS NOT NULL
           AND EXISTS (SELECT 1 FROM mst.CourseRegistration WHERE StudentID = @StudentID)
        BEGIN
            ;THROW 50000, 'This student has course registrations and cannot be permanently deleted. Deactivate the account instead.', 1;
        END

        IF EXISTS (SELECT 1 FROM edu.CourseScheduleInstructor WHERE UserID = @ID)
        BEGIN
            ;THROW 50000, 'This account is assigned to one or more course batches and cannot be permanently deleted. Reassign those batches first, or deactivate the account instead.', 1;
        END

        IF EXISTS (SELECT 1 FROM edu.CourseScheduleReschedule WHERE RequestedByUserID = @ID)
        BEGIN
            ;THROW 50000, 'This account has reschedule requests on record and cannot be permanently deleted. Deactivate the account instead.', 1;
        END

        IF EXISTS (SELECT 1 FROM edu.LectureMaterial WHERE UploadedByUserID = @ID)
        BEGIN
            ;THROW 50000, 'This account has uploaded lecture materials and cannot be permanently deleted. Deactivate the account instead.', 1;
        END

        -- ----- Safe to remove: delete dependents before the parent row -----
        DELETE t
        FROM usr.PasswordResetToken t
        INNER JOIN usr.UserAuth a ON a.AuthID = t.AuthID
        WHERE a.UserID = @ID;

        DELETE FROM usr.UserPermissionOverride WHERE UserID = @ID;
        DELETE FROM usr.UserAuth              WHERE UserID = @ID;

        IF @StudentID IS NOT NULL
            DELETE FROM mst.Student WHERE StudentID = @StudentID;

        DELETE FROM usr.Users WHERE UserID = @ID;

        SET @RetValue = @ID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: usr.Users_HardDelete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
