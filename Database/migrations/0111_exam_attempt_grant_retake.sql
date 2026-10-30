-- 0111_exam_attempt_grant_retake.sql
-- Lecturer reject can now also let the student REDO the exam.
--
-- edu.ExamAttempt_GrantRetake: rejects the attempt (same remark/reviewer
-- fields as TeacherReject) and sets Status = 'Voided'. The attempt row is
-- kept for the record, but a Voided attempt:
--   * no longer counts toward Exam.MaxAttempts (CountByExamAndStudent and
--     Start below exclude it), so the student's Join button comes back;
--   * drops out of ListPendingGrading / ListTeacherReviewQueue on its own,
--     since both only list Status IN ('Submitted','Expired','Terminated').
-- AttemptNumber keeps counting every attempt, voided ones included.

IF OBJECT_ID('edu.ExamAttempt_GrantRetake') IS NOT NULL
    DROP PROCEDURE edu.ExamAttempt_GrantRetake
GO
CREATE PROCEDURE [edu].[ExamAttempt_GrantRetake]
(
    @APIKey varchar(100),
    @AttemptID varchar(20),
    @ReviewedByUserID varchar(50),
    @Remark nvarchar(1000)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        IF @Remark IS NULL OR LTRIM(RTRIM(@Remark)) = ''
        BEGIN
            ;THROW 50000, 'A remark is required to reject an attempt', 1;
        END

        DECLARE @Status varchar(20), @TeacherReviewStatus varchar(20)
        SELECT @Status = Status, @TeacherReviewStatus = TeacherReviewStatus
        FROM edu.ExamAttempt WHERE AttemptID = @AttemptID

        IF @Status IS NULL
        BEGIN
            ;THROW 50000, 'Attempt not found', 1;
        END

        IF @Status NOT IN ('Submitted', 'Expired', 'Terminated')
        BEGIN
            ;THROW 50000, 'Only a finished attempt can be sent back for a retake', 1;
        END

        IF @TeacherReviewStatus = 'Approved'
        BEGIN
            ;THROW 50000, 'Already approved by a teacher', 1;
        END

        BEGIN TRANSACTION

        UPDATE edu.ExamAttempt
        SET Status = 'Voided',
            TeacherReviewStatus = 'Rejected',
            TeacherReviewedBy = @ReviewedByUserID,
            TeacherReviewedDate = GETDATE(),
            TeacherReviewRemark = @Remark,
            UpdatedDate = GETDATE()
        WHERE AttemptID = @AttemptID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttempt_GrantRetake', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamAttempt_CountByExamAndStudent -- voided attempts don't count.
-- ============================================================
IF OBJECT_ID('edu.ExamAttempt_CountByExamAndStudent') IS NOT NULL
    DROP PROCEDURE edu.ExamAttempt_CountByExamAndStudent
GO
CREATE PROCEDURE [edu].[ExamAttempt_CountByExamAndStudent]
(
    @APIKey varchar(100),
    @ExamID varchar(20),
    @StudentID varchar(20)
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        SELECT COUNT(*) AS RetValue FROM edu.ExamAttempt
        WHERE ExamID = @ExamID AND StudentID = @StudentID AND Status <> 'Voided'
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamAttempt_CountByExamAndStudent', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamAttempt_Start -- as 0071, but the MaxAttempts check skips
-- voided attempts.
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

        DECLARE @ExistingCount int, @CountedCount int
        SELECT @ExistingCount = COUNT(*),
               @CountedCount = SUM(CASE WHEN Status <> 'Voided' THEN 1 ELSE 0 END)
        FROM edu.ExamAttempt WHERE ExamID = @ExamID AND StudentID = @StudentID

        IF ISNULL(@CountedCount, 0) >= @MaxAttempts
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
