-- 0040_student_user_emailtemplate_delete.sql
--
-- Extends the Deactivate / Activate / DeletePermanently pattern (0032-0039)
-- to the last three modules still showing a trash-bin "Delete" that only
-- deactivated: Student, User and Email Template.
--
-- Also fixes a live bug in usr.Users_HardDelete (0025). It guards the
-- COURSE instructor and reschedule tables, but edu.ExamScheduleInstructor
-- and edu.ExamScheduleReschedule came later (0028/0030) and were never
-- added, so deleting a user who invigilates an exam sitting or who filed an
-- exam reschedule request failed on a raw foreign-key error instead of a
-- readable message. Both are now guarded.
--
-- Where a row merely records who did something (created by, approved by,
-- verified by), the delete clears the pointer rather than refusing: that
-- history belongs to the registration or the payment, not to the user
-- account, and it shouldn't keep a departed staff member's account alive.
-- Rows that represent the person's actual work -- their teaching
-- assignments, their reschedule requests, their uploaded material -- still
-- block, because deleting those would erase the work itself.

-- ============================================================
-- Student
-- ============================================================

IF OBJECT_ID('mst.Student_Deactivate') IS NOT NULL DROP PROCEDURE mst.Student_Deactivate
GO
CREATE PROCEDURE [mst].[Student_Deactivate]
(
    @APIKey    VARCHAR(100),
    @ID        VARCHAR(20),
    @LogUserID VARCHAR(50) = '',
    @RetValue  VARCHAR(50) = '' OUT
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

        UPDATE mst.Student SET IsActive = 'I' WHERE StudentID = @ID;

        -- The login is deactivated with the profile, otherwise the student
        -- could still sign in to a portal that no longer lists them.
        UPDATE usr.Users SET IsActive = 'I'
         WHERE UserID = (SELECT UserID FROM mst.Student WHERE StudentID = @ID);

        SET @RetValue = @ID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.Student_Deactivate', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.Student_Activate') IS NOT NULL DROP PROCEDURE mst.Student_Activate
GO
CREATE PROCEDURE [mst].[Student_Activate]
(
    @APIKey    VARCHAR(100),
    @ID        VARCHAR(20),
    @LogUserID VARCHAR(50) = '',
    @RetValue  VARCHAR(50) = '' OUT
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

        UPDATE mst.Student SET IsActive = 'A' WHERE StudentID = @ID;

        UPDATE usr.Users SET IsActive = 'A'
         WHERE UserID = (SELECT UserID FROM mst.Student WHERE StudentID = @ID);

        SET @RetValue = @ID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: mst.Student_Activate', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.Student_GetDeleteImpact') IS NOT NULL DROP PROCEDURE mst.Student_GetDeleteImpact
