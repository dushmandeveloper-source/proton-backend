-- 0117_online_assignment.sql
-- Online assignments: an edu.Exam row with IsAssignment = 1, tied to one
-- classroom batch (edu.CourseSchedule) and open from OpenDate to DueDate
-- (both Sri Lanka wall-clock time, like every other schedule in Proton).
-- Reuses the exam question editor, attempts, auto-marking and grading
-- screens, but with no proctoring (no fullscreen / camera / screen share /
-- strikes) and no edu.ExamSchedule row -- assignments never appear on the
-- exam calendars. The attempt timer is the due date itself (ExamAttempt_Start
-- below); ExamAttemptSweeper auto-submits whatever was saved at the deadline.

IF COL_LENGTH('edu.Exam', 'IsAssignment') IS NULL
    ALTER TABLE edu.Exam ADD IsAssignment bit NOT NULL CONSTRAINT DF_Exam_IsAssignment DEFAULT 0
GO
IF COL_LENGTH('edu.Exam', 'AssignmentScheduleID') IS NULL
    ALTER TABLE edu.Exam ADD AssignmentScheduleID varchar(20) NULL
GO
IF COL_LENGTH('edu.Exam', 'OpenDate') IS NULL
    ALTER TABLE edu.Exam ADD OpenDate datetime NULL
GO
IF COL_LENGTH('edu.Exam', 'DueDate') IS NULL
    ALTER TABLE edu.Exam ADD DueDate datetime NULL
GO
IF COL_LENGTH('edu.Exam', 'CreatedByUserID') IS NULL
    ALTER TABLE edu.Exam ADD CreatedByUserID varchar(50) NULL
GO
-- No index on purpose: edu.Exam is small, and a filtered index would make
-- every older proc that updates edu.Exam (created with QUOTED_IDENTIFIER
-- OFF, e.g. ExamQuestion_AddEdit's TotalMarks update) fail.

-- ============================================================
-- edu.Exam_SetAssignment -- called right after edu.Exam_AddEdit for an
-- assignment (Exam_AddEdit itself is unchanged, so the admin Exams editor
-- never touches these columns). CreatedByUserID is only set on first save.
-- ============================================================
IF OBJECT_ID('edu.Exam_SetAssignment') IS NOT NULL
    DROP PROCEDURE edu.Exam_SetAssignment
GO
CREATE PROCEDURE [edu].[Exam_SetAssignment]
(
    @APIKey               varchar(100),
    @ExamID               varchar(20),
    @AssignmentScheduleID varchar(20),
    @OpenDate             datetime,
    @DueDate              datetime,
    @CreatedByUserID      varchar(50) = NULL
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        IF NOT EXISTS (SELECT 1 FROM edu.CourseSchedule WHERE ScheduleID = @AssignmentScheduleID)
        BEGIN
            ;THROW 50000, 'Classroom batch not found', 1;
        END

        IF @DueDate <= @OpenDate
        BEGIN
            ;THROW 50000, 'The due date must be after the open date', 1;
        END

        UPDATE edu.Exam
        SET IsAssignment         = 1,
            AssignmentScheduleID = @AssignmentScheduleID,
            OpenDate             = @OpenDate,
            DueDate              = @DueDate,
            CreatedByUserID      = ISNULL(CreatedByUserID, @CreatedByUserID),
            UpdatedDate          = GETDATE()
        WHERE ExamID = @ExamID

        IF @@ROWCOUNT = 0
        BEGIN
            ;THROW 50000, 'Assignment not found', 1;
        END
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.Exam_SetAssignment', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamAttempt_Start -- as 0111, plus: for an assignment the attempt
-- expires at the assignment's DueDate (stored in Sri Lanka time, UTC+5:30
-- with no DST; ExpiresDate is UTC since 0071) instead of after
-- DurationMinutes, and it cannot start once the due date has passed.
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
        SELECT @DurationMinutes = DurationMinutes, @IsActive = IsActive, @MaxAttempts = MaxAttempts,
               @IsAssignment = IsAssignment, @DueDate = DueDate
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
            SET @Expires = DATEADD(MINUTE, -330, @DueDate)
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
