-- 0122_assignment_marker.sql  (marker lecturer + time zone for online assignments)
--
-- Online assignments (0117):
--  * edu.Exam.MarkerUserID -- the lecturer who marks and releases it. NULL =
--    any lecturer of the batch (behaviour before this migration). Admins can
--    always mark.
--  * edu.Exam.AssignmentTimeZone -- zone OpenDate/DueDate are written in,
--    like edu.CourseSchedule.TimeZone (0119): 'Asia/Shanghai' or
--    'Asia/Colombo'. Existing assignments were Sri Lanka time -> 'Asia/Colombo'.
--  * edu.Exam_SetAssignmentExtra -- set both after Exam_SetAssignment (kept
--    separate so the existing procs are not redefined).
--  * edu.ExamAttempt_Start -- as 0117, but the due date is converted to UTC
--    with the assignment's own zone (+8:00 China, +5:30 Sri Lanka).
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO

IF COL_LENGTH('edu.Exam', 'MarkerUserID') IS NULL
    ALTER TABLE edu.Exam ADD MarkerUserID varchar(50) NULL
GO
IF COL_LENGTH('edu.Exam', 'AssignmentTimeZone') IS NULL
    ALTER TABLE edu.Exam ADD AssignmentTimeZone varchar(40) NOT NULL
        CONSTRAINT DF_edu_Exam_AssignmentTimeZone DEFAULT ('Asia/Colombo')
GO

IF OBJECT_ID('edu.Exam_SetAssignmentExtra') IS NOT NULL DROP PROCEDURE edu.Exam_SetAssignmentExtra
GO
CREATE PROCEDURE [edu].[Exam_SetAssignmentExtra]
(
    @APIKey       varchar(100),
    @ExamID       varchar(20),
    @MarkerUserID varchar(50) = NULL,
    @TimeZone     varchar(40) = 'Asia/Colombo'
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SET @MarkerUserID = NULLIF(@MarkerUserID, '')
        IF @MarkerUserID IS NOT NULL AND NOT EXISTS (SELECT 1 FROM usr.Users WHERE UserID = @MarkerUserID)
        BEGIN
            ;THROW 50000, 'Lecturer not found', 1;
        END
        IF @TimeZone NOT IN ('Asia/Shanghai', 'Asia/Colombo') SET @TimeZone = 'Asia/Colombo'

        UPDATE edu.Exam
        SET MarkerUserID = @MarkerUserID, AssignmentTimeZone = @TimeZone, UpdatedDate = GETDATE()
        WHERE ExamID = @ExamID AND IsAssignment = 1

        IF @@ROWCOUNT = 0
        BEGIN
            ;THROW 50000, 'Assignment not found', 1;
        END
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.Exam_SetAssignmentExtra', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamAttempt_Start -- as 0117, with the assignment's own zone offset.
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
            IF @DueDate IS NULL
            BEGIN
                ;THROW 50000, 'Assignment has no due date', 1;
            END
            -- DueDate is wall-clock in the assignment's zone (no DST in either).
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
