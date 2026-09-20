-- 0071_exam_attempt_utc_timer.sql
--
-- Bug: edu.ExamAttempt.StartedDate/ExpiresDate were written with GETDATE(),
-- which returns the DATABASE SERVER's own local clock -- confirmed to be US
-- Pacific time on the hosted SQL instance (sql8005.site4now.net), not UTC
-- and not Sri Lanka time (the business's actual timezone). The app layer's
-- exam-timer countdown (ExamAttempt.SecondsRemaining, Web_Backend/Areas/
-- Admin/Models/ExamAttempt.cs) compares ExpiresDate against DateTime.UtcNow
-- -- correct in isolation, but wrong when ExpiresDate itself was never UTC
-- to begin with. Result: an attempt's real expiry time was off by the DB
-- server's UTC offset (7-8 hours depending on DST), so attempts could
-- expire far too early or allow far too much extra time.
--
-- Fix: redefine the three procs that read/write StartedDate/ExpiresDate/the
-- expiry check to use GETUTCDATE() instead of GETDATE(), so ExpiresDate is
-- stored as real UTC going forward and consistently compared as UTC
-- everywhere (both in T-SQL's own GETUTCDATE() > ExpiresDate checks and in
-- the C# SecondsRemaining comparison against DateTime.UtcNow). This does
-- NOT touch StartedDate/ExpiresDate values already written by prior
-- GETDATE()-based inserts -- any attempt already InProgress when this
-- migration runs keeps its old (Pacific-local) timestamps and should be
-- manually reviewed/expired if still open.
--
-- Audit-only columns (CreatedDate, UpdatedDate, SubmittedDate, AnsweredDate,
-- TeacherReviewedDate, AdminReviewedDate, ResultReleasedDate, OccurredDate)
-- are left on GETDATE() -- they're display-only "when did this happen"
-- stamps, not compared against anything, so changing them isn't needed for
-- correctness and would just mean two different clocks show up in the
-- admin UI's audit trail for no benefit.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

-- ============================================================
-- edu.ExamAttempt_Start -- StartedDate/ExpiresDate now UTC.
-- ============================================================
IF OBJECT_ID('edu.ExamAttempt_Start') IS NOT NULL
    DROP PROCEDURE edu.ExamAttempt_Start
GO
CREATE PROCEDURE [edu].[ExamAttempt_Start]
(
    @APIKey varchar(100),
    @ExamID varchar(20),
    @StudentID varchar(20),
    @RetValue varchar(50) = '' OUT
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        DECLARE @DurationMinutes int
        DECLARE @IsActive varchar(1)
        DECLARE @MaxAttempts int
        SELECT @DurationMinutes = DurationMinutes, @IsActive = IsActive, @MaxAttempts = MaxAttempts
        FROM edu.Exam WHERE ExamID = @ExamID

        IF @IsActive IS NULL OR @IsActive <> 'A'
        BEGIN
            ;THROW 50000, 'Exam is not active', 1;
        END

        DECLARE @ExistingCount int
        SELECT @ExistingCount = COUNT(*) FROM edu.ExamAttempt WHERE ExamID = @ExamID AND StudentID = @StudentID

        IF @ExistingCount >= @MaxAttempts
        BEGIN
            ;THROW 50000, 'Maximum attempts reached', 1;
        END

        BEGIN TRANSACTION

        DECLARE @PrimaryKey VARCHAR(20) = ''
        EXEC syst.NumberFormat_Get 'edu.ExamAttempt', 'AttemptID', @PrimaryKey OUT

        DECLARE @Now datetime = GETUTCDATE()
        DECLARE @Expires datetime = DATEADD(MINUTE, ISNULL(@DurationMinutes, 60), @Now)

        INSERT INTO edu.ExamAttempt
            (AttemptID, ExamID, StudentID, AttemptNumber, StartedDate, ExpiresDate, SubmittedDate, Status, TotalMarksAwarded, IsFullyGraded, CreatedDate, UpdatedDate)
        VALUES
            (@PrimaryKey, @ExamID, @StudentID, @ExistingCount + 1, @Now, @Expires, NULL, 'InProgress', NULL, 0, GETDATE(), NULL)

        EXEC syst.NumberFormat_Set 'edu.ExamAttempt'

        SET @RetValue = @PrimaryKey

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttempt_Start', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamAttemptAnswer_Save -- expiry check against UTC now.
-- ============================================================
IF OBJECT_ID('edu.ExamAttemptAnswer_Save') IS NOT NULL
    DROP PROCEDURE edu.ExamAttemptAnswer_Save
GO
CREATE PROCEDURE [edu].[ExamAttemptAnswer_Save]
(
    @APIKey varchar(100),
    @AttemptID varchar(20),
    @QuestionID varchar(20),
    @SelectedOptionID varchar(20) = NULL,
    @WrittenAnswerText nvarchar(max) = NULL
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
        SELECT @Status = Status, @ExpiresDate = ExpiresDate FROM edu.ExamAttempt WHERE AttemptID = @AttemptID

        IF @Status IS NULL
        BEGIN
            ;THROW 50000, 'Attempt not found', 1;
        END

        BEGIN TRANSACTION

        IF @Status <> 'InProgress' OR GETUTCDATE() > @ExpiresDate
        BEGIN
            IF @Status = 'InProgress' AND GETUTCDATE() > @ExpiresDate
            BEGIN
                UPDATE edu.ExamAttempt SET Status = 'Expired', UpdatedDate = GETDATE() WHERE AttemptID = @AttemptID
            END
            COMMIT TRANSACTION
            ;THROW 50000, 'Attempt is no longer accepting answers', 1;
        END

        IF EXISTS (SELECT 1 FROM edu.ExamAttemptAnswer WHERE AttemptID = @AttemptID AND QuestionID = @QuestionID)
        BEGIN
            UPDATE edu.ExamAttemptAnswer
            SET SelectedOptionID = @SelectedOptionID,
                WrittenAnswerText = @WrittenAnswerText,
                AnsweredDate = GETDATE()
            WHERE AttemptID = @AttemptID AND QuestionID = @QuestionID
        END
        ELSE
        BEGIN
            INSERT INTO edu.ExamAttemptAnswer
                (AttemptID, QuestionID, SelectedOptionID, WrittenAnswerText, IsCorrect, MarksAwarded, AnsweredDate)
            VALUES
                (@AttemptID, @QuestionID, @SelectedOptionID, @WrittenAnswerText, NULL, NULL, GETDATE())
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttemptAnswer_Save', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamAttempt_Submit -- @FinalStatus expiry check against UTC now.
-- Signature/body otherwise identical to 0049's version (the last one to
-- redefine this proc) -- only GETDATE() > @ExpiresDate becomes
-- GETUTCDATE() > @ExpiresDate.
-- ============================================================
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
            SubmittedDate = GETDATE(),
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
