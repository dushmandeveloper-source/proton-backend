-- 0129_exam_attempt_submitted_utc.sql
--
-- Bug (reported by the client): submission times were wrong. edu.ExamAttempt.
-- SubmittedDate was written with GETDATE() -- the DB server's own clock, which
-- on the live host is US Pacific time -- and shown as-is, so every submission
-- looked ~13.5 h earlier than it really was in Sri Lanka. StartedDate/
-- ExpiresDate have been UTC since 0071.
--
-- Fix: ExamAttempt_Submit writes GETUTCDATE() (the app now converts it to
-- Sri Lanka time for display, like StartedDate), and existing rows are
-- converted from this server's own time zone to UTC (AT TIME ZONE handles
-- daylight saving per row, and CURRENT_TIMEZONE_ID() makes it right on any
-- environment, local or hosted).

UPDATE edu.ExamAttempt
SET SubmittedDate = CONVERT(datetime, SubmittedDate AT TIME ZONE CURRENT_TIMEZONE_ID() AT TIME ZONE 'UTC')
WHERE SubmittedDate IS NOT NULL
GO

IF OBJECT_ID('edu.ExamAttempt_Submit') IS NOT NULL
    DROP PROCEDURE edu.ExamAttempt_Submit
GO
CREATE PROCEDURE [edu].[ExamAttempt_Submit]
(
    @APIKey varchar(100),
    @AttemptID varchar(20),
    @IsForced bit = 0,
    @Terminate bit = 0
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        DECLARE @Status varchar(20)
        DECLARE @ExpiresDate datetime
        DECLARE @ExamID varchar(20)
        SELECT @Status = Status, @ExpiresDate = ExpiresDate, @ExamID = ExamID
        FROM edu.ExamAttempt WHERE AttemptID = @AttemptID

        IF @Status IS NULL
        BEGIN
            ;THROW 50000, 'Attempt not found', 1;
        END

        IF @Status <> 'InProgress'
        BEGIN
            ;THROW 50000, 'Attempt already finalized', 1;
        END

        DECLARE @FinalStatus varchar(20) = CASE
            WHEN @Terminate = 1 THEN 'Terminated'
            WHEN GETUTCDATE() > @ExpiresDate THEN 'Expired'
            ELSE 'Submitted'
        END

        IF @IsForced = 0 AND @Terminate = 0 AND @FinalStatus = 'Submitted' AND EXISTS (
            SELECT 1
            FROM edu.ExamQuestion q
            LEFT JOIN edu.ExamAttemptAnswer aa ON aa.AttemptID = @AttemptID AND aa.QuestionID = q.QuestionID
            WHERE q.ExamID = @ExamID AND q.IsActive = 'A'
              AND (
                    aa.QuestionID IS NULL
                 OR (q.QuestionType = 'MCQ' AND (aa.SelectedOptionID IS NULL OR aa.SelectedOptionID = ''))
                 OR (q.QuestionType = 'Written' AND (aa.WrittenAnswerText IS NULL OR aa.WrittenAnswerText = ''))
              )
        )
        BEGIN
            ;THROW 50000, 'Answer every question before submitting', 1;
        END

        BEGIN TRANSACTION

        UPDATE aa
        SET aa.IsCorrect = CASE WHEN opt.IsCorrect = 1 THEN 1 ELSE 0 END,
            aa.MarksAwarded = CASE WHEN opt.IsCorrect = 1 THEN q.Marks ELSE 0 END
        FROM edu.ExamAttemptAnswer aa
        JOIN edu.ExamQuestion q ON q.QuestionID = aa.QuestionID
        LEFT JOIN edu.ExamQuestionOption opt ON opt.OptionID = aa.SelectedOptionID
        WHERE aa.AttemptID = @AttemptID AND q.QuestionType = 'MCQ' AND q.IsActive = 'A'

        DECLARE @Total decimal(8,2)
        SELECT @Total = SUM(MarksAwarded) FROM edu.ExamAttemptAnswer WHERE AttemptID = @AttemptID AND MarksAwarded IS NOT NULL

        DECLARE @UngradedWritten int
        SELECT @UngradedWritten = COUNT(*)
        FROM edu.ExamQuestion q
        JOIN edu.ExamAttempt att ON att.ExamID = q.ExamID
        LEFT JOIN edu.ExamAttemptAnswer aa ON aa.AttemptID = att.AttemptID AND aa.QuestionID = q.QuestionID
        WHERE att.AttemptID = @AttemptID
          AND q.QuestionType = 'Written'
          AND q.IsActive = 'A'
          AND aa.MarksAwarded IS NULL

        UPDATE edu.ExamAttempt
        SET Status = @FinalStatus,
            SubmittedDate = GETUTCDATE(),   -- 0129: UTC like StartedDate
            TotalMarksAwarded = @Total,
            IsFullyGraded = CASE WHEN @UngradedWritten = 0 THEN 1 ELSE 0 END,
            UpdatedDate = GETDATE()
        WHERE AttemptID = @AttemptID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttempt_Submit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
