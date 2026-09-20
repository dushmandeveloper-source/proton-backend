-- 0074_homework_submission_grade_requires_marks.sql
--
-- Bug: edu.HomeworkSubmission_Grade always stamped GradedDate = GETDATE(),
-- even when @MarksAwarded was NULL (a lecturer submitting the grading form
-- with an empty Marks field). The C# model's IsGraded => GradedDate.HasValue
-- then showed "Graded: —" to the student for a submission nobody actually
-- graded yet. Fix: only stamp GradedDate when @MarksAwarded is actually
-- provided -- an empty Marks field now saves Feedback (if any) without
-- flipping the submission into "graded" state.

IF OBJECT_ID('edu.HomeworkSubmission_Grade') IS NOT NULL DROP PROCEDURE edu.HomeworkSubmission_Grade
GO
CREATE PROCEDURE [edu].[HomeworkSubmission_Grade]
(
    @APIKey        VARCHAR(100),
    @SubmissionID  VARCHAR(20),
    @MarksAwarded  DECIMAL(8,2) = NULL,
    @Feedback      NVARCHAR(1000) = '',
    @GradedByUserID VARCHAR(50),
    @LogUserID     VARCHAR(20) = '',
    @RetValue      VARCHAR(50) = '' OUT
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

        IF @MarksAwarded IS NULL
        BEGIN
            ;THROW 50000, 'Enter marks before saving a grade.', 1;
        END

        UPDATE edu.HomeworkSubmission
        SET MarksAwarded   = @MarksAwarded,
            Feedback       = NULLIF(@Feedback, ''),
            GradedByUserID = @GradedByUserID,
            GradedDate     = GETDATE(),
            UpdatedDate    = GETDATE()
        WHERE SubmissionID = @SubmissionID

        SET @RetValue = @SubmissionID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.HomeworkSubmission_Grade', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- One-time cleanup: the bug above already stamped GradedDate on rows with
-- no actual marks before this fix shipped. Clear those back to ungraded so
-- existing data isn't stuck showing a false "Graded: —" to the student.
UPDATE edu.HomeworkSubmission
SET GradedDate = NULL, GradedByUserID = NULL
WHERE MarksAwarded IS NULL AND GradedDate IS NOT NULL
GO