GO
CREATE PROCEDURE [mst].[Student_GetDeleteImpact]
(
    @APIKey VARCHAR(100),
    @ID     VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        DECLARE @UID VARCHAR(50) = (SELECT UserID FROM mst.Student WHERE StudentID = @ID);

        SELECT
            (SELECT COUNT(*) FROM mst.CourseRegistration WHERE StudentID = @ID) AS RegistrationCount,
            (SELECT COUNT(*) FROM mst.CourseRegistrationPayment
              WHERE RegistrationID IN (SELECT RegistrationID FROM mst.CourseRegistration WHERE StudentID = @ID)) AS PaymentCount,
            (SELECT COUNT(*) FROM usr.UserAuth WHERE UserID = @UID) AS LoginAccountCount;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.Student_GetDeleteImpact', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('mst.Student_DeletePermanently') IS NOT NULL DROP PROCEDURE mst.Student_DeletePermanently
GO
CREATE PROCEDURE [mst].[Student_DeletePermanently]
(
    @APIKey    VARCHAR(100),
    @ID        VARCHAR(20),
    @LogUserID VARCHAR(50) = '',
    @RetValue  VARCHAR(50) = '' OUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        IF NOT EXISTS (SELECT 1 FROM mst.Student WHERE StudentID = @ID)
        BEGIN
            ;THROW 50000, 'That student no longer exists.', 1;
        END

        DECLARE @UID VARCHAR(50) = (SELECT UserID FROM mst.Student WHERE StudentID = @ID);

        IF @UID IS NOT NULL AND @LogUserID <> '' AND @UID = @LogUserID
        BEGIN
            ;THROW 50000, 'You cannot delete the account you are signed in with.', 1;
        END

        -- Enrolments carry the student's payment history; that record of who
        -- paid what has to outlive any tidy-up of the student list.
        DECLARE @RegCount INT = (SELECT COUNT(*) FROM mst.CourseRegistration WHERE StudentID = @ID);
        IF @RegCount > 0
        BEGIN
            DECLARE @RegMsg VARCHAR(500) = 'This student can''t be deleted because they have ' + CAST(@RegCount AS VARCHAR(10)) +
                ' course registration(s) and the payment history that goes with them. Deactivate the student instead.';
            ;THROW 50000, @RegMsg, 1;
        END

        -- Clear the "who did this" pointers before the account goes.
        UPDATE mst.Student SET PassportVerifiedByUserID = NULL WHERE PassportVerifiedByUserID = @UID;
        UPDATE mst.Student SET CreatedByUserID = ''           WHERE CreatedByUserID = @UID;

        DELETE FROM usr.PasswordResetToken
         WHERE AuthID IN (SELECT AuthID FROM usr.UserAuth WHERE UserID = @UID);
        DELETE FROM usr.UserPermissionOverride WHERE UserID = @UID;
        DELETE FROM usr.UserAuth               WHERE UserID = @UID;

        DELETE FROM mst.Student WHERE StudentID = @ID;
        DELETE FROM usr.Users   WHERE UserID = @UID;

        SET @RetValue = @ID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.Student_DeletePermanently', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- User — repairs the guards missing from 0025 and adds an impact proc
-- ============================================================

IF OBJECT_ID('usr.Users_GetDeleteImpact') IS NOT NULL DROP PROCEDURE usr.Users_GetDeleteImpact
GO
CREATE PROCEDURE [usr].[Users_GetDeleteImpact]
(
    @APIKey VARCHAR(100),
    @ID     VARCHAR(50)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        DECLARE @SID VARCHAR(20) = (SELECT StudentID FROM mst.Student WHERE UserID = @ID);

        SELECT
            (SELECT COUNT(*) FROM mst.CourseRegistration WHERE StudentID = @SID) AS RegistrationCount,
            (SELECT COUNT(*) FROM edu.CourseScheduleInstructor WHERE UserID = @ID) AS CourseBatchAssignmentCount,
            (SELECT COUNT(*) FROM edu.ExamScheduleInstructor   WHERE UserID = @ID) AS ExamBatchAssignmentCount,
            (SELECT COUNT(*) FROM edu.CourseScheduleReschedule WHERE RequestedByUserID = @ID) AS CourseRescheduleCount,
            (SELECT COUNT(*) FROM edu.ExamScheduleReschedule   WHERE RequestedByUserID = @ID) AS ExamRescheduleCount,
            (SELECT COUNT(*) FROM edu.LectureMaterial WHERE UploadedByUserID = @ID) AS LectureMaterialCount,
            (SELECT COUNT(*) FROM usr.UserPermissionOverride WHERE UserID = @ID) AS PermissionOverrideCount,
            CASE WHEN @SID IS NULL THEN 0 ELSE 1 END AS HasStudentProfile;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: usr.Users_GetDeleteImpact', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('usr.Users_HardDelete') IS NOT NULL DROP PROCEDURE usr.Users_HardDelete
GO
CREATE PROCEDURE [usr].[Users_HardDelete]
(
    @APIKey    VARCHAR(100),
    @ID        VARCHAR(50),
    @LogUserID VARCHAR(50) = '',
    @RetValue  VARCHAR(50) = '' OUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        IF NOT EXISTS (SELECT 1 FROM usr.Users WHERE UserID = @ID)
        BEGIN
            ;THROW 50000, 'That user no longer exists.', 1;
        END

        IF @LogUserID <> '' AND @ID = @LogUserID
        BEGIN
            ;THROW 50000, 'You cannot delete the account you are signed in with.', 1;
        END

        IF EXISTS (SELECT 1 FROM usr.Users WHERE UserID = @ID AND UserTypeID = 'MASTERADMIN')
           AND (SELECT COUNT(*) FROM usr.Users WHERE UserTypeID = 'MASTERADMIN' AND IsActive = 'A') <= 1
        BEGIN
            ;THROW 50000, 'This is the last active Master Admin account and cannot be deleted.', 1;
        END

        DECLARE @SID VARCHAR(20) = (SELECT StudentID FROM mst.Student WHERE UserID = @ID);

        IF @SID IS NOT NULL AND EXISTS (SELECT 1 FROM mst.CourseRegistration WHERE StudentID = @SID)
        BEGIN
            ;THROW 50000, 'This account belongs to a student with course registrations and payment history. Deactivate it instead.', 1;
        END

        IF EXISTS (SELECT 1 FROM edu.CourseScheduleInstructor WHERE UserID = @ID)
        BEGIN
            ;THROW 50000, 'This user is assigned to teach one or more course batches. Remove those assignments first, or deactivate the account instead.', 1;
        END

        -- Missing from 0025: edu.ExamScheduleInstructor arrived in 0028, so
        -- deleting an invigilator failed on a raw foreign-key error.
        IF EXISTS (SELECT 1 FROM edu.ExamScheduleInstructor WHERE UserID = @ID)
        BEGIN
            ;THROW 50000, 'This user is assigned to one or more exam sittings. Remove those assignments first, or deactivate the account instead.', 1;
        END

        IF EXISTS (SELECT 1 FROM edu.CourseScheduleReschedule WHERE RequestedByUserID = @ID)
        BEGIN
            ;THROW 50000, 'This user has submitted class reschedule requests, which are part of the schedule''s history. Deactivate the account instead.', 1;
        END

        -- Missing from 0025 for the same reason: edu.ExamScheduleReschedule
        -- arrived in 0030.
        IF EXISTS (SELECT 1 FROM edu.ExamScheduleReschedule WHERE RequestedByUserID = @ID)
        BEGIN
            ;THROW 50000, 'This user has submitted exam reschedule requests, which are part of the exam''s history. Deactivate the account instead.', 1;
        END

        IF EXISTS (SELECT 1 FROM edu.LectureMaterial WHERE UploadedByUserID = @ID)
        BEGIN
            ;THROW 50000, 'This user has uploaded lecture material that students still rely on. Reassign or remove it first, or deactivate the account instead.', 1;
        END

        -- Approvals and "created by" stamps name the account but aren't its
        -- work; clear the pointer so the underlying record survives intact.
        UPDATE edu.CourseScheduleReschedule    SET ApprovedByUserID = NULL WHERE ApprovedByUserID = @ID;
        UPDATE edu.ExamScheduleReschedule      SET ApprovedByUserID = NULL WHERE ApprovedByUserID = @ID;
        UPDATE mst.CourseRegistrationPayment   SET VerifiedByUserID = NULL WHERE VerifiedByUserID = @ID;
        UPDATE mst.CourseRegistrationPayment   SET CreatedByUserID  = ''   WHERE CreatedByUserID  = @ID;
        UPDATE mst.CourseRegistration          SET CreatedByUserID  = ''   WHERE CreatedByUserID  = @ID;
        UPDATE mst.Student                     SET PassportVerifiedByUserID = NULL WHERE PassportVerifiedByUserID = @ID;
        UPDATE mst.Student                     SET CreatedByUserID  = ''   WHERE CreatedByUserID  = @ID;

        DELETE FROM usr.PasswordResetToken
         WHERE AuthID IN (SELECT AuthID FROM usr.UserAuth WHERE UserID = @ID);
        DELETE FROM usr.UserPermissionOverride WHERE UserID = @ID;
        DELETE FROM usr.UserAuth               WHERE UserID = @ID;
        DELETE FROM mst.Student                WHERE UserID = @ID;
        DELETE FROM usr.Users                  WHERE UserID = @ID;

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

-- ============================================================
-- Email Template
-- ============================================================
-- Nothing references a template by key, but the application looks several
-- up by TemplateCode at send time and skips the mail when one is missing
-- OR inactive -- so deactivating a system template silently stops welcome
-- mail and password resets just as surely as deleting it would. Both procs
-- therefore refuse on the same list.

IF OBJECT_ID('syst.EmailTemplate_IsSystemCode') IS NOT NULL DROP FUNCTION syst.EmailTemplate_IsSystemCode
GO
CREATE FUNCTION [syst].[EmailTemplate_IsSystemCode](@TemplateID VARCHAR(20))
RETURNS BIT
AS
BEGIN
    RETURN CASE WHEN EXISTS (
        SELECT 1 FROM syst.EmailTemplate
         WHERE TemplateID = @TemplateID
           AND TemplateCode IN ('WELCOME_EMAIL','STUDENT_WELCOME_EMAIL','LECTURER_WELCOME_EMAIL',
                                'PASSWORD_RESET','CONTACT_ADMIN_NOTIFY','CONTACT_CLIENT_THANKS')
    ) THEN 1 ELSE 0 END
END
GO

IF OBJECT_ID('syst.EmailTemplate_Deactivate') IS NOT NULL DROP PROCEDURE syst.EmailTemplate_Deactivate
GO
CREATE PROCEDURE [syst].[EmailTemplate_Deactivate]
(
    @APIKey    VARCHAR(100),
    @ID        VARCHAR(20),
    @LogUserID VARCHAR(50) = '',
    @RetValue  VARCHAR(50) = '' OUT
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

        IF syst.EmailTemplate_IsSystemCode(@ID) = 1
        BEGIN
            ;THROW 50000, 'The application sends mail through this template, and turning it off would silently stop those emails. Edit its wording instead.', 1;
        END

        UPDATE syst.EmailTemplate SET IsActive = 'I' WHERE TemplateID = @ID;

        SET @RetValue = @ID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: syst.EmailTemplate_Deactivate', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.EmailTemplate_Activate') IS NOT NULL DROP PROCEDURE syst.EmailTemplate_Activate
GO
CREATE PROCEDURE [syst].[EmailTemplate_Activate]
(
    @APIKey    VARCHAR(100),
    @ID        VARCHAR(20),
    @LogUserID VARCHAR(50) = '',
    @RetValue  VARCHAR(50) = '' OUT
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

        UPDATE syst.EmailTemplate SET IsActive = 'A' WHERE TemplateID = @ID;

        SET @RetValue = @ID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: syst.EmailTemplate_Activate', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.EmailTemplate_GetDeleteImpact') IS NOT NULL DROP PROCEDURE syst.EmailTemplate_GetDeleteImpact
GO
CREATE PROCEDURE [syst].[EmailTemplate_GetDeleteImpact]
(
    @APIKey VARCHAR(100),
    @ID     VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT TemplateCode,
               syst.EmailTemplate_IsSystemCode(TemplateID) AS IsSystemTemplate
          FROM syst.EmailTemplate
         WHERE TemplateID = @ID;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: syst.EmailTemplate_GetDeleteImpact', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.EmailTemplate_DeletePermanently') IS NOT NULL DROP PROCEDURE syst.EmailTemplate_DeletePermanently
GO
CREATE PROCEDURE [syst].[EmailTemplate_DeletePermanently]
(
    @APIKey    VARCHAR(100),
    @ID        VARCHAR(20),
    @LogUserID VARCHAR(50) = '',
    @RetValue  VARCHAR(50) = '' OUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        IF NOT EXISTS (SELECT 1 FROM syst.EmailTemplate WHERE TemplateID = @ID)
        BEGIN
            ;THROW 50000, 'That email template no longer exists.', 1;
        END

        IF syst.EmailTemplate_IsSystemCode(@ID) = 1
        BEGIN
            ;THROW 50000, 'The application sends mail through this template -- deleting it would stop welcome emails or password resets from going out. Edit its wording instead.', 1;
        END

        DELETE FROM syst.EmailTemplate WHERE TemplateID = @ID;

        SET @RetValue = @ID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: syst.EmailTemplate_DeletePermanently', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
