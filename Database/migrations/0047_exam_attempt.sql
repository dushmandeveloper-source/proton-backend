-- 0047_exam_attempt.sql
-- Phase 1 exam-taking foundation: ExamAttempt + ExamAttemptAnswer

IF OBJECT_ID('edu.ExamAttempt') IS NULL
BEGIN
    CREATE TABLE [edu].[ExamAttempt] (
        [AttemptID] varchar(20) NOT NULL,
        [ExamID] varchar(20) NOT NULL,
        [StudentID] varchar(20) NOT NULL,
        [AttemptNumber] int NOT NULL,
        [StartedDate] datetime NOT NULL,
        [ExpiresDate] datetime NOT NULL,
        [SubmittedDate] datetime NULL,
        [Status] varchar(20) NOT NULL,
        [TotalMarksAwarded] decimal(8,2) NULL,
        [IsFullyGraded] bit NOT NULL DEFAULT 0,
        [CreatedDate] datetime NOT NULL,
        [UpdatedDate] datetime NULL,
        CONSTRAINT [PK_edu_ExamAttempt] PRIMARY KEY CLUSTERED ([AttemptID] ASC),
        CONSTRAINT [FK_edu_ExamAttempt_Exam] FOREIGN KEY ([ExamID]) REFERENCES [edu].[Exam]([ExamID]),
        CONSTRAINT [FK_edu_ExamAttempt_Student] FOREIGN KEY ([StudentID]) REFERENCES [mst].[Student]([StudentID])
    )
END
GO

IF OBJECT_ID('edu.ExamAttemptAnswer') IS NULL
BEGIN
    CREATE TABLE [edu].[ExamAttemptAnswer] (
        [AttemptID] varchar(20) NOT NULL,
        [QuestionID] varchar(20) NOT NULL,
        [SelectedOptionID] varchar(20) NULL,
        [WrittenAnswerText] nvarchar(max) NULL,
        [IsCorrect] bit NULL,
        [MarksAwarded] decimal(8,2) NULL,
        [AnsweredDate] datetime NOT NULL,
        CONSTRAINT [PK_edu_ExamAttemptAnswer] PRIMARY KEY CLUSTERED ([AttemptID] ASC, [QuestionID] ASC),
        CONSTRAINT [FK_edu_ExamAttemptAnswer_Attempt] FOREIGN KEY ([AttemptID]) REFERENCES [edu].[ExamAttempt]([AttemptID]),
        CONSTRAINT [FK_edu_ExamAttemptAnswer_Question] FOREIGN KEY ([QuestionID]) REFERENCES [edu].[ExamQuestion]([QuestionID]),
        CONSTRAINT [FK_edu_ExamAttemptAnswer_Option] FOREIGN KEY ([SelectedOptionID]) REFERENCES [edu].[ExamQuestionOption]([OptionID])
    )
END
GO

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

        DECLARE @Now datetime = GETDATE()
        DECLARE @Expires datetime = DATEADD(MINUTE, ISNULL(@DurationMinutes, 60), @Now)

        INSERT INTO edu.ExamAttempt
            (AttemptID, ExamID, StudentID, AttemptNumber, StartedDate, ExpiresDate, SubmittedDate, Status, TotalMarksAwarded, IsFullyGraded, CreatedDate, UpdatedDate)
        VALUES
            (@PrimaryKey, @ExamID, @StudentID, @ExistingCount + 1, @Now, @Expires, NULL, 'InProgress', NULL, 0, @Now, NULL)

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

IF OBJECT_ID('edu.ExamAttempt_Get') IS NOT NULL
    DROP PROCEDURE edu.ExamAttempt_Get
GO
CREATE PROCEDURE [edu].[ExamAttempt_Get]
(
    @APIKey varchar(100),
    @ID varchar(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT
            a.AttemptID, a.ExamID, a.StudentID, a.AttemptNumber, a.StartedDate, a.ExpiresDate,
            a.SubmittedDate, a.Status, a.TotalMarksAwarded, a.IsFullyGraded, a.CreatedDate, a.UpdatedDate,
            e.ExamTitle, e.DurationMinutes, e.TotalMarks, e.PassingMarks, e.PassingPercentage
        FROM edu.ExamAttempt a
        JOIN edu.Exam e ON e.ExamID = a.ExamID
        WHERE a.AttemptID = @ID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttempt_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

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

        IF @Status <> 'InProgress' OR GETDATE() > @ExpiresDate
        BEGIN
            IF @Status = 'InProgress' AND GETDATE() > @ExpiresDate
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

IF OBJECT_ID('edu.ExamAttemptAnswer_List') IS NOT NULL
    DROP PROCEDURE edu.ExamAttemptAnswer_List
GO
CREATE PROCEDURE [edu].[ExamAttemptAnswer_List]
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

        -- Driven from edu.ExamQuestion (every active question belonging to
        -- this attempt's exam), LEFT JOINed to edu.ExamAttemptAnswer so a
        -- question the student hasn't answered yet still appears (with NULL
        -- answer fields) instead of being invisible until something is saved
        -- for it -- a fresh attempt has zero ExamAttemptAnswer rows, so an
        -- INNER JOIN from that table alone would show no questions at all.
        SELECT
            att.AttemptID, q.QuestionID, aa.SelectedOptionID, aa.WrittenAnswerText,
            aa.IsCorrect, aa.MarksAwarded, aa.AnsweredDate,
            q.QuestionType, q.QuestionTextLatex, q.ImageURL, q.AudioURL, q.VideoURL, q.Marks, q.SortOrder
        FROM edu.ExamAttempt att
        JOIN edu.ExamQuestion q ON q.ExamID = att.ExamID AND q.IsActive = 'A'
        LEFT JOIN edu.ExamAttemptAnswer aa ON aa.AttemptID = att.AttemptID AND aa.QuestionID = q.QuestionID
        WHERE att.AttemptID = @AttemptID
        ORDER BY q.SortOrder
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttemptAnswer_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
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
        -- was saved (this mirrors the client-side Submit-button gating in
        -- Take.cshtml, but is the actual enforcement boundary: a request
        -- forged straight at this proc, bypassing the browser UI entirely,
        -- is rejected here regardless of what any client-side check did).
        -- Also skipped when @IsForced = 1 -- this is the exam UI's own
        -- auto-submit path when the student's camera/screen-share was lost
        -- and never restored within the grace window; that student no
        -- longer has working proctoring, so trapping them behind "answer
        -- everything first" defeats the point of ending the attempt. Also
        -- skipped when @Terminate = 1 (Phase 3's strike-3 auto-finalize) for
        -- the same reason.
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

IF OBJECT_ID('edu.ExamAttempt_ListPendingGrading') IS NOT NULL
    DROP PROCEDURE edu.ExamAttempt_ListPendingGrading
GO
CREATE PROCEDURE [edu].[ExamAttempt_ListPendingGrading]
(
    @APIKey varchar(100)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT
            a.AttemptID, a.ExamID, a.StudentID, a.AttemptNumber, a.StartedDate, a.ExpiresDate,
            a.SubmittedDate, a.Status, a.TotalMarksAwarded, a.IsFullyGraded,
            e.ExamTitle, u.FullName AS StudentName
        FROM edu.ExamAttempt a
        JOIN edu.Exam e ON e.ExamID = a.ExamID
        JOIN mst.Student s ON s.StudentID = a.StudentID
        JOIN usr.Users u ON u.UserID = s.UserID
        WHERE a.IsFullyGraded = 0 AND a.Status IN ('Submitted', 'Expired')
        ORDER BY a.SubmittedDate ASC
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttempt_ListPendingGrading', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

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

IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.ExamAttempt')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength)
    VALUES ('edu.ExamAttempt', 'AttemptID', 'EXAT', 1, 12)
GO

IF NOT EXISTS (SELECT 1 FROM syst.NumberFormat WHERE TableName = 'edu.ExamAttemptAnswer')
    INSERT INTO syst.NumberFormat (TableName, FieldName, Prefix, NumberPart, NumberLength)
    VALUES ('edu.ExamAttemptAnswer', 'AttemptID_QuestionID', 'EXAA', 1, 12)
GO
