-- 0049_exam_attempt_violation.sql
-- Phase 3: violation detection + strikes.
--
-- edu.ExamAttempt.Status gains a new valid value 'Terminated' (column is
-- plain varchar(20) with no CHECK constraint today, per 0047, so no ALTER
-- is needed for the new value itself -- only doc-comment updates below and
-- the Submit proc extension).
--
-- Camera/screen-share loss (Phase 2) is deliberately NOT logged into this
-- table -- see plan doc "Design decision" section above for the full
-- reasoning. Only the 5 strike-triggering signals are recorded here:
-- TabSwitch | WindowBlur | FullscreenExit | CopyPaste | RightClick.
--
-- Strike policy: 3 strikes total across all 5 types combined (not
-- per-type). Strikes 1-2 are logged with CountsAsStrike=1 and a
-- StrikeNumber (1 or 2); the exam continues. The 3rd counted violation is
-- logged as StrikeNumber=3 AND, in the same transaction, finalizes the
-- attempt via edu.ExamAttempt_Submit's new @Terminate=1 path -- a
-- killed/disconnected browser right after the 3rd violation cannot leave
-- the attempt hanging open in InProgress, because the server already
-- finalized it before responding to that 3rd ReportViolation call.

IF OBJECT_ID('edu.ExamAttemptViolation') IS NULL
BEGIN
    CREATE TABLE [edu].[ExamAttemptViolation] (
        [ViolationID] varchar(20) NOT NULL,
        [AttemptID] varchar(20) NOT NULL,
        [ViolationType] varchar(30) NOT NULL, -- TabSwitch | WindowBlur | FullscreenExit | CopyPaste | RightClick
        [CountsAsStrike] bit NOT NULL,
        [StrikeNumber] int NULL,
        [OccurredDate] datetime NOT NULL,
        CONSTRAINT [PK_edu_ExamAttemptViolation] PRIMARY KEY CLUSTERED ([ViolationID] ASC),
        CONSTRAINT [FK_edu_ExamAttemptViolation_Attempt] FOREIGN KEY ([AttemptID]) REFERENCES [edu].[ExamAttempt]([AttemptID])
    )
END
GO

IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.ExamAttemptViolation')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength)
    VALUES ('edu.ExamAttemptViolation', 'ViolationID', 'EXAV', 1, 12)
GO

