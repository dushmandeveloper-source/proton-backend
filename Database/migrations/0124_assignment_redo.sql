-- 0124_assignment_redo.sql
--
-- Online assignments: "Reject -> ask the student to redo". The lecturer's
-- reject voids the attempt (edu.ExamAttempt_GrantRetake, 0111) and gives
-- that student their own redo deadline, so a redo still works after the
-- assignment's normal due date.
--  * edu.ExamAssignmentRedo (ExamID, StudentID) -> DueDate (wall-clock in
--    the assignment's AssignmentTimeZone, like edu.Exam.DueDate) + Remark.
--  * edu.ExamAssignmentRedo_Set   -- add/replace one student's redo
--  * edu.ExamAssignmentRedo_List  -- by exam or by student
--  * edu.ExamAttempt_Start -- as 0122, but an assignment uses the student's
--    redo deadline when it is later than the assignment's due date.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO

IF OBJECT_ID('edu.ExamAssignmentRedo') IS NULL
BEGIN
    CREATE TABLE [edu].[ExamAssignmentRedo](
        [ExamID]          [varchar](20)   NOT NULL,
        [StudentID]       [varchar](20)   NOT NULL,
        [DueDate]         [datetime]      NOT NULL,
        [Remark]          [nvarchar](1000) NULL,
        [CreatedByUserID] [varchar](50)   NULL,
        [CreatedDate]     [datetime]      NOT NULL CONSTRAINT [DF_edu_ExamAssignmentRedo_Created] DEFAULT (GETDATE()),
        CONSTRAINT [PK_edu_ExamAssignmentRedo] PRIMARY KEY CLUSTERED ([ExamID] ASC, [StudentID] ASC),
        CONSTRAINT [FK_edu_ExamAssignmentRedo_Exam] FOREIGN KEY ([ExamID])
            REFERENCES [edu].[Exam]([ExamID]) ON DELETE CASCADE,
        CONSTRAINT [FK_edu_ExamAssignmentRedo_Student] FOREIGN KEY ([StudentID])
            REFERENCES [mst].[Student]([StudentID]) ON DELETE CASCADE
    )
END
GO

IF OBJECT_ID('edu.ExamAssignmentRedo_Set') IS NOT NULL DROP PROCEDURE edu.ExamAssignmentRedo_Set
GO
CREATE PROCEDURE [edu].[ExamAssignmentRedo_Set]
(
    @APIKey          VARCHAR(100),
    @ExamID          VARCHAR(20),
    @StudentID       VARCHAR(20),
    @DueDate         DATETIME,
    @Remark          NVARCHAR(1000) = NULL,
    @CreatedByUserID VARCHAR(50) = NULL
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END
        BEGIN TRANSACTION
        DELETE FROM edu.ExamAssignmentRedo WHERE ExamID = @ExamID AND StudentID = @StudentID
        INSERT INTO edu.ExamAssignmentRedo (ExamID, StudentID, DueDate, Remark, CreatedByUserID)
        VALUES (@ExamID, @StudentID, @DueDate, @Remark, @CreatedByUserID)
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAssignmentRedo_Set', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.ExamAssignmentRedo_List') IS NOT NULL DROP PROCEDURE edu.ExamAssignmentRedo_List
GO
CREATE PROCEDURE [edu].[ExamAssignmentRedo_List]
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
        SELECT r.ExamID, r.StudentID, r.DueDate, r.Remark, r.CreatedByUserID, r.CreatedDate
        FROM edu.ExamAssignmentRedo r
        WHERE (@ExamID IS NULL OR r.ExamID = @ExamID)
          AND (@StudentID IS NULL OR r.StudentID = @StudentID)
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.ExamAssignmentRedo_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamAttempt_Start -- as 0122, plus the student's redo deadline.
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
