-- 0045_student_cascade_delete.sql
--
-- Extends the cascade-delete pattern already used for Course (0039/0042/0043)
-- to Student: mst.Student_DeletePermanently used to outright REFUSE whenever
-- the student had any mst.CourseRegistration rows ("Deactivate the student
-- instead"), which meant "permanently delete" never actually worked for a
-- student who had ever registered for or paid for a course -- exactly the
-- common case. It now cascades through the student's course registrations
-- and payment history, their login account, and their exam-sitting
-- attempts/answers (see below), deleting all of it along with the student,
-- the same way Course's delete already does for a course's registrations.
--
-- Deletion order (children first, same discipline as 0042/usr.Users_HardDelete):
--   mst.ExamAttemptAnswer (if present)
--     -> mst.ExamAttempt (if present)
--   mst.CourseRegistrationPayment
--     -> mst.CourseRegistration
--   usr.PasswordResetToken
--     -> usr.UserAuth
--   usr.UserPermissionOverride
--   mst.Student
--   usr.Users
--
-- Exam tables (edu.Exam, edu.ExamSchedule, edu.ExamScheduleInstructor, etc.)
-- are NOT touched: per 0039's design, exams belong to the Course/Schedule,
-- not to any one student, and edu.ExamSchedule has no StudentID column at
-- all (a sitting is scheduled for a whole batch). If this database has a
-- per-student exam ATTEMPT/result table (e.g. mst.ExamAttempt, recording
-- which student sat which exam and their answers/score), it is guarded
-- with OBJECT_ID(...) IS NOT NULL below so this migration is a no-op for
-- that step on a database where the table doesn't exist yet, and starts
-- cascading it automatically once it does.

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

        -- Per-student exam attempt/result history, if this database has that
        -- table. Guarded with dynamic SQL behind OBJECT_ID so the migration
        -- runs cleanly whether or not the table exists.
        IF OBJECT_ID('mst.ExamAttemptAnswer') IS NOT NULL AND OBJECT_ID('mst.ExamAttempt') IS NOT NULL
        BEGIN
            DELETE aa FROM mst.ExamAttemptAnswer aa
             WHERE aa.AttemptID IN (SELECT AttemptID FROM mst.ExamAttempt WHERE StudentID = @ID);
        END
        IF OBJECT_ID('mst.ExamAttempt') IS NOT NULL
        BEGIN
            DELETE FROM mst.ExamAttempt WHERE StudentID = @ID;
        END

        -- Payment history, then the registrations themselves.
        DELETE FROM mst.CourseRegistrationPayment
         WHERE RegistrationID IN (SELECT RegistrationID FROM mst.CourseRegistration WHERE StudentID = @ID);
        DELETE FROM mst.CourseRegistration WHERE StudentID = @ID;

        -- Clear the "who did this" pointers before the account goes (same
        -- as usr.Users_HardDelete: this history belongs to the record it's
        -- stamped on, not to the account, and shouldn't block the delete).
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
-- mst.Student_GetDeleteImpact — RegistrationCount/PaymentCount no longer
-- describe a refusal (nothing is blocked anymore); they're purely
-- informational counts for the confirm dialog. Shape unchanged from 0040,
-- so no split is needed here the way 0043 split Course's (this one was
-- always single-result-set).
-- ============================================================
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

-- ============================================================
-- mst.Student_GetDeletePaymentImpact — per-currency registration/paid
-- breakdown, same shape as edu.Course_GetDeletePaymentImpact (0043), split
-- into its own single-result-set proc because IDBAccess only reads one
-- result set per call.
-- ============================================================
IF OBJECT_ID('mst.Student_GetDeletePaymentImpact') IS NOT NULL DROP PROCEDURE mst.Student_GetDeletePaymentImpact
GO
CREATE PROCEDURE [mst].[Student_GetDeletePaymentImpact]
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

        SELECT r.CurrencyCode,
               COUNT(*) AS RegistrationCount,
               ISNULL(SUM(pmt.Paid), 0) AS TotalPaid
        FROM mst.CourseRegistration r
        OUTER APPLY (
            SELECT SUM(Amount) AS Paid FROM mst.CourseRegistrationPayment
             WHERE RegistrationID = r.RegistrationID AND IsActive = 'A'
        ) pmt
        WHERE r.StudentID = @ID
        GROUP BY r.CurrencyCode;
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: mst.Student_GetDeletePaymentImpact', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- usr.Users_HardDelete — the parallel "delete the login account directly"
-- path (used from the Users admin screen) had the identical refusal for a
-- student-linked account with registrations. Bring it in line: cascade the
-- student's registrations/payments the same way, instead of refusing.
-- Every other guard (last Master Admin, teaching/invigilating assignments,
-- reschedule requests, uploaded material) is unchanged from 0040.
-- ============================================================
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

        IF EXISTS (SELECT 1 FROM edu.CourseScheduleInstructor WHERE UserID = @ID)
        BEGIN
            ;THROW 50000, 'This user is assigned to teach one or more course batches. Remove those assignments first, or deactivate the account instead.', 1;
        END

        IF EXISTS (SELECT 1 FROM edu.ExamScheduleInstructor WHERE UserID = @ID)
        BEGIN
            ;THROW 50000, 'This user is assigned to one or more exam sittings. Remove those assignments first, or deactivate the account instead.', 1;
        END

        IF EXISTS (SELECT 1 FROM edu.CourseScheduleReschedule WHERE RequestedByUserID = @ID)
        BEGIN
            ;THROW 50000, 'This user has submitted class reschedule requests, which are part of the schedule''s history. Deactivate the account instead.', 1;
        END

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

        IF @SID IS NOT NULL
        BEGIN
            IF OBJECT_ID('mst.ExamAttemptAnswer') IS NOT NULL AND OBJECT_ID('mst.ExamAttempt') IS NOT NULL
            BEGIN
                DELETE aa FROM mst.ExamAttemptAnswer aa
                 WHERE aa.AttemptID IN (SELECT AttemptID FROM mst.ExamAttempt WHERE StudentID = @SID);
            END
            IF OBJECT_ID('mst.ExamAttempt') IS NOT NULL
            BEGIN
                DELETE FROM mst.ExamAttempt WHERE StudentID = @SID;
            END

            DELETE FROM mst.CourseRegistrationPayment
             WHERE RegistrationID IN (SELECT RegistrationID FROM mst.CourseRegistration WHERE StudentID = @SID);
            DELETE FROM mst.CourseRegistration WHERE StudentID = @SID;
        END

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
