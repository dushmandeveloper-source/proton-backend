-- 0073_homework_submission_resubmit_request.sql
--
-- Locks a homework submission once graded -- a student should not be able
-- to freely resubmit and silently invalidate a grade the lecturer already
-- gave. Resubmission now requires the lecturer/admin to explicitly click
-- "Request Resubmission" (edu.HomeworkSubmission_RequestResubmission),
-- which flips ResubmissionRequested = 1 and re-opens the upload form for
-- that one student/item. edu.HomeworkSubmission_Upsert (the student's
-- submit/resubmit action) now refuses a resubmission unless either the
-- submission has never been graded yet, or ResubmissionRequested = 1 --
-- and clears the flag once the new file lands, same as it already clears
-- MarksAwarded/Feedback/GradedDate.

IF COL_LENGTH('edu.HomeworkSubmission', 'ResubmissionRequested') IS NULL
    ALTER TABLE edu.HomeworkSubmission ADD ResubmissionRequested BIT NOT NULL DEFAULT (0)
GO

IF COL_LENGTH('edu.HomeworkSubmission', 'ResubmissionRemark') IS NULL
    ALTER TABLE edu.HomeworkSubmission ADD ResubmissionRemark NVARCHAR(500) NULL
GO

-- ============================================================
-- edu.HomeworkSubmission_Upsert -- now refuses to overwrite a graded
-- submission unless ResubmissionRequested = 1. First-time submission
-- (no existing row) is always allowed, same as before.
-- ============================================================
IF OBJECT_ID('edu.HomeworkSubmission_Upsert') IS NOT NULL DROP PROCEDURE edu.HomeworkSubmission_Upsert
GO
CREATE PROCEDURE [edu].[HomeworkSubmission_Upsert]
(
    @APIKey     VARCHAR(100),
    @MaterialID VARCHAR(20),
    @StudentID  VARCHAR(20),
    @FileURL    VARCHAR(500),
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

        IF NOT EXISTS (
            SELECT 1
            FROM edu.LectureMaterial m
            JOIN edu.CourseSchedule sch ON sch.ScheduleID = m.ScheduleID
            JOIN mst.CourseRegistration r ON r.CourseID = sch.CourseID AND (r.ScheduleID IS NULL OR r.ScheduleID = sch.ScheduleID)
            WHERE m.MaterialID = @MaterialID
              AND m.Category = 'Homework'
              AND m.IsActive = 'A'
              AND r.StudentID = @StudentID
              AND r.IsActive = 'A'
        )
        BEGIN
            ;THROW 50000, 'Homework not found, or you are not enrolled in this batch.', 1;
        END

        DECLARE @ExistingID VARCHAR(20)
        DECLARE @ExistingGradedDate DATETIME
        DECLARE @ExistingResubmissionRequested BIT
        SELECT @ExistingID = SubmissionID, @ExistingGradedDate = GradedDate, @ExistingResubmissionRequested = ResubmissionRequested
        FROM edu.HomeworkSubmission WHERE MaterialID = @MaterialID AND StudentID = @StudentID

        IF @ExistingID IS NOT NULL
        BEGIN
            IF @ExistingGradedDate IS NOT NULL AND @ExistingResubmissionRequested = 0
            BEGIN
                ;THROW 50000, 'This submission has already been graded. Ask your lecturer to request a resubmission first.', 1;
            END

            UPDATE edu.HomeworkSubmission
            SET FileURL       = @FileURL,
                SubmittedDate = GETDATE(),
                MarksAwarded  = NULL,
                Feedback      = NULL,
                GradedByUserID = NULL,
                GradedDate    = NULL,
                ResubmissionRequested = 0,
                ResubmissionRemark = NULL,
                UpdatedDate   = GETDATE()
            WHERE SubmissionID = @ExistingID

            SET @RetValue = @ExistingID
        END
        ELSE
        BEGIN
            DECLARE @PrimaryKey VARCHAR(20)
            EXEC syst.NumberFormat_Get 'edu.HomeworkSubmission', 'SubmissionID', @PrimaryKey OUT

            INSERT INTO edu.HomeworkSubmission
                (SubmissionID, MaterialID, StudentID, FileURL, SubmittedDate, MarksAwarded, Feedback, GradedByUserID, GradedDate, ResubmissionRequested, ResubmissionRemark, CreatedDate, UpdatedDate)
            VALUES
                (@PrimaryKey, @MaterialID, @StudentID, @FileURL, GETDATE(), NULL, NULL, NULL, NULL, 0, NULL, GETDATE(), NULL)

            EXEC syst.NumberFormat_Set 'edu.HomeworkSubmission'

            SET @RetValue = @PrimaryKey
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.HomeworkSubmission_Upsert', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.HomeworkSubmission_RequestResubmission -- lecturer/admin re-opens
-- the upload form for one already-graded submission. Clears the existing
-- grade too -- once resubmitted, the old grade no longer applies to
-- whatever new file lands (same reasoning as a normal resubmission).
-- ============================================================
IF OBJECT_ID('edu.HomeworkSubmission_RequestResubmission') IS NOT NULL DROP PROCEDURE edu.HomeworkSubmission_RequestResubmission
GO
CREATE PROCEDURE [edu].[HomeworkSubmission_RequestResubmission]
(
    @APIKey       VARCHAR(100),
    @SubmissionID VARCHAR(20),
    @Remark       NVARCHAR(500) = '',
    @LogUserID    VARCHAR(20) = '',
    @RetValue     VARCHAR(50) = '' OUT
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

        IF NOT EXISTS (SELECT 1 FROM edu.HomeworkSubmission WHERE SubmissionID = @SubmissionID)
        BEGIN
            ;THROW 50000, 'Submission not found.', 1;
        END

        UPDATE edu.HomeworkSubmission
        SET ResubmissionRequested = 1,
            ResubmissionRemark    = NULLIF(@Remark, ''),
            UpdatedDate           = GETDATE()
        WHERE SubmissionID = @SubmissionID

        SET @RetValue = @SubmissionID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.HomeworkSubmission_RequestResubmission', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
