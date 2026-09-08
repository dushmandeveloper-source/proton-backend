-- 0032_course_deactivate_hard_delete.sql
--
-- Renames edu.Course_Delete to edu.Course_Deactivate to make it clear that
-- this operation is a soft delete (it only flips IsActive to 'I' and the
-- row stays queryable via "Show inactive") — same rename pattern already
-- used elsewhere (e.g. usr.Users_Delete vs usr.Users_HardDelete in
-- 0025_users_hard_delete.sql). Behavior is unchanged from the old
-- Course_Delete, including the CSCA block.
--
-- Also adds edu.Course_DeletePermanently: a genuine permanent delete for
-- courses, alongside Course_Deactivate. It REFUSES when the course is a
-- CSCA course (same rule as deactivation blocks it from being fully
-- removed — CSCA represents a real regulated exam offering) or when it is
-- referenced by real business/content records — subjects, schedules,
-- exams, or student course registrations. Those carry history that
-- shouldn't silently vanish, so the admin is told to deactivate instead.

IF OBJECT_ID('edu.Course_Delete') IS NOT NULL DROP PROCEDURE edu.Course_Delete
GO
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

        -- CSCA courses represent a real, regulated exam offering — deleting
        -- one here would silently drop student-facing exam-prep content, so
        -- it's blocked entirely rather than soft-deleted like other courses.
        IF EXISTS (SELECT 1 FROM edu.Course WHERE CourseID = @ID AND CourseType = 'CSCA')
        BEGIN
            ;THROW 50000, 'CSCA courses cannot be deactivated. Mark it inactive from the edit form instead.', 1;
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

        -- Same rule as deactivation: CSCA courses represent a real,
        -- regulated exam offering and can never be removed from here.
        IF EXISTS (SELECT 1 FROM edu.Course WHERE CourseID = @ID AND CourseType = 'CSCA')
        BEGIN
            ;THROW 50000, 'CSCA courses cannot be permanently deleted. Deactivate it from the edit form instead.', 1;
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
