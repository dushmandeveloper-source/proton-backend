-- 0038_course_allow_csca_delete.sql
--
-- edu.Course_Deactivate / edu.Course_DeletePermanently (0032) refused to
-- touch CSCA courses at all, treating them as permanently protected. That
-- turned out to be unwanted: CSCA courses should be deactivatable and
-- deletable exactly like General courses, subject to the same dependent-
-- record checks (registrations/schedules/exams) in DeletePermanently.
-- Drop the CourseType = 'CSCA' guard from both procs; everything else is
-- unchanged.

IF OBJECT_ID('edu.Course_Deactivate') IS NOT NULL DROP PROCEDURE edu.Course_Deactivate
GO
CREATE PROCEDURE [edu].[Course_Deactivate]
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

        UPDATE edu.Course        SET IsActive = 'I', UpdatedDate = GETDATE() WHERE CourseID = @ID;
        UPDATE edu.CourseSubject SET IsActive = 'I' WHERE CourseID = @ID;

        SET @RetValue = @ID

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.Course_Deactivate', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('edu.Course_DeletePermanently') IS NOT NULL DROP PROCEDURE edu.Course_DeletePermanently
GO
CREATE PROCEDURE [edu].[Course_DeletePermanently]
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

        IF NOT EXISTS (SELECT 1 FROM edu.Course WHERE CourseID = @ID)
        BEGIN
            ;THROW 50000, 'That course no longer exists.', 1;
        END

        -- ----- Refuse when real history hangs off this course -----
        DECLARE @RegCount INT = (SELECT COUNT(*) FROM mst.CourseRegistration WHERE CourseID = @ID);
        IF @RegCount > 0
        BEGIN
            DECLARE @RegMsg VARCHAR(500) = 'This course has ' + CAST(@RegCount AS VARCHAR(10)) +
                ' student registration(s) and cannot be permanently deleted. Deactivate it instead.';
            ;THROW 50000, @RegMsg, 1;
        END

        DECLARE @ScheduleCount INT = (SELECT COUNT(*) FROM edu.CourseSchedule WHERE CourseID = @ID);
        IF @ScheduleCount > 0
        BEGIN
            DECLARE @SchMsg VARCHAR(500) = 'This course can''t be deleted because it still has ' +
                CAST(@ScheduleCount AS VARCHAR(10)) + ' class schedule(s). Remove or reassign those first.';
            ;THROW 50000, @SchMsg, 1;
        END

        DECLARE @ExamCount INT = (SELECT COUNT(*) FROM edu.Exam WHERE CourseID = @ID);
        IF @ExamCount > 0
        BEGIN
            DECLARE @ExamMsg VARCHAR(500) = 'This course has ' + CAST(@ExamCount AS VARCHAR(10)) +
                ' exam(s) linked to it and cannot be permanently deleted. Remove or reassign those first.';
            ;THROW 50000, @ExamMsg, 1;
        END

        -- ----- Safe to remove: delete dependents before the parent row -----
        DELETE FROM edu.CourseSubject WHERE CourseID = @ID;

        DELETE FROM edu.Course WHERE CourseID = @ID;

        SET @RetValue = @ID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.Course_DeletePermanently', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
