-- 0033_exam_deactivate_hard_delete.sql
--
-- Renames edu.Exam_Delete to edu.Exam_Deactivate to make it clear that this
-- operation is a soft delete (it only flips IsActive to 'I', cascading to
-- the exam's questions, and the row stays queryable via "Show deleted") —
-- same rename pattern already used elsewhere (e.g. usr.Users_Delete vs
-- usr.Users_HardDelete in 0025_users_hard_delete.sql, and
-- edu.Course_Delete -> edu.Course_Deactivate in
-- 0032_course_deactivate_hard_delete.sql). Behavior is unchanged from the
-- old Exam_Delete.
--
-- Also adds edu.Exam_DeletePermanently: a genuine permanent delete for
-- exams, alongside edu.Exam_Deactivate. Exams are authoring-only in this
-- codebase so far (no student attempt/scoring tables exist yet), so the
-- only real dependents are the exam's own questions/options and any exam
-- schedules pointing at it. Questions and options are freely cascade-
-- deleted (FK_edu_ExamQuestionOption_ExamQuestion has no ON DELETE CASCADE,
-- so options are removed explicitly before their question) since they
-- carry no history of their own outside the exam; a referencing exam
-- schedule blocks the delete since removing the exam out from under a
-- scheduled session would leave it broken.

IF OBJECT_ID('edu.Exam_Delete') IS NOT NULL DROP PROCEDURE edu.Exam_Delete
GO
IF OBJECT_ID('edu.Exam_Deactivate') IS NOT NULL DROP PROCEDURE edu.Exam_Deactivate
GO
CREATE PROCEDURE [edu].[Exam_Deactivate]
(
    @APIKey    VARCHAR(100),
    @ID        VARCHAR(20),
    @LogUserID VARCHAR(20) = '',
    @RetValue  VARCHAR(50) = '' OUT
)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        BEGIN TRANSACTION
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END
        UPDATE edu.Exam SET IsActive = 'I', UpdatedDate = GETDATE() WHERE ExamID = @ID;
        UPDATE edu.ExamQuestion SET IsActive = 'I' WHERE ExamID = @ID;
        SET @RetValue = @ID
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.Exam_Deactivate', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.Exam_DeletePermanently') IS NOT NULL DROP PROCEDURE edu.Exam_DeletePermanently
GO
CREATE PROCEDURE [edu].[Exam_DeletePermanently]
(
    @APIKey    VARCHAR(100),
    @ID        VARCHAR(20),
    @LogUserID VARCHAR(20) = '',
    @RetValue  VARCHAR(50) = '' OUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A')
        BEGIN
            ;THROW 50000, 'Invalid API Key', 1;
        END

        IF NOT EXISTS (SELECT 1 FROM edu.Exam WHERE ExamID = @ID)
        BEGIN
            ;THROW 50000, 'That exam no longer exists.', 1;
        END

        -- ----- Refuse when real history hangs off this exam -----
        DECLARE @ScheduleCount INT = (SELECT COUNT(*) FROM edu.ExamSchedule WHERE ExamID = @ID);
        IF @ScheduleCount > 0
        BEGIN
            DECLARE @SchMsg VARCHAR(500) = 'This exam can''t be deleted because it still has ' +
                CAST(@ScheduleCount AS VARCHAR(10)) + ' scheduled exam session(s). Remove or reassign those first.';
            ;THROW 50000, @SchMsg, 1;
        END

        -- ----- Safe to remove: delete dependents before the parent row -----
        DELETE o
        FROM edu.ExamQuestionOption o
        INNER JOIN edu.ExamQuestion q ON q.QuestionID = o.QuestionID
        WHERE q.ExamID = @ID;

        DELETE FROM edu.ExamQuestion WHERE ExamID = @ID;

        DELETE FROM edu.Exam WHERE ExamID = @ID;

        SET @RetValue = @ID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.Exam_DeletePermanently', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