-- ============================================================
-- edu.ExamAttempt_Submit extended with @Terminate bit = 0.
-- Default 0 preserves exact current behavior for every existing caller
-- (Phase 1 manual submit, Phase 2 forced auto-submit via @IsForced).
-- When @Terminate = 1: completeness check is always skipped (same as
-- @IsForced = 1) and final Status is forced to 'Terminated' regardless of
-- whether ExpiresDate has already passed.
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

        -- Terminated attempts skip the expired-vs-submitted distinction
        -- entirely -- termination is a distinct, stricter outcome regardless
        -- of whether time had also run out.
        DECLARE @FinalStatus varchar(20) = CASE
            WHEN @Terminate = 1 THEN 'Terminated'
            WHEN GETDATE() > @ExpiresDate THEN 'Expired'
            ELSE 'Submitted'
        END

        -- Require every active question to have an answer row before a
        -- willing, on-time submit is accepted -- but never for an
        -- already-expired attempt, which must still be scored on whatever
        -- was saved. Also skipped when @IsForced = 1 (Phase 2's
        -- camera/screen-share grace-window auto-submit) or @Terminate = 1
        -- (this phase's strike-3 auto-finalize) -- neither is a willing
        -- manual submit, so trapping either behind "answer everything
        -- first" defeats the point of ending the attempt.
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

        -- Auto-score MCQ answers
        UPDATE aa
        SET aa.IsCorrect = CASE WHEN opt.IsCorrect = 1 THEN 1 ELSE 0 END,
            aa.MarksAwarded = CASE WHEN opt.IsCorrect = 1 THEN q.Marks ELSE 0 END
        FROM edu.ExamAttemptAnswer aa
        JOIN edu.ExamQuestion q ON q.QuestionID = aa.QuestionID
        LEFT JOIN edu.ExamQuestionOption opt ON opt.OptionID = aa.SelectedOptionID
        WHERE aa.AttemptID = @AttemptID AND q.QuestionType = 'MCQ' AND q.IsActive = 'A'

        -- Sum whatever marks are known so far (partial until Written rows graded)
        DECLARE @Total decimal(8,2)
        SELECT @Total = SUM(MarksAwarded) FROM edu.ExamAttemptAnswer WHERE AttemptID = @AttemptID AND MarksAwarded IS NOT NULL

        -- Fully graded if no Written questions exist for this exam, or all Written answers already have MarksAwarded
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

-- ============================================================
-- edu.ExamAttemptViolation_Report
-- The single server-authoritative write path for every violation event.
-- Inserts the row, computes the running CountsAsStrike total, and on the
-- 3rd counted violation finalizes the attempt in the SAME transaction via
-- edu.ExamAttempt_Submit's @Terminate=1 path (called as a nested EXEC,
-- same pattern this codebase already trusts for cross-proc calls within
-- one transaction -- see edu.ExamAttemptAnswer_GradeWritten's own
-- self-contained recompute of IsFullyGraded for precedent on keeping
-- finalization logic in one place).
-- Returns @StrikeCount (running total of CountsAsStrike rows, 0-3) and
-- @Status (the attempt's Status AFTER this report is applied) as OUT
-- params so the calling C# layer/JSON response never has to re-query.
-- ============================================================
IF OBJECT_ID('edu.ExamAttemptViolation_Report') IS NOT NULL
    DROP PROCEDURE edu.ExamAttemptViolation_Report
GO
CREATE PROCEDURE [edu].[ExamAttemptViolation_Report]
(
    @APIKey varchar(100),
    @AttemptID varchar(20),
    @ViolationType varchar(30),
    @StrikeCount int = 0 OUT,
    @Status varchar(20) = '' OUT
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        IF @ViolationType NOT IN ('TabSwitch', 'WindowBlur', 'FullscreenExit', 'CopyPaste', 'RightClick')
        BEGIN
            ;THROW 50000, 'Unknown violation type', 1;
        END

        DECLARE @CurrentStatus varchar(20)
        SELECT @CurrentStatus = Status FROM edu.ExamAttempt WHERE AttemptID = @AttemptID

        IF @CurrentStatus IS NULL
        BEGIN
            ;THROW 50000, 'Attempt not found', 1;
        END

        -- An already-finalized attempt (Submitted/Expired/Terminated from an
        -- earlier request racing this one) accepts no further violations --
        -- report back its current state so the client can redirect, but
        -- don't insert a row against a closed attempt.
        IF @CurrentStatus <> 'InProgress'
        BEGIN
            SELECT @StrikeCount = COUNT(*) FROM edu.ExamAttemptViolation WHERE AttemptID = @AttemptID AND CountsAsStrike = 1
            SET @Status = @CurrentStatus
            RETURN
        END

        BEGIN TRANSACTION

        DECLARE @PrimaryKey VARCHAR(20) = ''
        EXEC syst.NumberFormat_Get 'edu.ExamAttemptViolation', 'ViolationID', @PrimaryKey OUT

        DECLARE @PriorStrikes int
        SELECT @PriorStrikes = COUNT(*) FROM edu.ExamAttemptViolation WHERE AttemptID = @AttemptID AND CountsAsStrike = 1

        DECLARE @NewStrikeNumber int = @PriorStrikes + 1

        INSERT INTO edu.ExamAttemptViolation
            (ViolationID, AttemptID, ViolationType, CountsAsStrike, StrikeNumber, OccurredDate)
        VALUES
            (@PrimaryKey, @AttemptID, @ViolationType, 1, @NewStrikeNumber, GETDATE())

        EXEC syst.NumberFormat_Set 'edu.ExamAttemptViolation'

        SET @StrikeCount = @NewStrikeNumber

        IF @NewStrikeNumber >= 3
        BEGIN
            -- 3rd strike: finalize the attempt right now, in this same
            -- transaction, so a killed/disconnected browser immediately
            -- after this call cannot leave the attempt open. Nested EXEC
            -- of ExamAttempt_Submit runs inside this transaction (SQL
            -- Server nests transactions started with BEGIN TRANSACTION by
            -- reference-counting @@TRANCOUNT; the inner proc's own COMMIT
            -- only decrements the count, the outer COMMIT below is what
            -- actually persists everything).
            EXEC edu.ExamAttempt_Submit @APIKey = @APIKey, @AttemptID = @AttemptID, @IsForced = 1, @Terminate = 1

            SET @Status = 'Terminated'
        END
        ELSE
        BEGIN
            SET @Status = 'InProgress'
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttemptViolation_Report', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamAttemptViolation_ListByAttempt
-- Used by the new admin violation-trail view (Task 8).
-- ============================================================
IF OBJECT_ID('edu.ExamAttemptViolation_ListByAttempt') IS NOT NULL
    DROP PROCEDURE edu.ExamAttemptViolation_ListByAttempt
GO
CREATE PROCEDURE [edu].[ExamAttemptViolation_ListByAttempt]
(
    @APIKey varchar(100),
    @AttemptID varchar(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT ViolationID, AttemptID, ViolationType, CountsAsStrike, StrikeNumber, OccurredDate
        FROM edu.ExamAttemptViolation
        WHERE AttemptID = @AttemptID
        ORDER BY OccurredDate ASC
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttemptViolation_ListByAttempt', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
