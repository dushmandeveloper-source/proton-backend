-- 0054_grade_written_guard.sql
-- Bug: edu.ExamAttemptAnswer_GradeWritten had no guard against re-grading
-- an attempt that was already fully graded (IsFullyGraded=1) -- including
-- one already teacher-approved, admin-approved, or with its result
-- already released to the student. The Lecturer Grade page's "Save Grade"
-- form was reachable from the read-only "View Answers" link on the Exam
-- Results Review queue (an attempt that has IsFullyGraded=1 as a
-- precondition of even being in that queue), so a lecturer could silently
-- change a student's marks after approval/release with no re-review step
-- triggered. The Razor view is now also gated (IsFullyGraded hides the
-- form), but that alone is client-visible-only -- this proc-level guard is
-- the actual enforcement boundary, consistent with every other
-- authorization/ordering check in this pipeline living in the stored
-- procedure (see edu.ExamAttempt_AdminApprove's TeacherReviewStatus check
-- for the same pattern).

IF OBJECT_ID('edu.ExamAttemptAnswer_GradeWritten') IS NOT NULL
    DROP PROCEDURE edu.ExamAttemptAnswer_GradeWritten
GO
CREATE PROCEDURE [edu].[ExamAttemptAnswer_GradeWritten]
(
    @APIKey varchar(100),
    @AttemptID varchar(20),
    @QuestionID varchar(20),
    @MarksAwarded decimal(8,2)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        IF NOT EXISTS (SELECT 1 FROM edu.ExamAttemptAnswer WHERE AttemptID = @AttemptID AND QuestionID = @QuestionID)
        BEGIN
            ;THROW 50000, 'Answer row not found', 1;
        END

        IF EXISTS (SELECT 1 FROM edu.ExamAttempt WHERE AttemptID = @AttemptID AND IsFullyGraded = 1)
        BEGIN
            ;THROW 50000, 'This attempt is already fully graded -- reject it first to re-grade', 1;
        END

        BEGIN TRANSACTION

        -- IsCorrect left NULL for Written answers: correctness is not binary for free-text,
        -- only a numeric mark is meaningful, so IsCorrect is intentionally not derived here.
        UPDATE edu.ExamAttemptAnswer
        SET MarksAwarded = @MarksAwarded
        WHERE AttemptID = @AttemptID AND QuestionID = @QuestionID

        -- Driven from ExamQuestion (not ExamAttemptAnswer) so an unanswered Written question still counts as ungraded
        DECLARE @UngradedWritten int
        SELECT @UngradedWritten = COUNT(*)
        FROM edu.ExamQuestion q
        JOIN edu.ExamAttempt att ON att.ExamID = q.ExamID
        LEFT JOIN edu.ExamAttemptAnswer aa ON aa.AttemptID = att.AttemptID AND aa.QuestionID = q.QuestionID
        WHERE att.AttemptID = @AttemptID
          AND q.QuestionType = 'Written'
          AND q.IsActive = 'A'
          AND aa.MarksAwarded IS NULL

        IF @UngradedWritten = 0
        BEGIN
            DECLARE @Total decimal(8,2)
            SELECT @Total = SUM(MarksAwarded) FROM edu.ExamAttemptAnswer WHERE AttemptID = @AttemptID AND MarksAwarded IS NOT NULL

            UPDATE edu.ExamAttempt
            SET TotalMarksAwarded = @Total, IsFullyGraded = 1, UpdatedDate = GETDATE()
            WHERE AttemptID = @AttemptID
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttemptAnswer_GradeWritten', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
