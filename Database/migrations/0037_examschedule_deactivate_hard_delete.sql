-- 0037_examschedule_deactivate_hard_delete.sql
--
-- Renames edu.ExamSchedule_Delete to edu.ExamSchedule_Deactivate to make it
-- clear that this operation is a soft delete (it only flips IsActive to 'I'
-- and the row stays queryable via "Show inactive") -- same rename pattern
-- already used elsewhere (e.g. usr.Users_Delete vs usr.Users_HardDelete in
-- 0025_users_hard_delete.sql, edu.Course_Delete vs edu.Course_Deactivate in
-- 0032_course_deactivate_hard_delete.sql). Behavior is unchanged from the
-- old ExamSchedule_Delete.
--
-- Also adds edu.ExamSchedule_DeletePermanently: a genuine permanent delete
-- for exam schedules. It REFUSES when the schedule has reschedule history
-- (edu.ExamScheduleReschedule, 0030) -- that's real approval-workflow
-- history that shouldn't silently vanish -- and otherwise cascades the
-- purely-owned child rows (edu.ExamScheduleSegment,
-- edu.ExamScheduleInstructor) before removing the parent row. There is no
-- dedicated student-registration table keyed on ExamScheduleID in this
-- codebase (see 0028/0030 headers) -- the only related table is
-- edu.CourseSchedule via ExamSchedule.CourseScheduleID, and that FK points
-- the other way (ExamSchedule is the child side of that relationship), so
-- it does not need to be checked here.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF OBJECT_ID('edu.ExamSchedule_Delete') IS NOT NULL DROP PROCEDURE edu.ExamSchedule_Delete
GO
IF OBJECT_ID('edu.ExamSchedule_Deactivate') IS NOT NULL DROP PROCEDURE edu.ExamSchedule_Deactivate
GO
CREATE PROCEDURE [edu].[ExamSchedule_Deactivate]
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
        UPDATE edu.ExamSchedule SET IsActive = 'I', UpdatedDate = GETDATE() WHERE ScheduleID = @ID;
        SET @RetValue = @ID
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('%s. Script: edu.ExamSchedule_Deactivate', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- ============================================================
-- edu.ExamSchedule_DeletePermanently -- genuine hard delete. Blocks when
-- reschedule history exists; otherwise cascades owned child rows then the
-- parent row, all in one transaction.
-- ============================================================
IF OBJECT_ID('edu.ExamSchedule_DeletePermanently') IS NOT NULL DROP PROCEDURE edu.ExamSchedule_DeletePermanently
GO
CREATE PROCEDURE [edu].[ExamSchedule_DeletePermanently]
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

        IF NOT EXISTS (SELECT 1 FROM edu.ExamSchedule WHERE ScheduleID = @ID)
        BEGIN
            ;THROW 50000, 'That exam schedule no longer exists.', 1;
        END

        -- ----- Refuse when real history hangs off this schedule -----
        IF EXISTS (SELECT 1 FROM edu.ExamScheduleReschedule WHERE ScheduleID = @ID)
        BEGIN
            ;THROW 50000, 'This exam schedule can''t be deleted because it has reschedule history. Deactivate it instead.', 1;
        END

        -- ----- Safe to remove: delete purely-owned child rows first -----
        DELETE FROM edu.ExamScheduleSegment    WHERE ScheduleID = @ID;
        DELETE FROM edu.ExamScheduleInstructor WHERE ScheduleID = @ID;

        DELETE FROM edu.ExamSchedule WHERE ScheduleID = @ID;

        SET @RetValue = @ID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s. Script: edu.ExamSchedule_DeletePermanently', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO
