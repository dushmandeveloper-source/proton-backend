-- 0127_assignment_attempts.sql
--
-- Online assignments with more than one attempt (edu.Exam.MaxAttempts, now
-- set from the assignment form; 1 = as before). The LATEST attempt counts.
-- A submitted attempt is only marked once it is FINAL:
--   * the student has used all attempts, or
--   * the due date (or their redo deadline) has passed, or
--   * the student pressed "I'm done -- send for marking" (this table).
-- Earlier attempts are superseded: kept on record, never marked, never shown
-- to the student. Final / superseded are worked out in C#
-- (Areas/Student/OnlineAssignmentRules.Progress / Classify).
--  * edu.ExamAssignmentDone        -- one row per attempt the student finished early
--  * edu.ExamAssignmentDone_Set / _List
--  * edu.ExamAttempt_Start -- as 0124, plus: an assignment can't be started
--    again once the latest attempt was sent for marking or released.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

SET QUOTED_IDENTIFIER ON
GO
IF OBJECT_ID('edu.ExamAssignmentDone') IS NULL
BEGIN
    CREATE TABLE [edu].[ExamAssignmentDone](
        [AttemptID] [varchar](20) NOT NULL,
        [ExamID]    [varchar](20) NOT NULL,
        [StudentID] [varchar](20) NOT NULL,
        [DoneDate]  [datetime]    NOT NULL DEFAULT (GETDATE()),
        CONSTRAINT [PK_edu_ExamAssignmentDone] PRIMARY KEY CLUSTERED ([AttemptID] ASC)
    )
END
GO

IF OBJECT_ID('edu.ExamAssignmentDone_Set') IS NOT NULL DROP PROCEDURE edu.ExamAssignmentDone_Set
GO
CREATE PROCEDURE [edu].[ExamAssignmentDone_Set]
(
    @APIKey    VARCHAR(100),
    @AttemptID VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        DECLARE @ExamID VARCHAR(20), @StudentID VARCHAR(20), @Status VARCHAR(20)
        SELECT @ExamID = a.ExamID, @StudentID = a.StudentID, @Status = a.Status
        FROM edu.ExamAttempt a JOIN edu.Exam e ON e.ExamID = a.ExamID
        WHERE a.AttemptID = @AttemptID AND e.IsAssignment = 1

        IF @ExamID IS NULL
        BEGIN
            ;THROW 50000, 'Assignment attempt not found', 1;
        END
        IF @Status IN ('InProgress', 'Voided')
        BEGIN
            ;THROW 50000, 'Only a submitted attempt can be sent for marking', 1;
        END
        -- Only the latest (non-voided) attempt.
        IF EXISTS (SELECT 1 FROM edu.ExamAttempt x JOIN edu.ExamAttempt a ON a.AttemptID = @AttemptID
                   WHERE x.ExamID = a.ExamID AND x.StudentID = a.StudentID AND x.Status <> 'Voided' AND x.AttemptNumber > a.AttemptNumber)
        BEGIN
            ;THROW 50000, 'This is not your latest attempt', 1;
        END

        IF NOT EXISTS (SELECT 1 FROM edu.ExamAssignmentDone WHERE AttemptID = @AttemptID)
            INSERT INTO edu.ExamAssignmentDone (AttemptID, ExamID, StudentID, DoneDate)
            VALUES (@AttemptID, @ExamID, @StudentID, GETDATE())
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.ExamAssignmentDone_Set', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.ExamAssignmentDone_List') IS NOT NULL DROP PROCEDURE edu.ExamAssignmentDone_List
GO
CREATE PROCEDURE [edu].[ExamAssignmentDone_List]
(
    @APIKey    VARCHAR(100),
    @ExamID    VARCHAR(20) = NULL,
    @StudentID VARCHAR(20) = NULL
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END
        SELECT d.AttemptID, d.ExamID, d.StudentID, d.DoneDate
        FROM edu.ExamAssignmentDone d
        WHERE (@ExamID IS NULL OR d.ExamID = @ExamID)
          AND (@StudentID IS NULL OR d.StudentID = @StudentID)
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.ExamAssignmentDone_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.ExamAttempt_Start') IS NOT NULL DROP PROCEDURE edu.ExamAttempt_Start
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
        DECLARE @IsAssignment bit
        DECLARE @DueDate datetime
        DECLARE @Zone varchar(40)
        SELECT @DurationMinutes = DurationMinutes, @IsActive = IsActive, @MaxAttempts = MaxAttempts,
               @IsAssignment = IsAssignment, @DueDate = DueDate, @Zone = AssignmentTimeZone
        FROM edu.Exam WHERE ExamID = @ExamID

        IF @IsActive IS NULL OR @IsActive <> 'A'
        BEGIN
            ;THROW 50000, 'Exam is not active', 1;
        END

        DECLARE @ExistingCount int, @CountedCount int
        SELECT @ExistingCount = COUNT(*),
               @CountedCount = SUM(CASE WHEN Status <> 'Voided' THEN 1 ELSE 0 END)
        FROM edu.ExamAttempt WHERE ExamID = @ExamID AND StudentID = @StudentID

        IF ISNULL(@CountedCount, 0) >= @MaxAttempts
        BEGIN
            ;THROW 50000, 'Maximum attempts reached', 1;
        END

        DECLARE @Now datetime = GETUTCDATE()
        DECLARE @Expires datetime = DATEADD(MINUTE, ISNULL(@DurationMinutes, 60), @Now)

        IF @IsAssignment = 1
        BEGIN
            -- 0127: no new attempt once the latest one was sent for marking
            -- ("I'm done") or its marks were released.
            IF EXISTS (SELECT 1 FROM edu.ExamAssignmentDone d JOIN edu.ExamAttempt a ON a.AttemptID = d.AttemptID
                       WHERE d.ExamID = @ExamID AND d.StudentID = @StudentID AND a.Status <> 'Voided')
            BEGIN
                ;THROW 50000, 'This assignment was already sent for marking', 1;
            END
            IF EXISTS (SELECT 1 FROM edu.ExamAttempt
                       WHERE ExamID = @ExamID AND StudentID = @StudentID AND Status <> 'Voided' AND ResultReleasedDate IS NOT NULL)
            BEGIN
                ;THROW 50000, 'Marks for this assignment are already released', 1;
            END

            -- A redo deadline for this student (0124) wins when it is later.
            DECLARE @RedoDue datetime
            SELECT @RedoDue = DueDate FROM edu.ExamAssignmentRedo WHERE ExamID = @ExamID AND StudentID = @StudentID
            IF @RedoDue IS NOT NULL AND (@DueDate IS NULL OR @RedoDue > @DueDate) SET @DueDate = @RedoDue

            IF @DueDate IS NULL
            BEGIN
                ;THROW 50000, 'Assignment has no due date', 1;
            END
            SET @Expires = DATEADD(MINUTE, CASE WHEN @Zone = 'Asia/Shanghai' THEN -480 ELSE -330 END, @DueDate)
            IF @Expires <= @Now
            BEGIN
                ;THROW 50000, 'The due date for this assignment has passed', 1;
            END
        END

        BEGIN TRANSACTION

        DECLARE @PrimaryKey VARCHAR(20) = ''
        EXEC syst.NumberFormat_Get 'edu.ExamAttempt', 'AttemptID', @PrimaryKey OUT

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
